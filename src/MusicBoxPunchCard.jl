module MusicBoxPunchCard

using MIDI
using PortAudio
using SampledSignals
using ProgressMeter

export midi_to_musicbox, play_punch_card_preview

const DEFAULT_SAMPLE_RATE = 11250.0
const MUSIC_BOX_NOTE_DURATION_TICKS = 96

# Note: default for 15-note music box only
const DEFAULT_MUSIC_BOX_NOTES = let
    start_note = 68 # Ab3 
    start_scale = start_note .+ [0, 2, 4, 5, 7, 9, 11, 12]
    sort(unique(vcat(start_scale, start_scale .+ 12)); rev=true)
end

#####
##### Helper functions
#####

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
    @debug "Total size:" size(samples)
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

function get_min_max_internote_ticks(midi_notes::Vector{AbsoluteNoteMidi})
    per_note = map(unique(n.midi_note for n in midi_notes)) do note
        single_note = filter(n -> n.midi_note == note, midi_notes)
        length(single_note) <= 1 && return (missing, missing)
        dists = [n.start_time_ticks for n in single_note]
        d = diff(dists)
        return minimum(d), maximum(d)
    end
    @info skipmissing(per_note)
    min = minimum(skipmissing(first(d) for d in per_note))
    max = maximum(skipmissing(last(d) for d in per_note))
    return (; per_note, max, min)
end

#####
##### Public interface
#####

#TODO docstring
function midi_to_musicbox(filename; allowed_notes=DEFAULT_MUSIC_BOX_NOTES, quiet_mode=false,
                          transposition_amount=missing)
    midi = load(filename)
    track = midi.tracks[1]
    song_midi = flatten_midi_to_midi_notes(track.events)
    sec_per_tick = MIDI.ms_per_tick(midi) / 1000
    transpose_amount = ismissing(transposition_amount) ?
                       find_best_transposition_amount(song_midi) : transposition_amount
    song_transposed = generate_music_box_midi(song_midi; transpose_amount)

    # GREAT!!!!! :D Now: let's get it into a format that cuttle can handle
    # For now, set it up such that the x distance between two adjacent holes is 1, 
    # such that cuttle can appropariately scale the x axis to prevent overlapping notes 
    # In future, might want to control for speed of rotation 
    tick_ranges = get_min_max_internote_ticks(song_transposed)
    @debug tick_ranges

    noteCoordinatesX = map(n -> tick_ranges.min > 0 ? n.start_time_ticks / tick_ranges.min :
                                n.start_time_ticks, song_transposed)
    noteCoordinatesY = map(n -> findfirst(==(n.midi_note), allowed_notes) - 1,
                           song_transposed)

    if !quiet_mode
        println("")
        @info """Go to `https://cuttle.xyz/@hannahilea/Music-roll-punchcards-for-music-boxes-iTT4lnLVNL5f`, 
                    - copy this into `noteCoordinatesX`:
                      $(noteCoordinatesX)

                    - copy this into `noteCoordinatesY`:
                      $(noteCoordinatesY)
                    """
    end
    return (; song_transposed, sec_per_tick, noteCoordinatesX, noteCoordinatesY)
end

function play_punch_card_preview(; song_transposed, sec_per_tick, kwargs...)
    return play_midi(song_transposed; sec_per_tick)
end

end # module MusicBoxPunchCard
