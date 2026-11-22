# Glowey's Gear (DaylightUI Plugin)

## 1.0.6
- Other addons can ask Gear whether an item is an upgrade (GloweyGearAPI.Upgrade, and GloweyGearAPI.Watch to hear when the answers change). Glowey's Recipes 3.0.7 uses it to put an upgrade arrow on the recipes whose item would be one for you. Nothing changes in Gear's own window, tooltips or bag marks.

## 1.0.5
- The Gear Advice row shows on item tooltips without Daylight UI's tooltips too. Until now the row was handed to Daylight UI's Tooltip module, which only draws plugins' lines while it draws the tooltips itself: with that module switched off, or another addon styling the tooltips in its place, the row was gone. It is now written into the game's own tooltip in those cases, so the game's look or the other addon shows it. With Daylight UI's tooltips on, nothing changes.

## 1.0.4
- The window docks to the game's own Auction House window too. Until now it only docked to Daylight UI's Auction House, so a player who keeps the game's window (Daylight UI's Auction House switched off, or an addon built on the game's window) got it loose on the screen. It now sits flush against that window's right edge (the left one when the right has no room), follows it, and folds to its tab the same way. Daylight UI's window still comes first when it is the one in use.
- Beside the game's window a click on a row still says what to type in its search box: only Daylight UI's Buy page takes the search by itself.

## 1.0.3
- Gear that asks for a profession is no longer recommended to a character who lacks it. Engineering goggles, the fishing hats and poles, the blacksmith's and alchemist's trinkets and the like (72 items, from the game's own item table) are checked against your professions and your skill in them: one you can't equip is left out of the Auction House upgrades and gets no upgrade mark in your bags.
- Its tooltip says why instead: "Needs Engineering (150)".
- A profession's racial or worn skill bonus counts, as it does for the game.

## 1.0.2
- Fixed: the plugin's icon on Daylight UI's options rail did not show in 1.0.1 (a wrong file path).

## 1.0.1
- Glowey's Gear has its own icon: in the addon list, and on Daylight UI's options rail.

## 1.0.0
- First release. Glowey's Gear scores gear for your spec and compares it with what you wear and carry.
- Your spec is found from your talents (the tree with the most points); before your first talent point a Leveling profile is used. You can pick a spec yourself on the options page: Daylight UI options, Plugins, Gear.
- Stat weights for every class and talent tree, with their own values for leveling that change smoothly as you level. They are starting values: level 60 weights for many specs are based on the WoWSims simulator, the rest are our own.
- Options: Smallest Gain to Show, Only My Best Armor Type, Max Price per Item, and Best Pick (Most per Gold or Biggest Gain).
- **Upgrades for Sale:** a window with the best upgrade on the Auction House for each gear slot, with its price and how much better it is than what you own ("+12%", "Far Better" when a percent would mean nothing, or "Empty Slot"). Select a slot to see up to ten alternatives. Open it with `/gear` or the button beside Daylight UI's Auction House window.
- The list is ranked by improvement per gold (Most per Gold) or by the biggest improvement within your max price (Biggest Gain); Max Price and Best Pick can be changed right in the window.
- It reads the auctions Daylight UI's Full scan fetched, with no scan of its own, and keeps the gear list for each Auction House, so the window also works away from it. Where Daylight UI's Auction House is not in use, the window has its own scan button (the game allows one about every 15 minutes).
- Click an item (or press A on a controller) to search it on the Buy page of Daylight UI's Auction House. Glowey's Gear never buys anything for you.
- The window docks flush against Daylight UI's Auction House window while that is open, folds away from a tab, and stands on its own otherwise (Dock to the Auction House in the options).
- **Item tooltips:** one Gear Advice row on gear says how much better it is than your best for that slot ("+12% over your Chest"), that it is no better, that it fills an empty slot, or the level you can wear it at. Gear your class can't wear gets no row, and neither does what you have on.
- **Bag slots:** a green plus in a corner of bag and bank slots that hold an upgrade (Daylight UI's bags). Bag Corner in the options moves it, with no reload.
- A welcome on first launch and a short tour; Retake Tour and What's New are on the options page under Help.
- Works with a controller: the window, the tour and the welcome.
- Nothing is worked out in a fight: tooltips and bag slots show what was known before it, and catch up when it ends.
- English, German, Spanish, French, Korean, Russian and Simplified Chinese.
- If you can dual wield, a one-hand weapon is judged for the hand it helps most, and the row says which ("+8% over your Off Hand").
- An item with a Use, proc or Equip effect that cannot be counted says so on its tooltip ("Gear Advice does not count this item's special effect.") and has a * in the list.
- A percent is never inflated by a near-worthless item in the slot: it is measured against at least half a typical piece of your own gear, and beyond +200% it reads "Far better". A slot holding an item your spec gets nothing from is no longer called empty.
- Your spec choice is kept per character even though the game no longer gives realm names.
- `/gear debug` prints what the plugin knows (your spec and how it was found, stat names it does not know, what it read from the Auction House), for a bug report.
- **Prices stay true after the scan.** Whenever you look at an item in the Auction House, Upgrades for Sale learns what it costs now: a row moves to its new price, and an item that sold out drops off the list ("3 are no longer for sale."). Buying an auction yourself updates the row at once. A row's tooltip says when its price was last checked.
- **Check Prices:** a button in the window that looks up every item shown, one at a time, through Daylight UI's Auction House (Stop ends it). Clicking a row checks that item too.
- **Weapon pairs:** when a main hand and an off hand for sale are the better buy together (a one-hander and a shield against your two-hander, say), Upgrades for Sale shows them as one row, "Both Together", with the pair's gain and total price. It never suggests a pair you cannot hold.
- **Hit cap:** hit you do not need is not counted. The cap is the game's own (8% melee and ranged and 17% spells against raid bosses at level 60; 5% and 4% against targets of your level while leveling). Your hit is added up from the gear you wear and the hit the game reports beyond your gear (talents that raise melee, ranged or all spell hit; not enchants, set bonuses or talents for a single spell school). If you dual wield, hit past the cap still counts at half value up to 27% (24% while leveling), because it only helps normal swings.
- **Quest rewards:** when a quest lets you choose a reward, a chat line names the biggest upgrade for you (also when the rewards load a moment after the page; not again when you reopen the same page), and that reward's tooltip says so too. Vendor Value Hint (off to start) names the reward that sells for the most when none is an upgrade.
- **Chat Alert:** one quiet line when the Auction House has a better buy for a slot than last time. Never in a fight, never more than one a minute.
- **Other gear addons:** if Polestar, Pawn, Forever Leveling BiS or CheapUpgrades also points out upgrades where Gear Advice does, Glowey's Gear asks once who does it on bags and on tooltips. Gear Advice by default; you can change it back any time under Other Addons in the options. Another addon's own marks are only switched off while Gear Advice really shows in that place, and come back when it does not. An addon whose gear advice you have switched off yourself does not count: Gear Advice simply shows, and nothing is asked.
- A unique-equipped weapon is never suggested beside a copy of itself you already hold.
- A long Gear Advice verdict ("Needs a weapon skill you have not trained") goes on a line of its own under its label on the tooltip, so the label is never pushed out; short ones ("+12% over your Chest") stay beside it.
