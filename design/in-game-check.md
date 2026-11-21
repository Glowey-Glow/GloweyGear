# Glowey's Gear: the next run in the game (about ten minutes)

The first run (2026-11-20) found lag with the window up at a large Auction House, and one `/gear debug` paste from it settled several open questions (listed at the end). The loops behind the lag were rebuilt. **Step 0 is new and comes first: it is the one that proves the lag is gone.** The rest is the first run's list, with what is already settled marked. Each step says what to do, what a good result looks like, and what to paste back if it is not good.

**Before you start**

1. Link the folder into the game: `D:\World of Warcraft\_forever_\Interface\AddOns\DaylightGear` must point at `E:\daylight\DaylightGear` (a junction, like the other plugins).
2. Turn BugSack on (or `/console scriptErrors 1`).
3. Log in on a character with talents spent and some gear in the bags. A healer or caster is the most useful first character.

`/gear debug` prints to chat. To paste its lines back: shift-click drag in the chat frame does not copy, so use Daylight UI's chat copy button, or take a screenshot.

---

## 0. The lag (2 minutes)

**Do:** `/reload`. Go to the Auction House with the Upgrades for Sale window showing beside Daylight UI's window. Press Daylight UI's **Full scan** and keep the window up until its list has filled and the line under its title no longer says "Reading" or "Scoring". Then, within a minute, type `/gear debug`.

**Good:**
- The game stays smooth during the scan and after it, with the window up.
- `longest frame of our own work in the last minute, by part (ms): market ..., scoring ..., paint ..., context ..., marks ...`: market and scoring at about 3 to 5, paint and context under about 10. (These are milliseconds of our code in the worst single frame; a frame at 60 a second is 16.)
- `in the last minute: ... refreshes, ... new jobs, ... reads of what is owned, ... paints ...`: single or low double digits. Hundreds would mean something loops.
- `window: ... job: N of N saved items fed, M dropped unread (...), K read, U upgrades`: K is a few thousand at most, far below N.
- `window: job done; 0 queued, 0 waiting for item data ...` a short while after the scan.
- `market: ... gear items that could not be read:` a small number compared with the items saved.

**Not good, paste back:** the lines starting `longest frame`, `in the last minute`, `events in the last minute`, both `window:` lines, and the `market:` lines `last read`, `rows skipped` and `saved for`. If the game stutters, say when: during the scan, right after it, or all the time the window is up. Then fold the window to its tab (the small tab at its corner) and say whether the stutter stops: with the window folded the plugin does nothing but read the scan.

## 1. Login (1 minute)

**Do:** log in. Open Daylight UI's options. Type `/gear`. Type `/gear debug`.

**Good:**
- No error.
- "Gear" is in the options rail under Plugins, and its page draws with every row.
- `/gear` opens the Upgrades for Sale window (it says there is no list yet).
- The first debug line reads like `spec WARRIOR.FURY (talents), level 34; weights: ...`. The word in brackets must be `talents` on a character with points spent.
- The `character:` line shows `realm name not given by the game` (expected on this client now), a realm number, and `saved under its GUID: yes`.

**Not good, paste back:** the error text; or the first two debug lines if the bracket says `default` or `last` on a character with talents (then wait 30 seconds, type `/gear debug` again, and paste that too: it tells whether the talents arrive late or never).

## 2. Stat names (2 minutes)

**Do:** hover six items, in the bags or on the character sheet:

1. one with only plain green stats (+Stamina, +Strength);
2. one with "Equip:" spell power or healing;
3. one with "Equip:" attack power;
4. one with hit or critical strike;
5. a weapon;
6. a rolled "of the ..." item.

After **each** hover, type `/gear debug` and look at the lines `last item:` and `its tooltip:`.

**Good:**
- `stat keys with no mapping: none`.
- `last item:` lists every bonus the tooltip shows, in our names: `HEAL 40`, `SPELL_DMG 24`, `AP 20` and `RAP 20` (both, for general attack power), `CRIT 1` and `SPELL_CRIT 1` for "1%" of critical strike (14 rating), `HIT 1` and `SPELL_HIT 1` for 1% hit (10 rating), `MH_DPS 41.5` on a weapon, `ARMOR`.
- `its tooltip:` says how many effect lines the tooltip has and `effects not counted: 0` for items whose every bonus is in the list.

**Not good, paste back:**
- Any name after `stat keys with no mapping:` (a stat the plugin does not know).
- The `last item:` and `its tooltip:` lines for an item where the tooltip shows a bonus the list lacks, with the tooltip's own wording of that bonus. This is the most important thing this step can find.
- The `its tooltip:` line if it says `the game gave no effect line types` (then the "special effect is not counted" note can never show).
- The `fields on its effect lines:` line, whatever it says (one copy is enough).

