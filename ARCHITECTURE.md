# Glowey's Gear: architecture

Status: stage 1 is built (engine, Auction House reading, the window, the tooltip row, the bag mark, the guide), has been through one independent audit (`design\audit-stage1.md`) and a fix pass for it (section 13), and has had its first run in the game, which reported lag at a large Auction House and led to the rebuild of the scoring and reading loops described in section 6. `design\in-game-check.md` is the run to do next. The specification is `E:\daylight\cheapupgrades-in-essentials.md` (decisions D1 to D10); this page says how it is carried out and where it had to change (section 12).

Short path names:

- `DOC:` = `...\scratchpad\wow-ui-source\Interface\AddOns\Blizzard_APIDocumentationGenerated\` (the client's generated API docs, branch forever, commit 3d8abb1)
- `FX:` = `...\scratchpad\wow-ui-source\Interface\AddOns\` (the client's own UI source)
- `GAME:` = the installed game's own data files, read by `Tools\client_facts.py` into `Tools\tests\fixtures\`
- `DUI:` = `D:\World of Warcraft\_forever_\Interface\AddOns\` (Daylight UI **2.1.2**, plugin API 1.12: `DUI:DaylightUI\Plugins.lua:35`; read only). Every `DUI:` line number on this page and in the code's comments is 2.1.2's.
- `ES:` = `E:\daylight\DaylightEssentials\` (the owner's All Rights Reserved plugin the shared pieces come from)

## 1. Rules that shape everything

1. **Clean room.** Nothing of CheapUpgrades was opened, at any point; the study's neutral description is the only source for what it does. No code, text, key, constant, data or layout comes from it, from Pawn, from Forever Leveling BiS, from Polestar or from Daylight UI.
   - **What happened with the stat tables, plainly.** In the first pass the list of stat names in `Stats.lua`, the rating figures and the weapon skill numbers in `Score.lua` were written after reading the corresponding tables of Polestar (GPL-3) and Forever Leveling BiS (All Rights Reserved), and followed Polestar's list entry for entry; `design\data-format.md` cited both line by line. The audit caught it (M7). Those tables are gone. They were rebuilt on 2026-11-20 from primary sources only: the stat names from the client's GlobalStrings database, the rating figures from the client's combat ratings table (both `GAME:`), the weapon skill numbers from the client's character-sheet source (`FX:Blizzard_UIPanels_Game\Camelot\PaperDollFrameStats.lua:22-38`), with wowsims/forever (MIT, credited) as the second reference for the rating figures. The structure, order, naming and comments are this plugin's own, and the rebuild changed the content in eight places (`design\data-format.md`, 3.8). No citation of either addon remains as a source.
   - Other addons are named in comments only where one was looked at to learn how the game behaves: Auctionator and Daylight UI for how long the replicate list lives (`Market.lua` header). Nothing of theirs is copied.
2. **License.** All Rights Reserved (`LICENSE`, as the owner's other ARR plugins). Nothing was copied from the GPL-3 Glowey's Recipes: `Update.lua`, `Guide.lua`, the locale layout, the settings reader and the registration pattern come from Glowey's Essentials (the owner's own ARR code); the test runner, mocks and tools are written fresh. The wowsims-derived weights are MIT and their notice ships in `CREDITS.md`.
3. **The engine is pure Lua.** `Stats`, `Spec`, `Score`, `Compare`, `Rank` make no game call. Every game call they need is one function in `Game.lua`, which the tests replace with a mock that also forbids reading or setting any global. A game call appearing in an engine file fails the tests.
4. **Secret values.** Only character-sheet stat calls turn secret in a fight (`UnitStat`, `GetCombatRating`, `GetHitModifier`, `GetSpellHitModifier`: `DOC:PlayerScriptDocumentation.lua:303`, `:533`, `:1113`; `DOC:UnitDocumentation.lua:3198`). The plugin never calls them. What `Game.lua` reads carries no secret marker on its returns; every value still passes a guard (`issecretvalue`): names, links, class, level, quality, price, bag sizes, tooltip line types, and the whole stat table (a table holding anything unreadable is treated as "not loaded yet"). `test_game.lua` proves a secret value is never used. As a second safety nothing is worked out in a fight: the owned context is not rebuilt, the talents are not read, and tooltips and bag marks show only what was known before it.
5. **Every Daylight UI internal sits behind one guarded adapter** (section 8), type-checked and in `pcall`, with a public fall-back.
6. **Text.** American English; labels Title Case, sentences sentence case; "Daylight UI" spaced; nothing truncated (dropdown choices kept under about 15 characters for the 108 px a choice gets; the rail name is one word of at most 8 characters in every language, checked by `test_core.lua`).

## 2. Files

Load order is the `.toc`'s.

| File | Purpose | Lines | Offline tests |
|---|---|---|---|
| `Locales\Locales.lua`, six language files | Text; English key is the fallback (115 keys) | 82 + 6 x 127 | `Tools\locales.py` |
| `Data\Weights.lua`, `Data\README.md` | Stat weights, generated; pure table (`Tools\data\gen.py`, `extract.py`, `check.py`, `upstream.json`) | 1105 | `test_data.lua` |
| `Game.lua` | Every game call the engine makes | 311 | `test_game.lua` |
| `Stats.lua` | Link to normalized stat record; link identity; effects not counted | 479 | `test_stats.lua` |
| `Spec.lua` | Data check, spec from talents, weights by level | 298 | `test_spec.lua`, `test_data.lua` |
| `Score.lua` | Weighted sum; who can wear what; dual wield | 164 | `test_score.lua` |
| `Compare.lua` | What a candidate replaces; best of worn and carried; the percent | 318 | `test_compare.lua` |
| `Rank.lua` | Scoring job in slices; filter, order, group | 198 | `test_rank.lua` |
| `Update.lua`, `Guide.lua` | Shared with the owner's other plugins (newer-version alert, PREFIX `DaylightGear`; tours, welcome, What's New, `ns.Pad`). Never edited here | 135, 900 | |
| `GearGuide.lua` | This plugin's welcome, tour and What's New | 105 | `test_marks.lua` |
| `Core.lua` | Settings, saved variables, bus, events, who and owned caches, verdicts, `/gear`, registration, options page | 575 | `test_core.lua` |
| `Marks.lua` | Tooltip row and bag corner mark | 495 | `test_marks.lua` |
| `Market.lua` | Gear for sale: reads the replicate list, saves it per house | 811 | `test_market.lua` |
| `Check.lua` | What a search says since the scan: corrected prices, "none left", the player's purchases, Check Prices | 450 | `test_check.lua` |
| `Window.lua` | Upgrades for Sale window, docking, controller, hand-off | 1121 | `test_window.lua` |

`Tools\tests\` (runner, mocks, twelve test files, `fixtures\`), `Tools\locales.py`, `Tools\client_facts.py`, `Tools\data\`, `design\`, `ARCHITECTURE.md`, `README.md`, `CHANGELOG.md`, `CURSEFORGE.md` and `Data\README.md` stay out of the release zip (`.pkgmeta`). `LICENSE`, `CREDITS.md` and `AGENTS.md` ship.

## 3. Public functions

```
ns.Game      ItemStats(link) ItemInstant(link) ItemInfo(link) ItemSpeed(link) ItemUnique(link)
             ItemEffects(link) -> equip, use, proc | nil     ItemEffectFields(link)   RequestItem(id)
             Class() Level() Trees() KnowsSkill(line) KnowsSpell(id) WornLink(slot) BagLinks(out)
             Guid() Name() Realm() RealmID() Faction()        InCombat() Clock()

