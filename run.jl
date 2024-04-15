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
