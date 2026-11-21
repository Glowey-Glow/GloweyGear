# Glowey's Gear: independent audit before the first in-game run (stage 1)

Audited 2026-11-20, read-only, against the client's UI source and generated docs (branch forever,
commit 3d8abb1), Daylight UI 2.1.2 as installed, the owner's Essentials / Recipes / Fishing plugins,
Polestar and Guildy (for how item stats really arrive on this client), and real item links in the
saved variables. CheapUpgrades and its saved variables were not opened.

**State audited.** The plugin changed on disk while it was being read: at 12:39 a pass rewrote 20
files (a `/gear` slash command was added in `Core.lua`, and `/dui gear` in texts became `/gear`). Line
numbers below are from the files after that pass. Tests were run before and after it.

**Tests.** `python -I Tools\tests\run.py`: 11 files, 0 failed (7,737 checks), both times.
`Tools\locales.py`: 111 keys, 6 languages, 0 findings.

**Not installed yet.** There is no `DaylightGear` folder or junction in
`D:\World of Warcraft\_forever_\Interface\AddOns`. It will not load until it is linked there.

**Short answer.** Nothing was found that would throw at login, taint a secure path or call a scan
behind Daylight UI's back. Registration, the options spec, every game call's name, argument order and
return position, and every Daylight UI internal check out against 2.1.2. What is wrong is in the
advice itself: one stat key that is certainly unmapped, and several places where the number or word
shown would mislead. One short fix pass (H1, M2, M3) is worth doing before the run; the rest can
ride along with what the run finds.

## Findings

