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
- A best two-hander for sale stays a row of the Main Hand slot, as in stage 1. The pair is shown only when it gains more than the Main Hand pick and the Off Hand pick of the list add up to. With a two-hander as the Main Hand pick the two picks cannot be held together, so the pair then has to beat the larger of them, not their sum (audit L1). Two purchases that simply add up are already told by those two rows.
- The pair, the worn set and a two-hander are all valued as whole outfits under the hit cap (section 2), so a pair identical to the one worn gains nothing (audit M1) and a pair that starts or ends dual wielding gets the cap it makes (audit M3).
- Only the weapons in the short lists are remembered (audit L2). Check Prices asks about both items of a pair (audit L12).
- Also fixed in the single-item verdict: a unique-equipped weapon is never set beside an owned copy of itself.

**Where it shows.** One row "Both Together" under the two hands, labeled Weapons, with the pair's gain and total price. It opens to its two items (each labeled with its hand and its own price; a click searches it). No item is listed twice by default.

**Limits.** The short lists are filled at the prices of the moment an item is scored; a correction later updates a remembered item's price and whether it is gone, but does not bring back an item that had dropped off a list. Dual-wield talents and off-hand hit penalties beyond what the weights hold are not modeled.

---

## 2. Hit cap (`Compare.lua`, `Game.HitModifiers`, `ns.ReadHitMod`)

**What it does.** Hit beyond what is needed never to miss is not scored.

**The figures** are the client's own, from the text of its Hit Chance tooltip (`CR_DEFAULT_HIT_CAP_TOOLTIP` and `CR_ROGUE_HIT_CAP_TOOLTIP` in the GlobalStrings database, file 1394440): raid bosses 8% melee and ranged, 17% spells, 27% dual wielding; targets of the character's own level 5%, 4%, 24%. Second reference: `FX Blizzard_UIPanels_Game\Camelot\PaperDollFrameStats.lua:460-461` (5.0 and 4.0 at the same level, 17.0 for spells three levels up; its 9.0 for melee three levels up is not what the tooltip shows and is used nowhere in that file, so the tooltip's 8% stands). The owner's Essentials uses the same figures.

**The rule (rewritten after the stage 2 audit, M1 to M3 and L5).**
- Which cap: at level 60 the raid boss figures (the level 60 weights are made for raids); below 60 the same-level figures. The leveling brackets of the weights already make a point of hit worth less; the cap is about how much hit counts. The two do not interact beyond that.
- **Three kinds of attack, each with its own cap and total.** The weights have two hit stats, `HIT` (melee and ranged) and `SPELL_HIT`. For a hunter `HIT` is ranged hit (the ranged share from the game, 8% / 5%, never a dual wield figure); for every other class it is melee hit. A stat the weights do not value is not looked at.
- **Dual wielding** (an off-hand weapon is held; melee only). The 27% (24%) figure is for normal swings; special attacks never miss from 8% (5%). Two references: the client's rogue tooltip lists "8.00% Melee/Ranged" beside "27.00% Dual Wielding", and the client names the two kinds itself (`STAT_HIT_NORMAL_ATTACKS`, `STAT_HIT_SPECIAL_ATTACKS`). So hit counts in full up to 8%, and from 8% to 27% for `Compare.DUAL_SHARE` of its weight, **one half**. That share is our own estimate of the part of a dual wielder's damage that normal swings do, the same for every class: the upstream presets hold one hit weight and nothing for hit past the cap (`Tools\data\upstream.json` has only `StatHitRating`), and no table of damage shares ships. Past 27% hit counts for nothing.
- What the character has: the hit on every worn item, from its link (ratings: 10 per 1%), plus the part that does not come from ratings.
- **The part not from ratings** is read from the game, not from a table: `GetHitModifier`, `GetRangedHitModifier` (hunters), `GetSpellHitModifier`. The client's own character sheet adds exactly these to the rating's share (`FX ...\Camelot\PaperDollFrameStats.lua:524-527`); the docs mark them secret while unit stats are restricted (`DOC PlayerScriptDocumentation.lua:533-541`, `:946`, `:1113`). They are read only out of a fight, at login and when talents or the level change, and kept per character.
- **The outfit is valued as a whole.** A verdict compares two outfits: the one the character can make today (the best owned piece or pieces in the place in question) and the one with the candidate in. Each is worth the plain scores of its pieces with their hit taken out, plus what the outfit's total hit is worth under the caps that outfit has. A two-hander in place of two weapons ends dual wielding, a second weapon starts it, and the hit worn elsewhere is charged or credited accordingly. One item, a pair and a two-hander are measured the same way; an item identical to what it replaces gains exactly nothing.

**Limits, and what the player sees.**
- *Hit from an enchant on a worn item (a scope), set bonuses, rating buffs* is not on a link and not counted: the room under the cap reads that much too large, so a capped character can still see a little value on hit. A cheap improvement exists (keep "sheet total minus hit on the worn links" as the share not from items, at the read) but it ties the read to the gear worn at that moment; not done.
- *School-specific caster hit talents* (lower resist chance for one school) are very likely not in the spell figure the game gives: such a caster keeps seeing value on spell hit they no longer need, as in stage 1. Needs a table of talents; stage 3.
- *A buff that gives hit at the moment of a read* counts as the character's own until the next read (login, talent or level change), across a relog too. A cheap improvement exists (read again out of a fight a few seconds after the player's auras change); not done, because each change of the figure rebuilds every verdict and restarts the list's scoring.
- A carried item's place in the order of "best owned" is worked out against the worn item of its slot.
- `DUAL_SHARE` is an estimate (above).