ns.Stats     Of(link) -> record | nil, "pending" | "notgear" | "bad"
             Key(link)  ItemID(link)  IsRolled(link)  Normalize(raw, equipLoc) -> stats, bonuses
             Classify(gameKey) -> "scored" | "weapon" | "ignored" | nil      Uncounted(rec) -> n
             Forget()  Cached()   KEYS  RATING_PER_PERCENT  GEAR  DPS_KEY  unknown

ns.Spec      Load(data) -> problems     HasClass(c)  List(c)  Info(c, key)  Label(c, key, trees)
             Detect(c, trees, last)  Resolve(c, choice, trees, last)  Weights(c, key, level)
             Current() -> { class, spec, level, weights, how } | nil, why
             GetChoice / GetLast / SetLast   (hooks Core.lua fills from the saved variables)

ns.Score     Value(stats, weights)   Usable(rec, who, opts) -> ok, reason, atLevel
             CanDualWield(who)   Fresh()   CAN  SKILL

ns.Compare   Context(who, worn, carried, opts) -> ctx { pools, pending, typical, dual }
             FromGame(who, opts)
             Evaluate(rec, ctx, opts, out) -> { usable, reason, atLevel, group, slot, score, base,
                                                gain, pct, far, empty, replaces, twoHand, offHand }
             GROUPS  GROUP_OF  SLOT_OF  FAR

ns.Rank      Job(ctx) -> job:Add(link, price) :Step(n) :Run() :Retry() :Left(); job.rows .pending
             Arrange(rows, opts) -> { groups = { [group] = rows }, over = { [group] = row }, listed }
             Value(gain, price, level)   Pocket(level)

Core.lua     ns.Get(path)  ns.DB()  ns.Char()  ns.On(name, fn)  ns.Fire(name, ...)  ns.Print(text)
             ns.Who()  ns.Context()  ns.Verdict(link, carried)  ns.RankOptions(level)
             ns.SpecValues  ns.DEFAULTS  ns.lastSeen  ns.OpenWindow (set by Window.lua)

ns.Marks     Kind(verdict, minGain)  Text(verdict, minGain)  Advice(verdict, minGain)  Percent(pct)
             SlotName(group)  Lookup(view, link)  Refresh()  Register()  OnItemTooltip  NOTE  COLOR

ns.Market    List()  Feed(job)  Age()  State()  CanScan()  Scan()  House()  IsOpen()  Debug()  DuiAH()  TUNE
             fires "MarketChanged", "MarketProgress"

ns.Window    Open() Close() Toggle() Refresh(force) Rearrange() Dirty(force)
             Model(view, selected)  EmptyState(facts)  Mode(...)  DockSide(...)  StepPrice(gold, dir)
             SearchText(row)  AgeText(seconds)  GainText(row)  Uncounted(row)  Over(view)
```

The formulas, each explained where it lives:

- **Score** (`Score.lua`): the sum of stat amount times the spec's weight. Nothing derived, capped or scaled.
- **Weights by level** (`Spec.lua`): a bracket's table stands for the middle of its level span; weights slide in a straight line between middles and reach the level 60 table at 60.
- **Baseline** (`Compare.lua`): best owned for a one-slot place; second best owned for rings and trinkets; for the hands `W = max(best two-hander, best main hand + best off hand)` (two different items), with the candidate tried in the hand it can go in. A dual wielder's one-hand weapon is tried in both hands and the better answer stands (in the off hand its damage counts with the `OH_DPS` weight).
- **The percent** (`Compare.lua`, "THE PERCENT"): for reading only. `pct = gain / max(base, half a typical worn piece) x 100`, where a typical piece is the average score of the worn items that score anything. Above 200 the surfaces say "Far Better" in words. No percent only when nothing worn scores at all. "Empty" only when nothing is replaced. The one rule feeds the window (`Window.GainText`), the tooltip row and the bag mark (`Marks.Kind`).
- **Ranking** (`Rank.lua`): by gain in score points, or by gain per gold, `gain / max(price, pocket change)` in gold with pocket change `= max(1 silver, 5 copper x level x level)`. Never by the percent, so a near-worthless item in a slot cannot push its replacement up the list. The percent is used only by Smallest Gain to Show (default 3), where its floor is what makes the filter mean something.
- **Effects not counted** (`Stats.Uncounted`): section 9.

## 4. Event flow

```
Daylight UI "Login"                       -> ns.DB() migrates, spec names read, who worked out,
                                             "WhoChanged"; if the talent trees are not readable
                                             yet, looks again after 1, 3, 8 and 20 s
