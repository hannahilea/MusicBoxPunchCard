# MusicBoxPunchCard

Utilities for generating physical punch cards for playable music boxes (e.g. FOO and BAR) from symbolicly-notated music, e.g. MIDI files.  

Under active development! Next dev steps:
- [ ] Generate static website for conversion of MIDI, rather than running Julia script
- [ ] Support input from [musicbox.fun](https://musicbox.fun)
- [ ] Repo niceties as still needed (CI/etc)

## Usage

1. Install Julia
2. Launch Julia REPL: `julia --project=/path/to/MusicBoxPunchCard`
2. In Julia REPL
```julia
using Pkg
Pkg.activate(".")

using MusicBoxPunchCard

TODO

```
3. Copy output from parameters `noteCoordinatesX` and `noteCoordinatesY` into the Cuttle template [here](https://cuttle.xyz/@hannahilea/Music-roll-punchcards-for-music-boxes-iTT4lnLVNL5f); the template will generate a downloadable/cuttable SVG. See instructions there for how to cut out punchard by hand or with a laser cutter.
