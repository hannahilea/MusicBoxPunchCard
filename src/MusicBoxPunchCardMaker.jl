module MusicBoxPunchCardMaker

using MIDI
using PortAudio
using SampledSignals
using ProgressMeter

export midi_to_musicbox, play_punch_card_preview, MUSIC_BOX_15_NOTES, MUSIC_BOX_30_NOTES

const DEFAULT_SAMPLE_RATE = 11250.0
const MUSIC_BOX_NOTE_DURATION_TICKS = 96

const MUSIC_BOX_15_NOTES = let
    start_note = 68 # Ab3 
    start_scale = start_note .+ [0, 2, 4, 5, 7, 9, 11, 12]
    sort(unique(vcat(start_scale, start_scale .+ 12)); rev=true)
end

const MUSIC_BOX_30_NOTES = let
    start_note = 53 # F3 
    start_scale = start_note .+ [0, 2, 7, 9, 11, 12, 14, 16, 38, 40]
    chromatics = start_note .+ collect(17:36)
    sort(unique(vcat(start_scale, chromatics)); rev=false)
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
        isa(event, MIDI.NoteOffEvent) || continue
        event.note == n && return t
    end
    @warn "Uh oh, found a note that never ends...." n
    return t
end

Base.@kwdef struct AbsoluteNoteMidi
    midi_note::Int
    start_time_ticks::Int
    duration_ticks::Int
end

# Assumes each note on has corresponding note off
function flatten_midi_to_midi_notes(midi_events::Vector{TrackEvent})

    # Sometimes note off events are encoded as note on events with velocity=0;
    # convert them up front for happier downstream note on/off matching
    midi_events = map(midi_events) do e
        return (isa(e, MIDI.NoteOnEvent) && e.velocity == 0) ?
               MIDI.NoteOffEvent(e.dT, e.note, 0) : e
    end

    # Collect all note on/off pairs as individual note events
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
        elseif !(isa(event, MIDI.TimeSignatureEvent) || isa(event, MIDI.SetTempoEvent) ||
                 isa(event, MIDI.MIDI.KeySignatureEvent) ||
                 isa(event, MIDI.SMPTEOffsetEvent) ||
                 isa(event, MIDI.TrackNameEvent) || isa(event, MIDI.InstrumentNameEvent) ||
                 isa(event, MIDI.ProgramChangeEvent) ||
                 isa(event, MIDI.MIDIChannelPrefixEvent) ||
                 isa(event, MIDI.ControlChangeEvent) || isa(event, MIDI.MIDIPort) ||
                 isa(event, MIDI.PitchBendEvent))
            @warn "Event type unsupported: $event" # Is this important? No, more to keep track of potential event types for our future selves
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
                                 music_box_notes, transpose_amount)
    adjusted_notes = map(midi_notes) do n
        return AbsoluteNoteMidi(; midi_note=n.midi_note + transpose_amount,
                                n.start_time_ticks,
                                duration_ticks=MUSIC_BOX_NOTE_DURATION_TICKS)
    end
    return unique(filter(n -> n.midi_note in music_box_notes, adjusted_notes))
end

# Currently optimizes for most total notes; could instead weight chroma equally
# If multiple good options, returns first found
function find_best_transposition_amount(midi_notes::Vector{AbsoluteNoteMidi};
                                        music_box_notes)
    best_offset = 0
    highest_num_valid_notes = 0

    song_extrema = extrema(m.midi_note for m in midi_notes)
    box_extrema = extrema(music_box_notes)
    transposition_range = let
        start_range = first(box_extrema) - last(song_extrema) - 1
        stop_range = last(box_extrema) - first(song_extrema) + 1
        start_range:stop_range
    end

    @debug "Transposition range" transposition_range song_extrema box_extrema s = length(collect(transposition_range))
    for transpose_amount in transposition_range
        transposed_notes = generate_music_box_midi(midi_notes; music_box_notes,
                                                   transpose_amount)
        num_valid_notes = length(transposed_notes)
        num_valid_notes == 0 && continue

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
        return extrema(d)
    end
    min = minimum(skipmissing(first(d) for d in per_note))
    max = maximum(skipmissing(last(d) for d in per_note))
    return (; per_note, max, min)
end

#####
##### Public interface
#####