## 3. A rolled item (1 minute)

**Do:** hover two different rolls of the same item (two "of the ..." versions; chat links work). Read the Gear Advice row on each, then `/gear debug` after each.

**Good:** the two `last item:` lines show different stats and different keys ending in `:1:<number>`, and the two rows differ.

**Not good, paste back:** both `last item:` lines if the stats or the keys are the same.

## 4. The percent, the words and the off hand (1 minute)

**Do:** hover rings, necks, trinkets and cloaks in your bags, and one-hand weapons if the character dual wields.

**Good:**
- Percents are believable: most under 100, none in four digits. A much better item reads "Far better than your Neck".
- "Fills your empty ... slot" appears only for a slot that really has nothing in it.
- A dual wielder's one-hand weapon that beats the off-hand weapon reads "... over your Off Hand".
- An item with a Use effect or a "Chance on hit" has a second line: "Gear Advice does not count this item's special effect."

**Not good, paste back:** the row's text, the two items' names (the hovered one and the worn one), and the `last item:` line.

## 5. Full scan (3 minutes)

**Do:** go to the Auction House. The Upgrades for Sale window should sit against the right edge of Daylight UI's window. Press Daylight UI's **Full scan**. Watch our window: its sub-line counts rows, then the list fills. Then `/gear debug`.

**Good:**
- The list fills with one row per slot; no error; the game does not stutter while it reads.
- `kept items by link: N plain, 0 with a suffix field, N with bonus IDs` with a bonus-ID count above zero.
- `rows skipped:` shows mostly `no buyout` and `not gear`. `item never loaded` and `roll only in the name` are small or absent.
- `reads started 1, started over 0` (or 1).

**Not good, paste back:** all the debug lines from `house` to `our own read:`. In particular the line `a rolled link:` (it shows what an Auction House link really looks like: whether the roll is in it, and whether a context or `:1:28:` modifier is too) and `a roll only in the name (left out):` if present.

## 5a. Prices after the scan (3 minutes)

**Do, right after step 5, with the Auction House still open:**
1. Wait about 20 seconds, then `/gear debug`. Read the two lines `rows with no link in time, by cause:` and `the tail ...`.
2. Click a row of our window that is an "of the ..." roll. Daylight UI switches to Buy. Hover the row again.
3. Buy the cheapest auction of some cheap row (or have a friend buy it), then look at that row.
4. Press **Check Prices** in our window; watch the line under the title; press **Stop** before it ends, then press Check Prices again and let it end.
5. `/gear debug` once more.

**Good:**
- After 1: the tail line says rows were read since, and `gear items that could not be read` went down from the count at the end of the scan. The window's "could not be read" count shrinks with it.
- After 2: the row's tooltip ends with "Price checked just now." If the cheapest one had sold, the row shows the new price or is gone, and the line under the title counts it ("1 is no longer for sale.").
- After 3: the row shows the next price, or drops out, without another search.
- After 4: "Checking prices: 3 of 12." counts up, the button reads Stop meanwhile, and Daylight UI's own Buy page still works while it runs.
- After 5: `prices: N search results read; N prices corrected, N marked as none left`, `Check Prices sent N searches, N answered, 0 failed`, and `result sets whose links showed no roll for a suffixed item: 0`.

**Not good, paste back:** every `prices:` line, the `rows with no link in time, by cause:` line and the tail line. If a rolled row was marked gone while it is plainly still for sale (or the other way round), also the row's name.

## 5b. Stage 2 (5 minutes)

**Do:**
1. `/gear debug`, and read the `hit:` line and the two `other addons on ...` lines.
2. With the Upgrades for Sale list scored, look under Main Hand and Off Hand for a row labeled **Weapons** ("Both Together"). Click it; hover its two items.
3. Hand in (or pick up to hand in) a quest that offers a choice of gear. Hover the rewards.
4. Do a second Full scan a while after the first (or press Check Prices), with the window up.
5. With Polestar loaded: a few seconds after login a window "Glowey's Gear" asks about bags and tooltips. Press Apply as it stands, open the bags, then go to the options (Plugins, Gear, Other Addons), switch **Leave Bag Marks to Them** on, and look at the bags again.

