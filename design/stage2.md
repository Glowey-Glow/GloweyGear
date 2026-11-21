# Glowey's Gear: stage 2

What each piece does, the rule behind it, what it reads, and where it stops. Written with the build (2026-11-20); the code's own headers carry the same rules with their references.

Paths: `DOC` = the client's generated API docs (`Blizzard_APIDocumentationGenerated`), `FX` = the client's own UI source (Gethe/wow-ui-source, branch `forever`), `DUI` = Daylight UI 2.1.2 as installed. Nothing of CheapUpgrades was opened or used; nothing is copied from any other addon.

---

## 1. Weapon pairs from the Auction House (`Rank.Set`, `Compare.SetValue` / `PairScore` / `HandScores`)

**What it does.** Stage 1 judged one item for sale beside what is already owned. Stage 2 adds the case that cannot say: two items for sale that are an upgrade only (or mostly) together, typically a one-hander and a shield or held item for someone holding a two-hander.

**The rule.**
- What the hands are worth today: `W = max(best owned two-hander, best owned main hand + best owned off hand)` (as in stage 1).
- While the list is scored, the job remembers for each hand a short list of the weapons for sale the character can wield there, upgrade alone or not: the 8 best by score and the 8 best by score per gold. At most 16 per hand, whatever the house holds.
- Every main hand of those lists is tried with every off hand (at most 256 pairs): `gain = PairScore(main, off) - W`, `price = both prices added`. Each item must be within Max Price per Item. The best pair is the one with the most gain per gold of the pair, or the most gain (Best Pick).
- Never a pair the character cannot hold: only items that passed `Score.Usable` are remembered; a one-hander is an off hand only for a dual wielder, scored with the off-hand weights (`OH_DPS`, `OH_SPEED`) as the weights define; a two-hander is in no pair; one unique-equipped item is never both hands; one listing is never both hands.
- A best two-hander for sale stays a row of the Main Hand slot, as in stage 1. The pair is shown only when it gains more than the Main Hand pick and the Off Hand pick of the list add up to (a two-hander pick counts alone). Two purchases that simply add up are already told by those two rows.
- Also fixed in the single-item verdict: a unique-equipped weapon is never set beside an owned copy of itself.

**Where it shows.** One row "Both Together" under the two hands, labeled Weapons, with the pair's gain and total price. It opens to its two items (each labeled with its hand and its own price; a click searches it). No item is listed twice by default.

**Limits.** The short lists are filled at the prices of the moment an item is scored; a correction later updates a remembered item's price and whether it is gone, but does not bring back an item that had dropped off a list. Dual-wield talents and off-hand hit penalties beyond what the weights hold are not modeled.

---

## 2. Hit cap (`Compare.lua`, `Game.HitModifiers`, `ns.ReadHitMod`)

**What it does.** Hit beyond what is needed never to miss is not scored.