| # | Sev | Where | What |
|---|---|---|---|
| H1 | High | `Stats.lua:68` | Healing-only bonus arrives as `ITEM_MOD_SPELL_HEALING_DONE` (no `_SHORT`) on this client; only the `_SHORT` spelling is mapped, so healing gear scores 0 for healers. |
| M1 | Medium | `Stats.lua:264`, `Game.lua:34` | `C_Item.GetItemStats` does not list every equip bonus on this client (Polestar ships an item table to fill them); the plugin has no fallback, so such items are under-scored. |
| M2 | Medium | `Compare.lua:217` | Percent is gain over the replaced item's score with no floor: a small baseline gives "+1000%", "+19900%". |
| M3 | Medium | `Window.lua:119`, `Marks.lua:127` | A worn item that scores 0 makes the window row read "Empty Slot" although the slot is not empty. |
| M4 | Medium | `Compare.lua:57`, `:194-207` | Dual wielders: a one-hand weapon is only tried in the main hand, so an off-hand upgrade reads "No better than your Main Hand". |
| M5 | Medium | `Core.lua:265-272`, `:297` | Talent trees may not be readable at Daylight UI's "Login"; nothing listens to `TRAIT_CONFIG_LIST_UPDATED` or `PLAYER_ENTERING_WORLD`, so a first session can stay on the default (Leveling) weights. |
| M6 | Medium | `Stats.lua:193-209` | `Stats.Key` keeps the item context (field 12) and modifiers (fields 15 on): the same item with the same roll gets several keys, so it is not merged to its cheapest listing and can fill the alternatives. |
| M7 | Medium | `Stats.lua:45-112`, `Data\README.md:20`, `design\data-format.md:105` | The stat-key and rating tables follow Polestar's (GPL-3) entry for entry and cite Forever Leveling BiS (All Rights Reserved); `Data\README.md` says neither was used in any way. Owner's call. |
| L1 | Low | `Stats.lua:155`, `Game.lua:34`, `:54`, `:190` | Stat values, quality, level, price and slot counts are used without the secret check the file's header promises. |
| L2 | Low | `Stats.lua:60` | "+X attack power" feeds AP and RAP; hunters weight both, so it counts twice (0.1 + 0.4). |
| L3 | Low | `Data\Weights.lua` (Paladin Holy brackets) | Below 60, Holy has CRIT and SPELL_CRIT weights; a plain crit rating feeds both. |
| L4 | Low | `Stats.lua:230-285` | A record is kept for the session once read; if the game answered with an incomplete stat table, the wrong score stays until 12,000 records force a reset. |
| L5 | Low | `Core.lua:272`, `Window.lua:286`, `Rank.lua:130` | Every `GET_ITEM_INFO_RECEIVED` (thousands during a scan) rebuilds the owned context every 0.3 s and retries every unloaded listing; an item that never loads keeps the loop alive while the window is up. |
| L6 | Low | `Market.lua:85` | Items get 60 s at most to load; Daylight UI allows 120 s. On a cold cache gear rows are dropped as "item never loaded". |
| L7 | Low | `Market.lua:458` | `("%d"):format(copper)` overflows at 2^31 copper (214,748 g) in stock Lua 5.1; such a row is then dropped on read. Harmless, unverified on the client. |
| L8 | Low | `Market.lua:703-712` | With DaylightMogul owning the house, or the game's own window in use, our button spends the account-wide 15-minute scan that the other addon then cannot use. |
| L9 | Low | `Marks.lua:452-456` | Four widgets per slot (one per corner) means four frames per bag and bank slot; three never show. |
| L10 | Low | `Core.lua:379` | Dropdowns without `order` sort by label: "Arms, Auto, Fury..." puts Auto second or later. |
| L11 | Low | `Locales\deDE.lua`, `frFR.lua`, `esES.lua` | Dropdown choices longer than about 108 px are cut: "Am meisten pro Gold", "En haut à gauche", "Montée de niveau". |
| L12 | Low | `Core.lua:402-413` | Item Tooltips, Bag Slots and Bag Corner stay switchable when Daylight UI's tooltips or bags are off (or Baganator is on), where they do nothing. |
| L13 | Low | `Window.lua:143`, `GearGuide.lua:80` | "Full Scan" in one sentence, "Full scan" in another; Daylight UI's button reads "Full scan". |
| L14 | Low | `README.md:19`, `ARCHITECTURE.md:187`, `:249` | README says `/gear` "says which spec" (it opens the window); ARCHITECTURE says the default corner is top right (the code: bottom right). |
| L15 | Low | `Marks.lua:29-38`, `:404-406` | Line references into `DaylightUI_Tooltip\Tooltip.lua` are about 30 lines stale in 2.1.2 (comments only). |
| L16 | Low | `Core.lua:83-93` | A setting read before Daylight UI enables the module caches the default until the next setting change. Not reachable in the paths read, but nothing prevents it. |
| L17 | Low | `Rank.lua:50`, `Core.lua:71` | "Most per Gold" is the default: a 4% upgrade for 20 silver outranks a 160% upgrade for 3 gold 50. By design; worth a look in play. |
| L18 | Low | `Spec.lua:216-262` | Weights slide to the level 60 raid table: at 58 Arms hit is 18.4 per 1%, three times the 40-59 bracket's own 5.81. |
| L19 | Low | `Core.lua:354-358` | `/gear` is free among the installed addons that could be checked; CheapUpgrades was not opened, so a clash there is unknown. |
| L20 | Low | `Game.lua:205` | Timing uses `debugprofilestop`; another addon calling `debugprofilestart` resets it mid-read (waits get longer, nothing breaks). |

Counts: **1 High, 7 Medium, 20 Low.**

## Details

### H1. The healing key without `_SHORT`

`Stats.lua:68` maps `ITEM_MOD_SPELL_HEALING_DONE_SHORT` only. Guildy, which runs on this client and
reads the same call, handles the bare spelling in three places and names it:
`Guildy\Core\Upgrades.lua:90-94` ("a key the game gives without _SHORT (ITEM_MOD_SPELL_HEALING_DONE)"),
`Guildy\Game\Gear.lua:449-450`, `Guildy\Core\StatWeights.lua` header.

Run through the engine with the real weights: a ring whose stat table is
`{ ITEM_MOD_SPELL_HEALING_DONE = 40 }` scores 0.00, is filed under `Stats.unknown`, and the verdict
for a character wearing anything is "-100%" / "No better than your Finger". For Holy, Discipline and
Restoration, HEAL is the weight-1 stat, so most of their level 40+ gear is judged wrong.

