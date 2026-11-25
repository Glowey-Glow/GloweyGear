# Glowey's Gear

**Gear advice for Daylight UI on WoW: Forever. It scores gear for your spec, tells you what is an upgrade over what you wear and carry, and lists the best upgrades for sale on the Auction House by improvement per gold.**

By Glowey. A standalone addon that **integrates with Daylight UI** when it's installed: its pages sit in Daylight UI's options window, in its look, and ride in its profiles (not part of Daylight UI itself: report its bugs here, not to Daylight UI). Without Daylight UI, its settings are in the Glowey's Plugins window (**/glowey**, or Options > AddOns). It is not affiliated with any other gear addon, and uses none of their code, data or scales.

---

## New in 1.2.1
- **Comparisons in Glowey's Recipes too:** hovering a crafted item there shows Gear's comparison beside it. Other addons can ask for it the same way (GloweyGearAPI.Compare).
- **Comparison tooltips:** hover an item in Upgrades for Sale and the piece it replaces shows beside it, headed **Equipped** or **In Your Bags**, with the game's list of stat changes. Holding Shift still shows the game's own comparison, on the other side.
- **Works with your Auction House addon:** while AuctionMaster, AHDB, Auctioneer or ForeverForge Auction is installed (or Auctionator with its whole-house scan on), their full scan is the way and Gear reads the list it fetches. Auctionator on its default scan, TSM and Oribos Exchange no longer hide Gear's own scan.
---

## What's in it

### Upgrades for Sale
- **The best upgrade on the Auction House for every gear slot**, with its price and how much better it is than what you own ("+12%", "Far Better" when a percent would be meaningless, or "Empty Slot" when you have nothing there). Select a slot to see up to ten alternatives.
- **Most per Gold or Biggest Gain:** rank by the most improvement for each gold spent, or by the biggest improvement within your max price. **Max Price per Item** keeps it within what you want to spend.
- **Reads the scan you already run:** the auctions Daylight UI's **Full scan** fetched, or the full scan of Auctionator, AuctionMaster, AHDB, Auctioneer or ForeverForge Auction; without one, **Scan the Auction House** goes through the weapon and armor pages itself. It keeps the gear list for each Auction House, so the window also works away from it.
- **Click an item** (or press A on a controller) to search it on the Buy page of Daylight UI's Auction House. **It never buys anything for you.**
- **Prices stay true after the scan.** Whenever you look at an item in the Auction House, its row gets the current price, and items that sold out drop off the list. **Check Prices** looks up everything shown, one item at a time.
- **Weapon pairs:** a main hand and an off hand that are the better buy together get one row, priced as a set.
- **Compare as you hover:** beside an item's tooltip, the piece it replaces (Equipped or In Your Bags) and the stat changes the swap makes.
- **Docked** flush against Daylight UI's Auction House window while that is open (or the game's own Auction House window, if that's the one you use), with a fold tab; on its own anywhere else. Open it with `/gear`.

### Item tooltips
- **One Gear Advice row** on gear tooltips, in both of Daylight UI's tooltip looks: "+12% over your Chest", "No better than your Chest", "Fills your empty Finger slot" or "Wearable at level 40". If you dual wield, a one-hand weapon is judged for the hand it helps most ("+8% over your Off Hand").
- Gear your class can't wear gets no row, and neither does what you already have on.

### Bag slots
- **A green plus** in a corner of bag and bank slots that hold an upgrade, on Daylight UI's bags. **Bag Corner** moves it to the corner you like.

### Your spec
- **Your own stat weights:** the Stat Weights page has a box for each stat; only the ones you change are yours, the rest keep following Glowey's recommendation.
- **Found from your talents:** the tree with the most points. Before your first talent point a Leveling profile is used. Or pick a spec yourself.
- **Upgrades are measured against the best you own** for that slot, worn or in your bags, so it never suggests buying something worse than what you already carry.
- **Smallest Gain to Show** (3% to start) leaves out upgrades too small to care about; **Only My Best Armor Type** leaves out armor lighter than the heaviest your class wears.
- **Hit you do not need is not counted:** the game's own hit caps, with your hit added up from your gear and talents.
- **Quest rewards:** when a quest gives a choice, a chat line names the best reward for you.
- **Chat Alert:** one quiet line when the Auction House has a better buy for a slot than last time.

---

## What it needs

- Nothing else: **Daylight UI** 2.1 or later is optional.
- For the Upgrades for Sale list: **a Full scan in Daylight UI's Auction House**. Without it, a full scan by another Auction House addon, or the window's own **Scan the Auction House**.
- For the bag mark: Daylight UI's bags.

---

## About the numbers

Stat weights are **a starting point, not a final answer**, and can be wrong for your build. Level 60 weights for many specs are derived from the stat weight presets of the [WoWSims](https://wowsims.com) simulator for WoW: Forever ([github.com/wowsims/forever](https://github.com/wowsims/forever), MIT License, Copyright (c) 2022 wowsims team; the notice ships in `CREDITS.md`). The rest, and all weights below level 60, are our own.

---

## What it does not do yet

- **Weapon speed** counts for nothing yet.
- **Talents, procs, Use effects, some Equip effects, set bonuses, enchants and gems** are not counted: an item is the sum of its plain stats. An item with an effect that is not counted says so on its tooltip, and has a * in the list.
- **Class-restricted and profession-only gear** can be suggested wrongly.
- **Your bank and your other characters** do not count as owned: only what you wear and carry.
- No second spec to follow.
- **No mark on quest reward tiles:** the best reward is named in chat and on its tooltip.
- **The chat alert** speaks when the list is scored, which is while the Upgrades for Sale window is up.
- **Other gear addons:** only Polestar's own marks can be switched off for you. With Pawn, Forever Leveling BiS or CheapUpgrades, both show unless you switch theirs off in their options.
- Shown next to another gear addon's advice, the two can disagree: they use different weights.

---

## In your language
Glowey's Gear speaks German, French, Spanish, Russian, Korean and Simplified Chinese (machine drafts, corrections welcome; words the game already translates use the game's own wording).

---

## How to use it

- **Settings:** Daylight UI options > **Plugins > Gear**.
- **The list:** run a Full scan in Daylight UI's Auction House, then `/gear`.
- **Controller:** the window, the welcome and the tour work with a controller.
- **Help** on the settings page: **Retake Tour** and **What's New**.

---

*Copyright (c) 2026 Glowey. All rights reserved. Free to download and play with. Stat weights derived from WoWSims are used under the MIT License.*
