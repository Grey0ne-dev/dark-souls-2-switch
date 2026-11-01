# Dark Souls II — local Switch build

This experimental build uses MajulaRecomp's `ds2-2014-final` source and the game files extracted from your ISO.

1. Copy the staged `switch` folder to the SD card root. The resulting path is `sdmc:/switch/ds2-nx/ds2-dk.nro`, with `ds2.toml` and `game_root/` alongside it.
2. On a homebrew-capable Switch, hold **R** while starting an installed game to open the homebrew menu with full memory.
3. Launch **Dark Souls II**. Album mode does not provide enough memory.

The game shaders are embedded in the NRO. Shader variants may compile during the first visit to an area.

Settings are in `ds2.toml`. The upstream Early Dull Ember and fog-wall invulnerability changes are disabled in this package to preserve original gameplay.

The build and static binary checks passed. This local build has not been tested on Switch hardware; gameplay, performance, and stability are unverified.