Fix: map both spellings, and in `Stats.Normalize` try `key .. "_SHORT"` for any `ITEM_MOD_*` key
with no entry before counting it unknown. `/gear debug` already prints the unknown list, which is
how the run confirms it.

### M1. Equip bonuses the stat call leaves out

Polestar's own description of this client: "Item stats: the client's C_Item.GetItemStats ... when it
answers; equip bonuses it does not list and everything for uncached items come from
Polestar.ItemDB" (`Polestar\Gear\Gear.lua:71-73`), and "Stats the client always reports when it
reports an item at all; for the rest (equip bonuses) ItemDB fills what the client left out"
(`:539-541`, merged at `:612-618`). Glowey's Gear reads the call and nothing else.

How much is missing is not known from files: Polestar also maps rating and spell power keys from the
same call (`:512-527`, `:582`), so many bonuses do arrive. But any that come as a spell effect
("Equip: Increases damage done by Fire spells") would be absent, the item under-scored, and the
row would say "No better than your Chest" with nothing to hint that a stat was not counted.
`Stats.unknown` cannot see a key that never arrives. The run below settles it with three items.

### M2 and M3. The percent, and "Empty Slot"

There is no division by zero: `Compare.lua:216-220` only divides when `base > 0`, and no weight in
the data is negative (checked: 0 of all tables), so no base is below zero.

But `pct = gain / base * 100` has no floor on `base`. From the engine with real weights:

| Case | score | base | shown |
|---|---|---|---|
| Level 60 mage, ring with 10 hit rating and 9 spell power, over a ring with 6 Int, 5 Sta | 22.00 | 2.00 | +1000% over your Finger |
| Level 60 warrior, +15 Str neck over a +5 health neck | 15.00 | 0.07 | +19900% over your Neck |
| Level 22 warrior, mail chest of the Bear over a plain mail chest | 13.49 | 5.16 | +162% over your Chest |

