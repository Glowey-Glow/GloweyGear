# Data: stat weights

`Weights.lua` holds the stat weights the scoring engine uses: every class, every talent tree (27 specs), one extra variant (`DRUID.FERAL_BEAR`) and one generic `LEVELING` profile per class. Its shape is `design/data-format.md`, format 1. It is a generated file: change the generator's inputs and regenerate (last section), do not hand-edit numbers.

**Read this first.** Three kinds of numbers are in the file, and they deserve different trust:

1. **Level 60 tables with `source = "wowsims"`** (17 of the 27 specs, plus the bear variant): taken from published presets of the wowsims/forever simulator and converted to this addon's units. They describe a level 60 character in pre-raid gear with consumables and raid buffs, fighting a raid target.
2. **Level 60 tables with `source = "authored"`** (10 specs + 9 `LEVELING` profiles): no simulator preset exists. The numbers are this project's own reasoning. They are starting values.
3. **Every `brackets` table (levels 1 to 59), for every spec**: authored by a rule, not simulated. The simulator only knows level 60.

## Licensing of the inputs

Glowey's Gear is All Rights Reserved. Only sources whose license allows inclusion in a proprietary addon contribute numbers: MIT, BSD, Apache-2.0 or public domain. Nothing derived from GPL, LGPL, CC-SA, CC-NC or CC-ND material is in this folder.

| Source | Use | License, checked where |
|---|---|---|
| `github.com/wowsims/forever`, commit `21377c070b5ea111a9bb5e36eb766193270b0cc7` (2026-11-20) | Numbers for the 18 `wowsims` entries (17 specs and the bear variant); rating-per-percent constants and class stat rules read as game facts | MIT, "Copyright (c) 2022 wowsims team": the `LICENSE` file at that exact commit. Notice and full text are in `CREDITS.md`. |
| `github.com/wowsims/classic`, commit `7779ebbf79dc7f1341e6ab939b28a3402c9a730a` | Cross-check only (order of magnitude of caster and healer weights). **No number from it is in the file**: it models a different rule set (percent stats, Season of Discovery lineage). | MIT, "Copyright (c) 2024 wowsims team" |

Not used for any number in this folder: CheapUpgrades (All Rights Reserved; never opened), Pawn (CC BY-NC-ND), Forever Leveling BiS (All Rights Reserved), Polestar (GPL-3), any guide site. No guide was consulted for orderings either; the authored numbers come from the mechanics reasoning below and from the general, long-published "equivalence points" way of thinking about classic gear.

That sentence is about the weights. For the rest of the plugin the record is this: the first draft of the engine's stat-name and rating tables (`Stats.lua`) and of its weapon skill numbers (`Score.lua`) was written after reading the corresponding tables of Polestar and Forever Leveling BiS, and followed Polestar's. An audit caught it on 2026-11-20 and those tables were thrown away and rebuilt from the client's own data (its GlobalStrings database, its combat ratings table and its character-sheet source), with this folder's upstream as the second reference for the rating figures. `ARCHITECTURE.md`, rule 1, and `design/data-format.md`, 3.0 and 3.8, have the detail. Nothing from either addon is in the plugin now.

The upstream README asks, as a courtesy and not a license term, for a user-visible link back to the project. Suggested: a line on the plugin's options page or CurseForge page, "Level 60 stat weights for many specs are based on the WoWSims simulator (wowsims.com)".

## Which upstream repository

The wowsims organization has `classic`, `sod`, `tbc`, `wotlk`, `cata`, `mop` and **`forever`** ("World of Warcraft Forever simulations"). `forever` is the match for this client: level 60, the nine classes, classic stat rules (15 mana per Intellect, 10 health per Stamina, 2 attack power per Strength for warriors), combined with rating stats exactly as the engine expects (10 hit, 14 crit, 10 haste, 10 expertise, 12 dodge, 15 parry, 5 block rating per 1%; 1 defense rating per skill point; one hit or crit rating feeds melee, ranged and spells). `classic` and `sod` use percent stats and other talents.

## Provenance per spec

Upstream paths are under `ui/specs/` at the commit above. "÷ X" = every weight divided by the preset's weight for X, so X reads 1.

