# Glowey's Gear

A plugin for Daylight UI on WoW: Forever. It scores gear for your spec, compares it with what you wear and carry, and lists the best upgrades for sale on the Auction House by improvement per gold. The same verdict shows on item tooltips and on bag slots.

Status: in development, not released. Stage 1 is built and audited; the first run in the game is `design/in-game-check.md`.

## Requirements

- Nothing. Daylight UI 2.1 or later is optional (checked against 2.1.2): without it Host.lua stands in for it, and the settings are in /glowey.

## How it works

- **Your spec** comes from your talents: the tree with the most points. Before your first talent point a Leveling profile is used. You can pick a spec yourself.
- **Every piece of gear gets a score** from its stats and your spec's stat weights. An item is an upgrade when it scores higher than the best you already own for that slot, worn or in your bags.
- **Upgrades for Sale** ranks what the Auction House has by improvement per gold, under your max price. A switch ranks by the biggest improvement instead. It reads the list Daylight UI's Full scan fetched; it never buys anything for you.

## Settings

Open the Daylight UI options and go to **Plugins → Gear**. `/gear` (or `/dui gear`) opens the Upgrades for Sale window; `/gear debug` prints what the plugin knows, for a bug report.

## About the numbers

Stat weights are starting values, not final answers. Level 60 weights for many specs are based on the [WoWSims](https://wowsims.com) simulator (MIT License, see `CREDITS.md`); the rest, and all weights below level 60, are our own. `Data/README.md` says where every number comes from.

## For developers

- `ARCHITECTURE.md`: modules, events, saved variables, where Daylight UI is touched.
- `design/data-format.md`: the shape of `Data/Weights.lua` and how item stats are read.
- Checks, from this folder:
  - `python -I ~/tools/compile51.py .`
  - `~/tools/luacheck/luacheck.exe .`
  - `python -I Tools/tests/run.py` (needs `pip install lupa`)
  - `python -I Tools/locales.py`
  - `python -I Tools/data/check.py Data/Weights.lua`
  - `python -I Tools/client_facts.py` re-reads the stat names and the combat ratings table from the installed game into `Tools/tests/fixtures/`
- `Tools/data/` holds the scripts that generate `Data/Weights.lua` (`extract.py`, `gen.py`, `check.py`, `upstream.json`); `Data/README.md` explains how to run them. `Tools`, `design` and the documents above are left out of the zip players download.

## License

All Rights Reserved (see `LICENSE`). Stat weights derived from WoWSims are used under the MIT License; the notice is in `CREDITS.md`.

## Updates

What's new in each version is in [CHANGELOG.md](CHANGELOG.md).