TRAIT_CONFIG_LIST_UPDATED, TRAIT_CONFIG_UPDATED, PLAYER_TALENT_UPDATE,
ACTIVE_TALENT_GROUP_CHANGED, PLAYER_LEVEL_UP, PLAYER_ENTERING_WORLD
                                          -> one look 0.1 s after a burst; in a fight it waits for
                                             PLAYER_REGEN_ENABLED; "WhoChanged" only when the
                                             spec, level or weights really changed
PLAYER_EQUIPMENT_CHANGED, BAG_UPDATE_DELAYED, SKILL_LINES_CHANGED
                                          -> one refresh 0.3 s after the last of a burst; in a
                                             fight it waits; owned context dropped, "OwnedChanged"
GET_ITEM_INFO_RECEIVED                    -> counted; what is owned is read again only when some
                                             owned item was still waiting for its data; otherwise
                                             one "ItemsArrived" a second at most (Marks only)
GET_ITEM_INFO_RECEIVED, ITEM_DATA_LOAD_RESULT (Window.lua's own frame, registered only while
its job has items parked)                 -> job:Arrived(itemID, ok): one table lookup
Daylight UI "SettingChanged" (ours)       -> settings cache dropped, "Setting" (path)
```

Event names are checked in the generated docs: `DOC:SharedTraitsDocumentation.lua:867`, `:873`; `DOC:SpecializationInfoDocumentation.lua:503`, `:447`; `DOC:UnitDocumentation.lua:3832`, `:3893`; `DOC:SystemDocumentation.lua:136`; `DOC:PaperDollInfoDocumentation.lua:386`; `DOC:ContainerDocumentation.lua:677`; `DOC:ItemDocumentation.lua:1815`; `DOC:SkillInfoDocumentation.lua:105`.

Listeners: `Marks.lua` on "WhoChanged" / "OwnedChanged" / "Setting" drops its per-link answers and asks Daylight UI's bags to repaint (skipped when what is owned reads the same and nothing was waiting), and on "ItemsArrived" only when an answer of its own was waiting for data; `Window.lua` starts a new `Rank.Job` on the next frame (who, owned or the list changed, and only while it is shown), or only runs `Rank.Arrange` again ("Setting" for `maxPrice`, `minGain`, `mode`); `Market.lua` fires "MarketChanged" when a new list is saved.

`ns.Who()` and `ns.Context()` are kept until one of the events above; consumers never cache them.

## 5. Saved variables

Settings live in Daylight UI's profile under the plugin's name (read with `API.GetSetting`, defaults in `Core.lua`'s `DEFAULTS`; a default is given but not cached while Daylight UI has no value yet): `enabled`, `minGain`, `bestArmor`, `maxPrice` (gold), `mode`, `tooltips`, `bagMarks`, `bagCorner` (default `bottom_right`), `dock`.

What is not a setting is `DaylightGearDB`, per account:

```lua
DaylightGearDB = {
	v = 2,                         -- shape version; Core.lua's Migrate() steps old shapes forward
	updateCheck = false,           -- Update.lua's switch (absent = on)
	guide = { ... },               -- Guide.lua's own keys
	chars = {                      -- per character, by GUID
		["Player-4407-00ABCDEF"] = { spec = "auto" | "<SPEC KEY>", last = "<SPEC KEY Auto last found>", name = "Name" },
	},
	houses = {                     -- one gear list per Auction House
		["<house key>"] = {
			at = <server time>, asked = <server time of our own ask>, rows = <rows read>, by = "dui" | "own" | "other",
			items = { "<Stats.Key>#<copper>#<class>.<subclass>.<level>.<location>", ... },   -- gear only, cheapest listing per key
			lost = <gear items that could not be read>, lostRows = <in how many rows>,
		},
	},
}
```

**No key is made of a realm name.** On 2026-11-20 this client's `GetRealmName()` began answering an empty string (Daylight UI 2.1.2 works around the same thing: `DUI:DaylightUI\DB.lua:181-316`; the owner's Essentials too, `ES:Halo.lua`, `CharKey`).

- Characters are keyed by `UnitGUID("player")`, "Player-<realm number>-<character number>" (`DOC:UnitDocumentation.lua:1241-1254`; the public wiki's GUID page gives the same parts). Version 1 keyed them "Realm-Name": such a record is copied into the character's GUID record the first time it is asked for, when exactly one old record can be its own (the one under today's realm name if the game gives one, else the only one ending in "-Name"); with two candidates none is taken. Old records are left in place.
- The house key is Daylight UI's ruleset key when its Auction House module is readable (`Ruleset.Key()`, `DUI:DaylightUI_AuctionHouse\Ruleset.lua:54`: "US-PvE" or "US-Realm Name"). Without it: `"realm" .. <realm number> .. "-" .. <faction>`, the number from `GetRealmID()` (`DOC:ConnectionDocumentation.lua:60-67`) when it is above 0, else the middle part of the GUID; the realm's name only when there is no number; and nil (nothing saved) when there is neither, rather than one shared key for every realm. Whether two factions share one Auction House on this client is not known; keeping them apart costs a second list at worst.
- Only the newest list per house is kept; a house not read for 30 days is dropped at login. The saved text starts with `Stats.Key(link)`, which is itself an item string, so `"item:" .. key` is a link every game call takes.
- **The facts after the second `#`** (item class, subclass, required level, equip location as a number from a fixed list in `Market.lua`) are what lets a later session or another character drop most of a house without asking the game anything. An entry without them (an older save) still reads and is weighed the slow way. One string per item, not a table: 15,620 items measured about 820 KB in memory and 620 KB in the saved-variables file.

## 6. Performance at a real house