| Class | Spec key | Source | Upstream file # preset | Transformation | Confidence |
|---|---|---|---|---|---|
| WARRIOR | ARMS | wowsims | `warrior/dps/presets.ts` # `PreBiSArmsEpWeights` | ÷ Strength | high |
| WARRIOR | FURY | wowsims | `warrior/dps/presets.ts` # `PreBiSFuryEpWeights` | ÷ Strength | high |
| WARRIOR | PROTECTION | wowsims | `warrior/protection/presets.ts` # `PreBiSBalancedEpWeights` | ÷ Stamina; HEALTH 0.08 added | medium |
| PALADIN | HOLY | authored | | | low |
| PALADIN | PROTECTION | authored | | | low |
| PALADIN | RETRIBUTION | wowsims | `paladin/retribution/presets.ts` # `UnsealedWrathEpWeights` | ÷ Strength; **haste replaced** (below) | medium |
| HUNTER | BEAST_MASTERY | wowsims | `hunter/dps/presets.ts` # `TurretEpWeights` | none (Agility = 1 upstream) | medium |
| HUNTER | MARKSMANSHIP | wowsims | same | none | high |
| HUNTER | SURVIVAL | wowsims | same | none | medium |
| ROGUE | ASSASSINATION | wowsims | `rogue/dps/presets.ts` # `EP_PRESET_ASSASSINATION` | ÷ Agility | high |
| ROGUE | COMBAT | wowsims | `rogue/dps/presets.ts` # `EP_PRESET_COMBAT_SINISTER` | ÷ Agility | high |
| ROGUE | SUBTLETY | wowsims | `rogue/dps/presets.ts` # `EP_PRESET_SUBTLETY` | ÷ Agility | high |
| PRIEST | DISCIPLINE | wowsims | `priest/healer/presets.ts` # `DiscRaidHealingEpWeights` | none (healing = 1 upstream) | medium |
| PRIEST | HOLY | wowsims | `priest/healer/presets.ts` # `HolyRaidHealingEpWeights` | none | medium |
| PRIEST | SHADOW | wowsims | `priest/dps/presets.ts` # `ShadowEpWeights` | none (spell damage = 1) | high |
| SHAMAN | ELEMENTAL | wowsims | `shaman/elemental/presets.ts` # `DefaultEpWeights` | none | high |
| SHAMAN | ENHANCEMENT | wowsims | `shaman/enhancement/presets.ts` # `PreBiSEpWeights` | ÷ Strength | high |
| SHAMAN | RESTORATION | authored | | | low |
| MAGE | ARCANE | authored | | | low |
| MAGE | FIRE | authored | | | medium |
| MAGE | FROST | authored | | | medium |
| WARLOCK | AFFLICTION, DEMONOLOGY, DESTRUCTION | authored | | | low |
| DRUID | BALANCE | wowsims | `druid/balance/presets.ts` # `PreBiSEpWeights` | none | high |
| DRUID | FERAL_CAT | wowsims | `druid/feral_ep.ts` # `CatEp` | ÷ Agility | high |
| DRUID | FERAL_BEAR (variant, `manual`) | wowsims | `druid/feral_ep.ts` # `BearEp` | ÷ Stamina | medium |
| DRUID | RESTORATION | authored | | | low |
| all nine | LEVELING (`manual`, the class `default`) | authored | | | low |

"high" means: a measured upstream preset for that exact tree, converted without judgment calls. It does not mean the advice is right for a player who is not in the preset's situation (see Known weaknesses).

### Conversions applied to every wowsims entry

- **Ratings to percent.** Upstream weights are per rating point. The engine turns ratings into percent first, so each weight is multiplied by the rating that makes 1%: hit ×10, crit ×14, haste ×10, expertise ×10, dodge ×12, parry ×15, block ×5. Defense ×1.
- **Armor penetration.** Upstream weights are per point of the stat. The engine divides the game's number by 10, so the weight is ×10. (Upstream says 5.92 points ignore 1% of armor; the engine's "10 per 1%" comes from another addon. The product stays right either way, because both sides use 10; only the unit's name is in doubt.)
- **Hit and crit, physical or spell.** One rating feeds both on this client, and the engine reports it under both `HIT` and `SPELL_HIT` (same for crit). To avoid counting an item twice, a caster or healer entry files the upstream weight under `SPELL_HIT`/`SPELL_CRIT` only, and a melee, ranged or tank entry under `HIT`/`CRIT` only. Retribution and Enhancement gain from both sides; their single upstream weight already contains both effects and sits under `HIT`/`CRIT`. Consequence: an item with spell-only hit counts 0 for them.
- **Attack power.** Plain attack power reaches the engine as `AP` and `RAP`. Hunter entries carry upstream's ranged weight under `RAP` and upstream's melee weight (none in the Turret preset) under `AP`, so nothing is counted twice.
- **Dropped upstream keys** (no canonical key): `StatPhysicalDamage` (flat weapon damage), `StatArmorNoMods` and `StatBonusArmor` (same weight as armor upstream; the game reports one armor sum), `PseudoStatFeralCombatSkill`, the Holy school hit pseudo-stat on Retribution, and zero weights. Weights under 0.005 after normalizing (upstream 0.01 placeholders) are dropped.
- **Rounding.** Two decimals (one above 10, three below 0.1).
- **Survival floor (authored addition).** A damage simulator gives Stamina no value. Entries whose role is not tank get `STA` 0.15 (melee, ranged), 0.10 (caster) or 0.05 (healer) and `HEALTH` at a tenth of that, unless upstream already has more. The entry's `note` says "ADDED". Remove it by setting `STA_FLOOR` to zeros in the generator.

