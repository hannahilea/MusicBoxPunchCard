module MusicBoxMIDI

using MIDI
using PortAudio, SampledSignals
using ProgressMeter

export midi_to_hz, play_single_freq, DEFAULT_MUSIC_BOX_NOTES, flatten_midi_to_freq_event,
       audio_samples_from_freq_events, audio_samples_from_freq_event, play_audio_signal,
       flatten_midi_to_midi_notes, midi_notes_to_freq_notes, DEFAULT_SAMPLE_RATE,
       play_midi_notes, find_best_transposition_amount, generate_music_box_midi

const DEFAULT_SAMPLE_RATE = 11250.0
const MUSIC_BOX_NOTE_DURATION_TICKS = 96

const DEFAULT_MUSIC_BOX_NOTES = let
    start_note = 68 # Ab3 
    start_scale = start_note .+ [0, 2, 4, 5, 7, 9, 11, 12]
    unique(vcat(start_scale, start_scale .+ 12))
end

midi_to_hz(v::Int) = 440 * 2^((v - 69) / 12)

function audio_samples_from_freq_event(freq; duration, samplerate, amplitude=0.5)
    return amplitude .* cos.(2pi * (1:(duration * samplerate)) * freq / samplerate)
end

function play_single_freq(freq; duration::Float64=0.1, samplerate)
    samples = audio_samples_from_freq_event(freq; duration, samplerate)
    play_audio_signal(samples, samplerate)
    return samples
end

function get_event_duration_ticks(n, events)
    t = 0
    for event in events
        t += event.dT
        event.note == n && return t
    end
    @warn "Uh oh, this note never ends...." n
    return t
end

Base.@kwdef mutable struct AbsoluteNoteMidi
    midi_note::Int
    start_time_ticks::Int
    duration_ticks::Int
end

# Assumes each note on has corresponding note off
function flatten_midi_to_midi_notes(midi_events::Vector{TrackEvent})
    #TODO-future: validate that events are valid??
    time_ticks = 0
    midi_notes = AbsoluteNoteMidi[] # In absolute time, not the relative time of events
    for (i, event) in enumerate(midi_events)
        time_ticks += event.dT
        if isa(event, MIDI.NoteOnEvent)
            duration_ticks = get_event_duration_ticks(event.note, midi_events[(i + 1):end])
            push!(midi_notes,
                  AbsoluteNoteMidi(; midi_note=event.note, start_time_ticks=time_ticks,
                                   duration_ticks))
        elseif isa(event, MIDI.NoteOffEvent)
            # Already handled in above case 
        else
            @warn "Event type unsupported: $event"
        end
    end
    return midi_notes
end

function midi_notes_to_freq_notes(midi_notes::Vector{AbsoluteNoteMidi}; sec_per_tick)
    return map(midi_notes) do n
        start_time = n.start_time_ticks * sec_per_tick
        duration = n.duration_ticks * sec_per_tick
        freq = midi_to_hz(n.midi_note)
        return (; freq, start_time, duration)
    end
end

function audio_samples_from_freq_events(freq_events; samplerate)
    _sec_to_index(sec) = sec * samplerate + 1
    max_duration = maximum([e.start_time + e.duration for e in freq_events])
    samples = vec(zeros(Int(ceil(_sec_to_index(max_duration)))))
    @info "Total size:" size(samples)
    for e in freq_events
        # prob subtly buggy! should use AlignedSampels going forward etc
        start = Int(floor(_sec_to_index(e.start_time)))
        event_samples = audio_samples_from_freq_event(e.freq; e.duration, samplerate)
        samples[start:(start + length(event_samples) - 1)] += event_samples
    end
    return samples
end

function play_audio_signal(samples, samplerate;)
    return PortAudioStream(0, 2; samplerate) do stream
        return write(stream, samples)
    end
end

function play_midi_notes(midi_notes::Vector{AbsoluteNoteMidi}; sec_per_tick,
                         samplerate=DEFAULT_SAMPLE_RATE)
    freq_notes = midi_notes_to_freq_notes(midi_notes; sec_per_tick)
    samples = audio_samples_from_freq_events(freq_notes; samplerate)
    return play_audio_signal(samples, samplerate)
end

function generate_music_box_midi(midi_notes::Vector{AbsoluteNoteMidi};
                                 allowed_notes=DEFAULT_MUSIC_BOX_NOTES,
                                 transpose_amount=0)
    notes = deepcopy(midi_notes)
    notes = map(notes) do n
        n.midi_note += transpose_amount
        n.duration_ticks = MUSIC_BOX_NOTE_DURATION_TICKS
        return n
    end
    return filter(n -> n.midi_note in allowed_notes, notes)
end

#TODO-future: if multiple good, return all
# Currently optimizes for most total notes; could instead weight chroma equally
function find_best_transposition_amount(midi_notes::Vector{AbsoluteNoteMidi};
                                        allowed_notes=DEFAULT_MUSIC_BOX_NOTES)
    best_offset = 0
    highest_num_valid_notes = 0
    for transpose_amount in 0:(21 + 24)
        transposed_notes = generate_music_box_midi(midi_notes; allowed_notes,
                                                   transpose_amount)
        num_valid_notes = length(transposed_notes)
        num_valid_notes == 0 && continue
        @debug "For $(transpose_amount): $(num_valid_notes)"

        # Early return if we've found a transposition that succeeds!
        num_valid_notes == length(midi_notes) && return transpose_amount

        # ...otherwise, track it
        if num_valid_notes > highest_num_valid_notes
            highest_num_valid_notes = num_valid_notes
            best_offset = transpose_amount
        end
    end
    @warn "Best transposition amount ($best_offset) only retains $(highest_num_valid_notes) of the original $(length(midi_notes)) notes"
    return best_offset
end

end # module MusicBoxMIDI