Rings, necks, cloaks and trinkets carry one or two stats, so three- and four-digit percents will be
normal, and Smallest Gain to Show (3%) filters almost nothing. The sentence is true ("over your
Finger") but reads as a claim about the character. Options: cap the wording ("more than double"),
or divide by the score of all worn gear.

When the replaced item scores exactly 0 (a Spirit neck on an Arms warrior), `out.empty` is true
with `out.replaces` set. The tooltip handles it ("Better than your Neck", `Marks.lua:115`), but the
window's `GainText` (`Window.lua:119`) and `Marks.Text` (`Marks.lua:127`) both print "Empty Slot".
The slot is not empty. Use a second phrase when `row.replaces` is there.

### M4. One-hand weapons for dual wielders

`Compare.lua:57` files `INVTYPE_WEAPON` under MAINHAND, worn or candidate, and the off-hand pool
only takes `INVTYPE_WEAPONOFFHAND`, shields and held items. A rogue with a 28 dps sword in the main
hand and an 18 dps one-hand sword in the off hand, looking at a 26 dps one-hand sword: base 151.05,
score 140.26, verdict "No better than your Main Hand". It would replace the off hand. The file's
header declares this as a stage 1 limit, but the player only sees the flat sentence. Most rogue and
many Fury and Enhancement weapons are `INVTYPE_WEAPON`. Until stage 2, either say nothing for a
one-hander that beats the worn off hand, or word it as main hand only.

The paladin cases come out right: a 36 dps two-hander over mace plus shield is "+34% over your Main
Hand" (base is the pair); with the two-hander worn and mace plus shield in the bags, a better shield
is correctly no upgrade; an off-hand weapon gives no row (`dualwield`).

### M5. Spec detection at the first login

`Core.lua:297-301` reads the trees once at Daylight UI's "Login" (`PLAYER_LOGIN`). After that only
`TRAIT_CONFIG_UPDATED`, `PLAYER_TALENT_UPDATE`, `ACTIVE_TALENT_GROUP_CHANGED` and `PLAYER_LEVEL_UP`
ask again. If `C_SpecializationInfo.GetCombatConfigIDForSpecGroup` has no config at `PLAYER_LOGIN`
(on the mainline family the list arrives with `TRAIT_CONFIG_LIST_UPDATED`, documented at
`SharedTraitsDocumentation.lua:867`), `Game.Trees()` is nil, `Spec.Detect` answers the last saved
spec, and on a first session there is none: the class default, "Leveling", at any level, until a
talent changes. `/gear` would read "Scoring gear for Leveling, level 60." Whether the config is
there at login cannot be told from files. Cheap insurance: also listen to
`TRAIT_CONFIG_LIST_UPDATED` and `PLAYER_ENTERING_WORLD`.

### M6. Keys split by context and modifiers

Real links from the saved variables (1,973 distinct, none from CheapUpgrades):

```
item:7444::::::::33:1489:::1:12751::::::              Sentinel Boots of the Bandit
item:7448::::::::33:1489::1:1:12751::::::             field 12 = 1 (item context)
item:7445::::::::33:1489::1:1:12751:1:28:4522:::::    plus one modifier, type 28
item:6694::::::::30:1489::1::1:28:5246:::::           no roll, context and a modifier
```

143 of them carry a context, 81 a type-28 modifier whose value differs by where the item came
from. `Stats.Key` blanks fields 2, 9 and 10 and keeps the rest, so the three Sentinel shapes give
three keys for one item with one roll (run: `7445::::::::::::1:12751`,
`7445:::::::::::1:1:12751`, `7445:::::::::::1:1:12751:1:28:4522`). If Auction House links carry
these fields, `Market.lua` keeps each as a separate item, "cheapest listing per item" no longer
holds, and one item can take several of the ten alternative rows at different prices. The score is
the same for all. Blanking field 12 and the modifier block (or keying on ID plus bonus IDs) fixes it;
the run's "a rolled link" debug line shows whether the house's links have them.

### M7. Where the stat tables come from

`Stats.lua:45-112` (`PLAIN`, `RATING`, `RATING_PER_PERCENT`) has the same entries, in the same order
and grouping, with the same numbers (14, 10, 10, 10, 10, 12, 15, 5), as
`Polestar\Gear\Gear.lua:484-527` (`CLIENT_STATS`, `RATINGS`). `design\data-format.md:9-10` and
`:105-149` say so openly and also cite Forever Leveling BiS 1.4.2 line by line. Polestar is
`GPL-3.0-only`; Forever Leveling BiS is All Rights Reserved; Glowey's Gear is All Rights Reserved and
calls itself a clean-room work. `Data\README.md:20` states that Polestar and Forever Leveling BiS
were "Not used in any way", which is true of the weights and not of this table.

The content is facts about the client (which keys a call returns, the game's rating table), and no
code was carried over. Still, the selection and order are Polestar's, and five ratings are
single-sourced from it. Suggest: re-derive the list from the client (the run's unknown-key report
and `gametables/combatratings.txt`, which Polestar names as its source), reorder it your own way,
and correct the README sentence.

Other addons are named in comments only: Polestar (`Game.lua:152`), LFGForever (`Game.lua:107`),
Auctionator (`Market.lua:33-39`, `:61`), Pawn, Can I Mog It and Simple Item Levels (`Marks.lua:48`,
`:247`). No player-facing string names or imitates another addon. Wording could not be compared
with CheapUpgrades, which was not opened.

### Low findings worth a sentence

- **L1.** `Game.lua`'s header says every value goes through `Plain()`. It does for names, links,
  class and level; not for the stat table's values (`Stats.lua:155`, `:162` do arithmetic on them),
  `quality`, `minLevel`, `sellPrice` (`Game.lua:57-58`) or `slots` (`:190`). The docs mark none of
  them secret, and nothing is worked out in a fight (`Marks.lua:204`, `Core.lua:189`), but Polestar
  (`readable(v)`, `:566`) and Guildy (`ns.AnySecret(k, v)`, `Game\Gear.lua:381`) both check. One
  error inside the bag widget drops it for the session (`DaylightUI_Bags\Plugins.lua:37-47`).
- **L5.** Guildy met exactly this on this client: "765 of them in 30 s, because each render read
  the items still loading" (`Guildy\Game\Gear.lua:165-168`). Here the 0.3 s delay bounds it, and
  listed items do load, so it converges. Cheaper: only drop the context on `GET_ITEM_INFO_RECEIVED`
  when `ctx.pending > 0`, and only retry the item ID the event names.
- **L8.** `Market.CanScan` refuses only while Daylight UI's window is the one in use. That is right
  for "never scan under Daylight UI". Under DaylightMogul the button is offered and competes for the
  same cooldown.
- **Marks priority 0.** A widget takes its corner only on slots where it answers true
  (`Plugins.lua:95-100`), so ours hides another addon's mark only on a slot that is an upgrade, and
  only in the corner the player picked. The default, bottom right, is used by none of the marks
  Daylight UI hooks up (Can I Mog It and Simple Item Levels top right, Pawn top left, priority 1).
  Acceptable as it is.

## What was checked and found right

**Load and registration**
- Toc order: every `ns.X` used at file scope exists by then (`Core.lua` needs Spec, Compare, Stats,
  WeightData, UpdateGroup, Guide; Marks, Market and Window load after Core and stop on `ns.off`).
- `RegisterPlugin` / `RegisterModule` match `DaylightUI\Plugins.lua:104-142` and
  `Core.lua:711-776`, and Recipes' own call (`DaylightRecipes\Core.lua:480-488`). `needs = { 1, 12 }`
  equals the installed API (1.12). `short` is "Gear". Title carries the tag.
- Every options row passes `Options\Registry.lua:55-108`: defaults present and in range, dropdown
  defaults among the values, the keyless Spec dropdown has `get`, `set` and a function `default`,
  `disabled` functions take `get`. Page id `DaylightGear.gear`.
- `/dui gear`: `me.RegisterCommand(word, fn, help)` is the real way (`API.lua:1802-1811`); "gear" is
  not taken. `/gear` is set through `SlashCmdList` at file scope.
- Saved variables declared; `Guide.lua` creates the table on a first launch, `ns.DB()` migrates it.
- `Guide.lua` is byte-identical to Essentials'; `Update.lua` differs only in `PREFIX`
  ("DaylightGear", 12 characters).

**Game calls** (each against the generated docs)
- `GetReplicateItemInfo`: name 1, count 3, buyout 10, owner 14, itemID 17, hasAllInfo 18
  (`AuctionHouseDocumentation.lua:626-654`); index from 0 as Daylight UI reads it.
- `C_Item.GetItemInfoInstant`: equipLoc 4, classID 6, subclassID 7. `C_Item.GetItemInfo`: name 1,
  quality 3, minLevel 5, sellPrice 11. `GetItemStats`, `GetItemUniquenessByID`,
  `RequestLoadItemDataByID`, `GetItemIconByID` exist with those arguments.
- Talent reads follow the client's own talent window step for step
  (`Blizzard_ClassTalentsFrame.lua:86-108`, `:337-340`): group IDs, `traitNodeGroupID`,
  `currencyInfos[1].spent`, `orderIndex`, `displayName`.
- `C_SkillInfo.GetSkillLineInfoByID`, `C_SpellBook.IsSpellKnown`, `C_Container` calls,
  `GetInventoryItemLink`, slots 1 to 18 (`Constants.lua:136-153`), armor and weapon subclass numbers
  (`ItemConstantsDocumentation.lua:234-245`, `:625-645`), `NUM_BAG_SLOTS`, all nine events.
- Nothing called is protected or flagged restricted. All frames are plain; nothing of Daylight UI's
  is moved, shown, hidden or written to. Searching goes through Daylight UI's own `Submit`, which
  writes its own box. No path to its secure bag button or to a purchase.

**Daylight UI 2.1.2 internals**

| Used | Verdict | Fall-back engages |
|---|---|---|
| `DaylightUI:GetModule("AuctionHouse")`, `.enabled`, `.ns` | right (`Core.lua:721`, `Module.lua:5-8`) | yes: own house key, own scan offered |
| `ns.On("ScanStarted" / "ScanEnded")`, payload `(ok, sentence, total, info)` | right (`Base.lua:21-25`, `Scan.lua:94`, `:156`, `:198`) | yes: the game's event alone |
| `BuyPage.Submit(text, anywhere)` | right (`BuyPage.lua:560-567`) | yes: a chat line says what to type |
| `Window.ShowTab("buy")`, `frame.tab`, `DaylightUIAuctionHouse` | right (`Window.lua:33`, `:225-232`, `:487`) | yes: a window of its own |
| `Ruleset.Key()` | right (`Ruleset.lua:54-59`) | yes: realm and faction |
| `DaylightUI.MoneyString(copper)` | right (`Core.lua:97`) | yes: `GetMoneyString` |
| `DaylightUI:Set(scope, path, value)` | right (`Core.lua:889`) | the control does nothing |
| `Baganator.API.RegisterCornerWidget(label, id, onUpdate, onInit, { corner, priority })` | right (`DaylightUI_Bags\Plugins.lua:172-182`), corner names right (`:25`), `details.itemLink` / `bagID` right (`:85-88`) | yes: no bag mark |
| `me.AddTooltipLines("item", fn)`, `lines.Row(label, value, { r, g, b })`, `data.link` nil when secret | right (`API.lua:1619-1629`, `Tooltip.lua:1244-1255`, `:1346-1354`) | none needed (public) |
| `API.Skin`, `Text`, `Button` (`.text`, `.FitWidth`), `Close`, `Colors`, `Accent`, `Media` | right (`API.lua:831`, `:957-979`, `:1026-1036`; `Widgets.lua:377`, `:506`) | yes: `/gear` prints the status line |
| `Pad.On`, `Follow`, `Settle`, `Scrolls`; `padSecond`, `padTabs`, `padTabsLabel`, `padFirst`, `padSelect` | right (`Pad.lua:122-146`, `:466-489`, `:1054`, `:1085-1096`); same pattern as `DaylightRecipes\Shop.lua:555`, `:633` | yes: mouse only |

**Market reading**
- The loop ends: every wait has a clock (2 s settle, 15 s empty, 10 s since the last item, 60 s in
  all), blank rows are re-read at most until the count stops changing, and a row that raises aborts
  the read.
- Repeated events only set a flag while a read runs, and are folded to one look a frame otherwise;
  an echo of the list already read is recognized by size and probe rows.
- Closing mid-read: saved if every row was walked, continued only if the game still serves the same
  list, otherwise dropped with the old list kept.
- Another addon's scan is read like any other. The own scan is refused while Daylight UI's window
  is in use, while closed, while busy and for 15 minutes after any ask or read.
- Size: one string of about 30 bytes per distinct gear key. A house of 50,000 rows with 5,000
  distinct gear items saves about 150 to 200 KB; houses unread for 30 days are pruned at login.

**Window**: no template is used; the scroll frame, anchors and scale math are sound; nothing in it
is protected, so opening at the Auction House in a fight places it and shows "Gear isn't checked
during a fight"; Escape is only claimed while it stands alone; names wrap instead of cutting.

**Marks**: the tooltip callback is a table read after the first answer for a link; nothing is
computed in a fight; worn items get no row; caches drop on spec, gear and setting changes; pending
items answer nil and are retried by the bags; with Daylight UI's bags off there is simply no mark.

**Text**: American English throughout, labels in Title Case, sentences in sentence case, "Daylight
UI" with a space in every player-facing string, all six languages complete. The numbers are
disclaimed on the options page, in the welcome and in the tour.

## Tests' blind spots

Where a mock's shape differs from the documented or observed one:

| Mock | Assumes | Reality |
|---|---|---|
| `mocks.lua:125` `T.link`, `:34-44` `ident` | a roll sits in field 7 with a unique ID in field 8; items are told apart by ID and field 7 | 0 of 1,973 real links use field 7 or 8; the roll is fields 13-14 (bonus IDs), with context in 12 and modifiers after. Every "rolled item" comparison test runs on a shape the client does not produce. |
| `test_market.lua:360` | key `1002:::::::::::1:12745` | one colon short: the count lands in field 12. Real: `1002::::::::::::1:12745`. |
| `Game.ItemStats` mock, `test_stats.lua` | keys always end in `_SHORT`; every bonus is in the table | H1 and M1. |
| `Game.ItemStats` mock | nil until loaded, then complete | the docs only say "may return nothing"; a partial table is not ruled out (L4). |
| `GetItemUniquenessByID` (`test_game.lua`) | `true` means unique-equipped | the doc returns `isUnique` plus a limit category; whether a classic "Unique" (carry one) and "Unique-Equipped" both answer true is not stated. |
| `GetSkillLineInfoByID` (`test_game.lua`) | nil for a skill the character lacks | documented only as nilable. |
| `GetReplicateItemInfo` blank row (`mocks.lua:317`) | itemID nil | documented non-nil number (likely 0). `Row()` handles both. |
| `C_Timer`, frames (`mocks.lua:233-273`) | any capitalized method exists and returns nothing; `GetStringWidth` is nil | layout, anchors, scroll range and text measuring are untested; only show / hide / points are real. |
| `Game.InCombat` (`mocks.lua:100`) | false in the engine tests | fight paths are covered only in the marks and window tests. |
| Daylight UI stand-in (`mocks.lua:343-365`) | `RegisterPlugin` / `RegisterModule` accept anything; no `AddTooltipLines`; `Set` always succeeds | the options spec is never validated by a test (it was checked by hand above). |
| `("%d"):format` | not exercised above 2^31 | L7. |
| Game clock (`mocks.lua:213`) | only moves forward | L20. |

## The two biggest unknowns

**(a) Do replicate-list links carry the roll?** Probably yes, not proven.
- Every link the client itself wrote into saved variables carries a roll as bonus IDs: field 13 the
  count, field 14 the ID (12722 "of the Bear", 12751 "of the Bandit", 12754 "of the Defender"...).
  Field 7 is never used.
- Daylight UI's Auction House reads the replicate link at `Replicate.lua:130` and notes that
  "Forever's links don't carry the AH's number, only the words in their [text]"
  (`Items.lua:44-46`). That is about the Auction House's own suffix numbers (14296-14473), which are
  a different series from the bonus IDs; Daylight UI never looks at fields 13-14, so it says nothing
  about them either way.
- `Stats.Key` keeps rolls apart (12754 and 12755 give different keys), ignores the viewer's level
  and spec, and a saved key read back as `item:<key>` gives the same key and is still "rolled".
- Not provable from files: that `C_Item.GetItemStats("item:<key>")`, with level and spec blank,
  applies the roll. Polestar and Forever Leveling BiS always pass a full link.
- If the links carry the roll only in the name, `Market.lua:374-385` drops those rows and counts
  them: the window would quietly show no rolled gear. `/gear debug` prints all three counts and a
  sample link.

**(b) Do the stat keys and rating numbers match?** Mostly, with two holes.
- Keys: the same set as Polestar reads; Guildy independently uses the same names and the
  `ITEM_MOD_FIRE_DAMAGE_DONE_SHORT` spelling (`Guildy\Game\Gear.lua:503`), which `Stats.lua:101`
  also accepts. Hole one: the bare `ITEM_MOD_SPELL_HEALING_DONE` (H1).
- Ratings: 14 crit, 10 hit, 10 haste, 10 expertise, 10 armor penetration, 12 dodge, 15 parry,
  5 block equal Polestar's, which cites the client's `gametables/combatratings.txt`, build
  1.60.1.70862, "the same at every level". One source; Guildy counts ratings per point and does not
  confirm the numbers.
- "A plain hit or crit rating also counts for spells": Polestar plus the wowsims stat code per
  `design\data-format.md:153`. The weights agree with it: every caster and healer table at 60 has
  SPELL_HIT / SPELL_CRIT and no HIT / CRIT.
- Hole two: bonuses the call does not list (M1).

## Cannot be settled without the game

1. Whether replicate links carry bonus IDs, context and modifiers (a, M6).
2. Whether `GetItemStats("item:<key>")` returns the rolled stats for a saved key (a).
3. Which equip bonuses `GetItemStats` omits (M1), and whether healing arrives under the bare key (H1).
4. Whether the talent config is readable at `PLAYER_LOGIN` (M5).
5. Whether `GetItemInfo` on a rolled item string returns the name with its suffix (it feeds the row's
   name and the search text; without it every roll of an item shows the same name).
6. What `GetItemUniquenessByID` answers for "Unique" versus "Unique-Equipped".
7. Whether `GetSkillLineInfoByID` is nil for an untrained weapon skill (if it answers a table for
   every skill, untrained weapons are offered; if nil for all, the class table decides: both safe).
8. Whether the replicate list stays readable after the Auction House closes (the debug line says).
9. Whether `string.format("%d")` holds above 2^31 on this client (L7).
10. Whether `UnitLevel` has the new level 0.1 s after `PLAYER_LEVEL_UP`.
11. How the window sits beside Daylight UI's Auction House: strata, the fold tab's one-pixel overlap,
    clamping when the house window is near a screen edge, and the footer at other UI scales.
12. Whether Polestar's (and CheapUpgrades') own tooltip rows and bag marks sit acceptably beside ours;
    the overlap dialog is stage 2.

## A ten-minute first run

Link the folder into AddOns first. BugSack on. Riskiest first.

1. **Login (1 min).** No error; "Gear" in the options rail; the page draws; `/gear` opens the window.
   `/gear debug`, first line: is it `talents` or `default`? (M5.) A specced character that reads
   `default` confirms the gap.
2. **Stat keys on what you own (2 min).** Hover six pieces in bags and on the character: one with a
   plain green "+X" stat block, one with an "Equip:" spell power or healing line, one with "Equip:"
   attack power, one with hit or crit, a weapon, a rolled "of the ..." item. Then `/gear debug`:
   "stat keys with no mapping" answers H1 and the school-damage spelling. For the "Equip:" items,
   check that the Gear Advice row changes when compared with a similar item without the bonus: no
   change means the bonus never arrived (M1).
3. **A rolled item (1 min).** Hover two different rolls of the same item (chat links or bags): the
   rows must differ. Same answer on both means the roll is not applied.
4. **Full scan (3 min).** At the Auction House, with the window docked, run Daylight UI's Full scan.
   Watch the sub-line count rows and the list fill. Then `/gear debug`:
   - "kept items by link: N plain, N with a suffix field, N with bonus IDs" and "a rolled link"
     (unknown a, M6: look for context and `:1:28:` in the sample);
   - "rows skipped: ..." (a large "roll only in the name" or "item never loaded" is the bad news);
   - "reads started / started over" (more than one or two restarts means the list keeps changing).
5. **A saved roll read back (1 min).** In the window, hover a rolled row: the tooltip must show the
   roll's stats and name, and its percent must not equal the plain item's. Click it: Daylight UI's
   Buy page should search that name.
6. **The percent (1 min).** Read the ring, neck and trinket rows: note any percent over 300 and any
   "Empty Slot" on a slot you have filled (M2, M3).
7. **Close and reopen (1 min).** Close the Auction House, walk away,
   `/gear`: the list is still there, standing alone, Escape closes it. `/gear debug`, last lines:
   what the list answered two seconds after closing. Then `/reload` and `/gear` again: the saved
   list scores without the Auction House.

If time remains: a fight with the bags open (marks stay, no error), the fold tab, Max Price steps,
and a controller pass over the window.