### The one upstream number that was changed

Retribution's default preset weighs haste at 22.87 per rating with attack power = 1: 3.3 times its own hit weight and 5.6 times the haste weight of the sibling Holy Shock preset (4.06). It may be real in the simulator (a breakpoint in how the Unsealed Wrath talent replays seal hits) but an advisor that follows it would tell a paladin to take 10 haste rating over 95 Strength. The file uses the sibling preset's 4.06. This is a judgment call; an expert should look at it.

### Presets upstream that are not in the file

Available at the same commit if variants are wanted later: Hunter `WeaveEpWeights` and `MeleeEpWeights` (Survival melee styles; they value melee weapon DPS), Rogue `EP_PRESET_COMBAT_DAGS`, Warrior `PreBiSOffensiveEpWeights` (threat-leaning tank), Paladin `HolyShockEpWeights`, Priest `SmiteEpWeights`, `DiscSingleTargetEpWeights`, `HolySingleTargetEpWeights`, Druid `P1EpWeights` (Balance in raid gear) and `HybridEp` (cat and bear mixed). Each would need a spec key and a display name (`design/data-format.md`, section 8).

Upstream has **no** weights for: Mage and Warlock (their spec files have an empty weight set, although the simulations exist), Holy and Protection Paladin, Restoration Shaman, Restoration Druid.

## How the authored level 60 tables were made

Common anchor: stay inside what the same simulator measured for neighboring specs on the same rules, then adjust for the mechanics of the spec. All of this is judgment; none of it is measured.

- **Mage, Warlock (spell damage = 1).** First principles: with roughly 300 spell damage and a 0.8 coefficient, 1 spell damage is about 0.11% damage. 1% hit is about 1.1% damage, so about 10 spell damage, rising with gear; 1% crit is 0.5% to 1% damage depending on crit talents; 1% haste is a little under 1%. The three measured upstream casters (Balance, Shadow, Elemental) give hit 11.4 to 14.5, crit 8.5 to 11.8, haste 7.3 to 12.3 per 1%, Intellect 0.19 to 0.24. Authored values sit inside those ranges: hit 13 (mage) and 12.5 (warlock); crit 12 for Fire, 10 for Frost and Arcane, 10.5 Destruction, 8 Demonology, 5 Affliction (periodic damage does not crit); haste 9 to 9.5 for mages, 6 to 8.5 for warlocks; Intellect higher for Arcane (mana). School keys: a mage tree gets its own school at 1.0 (Arcane 0.9 plus Fire 0.1, because upstream has an Arcane rotation with Fire filler). Warlock splits: Affliction 0.9 Shadow / 0.1 Fire; Demonology 0.5 / 0.5 (upstream has a Fire Brand and a Shadow Brand build); Destruction 0.6 Fire / 0.4 Shadow, read from the spell mix of the upstream Destruction build file (Immolate and Fire nukes lead, Corruption and curses follow). Warlocks get Stamina 0.15 because Life Tap turns health into mana.
- **Healers (healing = 1).** Principle: throughput first, then staying power. The upstream Priest healer presets (same game, same team) fix the exchange rate between healing and regeneration: Intellect 0.2 to 0.3, Spirit 0.1 to 0.25, MP5 0.19 to 0.6, crit 3.2 to 6.7 per 1%, haste 1 to 4.8 per 1%. Each authored healer starts in that range and moves by class mechanics: Holy Paladin has crit 8.5 and Intellect 0.4 (crit heals give mana back, Intellect is crit and mana) and Spirit 0.05; Restoration Shaman has MP5 over Spirit and haste 4.5 for cast-time heals; Restoration Druid has crit 2 (periodic heals do not crit) and Spirit equal to Intellect. `SPELL_DMG` is 0 for healers on purpose.
- **Protection Paladin (Stamina = 1).** Principle: survive first, hold threat second, the same blend upstream uses for Protection Warrior (0.6 × threat weights + 1.15 × damage-smoothing weights). Mitigation stats (defense, dodge, parry, armor, block value) are copied in ratio from the Protection Warrior entry, because both tanks stand in front of the same enemy attack table. The threat part is moved from Strength and weapon DPS to spell damage, Holy damage, Intellect and MP5. Block value is set a little lower than the warrior's (no Shield Slam assumed).
- **Tanks in general.** Avoidance is valued per 1% of incoming damage removed, Stamina and armor as effective health. Resistances are 0 everywhere: their value depends on the fight, which the addon cannot know.

