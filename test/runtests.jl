using Test
using Aqua
using MusicBoxPunchCardMaker

@testset "Aqua" begin
    Aqua.test_all(MusicBoxPunchCardMaker; ambiguities=false)
end

@testset "MusicBoxPunchCardMaker" begin
    midi_file = joinpath(pkgdir(MusicBoxPunchCardMaker), "demo_songs", "ThousandMiles.mid")
    thousand = midi_to_musicbox(midi_file; music_box_notes=MUSIC_BOX_15_NOTES,
                                quiet_mode=true)
    @test isequal(694, length(thousand.noteCoordinatesX))
    @test isequal(length(thousand.noteCoordinatesX), length(thousand.noteCoordinatesY))

    thousand = midi_to_musicbox(midi_file; music_box_notes=MUSIC_BOX_15_NOTES,
                                track_range=1:1,
                                quiet_mode=true)
    @test isequal(330, length(thousand.noteCoordinatesX))

    thousand = midi_to_musicbox(midi_file; music_box_notes=MUSIC_BOX_15_NOTES,
                                quiet_mode=true, note_range=1:60)
    @test isequal(60, length(thousand.noteCoordinatesX))
end
