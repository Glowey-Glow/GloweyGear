# Glowey's Gear

## 1.3.1
- Translations: every text is now in all six languages (German, Spanish, French, Korean, Russian and Chinese), Max Spend for All Slots and what it says of your picks, and the Glowey's plugins window included.

## 1.3.0
- Max Spend for All Slots: a budget for the whole set of upgrades for sale. The picks fit it together, and it says what they cost of your budget, how many slots have an upgrade over it, and what to raise it to when nothing fits.
- Max Price per Item can be typed in, in gold, like Max Spend.
- With another of Glowey's plugins on, Gear's pages sit under one "Glowey's" entry on Daylight UI's options rail.

## 1.2.4
- At the Auction House, item data coming in no longer throws away every kept bag and tooltip answer once a second: only the ones still waiting are worked out.
- The welcome no longer keeps asking every 5 seconds for the whole session while Daylight UI is busy: it gives up after ten minutes and asks at the next login.

## 1.2.3
- Settings dropdowns no longer catch the click outside them: a click on a data text, an addon drawer or anything else closes the menu and reaches what you clicked the first time.
- An error in placing Upgrades for Sale beside the Auction House is caught, so the Auction House window's own moves and shows go on.
- After Escape closes a tour card, the card no longer keeps your keys to itself (it could stop movement keys in a later fight).
- BugSack reports now end with this addon's name and version on its own errors, so a report says which version it came from.

