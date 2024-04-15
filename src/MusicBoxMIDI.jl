module MusicBoxMIDI

using MIDI
using PortAudio, SampledSignals
using ProgressMeter

export midi_to_hz, play_single_freq, DEFAULT_MUSIC_BOX_NOTES, flatten_midi_to_freq_event,
       audio_signal_from_freq_events, audio_samples_from_freq_event, play_audio_signal,
       flatten_midi_to_freq_events

const DEFAULT_MUSIC_BOX_NOTES = let
    start_note = 68 # Ab3 
    start_scale = start_note .+ [0, 2, 4, 5, 7, 9, 11, 12]
    unique(vcat(start_scale, start_scale .+ 12))
end

midi_to_hz(v::Int) = 440 * 2^((v - 69) / 12)

function audio_samples_from_freq_event(freq; duration, samplerate)
    return cos.(2pi * (1:(duration * samplerate)) * freq / samplerate)
end

function play_single_freq(freq, duration::Float64=0.1; samplerate=11250.0)
    samples = audio_samples_from_freq_event(freq; duration, samplerate)
    play_audio_signal(; samples, samplerate)
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

# Assumes each note on has corresponding note off
function flatten_midi_to_freq_events(midi_events::Vector{TrackEvent}; ms_per_tick)
    #TODO-future: validate that events are valid??
    t = 0
    tempo = missing
    sec_per_tick = ms_per_tick / 1000
    freq_events = [] # In absolute time, not the relative time of midi
    for (i, event) in enumerate(midi_events)
        t += (event.dT * sec_per_tick)
        if isa(event, MIDI.SetTempoEvent)
            @warn "Just...switched tempo??" tempo new_tempo = event.tempo
            tempo = event.tempo
        elseif isa(event, MIDI.NoteOnEvent)
            duration = get_event_duration_ticks(event.note, midi_events[(i + 1):end]) *
                       sec_per_tick
            push!(freq_events, (; freq=midi_to_hz(event.note), start_time=t, duration))
        elseif isa(event, MIDI.NoteOffEvent)
        else
            @warn "Event type unsupported: $event"
        end
    end
    return freq_events
end

function audio_signal_from_freq_events(freq_events; samplerate=11250)
    _sec_to_index(sec) = sec * samplerate + 1
    max_duration = maximum([e.start_time + e.duration for e in freq_events])
    samples = vec(zeros(Int(ceil(_sec_to_index(max_duration)))))
    @info "Total size:" size(samples)
    for e in freq_events
        # could be buggy! prob use alignedsamples etc
        start = Int(floor(_sec_to_index(e.start_time)))
        event_samples = audio_samples_from_freq_event(e.freq; e.duration, samplerate)
        @info "An event!" start event_samples
        samples[start:(start + length(event_samples) - 1)] += event_samples
    end
    return (; samples, samplerate)
end

function play_audio_signal(; samples, samplerate)
    return PortAudioStream(0, 2; samplerate) do stream
        return write(stream, samples)
    end
end

end # module MusicBoxMIDI
