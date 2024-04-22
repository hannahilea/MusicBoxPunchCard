# MusicBoxPunchCardMaker: Create playable punch cards for music boxes!

Utilities for generating physical punch cards for playable music boxes (e.g. 15-note [Kikkerland music box kit](https://kikkerland.com/products/make-your-own-music-box-kit) or [30-note Wingostore music box kit](https://www.amazon.com/dp/B0774TSP3T?th=1)) from symbolicly-notated music, e.g. MIDI files.

Under active development! Next dev steps:
- [ ] Support 30-note boxes (currently defaults to 15-note boxes)
- [ ] Generate static website for conversion of MIDI, rather than running Julia script
- [ ] Support input from [musicbox.fun](https://musicbox.fun)
- [ ] Repo niceties as still needed (CI/etc)

## Usage

1. Install Julia
2. Clone this repo
2. Launch Julia REPL: `julia --project=/path/to/MusicBoxPunchCardMaker`
2. In Julia REPL
```julia
using Pkg
Pkg.activate(".")
using MusicBoxPunchCardMaker

file = joinpath(pkgdir(MusicBoxPunchCardMaker), "demo_songs", "ThousandMiles.mid")

# Run the conversion
output = midi_to_musicbox(DEMO_FILE)

# Preview the punch card song---warning, may be loud!! turn your computer volume down first. Also, not lovely, and will not sound like a music box :) 
play_punch_card_preview(output.song_transposed; output.sec_per_tick)

# What if you don't want to allow any transposition, and just want to throw out any unsupported notes? Hard-code the transposition amount to zero: 
output_no_transpose = midi_to_muiscbox(DEMO_FILE; transposition_amount=0)
```

3. As prompted by the output of `midi_to_musicbox`, copy arrays in `output.noteCoordinatesX` and `output.noteCoordinatesY` into the same-named parameters in this [Cuttle template](https://cuttle.xyz/@hannahilea/Music-roll-punchcards-for-music-boxes-iTT4lnLVNL5f). This template will generate a downloadable/cuttable SVG, with instructions for how to then cut out the cards/holes with a laser cutter or by hand.
