# Credits

Glowey's Gear is written by Glowey. It is a plugin for Daylight UI and holds no copies of Daylight UI's code or art.

## Data: stat weights

The level 60 stat weights of the entries marked `source = "wowsims"` in `Data/Weights.lua` are derived from the EP weight presets of the WoWSims "WoW Forever" simulator, <https://github.com/wowsims/forever> (commit `21377c070b5ea111a9bb5e36eb766193270b0cc7`), converted to this addon's units as described in `Data/README.md`. That material is used under the MIT License below. The license covers the WoWSims material only; Glowey's Gear as a whole keeps its own license (`LICENSE`).

All other weights (entries marked `source = "authored"`, and every table for levels below 60) are original to Glowey's Gear.

WoWSims: <https://wowsims.com>

```
MIT License

Copyright (c) 2022 wowsims team

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

## Code

All code in this addon is original to Glowey's Gear. The names of item stats and the rating figures it uses are the game's own, read from the game client (`design/data-format.md`, 3.0); the simulator credited above is the second reference for the rating figures. `Update.lua` is the newer-version alert shared by Glowey's Daylight UI plugins.