---

## 3. Quest rewards (`Quest.lua`, decision D6)

**What it does.** When a quest lets the player choose one of several rewards, one chat line names the biggest upgrade ("Best quest reward for you: [Item] (+12% over your Chest)."), and that reward's tooltip gets the line "Best reward of this quest for you." under its Gear Advice row. With **Vendor Value Hint** on and no upgrade among the rewards, the line names the one that sells for the most.

**What it reads, all public.** `QUEST_COMPLETE` (`DOC QuestLogDocumentation.lua:1332`), `QUEST_ITEM_UPDATE` and `QUEST_FINISHED` (`DOC QuestOfferDocumentation.lua:91`, `:79`); `GetNumQuestChoices`, `GetQuestItemLink("choice", i)`, `GetQuestItemInfo("choice", i)`, the calls the game's own quest frame makes (`FX Blizzard_UIPanels_Game\Mainline\QuestInfo.lua:526`, `:647`; `QuestFrame.lua:743`) and Daylight UI's quest window too (`DUI DaylightUI\Npc\Data.lua:141-147`).

**The tooltip row on a reward.** Both windows show a reward with `GameTooltip:SetQuestItem` (`FX ...\QuestInfo.lua:1297`; `DUI DaylightUI\Npc\Window.lua:260-261`). The client turns that into item tooltip data (`FX Blizzard_SharedXMLGame\Tooltip\TooltipDataHandler.lua:534`), Daylight UI's item post-call runs its plugins' "item" lines for it (`DUI DaylightUI_Tooltip\Tooltip.lua:1933-1938`), and our callback gets `data.link` and `data.itemID` (`:1344-1353`). The link is found from the data's guid, then its hyperlink, then `GameTooltip:GetItem` (`:705-722`); a reward the game is still loading can have none of the three. Then the row finds the link itself: the reward of the open quest page with that item ID (`Quest.LinkFor`: the choices and the fixed rewards). In the owner's first run the row was missing on a reward for another reason (the overlap state, section 5).

**No mark on the reward tiles.** Daylight UI's API has no frame kind for them (`DUI DaylightUI\API.md:200-215`), the tiles are built inside its window (`Npc\Window.lua:281-297`), and the game's own reward buttons are parked while that window is up (`Npc\Window.lua:36-45`). A mark would mean reading Daylight UI's internal table several times a second. Not done (the study's recommendation).

**The rule.** An upgrade as the tooltip row counts one (usable now, a real gain, not under Smallest Gain to Show). Nothing for a single reward, nothing in a fight.

