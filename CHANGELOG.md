# Glowey's Gear (DaylightUI Plugin)

## Unreleased
- First build, not released yet. Glowey's Gear scores gear for your spec and compares it with what you wear and carry.
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
- Fixed: lag with the Upgrades for Sale window up at a large Auction House. The window now looks only at gear your class and level can wear, takes a few milliseconds a frame at most while it works, repaints only when what it shows changed, and does nothing at all while it is closed or folded away. It no longer starts over whenever the game loads item data.
- Fixed: about a third of the gear for sale at a large Auction House could be left out of the list ("item never loaded"). A listing is now read as soon as the game has its link. What still cannot be read is counted, and the window says how many ("12 items for sale could not be read.").
- Fixed: Fire, Nature, Frost, Shadow and Arcane resistance on gear was not counted.
- `/gear debug` also reports how much time the plugin used in the last minute and what its list is doing.
- **Prices stay true after the scan.** Whenever you look at an item in the Auction House, Upgrades for Sale learns what it costs now: a row moves to its new price, and an item that sold out drops off the list ("3 are no longer for sale."). Buying an auction yourself updates the row at once. A row's tooltip says when its price was last checked.
- **Check Prices:** a button in the window that looks up every item shown, one at a time, through Daylight UI's Auction House (Stop ends it). Clicking a row checks that item too.
- Fixed: gear whose data arrived late during a Full scan could be left out of the list for good. Those listings are now read in the background while the Auction House stays open and join the list as they arrive.
