using Pkg
Pkg.activate(".")
using MusicBoxMIDI
using MIDI

samplerate = DEFAULT_SAMPLE_RATE

# Do we have the right default music box notes? Sanity check:
play_single_freq.(midi_to_hz.(DEFAULT_MUSIC_BOX_NOTES); samplerate)

# Okay, one track do we want to play? Probably the piano one...
file = "ThousandMiles.mid"
midi = load(file)
track = midi.tracks[1]

# Let's sanity-check the first few notes...
let
    notes_on = filter(e -> isa(e, MIDI.NoteOnEvent), track.events)
    note_values = [n.note for n in notes_on]
    demo_notes = note_values[1:8]
    play_single_freq.(midi_to_hz.(demo_notes); samplerate)
end

# Okay let's do it more nicely
midi_notes = flatten_midi_to_midi_notes(track.events)
sec_per_tick = MIDI.ms_per_tick(midi) / 1000
play_midi_notes(midi_notes[1:60]; sec_per_tick)

# OKAY let's see if our notes can fit nicely in our music box notes?
song_midi = midi_notes[1:60]

transpose_amount = find_best_transposition_amount(song_midi)
song_transposed = generate_music_box_midi(song_midi; transpose_amount)
play_midi_notes(song_transposed; sec_per_tick)

# GREAT!!!!! :D Now: let's get it into a format that cuttle can handle
# For now, set it up such that the x distance between two adjacent holes is 1, 
# such that cuttle can appropariately scale the x axis to prevent overlapping notes 
# In future, might want to control for speed of rotation 
tick_ranges = get_min_max_internote_ticks(song_transposed)

song_coords = map(song_transposed) do n
    x = n.start_time_ticks / tick_ranges.min
    # Guaranteed to exist b/c we've already run through filtering out invalid notes:
    y = findfirst(==(n.midi_note), DEFAULT_MUSIC_BOX_NOTES) - 1
    return (x, y)
end

song_coords_x = map(n -> n.start_time_ticks / tick_ranges.min, song_transposed)
song_coords_y = map(n -> findfirst(==(n.midi_note), DEFAULT_MUSIC_BOX_NOTES) - 1, song_transposed)

@info "Copy into ThousandMiles `notePositionsX`:\n$(song_coords_x)"
@info "Copy into ThousandMiles `notePositionsY`:\n$(song_coords_y)"


baby = midi_to_musicbox("babypunchcardmelody_willw_arr.mid")
play_midi_notes(baby.song_transposed; baby.sec_per_tick)
@info "Copy into Baby `notePositionsX`:\n$(baby.song_coords_x)"
@info "Copy into Baby `notePositionsY`:\n$(baby.song_coords_y)"

thousand = midi_to_musicbox("ThousandMiles.mid")
play_midi_notes(baby.song_transposed; baby.sec_per_tick)
@info "Copy into Thousand `notePositionsX`:\n$(thousand.song_coords_x)"
@info "Copy into Thousand `notePositionsY`:\n$(thousand.song_coords_y)"