**Choices that come late (audit M4).** Daylight UI's notes on this client say the page can arrive before its choices (`GetNumQuestChoices` reports 0) and that `QUEST_ITEM_UPDATE` does not always follow (`DUI DaylightUI\Npc\Window.lua:210-216`, `:750-752`). The page is looked at again on `QUEST_ITEM_UPDATE`, when any item's data arrives, and every half second on a timer of its own, 12 times at most, while fewer than two choices are there, a choice has no link, or a reward's stats are loading. After that it speaks about what it has (a choice that never gets a link, a currency, is passed over) or gives the page up. The same rewards are not spoken of twice within ten minutes (a page closed and opened again); the tooltip line is there each time.

**Vendor Value Hint is off by default.** Daylight UI's quest window already marks the best-selling reward with a coin (`Npc\Window.lua:32`, `:292`), and the standing rule is that what Daylight UI does is Daylight UI's by default.

---

## 4. Chat alert (`Alert.lua`)

**What it does.** When the list has been scored (a new scan) or prices were corrected (a search, Check Prices), the best pick per slot is compared with the pick remembered from the time before. A slot whose pick is another item and measures higher (gain per gold, or gain with Biggest Gain), or a slot that had no pick and has one now, is news. One line names the biggest: "New best upgrade for sale: [Item] for your Chest (+12%, 3g 20s)."

**Quiet by rule.** Nothing the first time a house is scored for a character, nor after the spec, Best Pick or house changed, nor (audit L7) after a change of Max Price, Smallest Gain to Show, Only My Best Armor Type, the level or what is worn and carried: those change the picks with nothing new for sale, so the picks are only remembered. One line at a time; never two within 60 seconds, and news found inside that minute is kept and said when it is over; never in a fight (and nothing is remembered then, so the news keeps); a switch (Chat Alert).

**Limit.** The list is scored while the Upgrades for Sale window is up (stage 1's rule against scoring behind a closed window stands), so news is found then. Docked beside the Auction House, the window is up.

---

## 5. Other gear addons (`Overlap.lua`, decision D7)

**What it does.** One question per surface, not per addon: **Upgrade Marks on Bags** and **Upgrade Advice on Tooltips**. Asked once, a few seconds after login, after Daylight UI's own first-login windows and the other Daylight plugins' guides; our side by default; reversible on the options page (Other Addons), where Ask Again opens the question with everything in it. A new rival on a surface asks again.

**"Ours"** shows ours and switches the other addon's copy off where it has a switch an outside addon may flip; its value from before is kept and put back when the choice is reversed. **"Theirs"** hides ours on that surface (only while such an addon is loaded). Nothing of another addon's is touched before the question is answered.

**Only where ours really shows (audit M5).** There is an overlap on a surface only while our side is on screen there: for bags, Show Gear Advice and Bag Slots on and Daylight UI's bags having taken our corner mark; for tooltips, Show Gear Advice and Item Tooltips on and Daylight UI's Tooltip module on. Otherwise no addon is a rival there, no question is asked, and anything taken is given back at once. This is looked at again at login, when an addon loads and when any setting of ours changes. Nothing is switched in a fight (it is done a moment after).

**The truth table (after the first run in the game).** The first build treated a loaded addon as a rival whatever its own switches said. The owner had Polestar's gear advice switched off and had answered "theirs": Polestar showed nothing, ours stood down, and a tooltip had no advice at all. The debug line also said "(switched by us)" for any addon that merely HAS a switch. Now, per surface, another addon's feature is in one of four states:

| Its state | Meaning | Is it a rival? |
|---|---|---|
| on | its feature shows | yes |
| off by us | we switched it off (this character holds its value from before) | yes (it is what the answer was about; not asked again) |
| off by the player | its own switch is off, or the addon's whole part is (Polestar: `gear.enabled`, `Polestar\Gear\Gear.lua:119-121`) | **no** |
| no switch we can read | Pawn, Forever Leveling BiS, CheapUpgrades: taken to show whenever loaded | yes |

And what happens, with ours on screen on that surface (otherwise: no rival, no question, everything taken is given back):

| Rival's feature | Not asked yet | Answer "ours" | Answer "theirs" |
|---|---|---|---|
| on | both show; the question is pending | we switch it off (value kept): **ours shows** | ours stands down: **theirs shows** |
| off by us | (cannot be: only an answer takes) | **ours shows** | given back: it is on again, ours stands down |
| off by the player | **ours shows**, nothing asked | **ours shows**, nothing written | **ours shows**, nothing written (it is never turned on by us) |
| no switch | both show; the question is pending | **both show** (the row says so) | ours stands down: theirs shows |
| addon not loaded | ours shows | ours shows | ours shows |

Ours stands down only when the player chose "theirs" and some rival's feature is really showing (on, or no switch). So a surface never has neither. If the player chose "theirs" and later turns theirs off, ours is back within a second, with no setting of ours changed (the other addon's switches are read again once a second at most). Restoring only ever writes back a value we took, and only where it is still off; a switch the player had off is never recorded and never turned on.

