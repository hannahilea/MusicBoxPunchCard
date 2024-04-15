using MusicBoxMIDI
using MIDI

# Do we have the right default music box notes? Sanity check:
play_single_freq.(midi_to_hz.(DEFAULT_MUSIC_BOX_NOTES))

# Okay, one track do we want to play? Probably the piano one...
file = "ThousandMiles.mid"
midi = load(file)
track = midi.tracks[1]

# Let's sanity-check the first few notes...
let
    notes_on = filter(e -> isa(e, MIDI.NoteOnEvent), track.events)
    note_values = [n.note for n in notes_on]
    demo_notes = note_values[1:8]
    play_single_freq.(midi_to_hz.(demo_notes))
end

# Okay let's do it more nicely
samplerate=DEFAULT_SAMPLE_RATE
freq_events = flatten_midi_to_freq_events(track.events; ms_per_tick=ms_per_tick(midi))
samples = audio_samples_from_freq_events(freq_events[1:60]; samplerate)
play_audio_signal(samples, samplerate)