**What happened.** The first run in the game (2026-11-20, a level 33 Enhancement shaman at Daylight UI's Auction House after a Full scan) lagged with the window up. The owner's `/gear debug` gave the real sizes: **232,540 rows**, 57,717 gear rows read and 27,689 more lost as "item never loaded", **16,159 distinct gear items kept**, 10,258 item records in memory, and **97,376 list events** in one scan. The first build was planned for "a few thousand gear" and did these things at that scale:

1. It scored every one of the 16,159 saved items for the character, although most are gear a level 33 shaman cannot wear or use yet.
2. It scored in batches of 20 items and looked at the clock only between batches, and repainted (a full sort of everything found, every row laid out, the window dressed again) four times a second while it scored.
3. Each read of an item the game had not cached made the game fetch it (that is what `C_Item.GetItemInfo` does), which raises an item event; every burst of item events, from anybody's code, started a refresh that put every waiting item back in the queue. Items that never arrive kept that going for as long as the window was up.
4. While a read ran, and for every echo of the list event afterwards, it re-read its probe rows (one per 1,000 rows of the list: 235 row reads a look for this house) to see whether the list was a new one.
5. The item cache was capped at 12,000 records and started over when full, so with 16,159 items it was filled, thrown away and filled again.

Which of these the owner felt most cannot be told from a file; all five are gone. `Tools\tests\bench.py` reproduces the house (its header lists what every game call is assumed to cost) and gave, old build against new, on the same stand-in:

| Scenario | Before | After |
|---|---|---|
| The scan is read with the window up, then scored (level 33 shaman) | 957 busy frames, **786 over 4.5 ms**, median 5.1 ms, worst 27 ms; 15,620 items scored | 1,190 busy frames, **0 to 1 over 4.5 ms**, median 3.1 ms, worst 4.3 to 7 ms (one frame, see below); **5,245** items scored, 10,375 dropped unread |
| 5,000 item events for other things, window up | 16 busy frames, 21 ms, 16 full paints | 1 busy frame, under 1 ms, no paint |
| A new session, cold cache (two items in three not cached, some never arriving) | 314 busy frames, 219 over 4.5 ms; 25,950 item reads (items read again and again) | 154 busy frames, 0 over 4.5 ms; the job ends by itself with 307 rows given up and counted |
| Window closed, events flooding | 0 | 0 |
| Level 60 dual wielder (can wear nearly everything) | 205 busy frames, 166 over 4.5 ms, worst 12.8 ms | 356 busy frames, 0 over 4.5 ms, worst 4.1 ms |
| Level 14 mage | 200 busy frames, 181 over 4.5 ms; 15,620 items scored | 44 busy frames, 0 over 4.5 ms; 1,481 items scored |
| A Max Price change | 2.2 ms | 1.6 ms |

The one frame of up to 7 ms in the first row comes and goes between runs of the same benchmark; it is Lua's garbage collector taking a step at the end of a read, not a loop of ours. The stand-in's prices for game calls are assumptions: the real client may be dearer or cheaper per call, which is why every loop below measures time instead of counting items, and why `/gear debug` now reports what our code really cost.

**The rules now, each in the file that keeps it.**

| Rule | Where |
|---|---|
| Nothing runs while the window is not shown (closed, folded to its tab, interface hidden). What changed is remembered and done when it shows. | `Window.lua` (`Window.IsShown`, `Refresh`, `Step`) |
| Nothing is scored while the Auction House's list is being read: the list is not whole and the reader has the frame's time. One job when the read is saved. | `Window.lua` |
| One tick a frame, 3 ms, the clock looked at after **every** item. No batch size to get wrong. A paint is a tick of its own. | `Window.lua` (`Step`) |
| Saved items are fed to the job a slice at a time and dropped at once, with no game call, when the saved facts say the character cannot wear them, cannot wear them yet, or (with the option) they are lighter than its best armor. | `Market.Feed`, `Rank.Job:Add` |
| An item the game has not cached is parked under its item ID, never read with a call that makes the game fetch it on the spot (`C_Item.IsItemDataCachedByID` is asked first: `DOC:ItemDocumentation.lua:1520-1533`; the client's own item object does the same, `FX:Blizzard_ObjectAPI\Mainline\Item.lua:295`). At most 20 loads are asked for a frame and 400 are out at once. | `Rank.Job` (`park`, `Pump`), `Game.ItemCached` |
| The job hears about its own parked items by item ID, on its own event frame, registered only while something is parked. An event for anything else is one table lookup. Nothing is retried wholesale. | `Window.lua` (`items` frame), `Rank.Job:Arrived` |
| A job ends: an item asked for twice (6 s each) with no answer is given up and counted, and the window says "N items for sale could not be read." | `Rank.Job:Expire`, `Window.Facts` |
| Only an upgrade's record is kept in memory (a candidate is read, weighed and dropped). | `Stats.Read` / `Stats.Keep`, `Rank.Job` |
| The best per slot is kept as rows come (a short sorted list per slot), so showing progress sorts nothing; while a job runs the window repaints at most once a second and only when what is shown changed. The full arrangement runs when a control changes. | `Rank.Live`, `Window.lua` |
| A paint dresses the window (`API.Skin`) only when its height changed, and asks for at most three new "effect not counted" marks. | `Window.lua` (`PaintNow`) |
| The list event does two counters and a flag. Whether the list is a new one is looked at once a second at most, with at most 23 probe rows however long the list. | `Market.lua` (`onListEvent`, `IsProbe`) |
| The read: 3 ms a frame; the clock looked at every 8 rows at most (20 until a real scan showed a market frame of 4.7 ms), fewer when rows turn out dear (the number halves and doubles with the measured time); item loads asked for 20 a frame (40 before: they were sent ahead of the first look at the clock); the saving itself (one string per item) is cut over frames and nobody sees half a list. | `Market.lua` (`pump`, `save`) |
| Item-data events (tens of thousands at an Auction House) cost a counter in `Core.lua`; what is owned is read again only when an owned item was waiting for data. | `Core.lua` (`ItemArrived`) |

**Memory, measured on the stand-in for the shaman:** the saved list 820 KB (15,620 strings); a finished job with its 2,221 upgrade rows and their records about 4.8 MB; item records kept 2,221 instead of 10,258.

**What `/gear debug` now says about all this:** the longest frame of our own work in the last minute for each part (market, scoring, paint, context, marks); how many refreshes, new jobs, reads of what is owned, paints, full arranges and bag repaints happened in the last minute; item-data and list events in the last minute; and the job's state (saved items fed, dropped unread and why, read, upgrades, queued, waiting for data, given up). One paste proves the fix or shows what is left.

## 6a. Prices after the scan, and rows that load late

**Corrections (`Check.lua`, `Market.Fix`).** The saved list is the house as the scan saw it. Whenever the game shows one item's auctions (`ITEM_SEARCH_RESULTS_UPDATED` / `_ADDED`, `DOC AuctionHouseDocumentation.lua:1465`, `:1455`), the results are read (`GetNumItemSearchResults` `:519`, `GetItemSearchResultInfo` `:374`, `HasFullItemSearchResults` `:746`), at most 120 a frame, and each result's **link** is turned into our key with `Stats.Key`. The lowest buyout among other players' auctions becomes the key's price. Stored beside the list, never in it: `fixP[key]` = copper (0 = none left), `fixT[key]` = server time.

**Newer wins.** A correction counts only while its time is after `readAt`, the moment the read of the list began. A new scan drops every correction not newer than itself; a correction learned while a scan was being read survives it. `Market.Feed` hands a job the corrected price (with the time, for the row's tooltip), leaves out a key with none left, and feeds keys that only a correction knows.

**"Covered".** A key is marked "none left" only when the result set is complete (`HasFullItemSearchResults`, every result had a link, under our cap of 600), the searched key had no suffix and no level, and for a roll, in addition, either the search was ours through Daylight UI (its gear search is the game's sell search, which returns every level and suffix) or the results themselves hold a roll. Two references for the sell search: `DOC :1046-1048` and the client's own `FX Blizzard_AuctionHouseUI\Shared\Blizzard_AuctionHouseUtil.lua:484-495`; Daylight UI's `Search.lua:39-42` is the third. A result whose item key has a suffix while its link shows no roll maps to nothing and is counted.

**Purchases.** `AUCTION_HOUSE_PURCHASE_COMPLETED(auctionID)` (`DOC :1221`; the client's buyout dialog waits for the same event, `FX Blizzard_AuctionHouseUI\Shared\Blizzard_AuctionHouseFrame.lua:15`, `:31`): the auction is taken out of the result set it was last seen in; its key gets the next price there, or "none left" when that set was complete.

**No re-score.** A score does not depend on a price. `Job:Reprice` sets the row's price or `gone`, and `Live:Regroup` rebuilds that one slot's short list from the rows of that slot. The window repaints once on the next frame however many prices came.

**Check Prices** (button in the window, only with Daylight UI's Auction House): the items on screen, one `ns.Search.Item` at a time, the next only after the answer (20 s at most), 0.2 s apart, nothing sent while `ns.Buy.Pending()` says a purchase is under way, stopped by Stop and by the house closing. A click on a row asks about that one item the same way.

**The tail (`Market.StartTail`).** Gear rows that gave no link before the read ended are no longer dropped: after the list is saved they are read again by index, 1.5 ms a frame, a pass every 2 s, for as long as the house is open, the game's list is the same and passes still bring something (5 empty passes end it). A row that has its link is merged into the saved list (`Market.Merge`, "MarketAdded"), and the window adds it without a new job. Each lost row is counted by cause (`refused`, `nolink`, `quiet`, `cap`, `closed`, `unasked`) in `/gear debug`.

## 7. The three surfaces, as built

### 7.1 `Market.lua`

The client keeps one whole-house ("replicate") list; whoever calls `C_AuctionHouse.ReplicateItems()` fills it and any addon can read it: `GetNumReplicateItems()` (`DOC:AuctionHouseDocumentation.lua:552`), `GetReplicateItemInfo(index)` (`:626-654`; 10 `buyoutPrice`, 14 `owner`, 17 `itemID`, 18 `hasAllInfo`), `GetReplicateItemLink(index)` (`:658-672`), index from 0, event `REPLICATE_ITEM_LIST_UPDATE` (`:1491-1495`). None is flagged `HasRestrictions` (the flagged calls of the namespace are the cancel, post, bid and purchase calls: `:62`, `:96`, `:110`, `:854`, `:866`, `:885`, `:1081`) and none carries a secret marker. Second references: Daylight UI's own reader (`DUI:DaylightUI_AuctionHouse\Replicate.lua:111-137`) and the public wiki pages for `ReplicateItems` and `GetReplicateItemInfo`.

- Reading starts at the game's own event, whoever asked: during Daylight UI's Full scan, not after it. Daylight UI's module-private `ScanStarted` / `ScanEnded` (through its `ns.On`, `Base.lua:21`; fired at `Scan.lua:198`, `:156`, `:94`) are only a second trigger.
- A list is "new" when its size or a few probe rows differ from the one last read (the event repeats per loaded item). A list replaced mid-read starts the read over.
- Per `Stats.Key(link)` the lowest buyout of gear rows is kept; the player's own auctions are left out; a roll that exists only in the link's text (no suffix, no bonus ID) is left out and counted.
- **A row is read as soon as it has a link**, whatever its `hasAllInfo` says: the link (the item and its roll) is all that is needed of it. The first build waited on `hasAllInfo` and lost 27,689 of 85,406 gear rows of a real house as "item never loaded"; which of the two (the flag never turning true for some rows, or the wait ending too early) cost those rows cannot be told from the paste, so both are changed: only a row with no link waits for its item, the item is asked for up to three times, and the wait ends when nothing has arrived for 15 s or 5 minutes after the last row was walked, or when the Auction House closes. What is still lost is counted per item and saved with the list (`lost`, `lostRows`), and the window says so.
- With each kept item the read saves what can be known of it without loading it again: item class, subclass and equip location (an instant call on the item ID) and its required level (in the item's data, which the game has at that moment).
- **No scan of our own while another scanner owns the house:** `Market.CanScan()` refuses with "dui" while Daylight UI's Auction House is the one in use, and with "other" while DaylightMogul runs the house (`DaylightUI.ahMogul`, `Module.lua:18`): one whole-house scan is allowed in about 15 minutes for everybody together (the wiki's figure; Daylight UI assumes 900 s and calls it a guess, `Scan.lua:26`; the client's source states none), so ours would spend theirs. Their list is read like any other. Our own button exists only with the game's own Auction House window.
- `/gear debug` prints what Market saw: events, rows read, rows skipped by reason, the kept items by link shape (plain, suffix field, bonus IDs), a sample rolled link, and what the list answered two seconds after the Auction House closed.

### 7.2 `Window.lua`

A compact list (340 wide): one row per slot group with the best pick for sale, its price and its gain ("+12%", "Far Better", "Better" or "Empty Slot", from `Window.GainText`; a trailing "*" when the item has an effect the score leaves out), the alternatives under the row that was clicked, and a footer with Max Price and Best Pick. Docked flush against Daylight UI's Auction House window (`_G.DaylightUIAuctionHouse`: `Window.lua:33`, made at `:487`) while that is up and Dock to the Auction House is on, with a fold tab at the nearest corner; a window of its own otherwise. A click (A on a controller) searches the item in Daylight UI's Buy page (`BuyPage.Submit(text, anywhere)`, `BuyPage.lua:560-567`, after `Window.ShowTab("buy")`, `Window.lua:225`); fall-back a chat line with the text to type. Nothing is ever bought.

### 7.3 `Marks.lua`

- Tooltip row: `me.AddTooltipLines("item", fn(lines, data))` (public, API 1.12: `DUI:DaylightUI\API.lua:1610-1629`; the plugin-lines block is at `DUI:DaylightUI_Tooltip\Tooltip.lua:1225`, `Row` at `:1246-1267`, `data.link` at `:1346-1354`). One `lines.Row("Gear Advice", text, color)`; for an item with an effect the score leaves out, one more `lines.Text` sentence. What is worn gets no row.
- Bag mark: the Baganator-style calls Daylight UI's bags answer (`DUI:DaylightUI_Bags\Plugins.lua:172-195`; its stand-in marks itself `DaylightUI = true`, `:206-207`; details `:85-88`). A green plus in the corner picked (default bottom right: Daylight UI's own overlays use the other three, `DUI:DaylightUI_Bags\Items.lua:499-500`, `:686-696`). One widget is registered per corner and only the picked one answers true, because the calls cannot move or drop a widget; that is three idle frames per slot, taken knowingly so Bag Corner works without a reload.
- Overlap with Pawn, Forever Leveling BiS, Polestar and CheapUpgrades (study section 4.3) is stage 2.

## 8. Where Daylight UI is touched

Public API: `DUI:RegisterPlugin`, `DUI:RegisterModule`, `API.For`, `API.GetSetting` (`DUI:DaylightUI\API.lua:892`), `API.IsModuleEnabled` (`:897`), `me.On`, `me.RegisterCommand` (`:1802`), `me.AddTooltipLines` (`:1619`), `API.Skin` (`:957`), `API.Text`, `API.Button`, `API.Colors`, `API.Accent`, `API.Media`.

Internals, each behind exactly one adapter function that answers nil or false when anything is not as read:

| Adapter (file) | Relies on (2.1.2) | Fall-back |
|---|---|---|
| `DuiAH()`, `DuiModule()` (`Market.lua`) | `DaylightUI.ahMogul` (`DaylightUI_AuctionHouse\Module.lua:18`); `DaylightUI:GetModule("AuctionHouse")` (`DaylightUI\Core.lua:721`), `.enabled`, `.ns` (`Module.lua:5-8`) | Treated as "Daylight UI's Auction House is not in use" |
| scan callbacks (`Market.lua`) | the module's `ns.On("ScanStarted" / "ScanEnded")` (`Base.lua:21`; `Scan.lua:198`, `:156`, `:94`) | The game's list event alone |
| `DuiHouseKey()` (`Market.lua`) | `Ruleset.Key()` (`Ruleset.lua:54`) | realm number and faction |
| `SearchInDui()` (`Window.lua`) | `BuyPage.Submit(text, anywhere)` (`BuyPage.lua:560-567`); `Window.ShowTab("buy")`, `.frame.tab` (`Window.lua:225`, `:31`) | chat line with the text to type |
| `Dui()`, `Buying()` (`Check.lua`) | the module's `ns.Search.Item(itemID, onDone)` (`Search.lua:413`; gear goes through the sell search with level and suffix cleared: `:39-42`, `:331`, `:367`; one at a time on its request line, counted toward the 100 a minute: `:48`); `ns.Buy.Pending()` (`Buy.lua:101`) | no Check Prices and no search on a row click; results the player's own searches bring are still learned from |
| `Host()` (`Window.lua`) | global `DaylightUIAuctionHouse` (`Window.lua:33`, `:487`) | a window of its own |
| `Money()`, `SetSetting()` (`Window.lua`) | `DaylightUI.MoneyString` (`DaylightUI\Core.lua:97`); `DaylightUI:Set` (`:889`) | the game's `GetMoneyString`; the control does nothing |
| `ns.Pad.*` (`Guide.lua`, shared) | `DaylightUI.Pad` (`DaylightUI\Pad.lua:72`; `Follow` `:1085`, `Settle` `:1169`, `Popup` `:1192`) | mouse only |
| `BagShim()` (`Marks.lua`) | `_G.Baganator.API.RegisterCornerWidget` / `RequestItemButtonsRefresh` (`DaylightUI_Bags\Plugins.lua:172`, `:195`, stand-in at `:206-207`) | no bag mark |

Nothing of Daylight UI's is written, hooked or replaced. The owner's "addons updated, run our checks" routine re-reads these lines at every Daylight UI release.

**A candidate to replace internal reads later (no change now):** Daylight UI 2.1.2 sets `DaylightUI.AuctionPrices` (`DUI:DaylightUI_AuctionHouse\Bridge.lua:38`: `Item(itemID)` gives a price and when it was seen, `Vendor(itemID)`; event `AuctionPricesChanged`). It looks meant for other parts to use. It gives one price per item ID, not listings with links, so it cannot supply the gear list, but it could serve a "usual price" figure or a vendor comparison in stage 2 in place of reading the store directly.

## 9. What the score leaves out, and how it is said (audit M1)

`C_Item.GetItemStats` does not promise every bonus. An effect that is a spell on the item ("Equip:", "Use:", "Chance on hit:") has its size only in the tooltip's sentence, in the client's language. The question was whether any language-free route gives the amount. **None was found**, by two references. (1) The generated docs: a tooltip line is text, colors and a `type`, with any extras typed loosely (`TooltipDataArg`, `DOC:TooltipInfoSharedDocumentation.lua:163-174`); `C_Item.GetItemSpell` answers only a spell name and ID (`DOC:ItemDocumentation.lua:970-984`); `C_Item.GetItemStats` is the only call that answers amounts. (2) The client's own tooltip code, which reads named extras from a line for sockets, essences and threat but none for an item's effect lines (`FX:Blizzard_SharedXMLGame\Tooltip\TooltipDataHandler.lua:320-348` and the line handlers beside it); the public wiki's pages for `C_Item.GetItemStats` and `Enum.TooltipDataLineType` list nothing more. Even a spell ID on such a line would lead only to the spell's description, which is a sentence again. So nothing is guessed. (`/gear debug` prints the field names the game puts on the last item's effect lines, in case this client carries more than the docs say.)

What the game does give without text is the **kind** of each tooltip line: `Enum.TooltipDataLineType` has `ItemSpellTriggerOnUse` (44), `ItemSpellTriggerOnEquip` (45) and `ItemSpellTriggerOnProc` (46) (`DOC:TooltipInfoSharedDocumentation.lua:78-80`; the wiki lists the same three, added in 12.1.0), read from `C_TooltipInfo.GetHyperlink(link).lines[i].type` (`DOC:TooltipInfoDocumentation.lua:337-353`; the client's own tooltip code reads `lineData.type`, `FX:Blizzard_SharedXMLGame\Tooltip\TooltipDataHandler.lua:320-334`). `Stats.Uncounted(rec)` counts them: every Use and proc line is an effect the score leaves out; Equip lines are left out only as far as there are more of them than bonuses the stat call did answer. The count is right whether this client types every "Equip:" line this way or only the ones that are spells (it never goes below zero, and never claims more than the lines there are), and it is 0 when the client gives no line types at all.

An item with a count above 0 is marked: the tooltip gets one more line, "Gear Advice does not count this item's special effect.", and its window row a "*" (with the same sentence on its tooltip when the tooltip row is switched off). The verdict itself is unchanged: the item is scored on what is known.

## 10. Controller

- The options page: Daylight UI's own, already controller-ready.
- The window: `ns.Pad.Follow(window, close)`; rows are plain buttons the D-pad walks, `padFirst` starts on the first row; A on a slot row opens its alternatives, A on an alternative searches it; LB / RB switch Best Pick (`padTabs`); Max Price is two buttons (D-pad), never a typed field; the fold tab is a D-pad stop; the list scrolls with the right stick. The welcome and the tour work with a controller through the shared `Guide.lua`.
- No keybind and no picker of its own in stage 1; `/gear`, `/dui gear` and a button beside the Auction House window open it.
- The kit does not announce a window in a fight (`DUI:DaylightUI\Pad.lua:4-6`); the window can open in one and gets the cursor when it ends.

## 11. Limits of stage 1

- **Effects that are not stats** (Use, proc and some Equip effects), set bonuses, enchants and gems are not counted. Items with such an effect are marked (section 9); how much the effect is worth is not known.
- **Weapon pairs across the Auction House:** a main hand and an off hand that are only an upgrade when bought together are not found. (A one-hand weapon is tried in both hands for a dual wielder; shields and held items against the off hand.)
- **Weapon speed** (no language-free source), **hit cap**, **talents**.
- **Class-restricted and profession-only gear** can be suggested wrongly (no table ships; `C_PlayerInfo.CanUseItem` is a game check). The class table of who can train which weapon and armor type is written by hand (single source).
- A second followed spec; custom weights; other addons' weights; quest rewards; chat alerts; vendor-value rules; the overlap dialog for Pawn, Forever Leveling BiS, Polestar and CheapUpgrades.
- The bank and other characters do not count as owned; no `RegisterUpgradePlugin` (the bag search word "upgrade").
- A stat table the game answered incompletely once is kept for the session (audit L4): the game gives no sign that a table is partial, so there is nothing to test for.

What only the game can answer is `design\in-game-check.md`, a numbered run, with the open questions it settles listed at its end.

**Settled by the first run in the game (the owner's `/gear debug`, 2026-11-20):**

- Auction House links carry a roll as bonus IDs: 13,472 of 16,159 kept items had them, none used the suffix field. The sample, `item:9764::::::::33:1489:::1:12718::::::` ("Cadet Shield of the Eagle"), has the count in field 13, the ID in field 14, and the linking character's level and spec in fields 9 and 10, as `Stats.Key` assumes.
- The replicate list does **not** survive the Auction House closing: 0 rows at the close and two seconds later. Reading during the scan, as built, is the only way.
- The game gives no realm name (the realm number, 6800, came from the GUID) and the house key was Daylight UI's ("US-PvP").
- The stat call answers names that are not in the client's readable string list: the five `ITEM_MOD_<SCHOOL>_RESISTANCE_SHORT` names were reported as unknown a few hundred times each. They are scored now. Why the completeness test did not catch them: the list it holds is what could be read from the client's GlobalStrings database, and these names are not in the readable part of it (one of its ten blocks is encrypted in the install; the names may be there, or the engine may answer names that have no global string at all). So "every name on the list is classified" was true and was not enough. The unknown-name report in `/gear debug` is what found them, and stays the safety net.
- Still **not** verified: finding the spec from talents (the paste said "chosen": the owner had picked the spec by hand).

## 12. Where the study was wrong or had to change

1. **License** (D3): All Rights Reserved; nothing GPL-3 is in the plugin.
2. **Saved variable name**: `DaylightGearDB` (the shared `Update.lua` derives `ADDON .. "DB"`), not the study's `GloweyGearDB`.
3. **Spec detection**: the client's talent window reads the spec group's combat config and the three trait groups' spent points (`FX:Blizzard_PlayerSpells\Camelot\ClassTalents\Blizzard_ClassTalentsFrame.lua:86-120`), five calls with no node walk; that is what `Game.Trees()` does, not the study's `GetActiveConfigID` and node walk.
4. **Improvement per gold**: a floor, `max(price, pocket change)`, written independently of the reference addon's form.
5. **Usability**: our own class table plus the character's learned weapon skills (the client's own subclass-to-skill table), no tooltip read.
6. **Level brackets** slide between bracket middles instead of stepping.
7. **Rating constants and stat names**: the study took them from other addons' statements ("stated independently in ..."). They are in the client itself: a combat ratings table that is flat over all levels, and the GlobalStrings database. The study's worry that "percent stats arrive as ratings and need careful conversion" comes down to one division by a constant.
8. **Percent stats from tooltip text**: the study proposed pairing tooltip percents with ratings as a fall-back. Not needed (item 7) and not done: nothing reads tooltip text.
9. **Realm names**: the study's sketch keyed characters "name-realm" and houses by realm; the game stopped giving realm names, so both are keyed by GUID and realm number (section 5).
10. **Replicate calls**: not `HasRestrictions`; a 15-minute throttle per account by the wiki, a guess in Daylight UI, nothing in the client.
11. The study's "Polestar" path `DUI:Polestar\...`: a separate GPL-3 addon, not part of Daylight UI.

## 13. The audit and the fix pass (2026-11-20)

`design\audit-stage1.md`: 1 High, 7 Medium, 20 Low. Every High and Medium is fixed with a test that failed before the fix.

| # | Fix | Test |
|---|---|---|
| H1 | Both names of every stat are read (stem lookup); the list of names comes from the client and every one is scored or known and left out | `test_stats.lua`: "every stat name the client has...", "a stat answers under both of its names", "healing arrives under the bare name too" |
| M1 | No language-free amount exists; effect lines are counted by type and the item is marked (section 9) | `test_stats.lua` "effects the score leaves out..."; `test_marks.lua`, `test_window.lua`, `test_game.lua` |
| M2 | The percent has a floor and a cap in `Compare.Evaluate`, used by all three surfaces; ranking goes by gain | `test_compare.lua` "the percent has a floor..."; `test_rank.lua` "ranking goes by the gain..." |
| M3 | `empty` only when nothing is replaced; "Better" for a worn item that scores nothing | `test_compare.lua`, `test_marks.lua`, `test_window.lua` |
| M4 | Implemented: a dual wielder's one-hander is tried in both hands; owned one-handers count as off hands; the verdict names the hand | `test_compare.lua` "a dual wielder's one-hander is tried in both hands" |
| M5 | `TRAIT_CONFIG_LIST_UPDATED` and `PLAYER_ENTERING_WORLD` added, timed looks after login, nothing read in a fight | `test_core.lua` "talents not readable at login, readable later" |
| M6 | `Stats.Key` keeps the item and its roll only; mocks write links in the client's real shape | `test_stats.lua` "link identity..."; `test_rank.lua` "the same roll listed under three link shapes..." |
| M7 | Tables rebuilt from the client (rule 1); documents corrected | `test_stats.lua` "the rating figures are the client's own table..."; `test_score.lua` "the weapon skill numbers..." |

Low findings: fixed L1 (every value guarded), L5 (item data no longer rebuilds what is owned), L6 (two minutes), L7 (`%.0f`), L8 (no scan beside DaylightMogul), L10 (picker order), L11 (shorter choices in German, French, Spanish, Russian, Chinese), L12 (switches dim when Daylight UI's tooltips or bags are off), L13 ("Full scan" as Daylight UI's button reads), L14, L15 (line references), L16 (a default is not cached), L20 (a clock nobody can reset). Not changed, with the reason:

- L2: not a fault. A general attack power point does two things, and a hunter's two weights are its two values (`design\data-format.md`, 3.3).
- L3: the Holy Paladin brackets below 60 weight melee and spell crit on purpose (the bracket blends in a weapon-swinging leveling profile); the data agent's file, noted in `design\data-format.md` 3.2.
- L4: the game gives no sign of a partial stat table; nothing to act on (listed in the limits).
- L9: three idle frames per slot are the price of Bag Corner working without a reload (section 7.3).
- L17: "Most per Gold" as the default is the owner's decision D5; watch it in play.
- L18: weights sliding toward the level 60 raid table near 60 is the bracket rule working as designed; whether the level 60 table is right for a fresh 60 is a data question (`Data\README.md`).
- L19: per the study (section 1.4) CheapUpgrades' commands are `/cu` and `/cheapupgrades`; its files were not opened to confirm.

## 14. Checks

```
python -I ~/tools/compile51.py .            Lua 5.1 compile of every file
~/tools/luacheck/luacheck.exe .             lint (config in .luacheckrc)
python -I Tools/tests/run.py                eleven test files
python -I Tools/locales.py                  six languages against the code
python -I Tools/data/check.py Data/Weights.lua    the data's own checks
python -I Tools/client_facts.py             re-reads the stat names and the ratings table from the game
python -I Tools/tests/bench.py              not a check: per-frame timings at a real-size house
python -I Tools/tests/bench.py <folder>     the same for another copy of the plugin (before and after)
```
