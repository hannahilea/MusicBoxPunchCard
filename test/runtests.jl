using Test
using Aqua
using MusicBoxPunchCardMaker

@testset "Aqua" begin
    Aqua.test_all(MusicBoxPunchCardMaker; ambiguities=false)
end

@testset "MusicBoxPunchCardMaker" begin
    midi_file = joinpath(pkgdir(MusicBoxPunchCardMaker), "demo_songs", "ThousandMiles.mid")
    thousand = midi_to_musicbox(midi_file)
    @test isequal(330, length(thousand.noteCoordinatesX))
    @test isequal(length(thousand.noteCoordinatesX), length(thousand.noteCoordinatesY))
end