**The figures** are the client's own, from the text of its Hit Chance tooltip (`CR_DEFAULT_HIT_CAP_TOOLTIP` and `CR_ROGUE_HIT_CAP_TOOLTIP` in the GlobalStrings database, file 1394440): raid bosses 8% melee and ranged, 17% spells, 27% dual wielding; targets of the character's own level 5%, 4%, 24%. Second reference: `FX Blizzard_UIPanels_Game\Camelot\PaperDollFrameStats.lua:460-461` (5.0 and 4.0 at the same level, 17.0 for spells three levels up; its 9.0 for melee three levels up is not what the tooltip shows and is used nowhere in that file, so the tooltip's 8% stands). The owner's Essentials uses the same figures.

**The rule.**
- Which cap: at level 60 the raid boss figures (the level 60 weights are made for raids); below 60 the same-level figures. The leveling brackets of the weights already make a point of hit worth less; the cap is about how much hit counts. The two do not interact beyond that.
- Dual wielding (an off-hand weapon is worn): the dual wield figure. In practice no cap.
- What the character has: the hit on every worn item, from its link (ratings: 10 per 1%), plus the part that does not come from ratings.
- **The part not from ratings** (talents, mostly) is read from the game, not from a table: `GetHitModifier`, `GetRangedHitModifier` (hunters), `GetSpellHitModifier`. The client's own character sheet adds exactly these to the rating's share (`FX ...\Camelot\PaperDollFrameStats.lua:524-527`); the docs mark them secret while unit stats are restricted (`DOC PlayerScriptDocumentation.lua:533-541`, `:946`, `:1113`). So they are read only out of a fight, at login and when talents or the level change, and kept per character. No call is made in a fight. This is language-free and needs no table of talents. (The alternative, a table of hit talents from the client's spell-effect data, would need a reader for that database; the game answering the question itself is both simpler and exact.)
- An item's hit counts only as far as the cap has room once the item it replaces is taken off: `counted = min(its hit, cap - (hit had - hit of what leaves))`, never under 0. What is owned is valued the same way (each piece as if it were the last one put on), so a gain is always (new piece in the set) minus (old piece in the set). A pair's hit is counted over both items.
- Melee and spell hit are capped separately; a general hit rating feeds both.

**Limits.** A buff that gives hit at the moment of a read counts as the character's own until the next read. A carried item is valued against the worn item of its slot. Weapon skill (which lowers the need) is not counted. Only specs whose weights value hit are touched at all.

---

## 3. Quest rewards (`Quest.lua`, decision D6)

**What it does.** When a quest lets the player choose one of several rewards, one chat line names the biggest upgrade ("Best quest reward for you: [Item] (+12% over your Chest)."), and that reward's tooltip gets the line "Best reward of this quest for you." under its Gear Advice row. With **Vendor Value Hint** on and no upgrade among the rewards, the line names the one that sells for the most.

**What it reads, all public.** `QUEST_COMPLETE` (`DOC QuestLogDocumentation.lua:1332`), `QUEST_ITEM_UPDATE` and `QUEST_FINISHED` (`DOC QuestOfferDocumentation.lua:91`, `:79`); `GetNumQuestChoices`, `GetQuestItemLink("choice", i)`, `GetQuestItemInfo("choice", i)`, the calls the game's own quest frame makes (`FX Blizzard_UIPanels_Game\Mainline\QuestInfo.lua:526`, `:647`; `QuestFrame.lua:743`) and Daylight UI's quest window too (`DUI DaylightUI\Npc\Data.lua:141-147`).

**The tooltip row needed nothing new.** Both windows show a reward with `GameTooltip:SetQuestItem` (`FX ...\QuestInfo.lua:1297`; `DUI DaylightUI\Npc\Window.lua:260-261`), an item tooltip, so the stage 1 row comes with it.

**No mark on the reward tiles.** Daylight UI's API has no frame kind for them (`DUI DaylightUI\API.md:200-215`), the tiles are built inside its window (`Npc\Window.lua:281-297`), and the game's own reward buttons are parked while that window is up (`Npc\Window.lua:36-45`). A mark would mean reading Daylight UI's internal table several times a second. Not done (the study's recommendation).

**The rule.** An upgrade as the tooltip row counts one (usable now, a real gain, not under Smallest Gain to Show). Said once per reward page, a moment after it opens, again only if a reward had still been loading. Nothing for a single reward, nothing in a fight.

**Vendor Value Hint is off by default.** Daylight UI's quest window already marks the best-selling reward with a coin (`Npc\Window.lua:32`, `:292`), and the standing rule is that what Daylight UI does is Daylight UI's by default.

---

## 4. Chat alert (`Alert.lua`)

**What it does.** When the list has been scored (a new scan) or prices were corrected (a search, Check Prices), the best pick per slot is compared with the pick remembered from the time before. A slot whose pick is another item and measures higher (gain per gold, or gain with Biggest Gain), or a slot that had no pick and has one now, is news. One line names the biggest: "New best upgrade for sale: [Item] for your Chest (+12%, 3g 20s)."

**Quiet by rule.** Nothing the first time a house is scored for a character, nor after the spec, Best Pick or house changed (only remembered). One line at a time; never two within 60 seconds; never in a fight (and nothing is remembered then, so the news keeps); a switch (Chat Alert).

**Limit.** The list is scored while the Upgrades for Sale window is up (stage 1's rule against scoring behind a closed window stands), so news is found then. Docked beside the Auction House, the window is up.

---

## 5. Other gear addons (`Overlap.lua`, decision D7)

**What it does.** One question per surface, not per addon: **Upgrade Marks on Bags** and **Upgrade Advice on Tooltips**. Asked once, a few seconds after login, after Daylight UI's own first-login windows and the other Daylight plugins' guides; our side by default; reversible on the options page (Other Addons), where Ask Again opens the question with everything in it. A new rival on a surface asks again.

**"Ours"** shows ours and switches the other addon's copy off where it has a switch an outside addon may flip; its value from before is kept and put back when the choice is reversed. **"Theirs"** hides ours on that surface (only while such an addon is loaded). Nothing of another addon's is touched before the question is answered.

| Addon | Bags | Tooltips | Its switch |
|---|---|---|---|
| Polestar (GPL-3) | yes | yes | `gear.bagArrows`, `gear.tooltip` through its global `Polestar.Get` / `Polestar.Set` (`Polestar\Gear\Gear.lua:104-110`, `Gear\Bags.lua:58`, `Core\Init.lua:11`, `:966`, `:1002`), the way the owner's Addon Skins already hands Polestar settings over (`DaylightAddonSkins\Packs\Polestar.lua:458-470`) |
| Pawn | yes (Daylight UI draws Pawn's arrow itself: `DUI DaylightUI_Bags\Plugins.lua:272-284`) | yes | none verified (not installed): both show |
| Forever Leveling BiS | yes | yes | none verified (All Rights Reserved, not installed): both show |
| CheapUpgrades | no | yes | known by folder name only; its files were not opened and none of its settings is read or written: both show |

**Could not be done cleanly.** (1) Pawn, Forever Leveling BiS and CheapUpgrades get no hand-over: with "ours" both show, and the row says so. (2) An addon that marks bag upgrades through Daylight UI's corner-widget call without being on the list cannot be told from any other corner widget (the call takes a free name, `Plugins.lua:172`). (3) Polestar's "Best pick" on quest rewards (`gear.pickTooltip`, `gear.rewards`) is left alone: it is its own feature in its own window, and no surface of ours replaces it.

The window follows the owner's Addon Skins choice window (`DaylightAddonSkins\Choices.lua`, the owner's own): same widgets, same meaning of the switch, same waiting.

---

## 6. Options, guide, languages

Options page: Chat Alert (Upgrades for Sale); a Quest Rewards group (Best Reward in Chat, Vendor Value Hint); an Other Addons group (Leave Bag Marks to Them, Leave Tooltips to Them, Ask Again). The weapon pair and the hit cap have no switch: they are how the score works. One What's New line and one tour step (Quest Rewards). 32 new strings in six languages.

## 7. Not in stage 2

A second followed spec; "why nothing" hints per slot; the bag search word "upgrade"; a chat line for new upgrades in bags; talents and procs (stage 3).