## Leveling (levels 1 to 59)

The simulator has `CharacterLevel = 60` fixed, so nothing below 60 is simulated. The addon is used most while leveling, so every spec carries three authored brackets, `upTo = 19`, `39`, `59`. The base table applies at 60, and between brackets the engine slides the weights in a straight line (a bracket stands for the middle of its level span: `design/data-format.md`, section 5), so there is no step at a bracket's edge or at 60.

Reasoning behind the brackets:

1. **Percent stats are worth less at low level, flat stats are not.** 1 Strength is the same 2 attack power at level 20 and at 60, but 1% crit is 1% of a much smaller damage number. A level 60 character in the simulator's setup does several times the damage of a level 50 questing alone. So every percent key of the spec's level 60 table (hit, crit, haste, expertise, armor penetration, dodge, parry, block, and defense) is multiplied by 0.08 (to 19), 0.22 (to 39), 0.50 (to 59). The factors come from a rough damage curve (about 15, 50 and 120 damage per second at levels 15, 30 and 50, against the simulator's raid-buffed 60), cross-checked on one case: a level 58 warrior at about 170 DPS gains about 10 Strength-equivalents from 1% crit, against 14.2 in the level 60 table.
2. **Hit matters less against same-level targets.** The level 60 hit weights are against a raid target (8% melee, 17% spell to cap). Quest targets are the player's level, where the miss chance is small and soon capped. Hit, spell hit and expertise get a further ×0.6. Spell penetration ×0.25.
3. **Stamina, Spirit and regeneration matter more.** Leveling is a series of fights with rests between them; a larger health and mana pool and faster recovery mean fewer rests, and dying costs more than a slow kill. This comes from the class leveling profile (next point), which values Stamina at 0.5 to 0.6 of the main stat for physical classes and 0.4 to 0.55 of spell damage for casters, more in the lower brackets (×1.15 to 39, ×1.3 to 19; Spirit and health regeneration ×1.25 and ×1.5; armor ×1.5 and ×2).
4. **Weapon DPS dominates for melee and hunters without any extra factor.** 1 weapon DPS is worth about 7 Strength for a warrior at any level, and low-level items carry few stats, so the weapon line decides. The leveling profiles keep the level 60 weapon weights (warrior 7.5, paladin and shaman 6.5, rogue 5.4 main hand / 1.5 off hand, hunter ranged 3.0, druid 3.2).
5. **Wands for casters.** A leveling priest, mage or warlock wands for a large share of every fight early on. Wand DPS (`RANGED_DPS`) is 3.0 / 1.8 / 0.8 for priests by bracket, 2.0 / 1.0 / 0.4 for mages, 2.5 / 1.5 / 0.6 for warlocks, in spell-damage units, and 0 at 60.
6. **Talents commit slowly.** A level 15 "Arms" warrior has five talent points and plays like any warrior. Each bracket is a blend: `(1 - a) × class leveling profile + a × spec table (scaled as in 1 and 2)`, with a = 0.15, 0.45, 0.75. Healer and tank trees blend toward the way that class actually levels (a Holy priest casts damage spells; a Holy paladin swings a weapon), so at low level they value damage stats, and at 40 to 59 mostly their own. Healer tables are in "healing = 1" units; before blending they are scaled by 0.55 (against a caster profile) or 0.45 (against a melee profile), from the classic item budget where 1 healing costs about half of 1 spell damage or 1 primary stat.

The class leveling profile is also the class's `LEVELING` spec: `manual = true`, and the class `default`, so it is what a character with no talent point spent gets. Its base (level 60) table is the 40 to 59 profile with percent stats doubled. Leveling style assumed: Warrior, Paladin, Rogue, Enhancement-style Shaman and cat Druid in melee; Hunter at range; Priest, Mage, Warlock casting; Elemental, Restoration Shaman and Balance, Restoration Druid blend toward a caster profile of their class.

**Proposal if the format can grow later:** the three brackets are coarse and the step at 60 is large (a fresh 60 in quest greens is not the simulator's character). Better would be interpolation between bracket tables by level, and a "fresh 60" table used until the character's gear passes some item level.

## Known weaknesses

- **Everything below 60, and all authored specs, are untested judgment.** Expect some wrong orderings.
- **Level 60 tables assume a raid setting.** Hit is priced below the cap; the engine has no cap logic in stage 1, so hit keeps full value after a character is capped (8% melee, 17% spell on this game version per upstream). Stage 2's hit cap fixes the largest error this causes.
- **Protection Warrior hit** is upstream's value *past* the cap (0.35 per 1%), so a tank below the cap gets no credit for hit. Fury's hit (7.7 per 1%) is likewise measured past the 8% special-attack cap.
- **Spell penetration** has a real weight for Elemental (1.81) and Enhancement (1.15) against upstream's resistant raid target. It is probably too high outside raids.
- **Priest healer presets** carry no measurement note upstream and are round numbers; they look hand-set by the simulator's authors.
- **Beast Mastery and Survival** use weights measured on a Marksmanship build. A melee-weaving Survival hunter is not served (see "Presets upstream that are not in the file").
- **Feral weapon DPS**: upstream values weapon DPS in cat and bear form on this game version (`sim/druid/forms.go`), unlike original classic. Taken on trust; the game check should confirm a staff's DPS changes cat damage.
- **Ratings convert the same at every level**: confirmed from the client's own combat ratings table, which holds one value per rating for every level from 1 to 123 (`Tools/tests/fixtures/client_combat_ratings.txt`). Not an assumption any more.
- **Talents are not modeled.** A Fire mage with no crit talents, a warlock build with other schools, or a paladin without the preset's talents gets the tree's default table.
- **Weapon speed, procs, set bonuses, on-use effects** have no weight.
- **`OH_DPS` for specs that cannot dual wield** comes into the low brackets through the class profile (warrior, hunter). The engine now tries a one-hand weapon in the off hand for a character who can dual wield (a warrior from level 20, a hunter from 20), and only for such a character, so the weight is used where it applies.
- **The upstream simulator is young and changing** (the commit used is from the day of generation, and several presets say "placeholder until the Phase 1 gear is known"). Regenerate when upstream settles.

## What an expert player should review first

1. Retribution haste (changed from upstream) and whether hit 28.5 Strength per 1% is believable for them.
2. The 0.08 / 0.22 / 0.50 percent-stat factors and the Stamina and Spirit levels in the leveling profiles: do bracket 39 and 59 pick the gear a leveler would?
3. Mage and Warlock crit and haste per tree, and the Warlock school splits.
4. Holy Paladin, Restoration Shaman and Druid: Intellect, Spirit and MP5 against healing.
5. Protection Paladin as a whole; Protection Warrior hit and expertise (20.4 Stamina per 1% expertise is upstream's number).
6. Wand DPS weights by bracket.
7. Hunter: is the Turret table right for Beast Mastery, and should Survival default to it?

## Regenerating

The generator is three small Python scripts (standard library plus `lupa` for the check). They were written in a session scratch folder, which does not survive; the lead builder should copy them into the repository (suggested `Tools\data\`) if regeneration is wanted:

- `extract.py <checkout> <upstream.json>`: reads the preset files of a wowsims/forever checkout as text (nothing from the checkout is executed) and writes every `Stats.fromMap` weight set to JSON.
- `gen.py <upstream.json> <commit> <Weights.lua>`: holds the spec list, the conversions above, the authored tables, the leveling profiles and the bracket rule; writes `Weights.lua`.
- `check.py <Weights.lua>`: structure checks (27 specs present, canonical keys only, no negative or absurd weights, tabs auto-pick the right spec, no double counting of hit and crit) and 52 item-pair checks. The item stat tables in it are written by hand from memory of classic-era items or are labeled synthetic; they are illustrations, not client data.

Steps:

1. Clone `https://github.com/wowsims/forever` into a new, empty directory outside the repository; note the commit; confirm `LICENSE` is still MIT.
2. `python -I extract.py <checkout> upstream.json`. A preset that was renamed or removed upstream shows as a missing key in the next step.
3. `python -I gen.py upstream.json <full commit hash> Data\Weights.lua`
4. `python -I check.py Data\Weights.lua` and `python -I ~/tools/compile51.py Data`
5. Update the commit in this file and in `CREDITS.md`, and re-read the upstream comments above each preset: they say what gear and talents a preset was measured on.