**Good:**
- After 1: `hit: melee and ranged X% of 8` (or `of 5` below level 60, `of 27` dual wielding), where X is what the character sheet's Hit Chance says, and the "not from gear" part matches your talents. A capped character sees a hit item score as if it had no hit.
- After 2: the row is there only when two items for sale beat your weapons by more than the Main Hand and Off Hand rows add up to; it opens to exactly two items, each saying its hand; neither is something your class cannot hold.
- After 3: one chat line "Best quest reward for you: [Item] (...)." about half a second after the page opens, once; that reward's tooltip has the Gear Advice row and "Best reward of this quest for you." A quest with one reward says nothing.
- After 4: at most one line "New best upgrade for sale: ..." and only if a slot's pick really changed for the better; the link in it can be clicked.
- After 5: with Apply, Polestar's bag arrows are gone and ours show; with the switch on, ours are gone and Polestar's are back. Nothing else of Polestar's changed.

**Not good, paste back:** the `hit:` line with what the character sheet shows; the chat line and the rewards' names; the `other addons on ...` lines; for the pair, the two items' names and your class.

## 6. A saved roll, read back (1 minute)

**Do:** in our window, hover a row whose item is an "of the ..." roll. Then click it.

**Good:**
- The tooltip shows the roll's own name and stats, not the plain item's.
- The click switches Daylight UI's window to Buy and searches that exact name, and the roll is in the results.

**Not good, paste back:** the row's name, what the tooltip shows, and `/gear debug`'s `last item:` line after the hover.

## 7. Close and come back (1 minute)

**Do:** close the Auction House. Walk a few steps. Type `/gear`: the window opens on its own with the same list; Escape closes it. Type `/gear debug` and read the line `when the Auction House closed the list had ...`. Then `/reload`, and `/gear` again.

**Good:** the list is there before and after the reload, scored, with the Auction House closed. The age line says when it was read.

**Not good, paste back:** the `when the Auction House closed ...` line and the `saved for ...` line.

---

## If there is time

- Bags open during a fight: marks stay as they were, no error; after the fight they catch up.
- The fold tab on the docked window; Max Price up and down; Best Pick.
- A controller: D-pad through the rows, A on a row, LB / RB for Best Pick, B to close.
- Bag Corner in the options moves the green plus at once.
- A second character: its spec choice is its own.

## What each step settles

| Open question | Step |
|---|---|
| Is the lag gone, and what does our code really cost per frame on this client? | 0 |
| Are the talent trees readable at login, and in the classic left-to-right order? **Still open:** in the first run the spec had been picked by hand ("chosen"). Set Spec to Auto on the options page before step 1. | 1 |
| Does `GetItemStats` answer names the client's list lacks? Does healing arrive under the bare name? | 2 |
| Which bonuses does `GetItemStats` leave out, and does the game type effect lines (44, 45, 46)? Do they carry any field beyond text? | 2 |
| Is one hit or crit rating reported once (general) or split? Is "damage and healing" one stat beside a damage-only one? Is bonus armor inside the armor figure? Which name does a feral weapon's bonus use? | 2 |
| Does the stat call apply a roll for a full link? | 3 |
| Are the floor and the "far better" cap of the percent sensible in play? Is the off-hand rule right? | 4 |
| ~~Do replicate links carry the roll as bonus IDs?~~ **Settled: yes** (13,472 of 16,159 items; field 13 the count, field 14 the ID). Do they also carry a context or modifiers? | 5 |
| Does `GetItemStats("item:<saved key>")` give the rolled stats, and `GetItemInfo` the rolled name? Does a search by a rolled name find the roll? | 6 |
| Do search-result links carry the roll as bonus IDs, as scan links do? (`showed no roll for a suffixed item` must stay 0.) Does Daylight UI's item search for gear really return every roll, so "none left" is right for rolls? Does the purchase event arrive with the auction ID we read? | 5a |
| Why did a quarter of the gear rows give no link in time (which cause), and does reading them again while the house stays open bring them in? | 5a |
| Does `GetHitModifier` give the talent part of hit alone (no gear, no rating)? Is the Weapons row right for a real character? Do `QUEST_COMPLETE` and the choice calls behave as read, in Daylight UI's quest window and the game's? Does Polestar follow `Set("gear.bagArrows", false)` at once? Does the overlap window work with a controller? | 5b |
| ~~Does the replicate list survive the Auction House closing?~~ **Settled: no** (0 rows at the close). Step 7 still checks the saved list. | 7 |
| How many gear rows are still lost as "item never loaded" now that a row is read as soon as it has a link (27,689 of 85,406 before)? | 0, 5 |
| Still open after this run: what `GetItemUniquenessByID` answers for "Unique" versus "Unique-Equipped"; whether an untrained weapon skill reads as nil; whether `C_PlayerInfo.CanUseItem` knows class restrictions; the real scan cooldown; how our rows and marks sit beside Polestar's. | |