`/gear debug` says one thing per surface: each loaded addon's state ("Polestar's is on", "Polestar's switched off by us", "Polestar's is off (by the player)", "Pawn is loaded (no switch we can read)"), then what ours does ("ours shows", "you chose theirs: ours stands down", "not asked yet: both show", "ours is switched off here, so nothing is asked or taken").

**What was taken is remembered per character** (audit L9), because Polestar's settings follow its own profiles: a value taken on one character is put back on that character. Left open: two characters sharing one Polestar profile, where the second reverses the choice (the first's login puts it back).

| Addon | Bags | Tooltips | Its switch |
|---|---|---|---|
| Polestar (GPL-3) | yes | yes | `gear.bagArrows`, `gear.tooltip` through its global `Polestar.Get` / `Polestar.Set` (`Polestar\Gear\Gear.lua:104-110`, `Gear\Bags.lua:58`, `Gear\Tooltip.lua:157`, `Core\Init.lua:11`, `:966`, `:1002`), the way the owner's Addon Skins already hands Polestar settings over (`DaylightAddonSkins\Packs\Polestar.lua:458-470`) |
| Pawn | yes (Daylight UI draws Pawn's arrow itself: `DUI DaylightUI_Bags\Plugins.lua:272-284`) | yes | none verified (not installed): both show |
| Forever Leveling BiS | yes | yes | none verified (All Rights Reserved, not installed): both show |
| CheapUpgrades | no | yes | known by folder name only; its files were not opened and none of its settings is read or written: both show |

**Polestar's bag arrow and Daylight UI's bags: where this differs from the audit.** The audit (M5) says Polestar never draws on Daylight UI's bags. The registration path says it does. Polestar registers its arrow as a corner widget with whatever `_G.Baganator.API` offers `RegisterCornerWidget` (`Polestar\Core\BagSlots.lua:140-145`, `:155-168`; `Gear\Bags.lua:164`, top left, priority 1). Daylight UI's bags put exactly that table in place at load (`DUI DaylightUI_Bags\Plugins.lua:172-180`, `:199-213`), and load before Polestar (not load-on-demand; the folder sorts first). It is the same call our own mark uses. So Polestar stays a rival on bags, switched only while our mark really shows there. Step 2 of the in-game check settles it: if no Polestar arrow ever shows in Daylight UI's bags, the bag row for Polestar should go.

**Could not be done cleanly.** (1) Pawn, Forever Leveling BiS and CheapUpgrades get no hand-over: with "ours" both show, and the row says so. (2) An addon that marks bag upgrades through Daylight UI's corner-widget call without being on the list cannot be told from any other corner widget (the call takes a free name, `Plugins.lua:172`). (3) Polestar's "Best pick" on quest rewards (`gear.pickTooltip`, `gear.rewards`) is left alone: it is its own feature in its own window, and no surface of ours replaces it.

The window follows the owner's Addon Skins choice window (`DaylightAddonSkins\Choices.lua`, the owner's own): same widgets, same meaning of the switch, same waiting.

---

## 6. Options, guide, languages

Options page: Chat Alert (Upgrades for Sale); a Quest Rewards group (Best Reward in Chat, Vendor Value Hint); an Other Addons group (Leave Bag Marks to Them, Leave Tooltips to Them, Ask Again). The weapon pair and the hit cap have no switch: they are how the score works. One What's New line and one tour step (Quest Rewards). 32 new strings in six languages.

## 7. Not in stage 2

A second followed spec; "why nothing" hints per slot; the bag search word "upgrade"; a chat line for new upgrades in bags; talents and procs (stage 3).
