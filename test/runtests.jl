using Test
using Aqua
using MusicBoxPunchCard

@testset "Aqua" begin
    Aqua.test_all(MusicBoxPunchCard; ambiguities=false)
end

@testset "MusicBoxPunchCard" begin
    midi_file = joinpath(pkgdir(MusicBoxPunchCard), "demo_songs", "ThousandMiles.mid")
    thousand = midi_to_musicbox(midi_file)
    @test isequal(330, length(thousand.noteCoordinatesX))
    @test isequal(length(thousand.noteCoordinatesX), length(thousand.noteCoordinatesY))
end