## 1.2.2
- Scan the Auction House is offered again with Auctionator (or another scanning addon) installed but switched off. Gear asked the addon list by your character's name, which this client answers for all characters, so a switched-off Auctionator still counted and Gear's own scan stayed hidden. It now counts only a scanning addon that is loaded (or one that loads on demand and is on for this character).
- Lighter: the comparison beside an item no longer re-places itself on every frame (it moves only when Shift or the game's own comparison changes it), the Upgrades for Sale window no longer checks the Auction House window's position every frame while it's open, and the login question no longer re-asks every 3 seconds forever while you're busy.
- Without Daylight UI's tooltips, the Gear Advice line looks up the tooltip's lines once instead of on every refresh.

## 1.2.1
- Other addons can show Gear's comparison beside their own item tooltips (GloweyGearAPI.Compare, API version 2): Glowey's Recipes uses it for the items you can craft.
- The comparison beside an item moves to the other side as soon as the game's own comparison appears or goes with Shift.

## 1.2.0
- Comparison tooltips in the Upgrades for Sale list. Hovering an item now shows, beside its tooltip, the piece Gear says it replaces, headed "Equipped" when you wear it or "In Your Bags" when it's carried, with the game's own list of the stat changes the swap makes. For rings and trinkets that is the weaker of your two; under Both Together, each hand's row compares with what that hand holds now. An item that fills an empty slot shows none. Holding Shift still shows the game's own comparison with what you have equipped; Gear's then moves to the other side so both can be read.
- Scan the Auction House now knows the Auction House addons that do a full scan of their own: AuctionMaster, Auction House DataBase (AHDB), Auctioneer and ForeverForge Auction, besides Daylight Mogul and Auctionator. While one of them is installed, its full scan is the way (Gear reads the list it fetches), as the game allows only one full scan in about fifteen minutes.
- Auctionator only counts when its own full scan is set to read the whole house at once (its "replicate scan" option). By default it scans another way that Gear can't read, so Gear's own scan is offered beside it again.
- TradeSkillMaster and Oribos Exchange never block Gear's scan: neither scans the whole house in game.
- With AHDB installed, Gear's scan tells it the Auction House is in use, so AHDB's own requests wait instead of being dropped.

## 1.1.1
- A list read more than a day ago says it's stale ("Stale: List read 30 h ago."), so you know to scan again: auctions run 12, 24 or 48 hours and most are posted for 24, so by then most of it has sold or run out.
- Smoother at the Auction House: Scan the Auction House reads each page of results over a few frames instead of all at once, moving the Max Price per Item or Smallest Gain to Show setting arranges the list once a frame (and not at all while the window is closed), and looting or sorting your bags no longer reads your gear again when no gear moved.
- An owned item whose stats the game never gives (such as a trinket with only a Use effect) is now read as having no stats, instead of being waited for while every item loaded at the Auction House read your bags again. Rolled links learned by the scan that the house hasn't sold in 30 days are dropped, so the saved file no longer grows without end.

## 1.1.0
- Blizzard Style: docked to the Auction House, the window's metal frame and title bar now sit flush against the Auction House window with the tops level, instead of overlapping it and riding above it.
- With Daylight UI installed, the Upgrades for Sale window follows it more closely: its colors and tooltips change with Daylight UI's look, on its own it takes Daylight UI's scale, other windows slide aside for it, its place is kept in your Daylight UI profile, and it fades and plays Daylight UI's window sounds as it opens and closes. Beside the Auction House it keeps that window's size and leaves Escape to it. Without Daylight UI it does the same in the look you picked in /glowey, with the game's window sounds.
- Set your own stat weights. A new Stat Weights page in Gear's options has a box for every stat your spec's weights use (Show Every Stat lists the rest too, such as resistances), starting on Glowey's recommendation. Type your number in a box, and gear is scored with it at once: the Upgrades for Sale list, tooltips, bag marks and quest rewards all follow. Hit, critical strike and the other percent stats are per 1%; armor, health and mana are per 100 points.
- Only the weights you change are yours. Every other weight keeps following Glowey's recommendation, for your level and in later versions when a weight is corrected. A weight you set is used at every level. Your weights are kept per class and spec for every character on the account, and Spec to Edit picks another spec of your class to edit without changing the one gear is scored for.
- Back to Glowey's recommendation whenever you like: the revert arrow beside a weight you changed puts that one back, Revert This Spec puts every weight of the spec back, and Revert Every Spec does it for every spec of every class (both ask first). A line at the top of the page names the weights that are yours.
- The weights are a compact grid of number boxes, two or three across as the window's width allows, so the page needs little scrolling. Type a number (0 or more, up to 4 decimals) and press Enter or click elsewhere to save it; Escape cancels the edit, and Tab moves to the next box (Shift+Tab goes back). Anything that isn't such a number is ignored and the box shows the weight again. Weights you set show in the accent color with a small revert arrow beside them; the others are plain. Hover a box to see Glowey's recommendation for it. With a controller and Daylight UI, the D-pad moves between the boxes, A picks one up, left and right change it, and A or B puts it down. Daylight UI before 2.2.5 keeps the sliders.
- /gear and the Upgrades for Sale window say "with your own stat weights" while some are in use, and /gear debug lists them. A change of your weights is not taken for a new best buy by the chat alert.
- Without Daylight UI: dropdown menus fit their words. Each menu is as wide as its longest choice, its rows are as tall as the font, and in Blizzard Style it keeps the game's own margins (8 at the sides and top, 15 at the foot), so the last choice no longer runs past the bottom edge. Menus are solid, so the setting underneath no longer shows through.
- Without Daylight UI: a dropdown on a settings page is wide enough for its longest choice.
- Without Daylight UI: sliders on the settings pages can be dragged and clicked again. They were made without taking the mouse, so none of them moved.
- Without Daylight UI: a slider can be dragged all the way. The page was drawn again on every step, which let go of the slider under the mouse; it now waits until the slider is let go.
- Blizzard Style: bars are the profession window's own (its skill bar's border and fill, 14 high), such as the Chance of Skill Up bar.
- The tour has a step on your own stat weights, and What's New lists this release.
- Blizzard Style: scroll bars are the game's own (its minimal scroll bar, with arrows at both ends): drag the thumb, click the track or the arrows, as in the game's windows.
- Works without Daylight UI. Daylight UI is no longer required: with it installed nothing changes, and without it the plugin runs on its own. Its settings are then in a Glowey's Plugins window (/glowey, or the game's Options > AddOns), shared by every Glowey plugin you have, with a General page for the accent color, window opacity and moving frames. Frames move with /glowey unlock (drag; right-click puts one back), and /glowey <command> stands in for /dui <command>.
- Your settings are kept either way: they are now also saved in the plugin's own saved variable, so taking Daylight UI out keeps them, and settings made without it are taken into Daylight UI when it comes back.
- Without Daylight UI: a Look choice on the General page of /glowey for every Glowey window: Glowey's own, Blizzard Style (Blizzard's own window frames from this client: the metal frame with its title bar and red close button, dialog borders, tooltip boxes, red buttons, edit boxes, check boxes, sliders, tabs and gold text), or Polestar's when Polestar is loaded. With Polestar, Polestar itself paints the windows in the look you picked in its settings, and they change when you change it there. And a minimap button: click it for the settings, right-click to move frames, drag it round the map. It also appears in the game's addon menu, and Minimap Icon on the General page hides it.
- Blizzard Style fits its borders to each window: a small box (Essentials' combat timer, the tabs) gets the tooltip's thin border instead of the dialog's, which overlapped itself there, and the border sits round the outside of a window so it never covers what's inside.
- Without Daylight UI: the Gear Advice row is written into the game's item tooltips, and the window docks to the game's Auction House window, read with Scan the Auction House. Bag slot marks need Daylight UI's bags, so Bag Slots and Bag Corner are left out without it.
- Controller navigation of the plugin's windows comes from Daylight UI's controller support, so it needs Daylight UI.
- Scan the Auction House (the button was Read the Auction House) now really scans. It used to ask the game for its whole-house list, which the game hands out once every 15 minutes for all addons of an account together and otherwise ignores without a word, so with another scanner about the button did nothing. Now it goes through every weapon and armor category of the Auction House, the same ones the game's own Auction House lists, page by page, at the pace the game allows (one request at a time, half a second apart at least, waiting whenever the game says it is busy). Everything else in the house (trade goods, consumables and the rest) is never asked for. A bar above the button shows how far it is, with the categories done and the items found, and the button stops it and goes on with it. Closing the Auction House pauses it, and it picks up from the category it was in. Items with a random roll ("of the Bear") are listed under their own roll: the game's sample link of the item says which, and for the few it doesn't, the scan searches that item at the end, under the game's limit of 100 searches a minute; rolls it learns are kept, so later scans need fewer. When it ends, the list is saved and the upgrades are scored as before. /gear debug says what the scan did.
- Beside the game's own Auction House window, a left click on an item in the upgrade list now puts its name in the Auction House's search bar and runs the search (switching to the Buy tab and letting go of a picked category first), as it already did in Daylight UI's Auction House. Until now it only said in chat what to type. The controller's Search works there too.
- Scan the Auction House is offered only when no other installed addon scans the whole house: with Daylight Mogul, Auctionator or AuctionLite on for your character the button is left out, as it already was beside Daylight UI's Auction House, and the window says to run a full scan in that addon. Gear reads the list any of them fetches.

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
