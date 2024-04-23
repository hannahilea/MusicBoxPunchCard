# Script generated in service of creating top-level functions and adding additional 
# note processing

using MusicBoxPunchCardMaker
using MIDI

using MusicBoxPunchCardMaker: DEFAULT_SAMPLE_RATE, play_single_freq, midi_to_hz,
                              flatten_midi_to_midi_notes, play_midi_notes,
                              find_best_transposition_amount,generate_music_box_midi,
                              get_min_max_internote_ticks

samplerate = DEFAULT_SAMPLE_RATE

# Do we have the right default music box notes? Sanity check:
play_single_freq.(midi_to_hz.(MUSIC_BOX_15_NOTES); samplerate)
play_single_freq.(midi_to_hz.(MUSIC_BOX_30_NOTES); samplerate)

# Okay, one track do we want to play? Probably the piano one...
file = joinpath(pkgdir(MusicBoxPunchCardMaker), "demo_songs", "ThousandMiles.mid")
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

# Demo song 1: thousand miles
tm = joinpath(pkgdir(MusicBoxPunchCardMaker), "demo_songs", "ThousandMiles.mid")
tm_output = midi_to_musicbox(tm; music_box_notes=MUSIC_BOX_15_NOTES, note_range=1:60, track_range=missing)
play_punch_card_preview(; tm_output...)

# Demo song 2: PK's "still dre"
pk = joinpath(pkgdir(MusicBoxPunchCardMaker), "demo_songs", "pk-still-dre.mid")
pk_output = midi_to_musicbox(pk; music_box_notes=MUSIC_BOX_15_NOTES)
play_midi_notes(; pk_output...)

# Demo song 3: AD's "pure imagination"
ad = joinpath(pkgdir(MusicBoxPunchCardMaker), "demo_songs", "ad_pure_imagination_short_musicbox.mid")
aad_output = midi_to_musicbox(pk; music_box_notes=MUSIC_BOX_30_NOTES);
play_punch_card_preview(; ad_output...)
