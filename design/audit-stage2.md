# Glowey's Gear: independent audit of stage 2, before its first in-game run

Audited 2026-11-20, read-only, at commit 394125f (the four commits on top of 426592d), against the
client's UI source and generated docs (branch forever, commit 3d8abb1), the client's GlobalStrings
database (read with `Tools\client_facts.py`'s reader), Daylight UI 2.1.2 as installed, Polestar as
installed (read only to verify the calls made into it), and the owner's Addon Skins
(`Choices.lua`, `Packs\Polestar.lua`). CheapUpgrades was not opened. Findings that say "probe"
were reproduced by running the plugin's real engine files in the test harness with a scratch
script (nothing in the repository was changed).

**Tests.** `python -I Tools\tests\run.py`: 13 files, 0 failed (11,080 checks).
`Tools\locales.py`: 163 keys, 6 languages, 0 findings. `compile51.py`: 40 files, 0 failed.

**Short answer.** Nothing was found that would throw, taint a secure path, or cost frame time.
Every game call, event name, Daylight UI call and both Polestar calls check out against their
sources. The findings are all in what is said: five places where the advice or the hand-over
would be wrong or missing for a real character. Four of them are small code changes
(M1, M2, M4, M5). The owner can try it as it is; a short fix pass first would save a round trip,
because M4 and M5 will show in the planned in-game check itself.

## Findings

| # | Sev | Where | What |
|---|---|---|---|
| M1 | Medium | `Compare.lua:255-263`, `:363-371`; `Rank.lua:312`, `:327-328` | Hit cap when both hands change at once: owned hands are valued one piece at a time, a new pair or two-hander together. A pair identical to the worn one reads "Both Together +40%"; a two-hander of equal worth reads as an upgrade. |
| M2 | Medium | `Compare.lua:242-244`, `Core.lua:310` | A hunter holding two one-handers gets the dual wield figure (27%) for ranged hit, so the cap never applies. |
| M3 | Medium | `Compare.lua:242-244`, `:363-371`, `:441` | The cap is fixed by what is worn, not by what the candidate would make: a dual wielder with 12% hit sees a two-hander as +2 where it is -40; a two-hand wearer's dual-wield pair is capped at 8. |
| M4 | Medium | `Quest.lua:102-103` | When the choices are not there 0.3 s after the page opens (count 0), nothing looks again unless `QUEST_ITEM_UPDATE` comes. Daylight UI's own notes say both happen on a first visit. The line then never comes. |
| M5 | Medium | `Overlap.lua:119-141` | "Ours" switches Polestar's arrows and tooltip line off without asking whether ours shows there. Polestar never draws on Daylight UI's bags and ours draws nowhere else, so with Daylight UI's bags off (or Baganator), or our own switches off, nothing marks upgrades. |
| L1 | Low | `Rank.lua:354-361` | A two-hander as the Main Hand pick is added to the Off Hand pick (the comment says it is not), so a pair that beats the two-hander is hidden. |
| L2 | Low | `Rank.lua:495`, `:506` | `hands.byKey` keeps every wieldable weapon of the house, not the 16 per hand: 600 entries for 300 one-handers. |
| L3 | Low | `Compare.lua:234-241` | Hit from enchants on worn gear (a scope), set bonuses and rating buffs is not in "have": the room under the cap is overstated by that much. |
| L4 | Low | `Game.lua:297-307`, `CHANGELOG.md` | "Your hit is added up from what you wear and your talents": school-specific spell hit talents are very likely not in `GetSpellHitModifier`. Casters keep counting hit they do not need. |
| L5 | Low | `Compare.lua:122`, `:129` | 27% and 24% are the caps for a dual wielder's normal swings; special attacks cap at 8% and 5%. Hit between the two counts at full weight. |
| L6 | Low | `Core.lua:305-317` | The talent share is read at login and on talent or level events only, and saved: a hit buff at that moment stays counted, across sessions too. |
| L7 | Low | `Alert.lua:232-238` | What is remembered does not know Max Price, Smallest Gain, Best Armor Only or the owned gear: change one and the next repaint can say "New best upgrade for sale" about an old listing. News found inside the quiet minute is dropped, not kept. |
| L8 | Low | `Quest.lua:141-142`, `:107-108` | The line is said again every time the same page is opened. A choice that never gets a link (a currency) silences the whole page after 5 s. Polestar's own "Best pick" stays on and may name another reward. |
| L9 | Low | `Overlap.lua:110-117`, `:132-137` | What was taken is kept per account; Polestar's settings are per Polestar profile. Reversal on a second profile restores the first profile's value and leaves the first one off. |
| L10 | Low | `Overlap.lua:336-357` | The question is asked with Show Gear Advice off; `Apply` at 1 s and 6 s after login can run in a fight. |
| L11 | Low | `Overlap.lua:95-108`, `Marks.lua:315` | With Leave Bag Marks to Them on, every bag slot update builds a list and two closures to learn that a rival is loaded. |
| L12 | Low | `Window.lua:988-998`, `:849` | Check Prices asks about the pair's main hand only while the row is closed; the pair's two items never carry the "*" for an uncounted effect. |
| L13 | Low | `Compare.lua:265-275` | Stage 1 change not in the notes: a dual wielder's worn off-hand one-hander now counts in "typical" with its off-hand score, so percents with a tiny baseline shift a little. |
| L14 | Low | `design\in-game-check.md:130` | Step 5 expects Polestar's arrows "back" in the bags. In Daylight UI's bags they were never there (M5). |

Counts: **0 High, 5 Medium, 14 Low.**

## What was verified and holds

- **The three hit calls.** `GetHitModifier`, `GetRangedHitModifier`, `GetSpellHitModifier` exist,
  return one non-nil number, are not protected, and are marked `SecretWhenUnitStatsRestricted`
  (`PlayerScriptDocumentation.lua:533-541`, `:946-954`, `:1113-1121`). `Game.HitModifiers`
  passes each through `issecretvalue` and `Core.lua:306` does not call in a fight. The unit is
  percent: the character sheet adds them to `GetCombatRatingBonus` and prints the sum with
  `%.1F%%` (`Camelot\PaperDollFrameStats.lua:524-527`, `:548`).
- **Double counting of gear hit is ruled out by the same lines.** The sheet shows
  rating share + modifier; if the modifier held the rating share, the sheet itself would count it
  twice. Gear hit arrives as a rating (`ITEM_MOD_HIT_RATING` family in the client's string
  database), 10 per 1% at every level (`Tools\tests\fixtures\client_combat_ratings.txt:8-10`).
- **The cap figures.** Read again from the string database: `CR_DEFAULT_HIT_CAP_TOOLTIP` has
  8.00 / 17.00 and 5.00 / 4.00; `CR_ROGUE_HIT_CAP_TOOLTIP` adds 27.00 and 24.00 Dual Wielding.
  The pet tooltip repeats 8 / 17 / 5 / 4. The 9.0 in `PaperDollFrameStats.lua:460` is in a table
  the function never reads.
- **Three characters walked through the engine (probe).**
  1. Level 60 Arms, two-hander, 3% from talents and 5% on gear (exactly 8 of 8): a ring with 1%
     hit and 7 Strength over a 6 Strength ring gains 1 (the hit counts for nothing); a 40
     Strength helm over a helm with 2% hit and 10 Strength is -12.8 (the worn 2% counts in full,
     2 x 21.4 + 10); a helm with 3% in place of the 2% one gains 0. Over the cap (10%): the 2%
     helm's hit is worth 0 and its base is its 10 Strength. All correct.
  2. Level 60 mage, 16% spell hit worn, cap 17: a neck with 20 general hit rating gains one
     percent's worth (12), not two. Correct. Melee hit is not weighted, so it is not touched.
  3. Level 60 hunter, two one-handers, 3% from talents and 5% worn: cap reads 27, a 3% neck
     gains 34.2 where it should gain 0. This is M2.
  A level 42 priest (healer weights with spell hit below 60): cap 4, no saved talent share, no
  error. A spec with no hit weight: `ctx.hit` is nil and every score is as in stage 1.
- **Pairs are bounded.** At most 16 entries per hand, at most 256 pairs tried per call, one call
  per paint (once a second at most while scoring). No cross product over the house.
- **Wieldability.** Two-handers are in no pair; an off-hand-only weapon needs dual wield
  (`Score.lua:147-151`); a one-hander is an off hand only for a dual wielder; shields by class;
  one listing is never both hands (`Rank.lua:325`); one unique-equipped item is never both
  (`Compare.lua:364`). The client does tell main-hand-only and off-hand-only weapons apart
  (`INVTYPE_WEAPONMAINHAND`, `INVTYPE_WEAPONOFFHAND`), and `GROUP_OF` files them.
- **Pair and corrections.** A half that sold sets `gone` on both of its entries
  (`Rank.lua:533-539`) and the next paint drops or replaces the pair. The pair's own row only
  opens; its two rows each search their own item.
- **Quest calls.** `GetNumQuestChoices`, `GetQuestItemLink("choice", i)`,
  `GetQuestItemInfo("choice", i)` (count is the third return) are what the client's quest frame
  calls (`Mainline\QuestInfo.lua:525-526`, `:647`; the .toc loads the Mainline file). The three
  events exist. The plugin listens on a frame of its own and touches nothing of `QuestFrame`
  or its buttons: no taint path.
- **Polestar.** `Polestar` is the addon's global table (`Core\Init.lua:10-11`); `Get(path)` and
  `Set(path, value)` are plain functions, not methods (`:966`, `:1002`); `gear.bagArrows` and
  `gear.tooltip` are registered defaults (`Gear\Gear.lua:104-110`), read at `Gear\Bags.lua:58`
  and `Gear\Tooltip.lua:157`. `Set` stores nil for a value equal to the default, so putting
  `true` back restores the stored state exactly. A `gear.` change repaints on its own
  (`Gear\Gear.lua:1574`). Nothing else of Polestar's is written.
- **Clean room.** CheapUpgrades and Forever Leveling BiS appear once each, as a folder name in
  `Overlap.lua:60-61`. Nothing of Pawn's is called. No text or table in the stage 2 files
  follows Polestar's; the two setting paths are the interface.
- **Dialog timing.** The plugin's own welcome shows 4 s after login and sets the shared busy
  flag; the overlap question first looks at 8 s, waits while any Daylight dialog or guide is
  up, then needs 6 quiet seconds. The frame names it waits for exist in Daylight UI 2.1.2
  (`InstallerUI.lua:291`, `Tour.lua:42-43`, `Options\Widgets.lua:4411`). It sets its own busy
  flag while shown, so the other plugins' guides wait for it.
- **Disabled addons.** A listed addon that is installed but disabled is not loaded, is no
  rival, and ours shows.
- **Text.** New labels are Title Case, sentences sentence case, American English; no new option
  description is longer than the longest stage 1 one in any of the six languages.
- **Performance.** No new per-frame script. Per item scored: one extra score for a usable
  weapon. Saved variables: two numbers and at most 15 slot entries per character, a handful of
  flags per account.

## Details

### M1. Two pieces leaving at once

`Compare.Context` values every owned piece "as the last one put on" (`:255-263`): for a main
hand, with the off hand still on. `Compare.PairScore` (`:363-371`) and the two-hander branch
(`:441`) take both hands off first. The two views differ whenever both worn hands carry hit and
the total is over the cap by less than their sum.

Probe, weights Strength 1, hit 10 per 1%: main hand (10 dps, 1% hit) and shield (5 Strength, 1%
hit) worn, 7% elsewhere, 9 of 8. Each hand's hit is valued 0, so the set is 25; together they
hold one useful percent, so it is really 35.
- A two-hander worth exactly 35: `gain 10, pct 40`.
- The same two items for sale under other names: no single row, and `Rank.Set` returns
  `gain 10, pct 40`. The window would show "Both Together +40%" for a pair no better than the
  one held.

With Arms weights the false gain is 21.4 points per percent. Fix: when both hands leave, value
the old set the way the new one is valued (main with both off, off with the main's hit as
`extra`), in `SetValue` and in the two-hander branch.

### M2. Hunters with two one-handers

`Core.lua:310` makes a hunter's "melee" share the ranged one, which is right. But
`Compare.lua:243` then sees a weapon in slot 17 and takes the dual wield figure. Ranged attacks
do not dual wield. Probe: 8% of 8, a neck with 3% hit gains 34.2. Two one-handers is an ordinary
hunter setup, so for them the cap does nothing. Fix: no dual wield figure for a hunter.

### M3. The cap follows what is worn

`ctx.hit.cap` is set once from slot 17. Probe: a warrior with two one-handers and 12% hit, cap
27. A two-hander with slightly more damage reads `gain 2`. With it equipped the cap is 8 and
4% of worn hit is lost: with the probe's weights that is -40. The other way, a two-hand wearer
at 8% looking at two one-handers has the pair's hit, and nothing else's, capped at 8. The
design note lists neither. Fix or say so: when the candidate changes whether an off-hand weapon
is held, use the cap of the result and charge or credit the hit worn elsewhere.

### M4. Choices that arrive late

`Quest.Look` returns at `n < 2` with no timer (`:103`); only the "a link is missing" case
retries (`:123-127`). Daylight UI, on this client: "On a first visit the page arrives before
its choices. GetNumQuestChoices reports 0 until they load" (`DaylightUI\Npc\Window.lua:210-216`)
and "QUEST_ITEM_UPDATE doesn't always follow" (`:750-751`). In that case the one look at 0.3 s
sees 0 and nothing speaks. Fix: treat a count under 2 like a missing link for the first few
tries.

### M5. Taking Polestar's switch when ours shows nothing

Polestar's bag arrows are drawn on the client's bags, Baganator, BagSmith and EllesmereUI Bags
(`Polestar\Gear\Bags.lua:18-35`); Daylight UI's bags are not among them. Ours is drawn only
through Daylight UI's bag corner call. So on bags the two never meet in one window. `Apply`
looks only at `yieldBags` / `yieldTips` and the answered flag (`:122-134`). Cases where "ours"
(the default answer) leaves no mark at all:
- Daylight UI's Bags module off, or Baganator in use (stage 1 L12: our mark does nothing there);
- Bag Slots, Item Tooltips or Show Gear Advice switched off in our options;
- Daylight UI's Tooltip module off.

Fix: take a switch only while ours is really shown on that surface (module on, our own switch
on), and give it back when that stops. The dialog text and the in-game check's step 5 need the
same correction.

### L1. The threshold with a two-hander pick

`Rank.lua:356-360` runs Main Hand then Off Hand: a two-hand pick sets `apart` to its gain and
the Off Hand pick is then added. Probe: mace and shield worn; for sale a two-hander (+30), a
shield (+10), a mace that with the shield is +35. Threshold 40, pair hidden, though both picks
cannot be held together and the pair beats the two-hander. Intended: the larger of (two-hander)
and (one-hand main pick + off pick).

### L2 to L6. Smaller things in the hit cap and pairs

- L2: `hands.byKey[key] = e` is set before the short lists decide (`Rank.lua:495`), and the
  entry stays when it is pushed out. For a level 60 warrior in a 20,000-item house that is every
  usable weapon, three to five small tables each. Keep the entry only while it is in a list.
- L3: `have` is summed from links (`Compare.lua:235-241`), and the stats of a link leave out
  enchants. A hunter with a +3% scope is counted 3% short. An alternative that needs no table:
  at the read, keep (sheet total - hit summed from the worn links) as the share not from items.
- L4: `GetSpellHitModifier` reports auras that raise spell hit as a whole. Talents that lower
  one school's resist chance are spell modifiers and were not in it on earlier clients. Not
  settled for this one (see below). The effect is the stage 1 behavior, not a new error.
- L5: stated in the design note as "in practice no cap". The weights hold one hit value.
- L6: stated as a limit. It also survives a relog, since `c.hit` is saved.

### L7. What the alert compares with

`c.seen` records house, spec and mode. `Window.Rearrange` after a Max Price or Smallest Gain
change does not call `Alert.Check`, but the next corrected price does (`Window.lua:566`), and a
slot whose pick changed to a dearer, better item is "news". The same after selling or banking
an owned piece. And `c.seen` is written (`:235`) before the 60-second test (`:238`), so a
second slot's news inside the minute is remembered as seen and never said.

### L9. Per account against per profile

Addon Skins notes that Polestar's settings "are per Polestar profile"
(`Packs\Polestar.lua:455`). `took["Polestar:bags"]` is one value per account. Character A (profile
X) answers "ours": X is switched off, took = true. Character B (profile Y) logs in: Y is switched
off too. B reverses: Y gets `true`, took is cleared; X stays off with nothing left to restore it.

## Tests' blind spots

- `Game.HitModifiers` and `Game.QuestChoices` are replaced by `mocks.lua`; the real functions
  in `Game.lua` run in no test (`test_game.lua` does not load stand-ins for the three hit calls
  or the quest calls).
- The mock quest world always has its choices at once. Count 0 first, then choices with no
  `QUEST_ITEM_UPDATE`, is not modeled (M4).
- No pair or two-hander test has hit on both worn hands (M1); no hit test uses a hunter (M2) or
  a candidate that changes the dual wield state (M3).
- No test has a two-hander as the Main Hand pick together with an Off Hand pick (L1).
- The Polestar stand-in has the right call shape (`Get(path)`, `Set(path, value)`), but stores
  `true` as `true` and has one profile (L9).
- `Overlap.Show` and `Build` (Daylight UI's widgets) and the options button run in no test.
- `Alert.Check` is only called with hand-made views; no test changes a setting between calls.

## Cannot be settled without the game

1. Whether `GetHitModifier` is settled at Daylight UI's "Login", or only later (the read is
   repeated on talent events and at entering the world, so a late value should still arrive).
2. Whether school-specific talents show in `GetSpellHitModifier` (L4).
3. The warrior and hunter Hit Chance tooltips. `CR_WARRIOR_HIT_CAP_TOOLTIP` and
   `CR_HUNTER_HIT_CAP_TOOLTIP` exist but have no text of their own in the readable part of the
   database; most likely they share the rogue text. The design note cites only the default and
   rogue ones.
4. 8% or 9% against bosses. The tooltip says 8.00; the unused table in the same file says 9.0.
5. Whether the quest tooltip's link gives the same `Stats.Key` as `GetQuestItemLink`, on which
   "Best reward of this quest for you." depends.
6. Whether `QUEST_FINISHED` ever comes after the next page's `QUEST_COMPLETE` in a quest chain.
7. Whether the overlap window opens above Daylight UI's options when Ask Again is pressed.
8. Whether the chat line's built link (`Alert.Link`) shows the right color and opens on click.

## In-game check, in order

1. `/gear debug`: the `hit:` line against the character sheet's Hit Chance tooltip. On a hunter
   with two one-handers, note the "of 27" (M2). On a mage or warlock with a school hit talent,
   note whether "not from gear" shows it (L4).
2. Hover the Hit Chance line on a warrior and a hunter and read the cap text (items 3 and 4).
3. A character at or over the cap: hover a hit item in the bags; its row should score as if it
   had no hit.
4. Hand in a quest with a choice of gear at an NPC not visited this session. Does the line come
   (M4)? Does the best reward's tooltip carry the extra line? Open the same page twice (L8).
5. Upgrades for Sale with the list scored: look for "Both Together". If it shows, compare the
   two items with what is held; with hit on both worn hands, expect M1.
6. Press Check Prices, then raise Max Price, then search any listed item: note whether "New best
   upgrade for sale" speaks about a listing that was there all along (L7). Click its link.
7. With Polestar loaded: answer the question with Apply. `/gear debug` shows "switched by us".
   In Daylight UI's bags only ours can show either way. Switch Leave Tooltips to Them on and
   hover an item: Polestar's line is back, ours is gone. Switch it off again.
8. Press Ask Again with the options open; with a controller, move through the two switches.