"""
    midi_to_musicbox(filename; music_box_notes, quiet_mode=false,
                     transposition_amount=missing, notes_slice=missing,
                     tracks_slice=missing) -> NamedTuple

Return named tuple of MIDI `filename` converted to a coordinate set of plottable 
X- and Y- values for the given MIDI notes. 

ARGS
* `filename`: Path to input MIDI file
* `music_box_notes`: Notes (MIDI note numbers) playable by a given music box; should be
    sorted by desired output index. Should be either `MUSIC_BOX_15_NOTES` or 
    `MUSIC_BOX_30_NOTES` unless a custom box is present. All MIDI note events in `filename`
    that do not occur in `musib_box_notes` (after `transposition_amount` is applied)
    will be stripped from output `music_box_notes`.
* `quiet_mode`: Default false; supresses info statements that contain output values
    coordinate arrays. 
* `transposition_amount`: Transposition offset applied to input MIDI file notes. 
    If `missing`, an optimimal transposition amount is selected for the given 
    input notes and `music_box_notes`. Set to `0` to prevent transposition. Default is `missing`.
* `notes_slice`: If non-missing, indicates range of note indices to include in output song.
     If `missing`, all notes are included. Default is `missing`.
* `tracks_slice`: If `filename` contains multiple tracks and `tracks_slice` is non-missing, 
    indicates tracks to include. Default is `missing`.

OUTPUT KWARGS
* `music_box_notes`: Vector of output [`MusicBoxPunchCardMaker.AbsoluteNoteMidi`](@ref) notes, 
    to be used in playback preview (see [`play_punch_card_preview`](@ref)). Used to 
    derive `noteCoordinatesX` and `noteCoordinatesY`.
* `sec_per_tick`: BPM conversion from input MIDI file, currently used only in previewing 
    output song ([`play_punch_card_preview`](@ref))
* `noteCoordinatesX`: Per-note x-coordinate values to be input into SVG punch card template 
* `noteCoordinatesY`: Per-note y-coordinate values to be input into SVG punch card template 
* `transpose_amount`: Transposition (semitone offset) applied to original MIDI file to generate `music_box_notes`
"""
function midi_to_musicbox(filename; music_box_notes, quiet_mode=false,
                          transposition_amount=missing, notes_slice=missing,
                          tracks_slice=missing)
    midi = load(filename)
    ismissing(tracks_slice) && (tracks_slice = 1:length(midi.tracks))
    song_midi = vcat(map(midi.tracks[tracks_slice]) do track
                         return song_midi = flatten_midi_to_midi_notes(track.events)
                     end...)
    song_midi = sort(song_midi; by=m -> m.start_time_ticks)
    if !ismissing(notes_slice)
        song_midi = song_midi[notes_slice]
    end
    sec_per_tick = MIDI.ms_per_tick(midi) / 1000
    transpose_amount = ismissing(transposition_amount) ?
                       find_best_transposition_amount(song_midi; music_box_notes) :
                       transposition_amount
    music_box_notes = generate_music_box_midi(song_midi; music_box_notes, transpose_amount)

    # GREAT!!!!! :D Now: let's get it into a format that cuttle can handle
    # For now, set it up such that the x distance between two adjacent holes is 1, 
    # such that cuttle can appropariately scale the x axis to prevent overlapping notes 
    # In future, might want to control for speed of rotation.
    tick_ranges = get_min_max_internote_ticks(music_box_notes)
    @debug tick_ranges

    # Because we unique'd over notes in `generate_music_box_midi`,
    # we know the minimum diffs will be greater than 0. 
    # The resultant coordinates will be a minimum distance of "1" apart---which 
    # can be adjusted in cuttle to meet requirements of printed material such that 
    # all notes can be played.
    # TODO-future: adjust x-coords for a fixed playback crank rotation! and/or 
    # return the required playback crank rotation to support the MIDI bpm
    noteCoordinatesX = map(n -> n.start_time_ticks / tick_ranges.min, music_box_notes)

    # Note that we subtract by 1 here because we're converting from 1-based indices (Julia)
    # to 0-based indices (javascript, as used by Cuttle)
    noteCoordinatesY = map(n -> findfirst(==(n.midi_note), music_box_notes) - 1,
                           music_box_notes)

    if !quiet_mode
        println("")
        @info """Conversion succeeded (transpoition amount: $(transpose_amount))
                    Go to Cuttle template `https://cuttle.xyz/@hannahilea/Music-roll-punchcards-for-music-boxes-iTT4lnLVNL5f`
                    - Use template for $(length(music_box_notes)) note music roll

                    - copy into template's `noteCoordinatesX`:
                      $(noteCoordinatesX)

                    - copy into template's `noteCoordinatesY`:
                      $(noteCoordinatesY)
                    """
    end
    return (; music_box_notes, sec_per_tick, noteCoordinatesX, noteCoordinatesY,
            transpose_amount)
end

"""
    play_punch_card_preview(; music_box_notes, sec_per_tick, kwargs...) -> nothing

Basic MIDI synth playaback of `music_box_notes` at tempo `sec_per_tick`. 
All other `kwargs` will be ignored. May misbehave if audio configuration changes 
during Julia session (e.g., headphones switched, etc).
"""
function play_punch_card_preview(; music_box_notes, sec_per_tick, kwargs...)
    return play_midi_notes(music_box_notes; sec_per_tick)
end

end # module MusicBoxPunchCardMaker
