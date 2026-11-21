-- Stage 2 on the stand-in world (mocks.lua, T.world): the best reward of a quest and the line
-- that says so (Quest.lua), the line for a new best buy and when it keeps quiet (Alert.lua),
-- who else marks upgrades and whose switch is flipped (Overlap.lua), and the weapon pair's row
-- in the window's list.
-- The globals stay locked: the files may read only what T.world() and the lines below gave them.
-- luacheck: read globals UISpecialFrames GetServerTime
-- luacheck: globals Polestar

local w = T.world()
w.load("Marks.lua")
w.load("Market.lua")
w.load("Check.lua")
rawset(_G, "UIParent", {})
rawset(_G, "GameTooltip", {})
rawset(_G, "C_Item", {})
rawset(_G, "ITEM_QUALITY_COLORS", { [2] = { hex = "|cff1eff00" } })
rawset(_G, "GetMoneyString", function(copper) return copper .. "c" end)
rawset(_G, "UISpecialFrames", {})
rawset(_G, "DaylightUIAuctionHouse", false)
rawset(_G, "InCombatLockdown", function() return WORLD.combat == true end)
rawset(_G, "GetTime", function() return w.time end)
local addons = {}
rawset(_G, "C_AddOns", { IsAddOnLoaded = function(name) return addons[name] == true end })
rawset(_G, "Polestar", false)
rawset(_G, "DaylightGuides", false)
w.load("Window.lua")
w.load("Quest.lua")
w.load("Alert.lua")
w.load("Overlap.lua")
local Quest, Alert, Overlap, Window, Stats, Compare = NS.Quest, NS.Alert, NS.Overlap, NS.Window, NS.Stats, NS.Compare
local L = NS.L
-- (The game's own words for the slots are not in this world: the English stand-ins are used.)
NS.GameText = function(_, fallback) return fallback end

w.dui("Login")

local function gear(def)
	def.equipLoc = def.equipLoc or "INVTYPE_CHEST"
	def.subclassID = def.subclassID or 4
	return T.item(def)
end
local function str(n) return { ITEM_MOD_STRENGTH_SHORT = n } end
local function character()
	WORLD.class, WORLD.level = "WARRIOR", 60
	WORLD.trees = { { name = "Arms", spent = 31 }, { name = "Fury", spent = 20 }, { name = "Protection", spent = 0 } }
	WORLD.worn, WORLD.bags = {}, {}
	w.settings.DaylightGear = {}
	w.dui("SettingChanged", "DaylightGear", "enabled")
	w.dui("Login")
end
local function said() return w.chat[#w.chat] or "" end

-- ---------------------------------------------------------------------------------------------
-- Quest rewards
-- ---------------------------------------------------------------------------------------------
T.case("the best reward is the biggest upgrade; a single reward is no choice", function()
	local up = function(gain, pct) return { usable = true, gain = gain, pct = pct } end
	T.eq(Quest.Choose({ { link = "a", v = up(5, 10) } }, 3, true), nil, "one reward: nothing to choose")
	local pick = Quest.Choose({ { link = "a", v = up(5, 10) }, { link = "b", v = up(9, 20) }, { link = "c", v = up(-2, -5) } }, 3, false)
	T.eq(pick.kind, "upgrade", "an upgrade"); T.eq(pick.link, "b", "the biggest gain"); T.eq(pick.index, 2, "its place")
	pick = Quest.Choose({ { link = "a", v = up(1, 2) }, { link = "b", v = { usable = false, gain = 50, pct = 90 } } }, 3, false)
	T.eq(pick, nil, "a gain under the smallest gain to show is no upgrade, nor is gear that cannot be worn yet")
	pick = Quest.Choose({ { link = "a", v = { usable = true, gain = 4, empty = true } }, { link = "b" } }, 3, false)
	T.eq(pick.link, "a", "something for an empty slot always counts")
	-- no upgrade: the vendor value, only when asked for
	local list = { { link = "a", sell = 100, count = 1 }, { link = "b", sell = 30, count = 5 }, { link = "c", v = up(-1, -1), sell = 120 } }
	T.eq(Quest.Choose(list, 3, false), nil, "switched off: nothing is said")
	pick = Quest.Choose(list, 3, true)
	T.eq(pick.kind, "sell", "switched on: the one that sells for the most"); T.eq(pick.link, "b", "five at 30 beat one at 120")
	T.eq(pick.total, 150, "its total")
	T.eq(Quest.Choose({ { link = "a", sell = 0 }, { link = "b" } }, 3, true), nil, "nothing sells: nothing is said")
end)

T.case("a quest's reward page: one line, once, never in a fight", function()
	T.reset()
	character()
	WORLD.worn[5] = gear({ name = "Worn Vest", raw = str(10) })
	local small, big, legs = gear({ name = "Small", raw = str(12) }), gear({ name = "Big", raw = str(20) }),
		gear({ name = "Legs", raw = str(1), equipLoc = "INVTYPE_LEGS", sellPrice = 500 })
	w.dui("Login")
	WORLD.quest = { { link = small }, { link = big }, { link = legs } }
	local lines = #w.chat
	w.fire("QUEST_COMPLETE")
	T.eq(#w.chat, lines, "not in the same instant (the choices can come a moment after the page)")
	w.advance(0.5)
	T.eq(#w.chat, lines + 1, "one line")
	T.check(said():find("Big", 1, true) and said():find(L["Best quest reward for you: %s (%s)."]:match("^[^%%]+"), 1, true), "naming the biggest upgrade: " .. said())
	T.check(said():find("+100%", 1, true), "with the verdict the tooltip row gives: " .. said())
	T.eq(Quest.Best(), Stats.Key(big), "and the pick is known to the tooltip")
	w.fire("QUEST_ITEM_UPDATE"); w.fire("QUEST_ITEM_UPDATE")
	w.advance(1)
	T.eq(#w.chat, lines + 1, "said once for the page, however often its items update")
	w.fire("QUEST_FINISHED")
	T.eq(Quest.Best(), nil, "the page closed: no pick")
	-- a reward not loaded yet: said when it has arrived
	WORLD.items[T_ident(big)].loaded = false
	Stats.Forget()
	w.fire("QUEST_COMPLETE")
	w.advance(0.5)
	T.eq(#w.chat, lines + 1, "a reward is still loading: nothing yet")
	T.load(big)
	w.advance(1)
	T.eq(#w.chat, lines + 2, "then the line")
	w.fire("QUEST_FINISHED")
	-- in a fight: nothing
	WORLD.combat = true
	w.fire("QUEST_COMPLETE")
	w.advance(1)
	T.eq(#w.chat, lines + 2, "nothing in a fight")
	WORLD.combat = false
	w.fire("QUEST_FINISHED")
	-- switched off
	w.set("questPick", false)
	w.fire("QUEST_COMPLETE")
	w.advance(1)
	T.eq(#w.chat, lines + 2, "nothing with the switch off")
	w.fire("QUEST_FINISHED")
	w.set("questPick", true)
	-- no upgrade among them
	WORLD.quest = { { link = legs, count = 2 }, { link = gear({ name = "Rag", raw = str(1), sellPrice = 10 }) } }
	WORLD.worn[7] = gear({ name = "Worn Legs", raw = str(30), equipLoc = "INVTYPE_LEGS" })
	w.fire("PLAYER_EQUIPMENT_CHANGED")
	w.advance(1)
	w.fire("QUEST_COMPLETE")
	w.advance(1)
	T.eq(#w.chat, lines + 2, "no upgrade and the vendor hint off: nothing")
	w.fire("QUEST_FINISHED")
	w.set("questSell", true)
	w.fire("QUEST_COMPLETE")
	w.advance(1)
	T.eq(#w.chat, lines + 3, "with the vendor hint on: one line")
	T.check(said():find("Legs", 1, true) and said():find("1000c", 1, true), "the one that sells for the most, and for how much: " .. said())
	T.eq(Quest.Best(), nil, "a reward to sell is not marked as the best for you")
	w.fire("QUEST_FINISHED")
end)

-- ---------------------------------------------------------------------------------------------
-- The alert
-- ---------------------------------------------------------------------------------------------
local function view(groups) return { groups = groups } end
local function row(key, gain, value, group) return { key = key, gain = gain, value = value, group = group, name = key, quality = 2,
	link = "item:" .. key, price = 12345, pct = 12 } end

T.case("what counts as news", function()
	local a, b, c = row("1", 10, 2, "HEAD"), row("2", 8, 3, "HEAD"), row("3", 5, 1, "LEGS")
	local news, slots = Alert.News(nil, view({ HEAD = { a }, LEGS = { c } }), "perGold")
	T.eq(news, nil, "nothing remembered: nothing is news"); T.eq(slots.HEAD[1], "1", "but it is remembered")
	T.eq(Alert.News(slots, view({ HEAD = { a }, LEGS = { c } }), "perGold"), nil, "the same picks: no news")
	news = Alert.News(slots, view({ HEAD = { b }, LEGS = { c } }), "perGold")
	T.eq(news, b, "another item that is the better buy per gold")
	local _, byGain = Alert.News(nil, view({ HEAD = { a }, LEGS = { c } }), "biggest")
	T.eq(Alert.News(byGain, view({ HEAD = { b }, LEGS = { c } }), "biggest"), nil, "by gain it is not better")
	local worse = row("4", 20, 1.5, "HEAD")
	T.eq(Alert.News(slots, view({ HEAD = { worse } }), "perGold"), nil, "another item that is a worse buy per gold: no news")
	local sameCheaper = row("1", 10, 4, "HEAD")
	T.eq(Alert.News(slots, view({ HEAD = { sameCheaper } }), "perGold"), nil, "the same item, cheaper: not a new item")
	local d = row("5", 30, 1, "FEET")
	news = Alert.News(slots, view({ HEAD = { b }, LEGS = { c }, FEET = { d } }), "perGold")
	T.eq(news, d, "a slot that had no pick has one: news, and the biggest gain is the one spoken of")
end)

T.case("one quiet line, and when it keeps silent", function()
	T.reset()
	character()
	Alert.Reset()
	local c = NS.Char()
	c.seen = nil
	WORLD.clock = 1000000
	local a, b = row("1", 10, 2, "HEAD"), row("2", 8, 3, "HEAD")
	local lines = #w.chat
	Alert.Check(view({ HEAD = { a } }))
	T.eq(#w.chat, lines, "the first time a house is scored: silent"); T.check(c.seen and c.seen.slots.HEAD, "and remembered")
	WORLD.combat = true
	Alert.Check(view({ HEAD = { b } }))
	T.eq(#w.chat, lines, "never in a fight"); T.eq(c.seen.slots.HEAD[1], "1", "and what is remembered stays, so the news keeps")
	WORLD.combat = false
	Alert.Check(view({ HEAD = { b } }))
	T.eq(#w.chat, lines + 1, "after the fight: one line")
	T.check(said():find("|Hitem:2|h[2]|h", 1, true), "with a link the chat can show: " .. said())
	T.check(said():find("+12%", 1, true), "its gain: " .. said())
	T.check(said():find("12345c", 1, true), "and its price")
	local e = row("9", 50, 9, "HEAD")
	Alert.Check(view({ HEAD = { e } }))
	T.eq(#w.chat, lines + 1, "another one within a minute: no second line")
	WORLD.clock = WORLD.clock + 61000
	local f = row("10", 60, 10, "HEAD")
	Alert.Check(view({ HEAD = { f } }))
	T.eq(#w.chat, lines + 2, "a minute later a new best is said again")
	-- another Best Pick is another measure: remembered afresh, silently
	WORLD.clock = WORLD.clock + 61000
	w.set("mode", "biggest")
	Alert.Check(view({ HEAD = { row("11", 70, 11, "HEAD") } }))
	T.eq(#w.chat, lines + 2, "Best Pick changed: nothing to compare with")
	w.set("alert", false)
	WORLD.clock = WORLD.clock + 61000
	Alert.Check(view({ HEAD = { row("12", 80, 12, "HEAD") } }))
	T.eq(#w.chat, lines + 2, "switched off: silent")
	w.set("alert", true); w.set("mode", "perGold")
end)

-- ---------------------------------------------------------------------------------------------
-- Other addons
-- ---------------------------------------------------------------------------------------------
T.case("who else marks upgrades, and whose switch is flipped", function()
	T.reset()
	character()
	DaylightGearDB.overlap = nil
	addons = {}
	T.eq(#Overlap.Rivals("bags"), 0, "no other addon: no rival"); T.eq(#Overlap.Unasked(), 0, "nothing to ask")
	w.set("yieldBags", true)
	T.eq(Overlap.Yields("bags"), false, "with no rival ours never stands down, whatever the setting")
	w.set("yieldBags", false)
	DaylightGearDB.overlap = nil

	local theirs = { ["gear.bagArrows"] = true, ["gear.tooltip"] = true, ["gear.rewards"] = true }
	local sets = 0
	rawset(_G, "Polestar", { Get = function(path) return theirs[path] end, Set = function(path, value) sets = sets + 1; theirs[path] = value end })
	addons = { Polestar = true, Pawn = true, CheapUpgrades = true }
	local bags, tips = Overlap.Rivals("bags"), Overlap.Rivals("tips")
	T.eq(#bags, 2, "Polestar and Pawn mark bags"); T.eq(#tips, 3, "all three add to tooltips")
	T.eq(bags[1].name, "Polestar", "Polestar"); T.eq(bags[1].can, true, "has a switch we may flip"); T.eq(bags[2].can, false, "Pawn has none")
	T.eq(table.concat(Overlap.Unasked(), ","), "bags,tips", "both surfaces are to be asked about")
	-- before an answer nothing of another addon's is touched
	Overlap.Apply()
	T.eq(sets, 0, "not answered yet: Polestar's settings are left alone")
	T.eq(Overlap.Yields("bags"), false, "ours shows by default")
	T.check(Overlap.What("bags"):find("Polestar", 1, true) and Overlap.What("bags"):find("Pawn", 1, true), "the row names them: " .. Overlap.What("bags"))
	-- the answer "ours" for bags
	Overlap.Choose("bags", false)
	T.eq(theirs["gear.bagArrows"], false, "ours: Polestar's bag arrows are switched off")
	T.eq(theirs["gear.tooltip"], true, "its tooltip line is another question: untouched")
	T.eq(theirs["gear.rewards"], true, "and nothing else of Polestar's")
	T.eq(table.concat(Overlap.Unasked(), ","), "tips", "bags are answered")
	-- reversed: theirs
	Overlap.Choose("bags", true)
	T.eq(theirs["gear.bagArrows"], true, "theirs: Polestar's arrows are put back as they were")
	T.eq(Overlap.Yields("bags"), true, "and ours stands down")
	T.eq(w.settings.DaylightGear.yieldBags, true, "the setting follows")
	-- and back again through the options page
	w.set("yieldBags", false)
	T.eq(theirs["gear.bagArrows"], false, "the options page reverses it again")
	-- a value the player had already switched off is not turned on when ours yields
	theirs["gear.tooltip"] = false
	Overlap.Choose("tips", false)
	Overlap.Choose("tips", true)
	T.eq(theirs["gear.tooltip"], false, "what the player had off stays off")
	T.eq(#Overlap.Unasked(), 0, "everything answered: not asked again")
	-- a new rival on a surface asks again
	addons.ForeverLevelingBiS = true
	T.eq(table.concat(Overlap.Unasked(), ","), "bags,tips", "a new addon is a new question")
	-- a Polestar whose table is not as read: no switch, never an error
	rawset(_G, "Polestar", { Get = "no" })
	T.eq(Overlap.Rivals("bags")[1].can, false, "Polestar without its Get and Set: treated as having no switch")
	Overlap.Apply()
	rawset(_G, "Polestar", false)
	addons = {}
	w.set("yieldTips", false); w.set("yieldBags", false)
end)

T.case("ours stands down on the surface the player gave away", function()
	T.reset()
	character()
	WORLD.worn[5] = gear({ name = "Worn Vest", raw = str(10) })
	local better = gear({ name = "Better", raw = str(20) })
	w.dui("Login")
	local rows = {}
	local lines = { Row = function(label, value) rows[#rows + 1] = label .. ": " .. value end, Text = function() end }
	NS.Marks.OnItemTooltip(lines, { link = better })
	T.eq(#rows, 1, "the tooltip row is there")
	addons = { Pawn = true }
	w.set("yieldTips", true)
	rows = {}
	NS.Marks.OnItemTooltip(lines, { link = better })
	T.eq(#rows, 0, "tooltips left to another addon: no row of ours")
	addons = {}
	rows = {}
	NS.Marks.OnItemTooltip(lines, { link = better })
	T.eq(#rows, 1, "that addon is gone: ours is back without a change of setting")
	w.set("yieldTips", false)
end)

-- ---------------------------------------------------------------------------------------------
-- The weapon pair in the window's list
-- ---------------------------------------------------------------------------------------------
T.case("the pair has one row under the two hands, and opens to its two items", function()
	local m = { key = "1", link = "item:1", name = "Sword", quality = 2, price = 300 }
	local o = { key = "2", link = "item:2", name = "Board", quality = 2, price = 200 }
	local set = { main = m, off = o, gain = 5, price = 500, pct = 8 }
	local chest = { key = "3", link = "item:3", name = "Vest", group = "CHEST", gain = 1, price = 1 }
	local ranged = { key = "4", link = "item:4", name = "Bow", group = "RANGED", gain = 1, price = 1 }
	local v = { groups = { CHEST = { chest }, RANGED = { ranged } } }
	local model = Window.Model(v, nil, set)
	T.eq(#model, 3, "three rows: chest, the pair, ranged")
	T.eq(model[2].group, "WEAPONS", "the pair sits where the hands are, before the ranged slot"); T.eq(model[2].row.isSet, true, "marked as a pair")
	T.eq(model[2].row.price, 500, "priced as a set"); T.eq(model[2].row.name, L["Both Together"], "named in words")
	T.eq(Window.GainText(model[2].row), L["+%s%%"]:format("8"), "with the pair's gain")
	model = Window.Model(v, "WEAPONS", set)
	T.eq(#model, 5, "opened: its two items under it")
	T.eq(model[3].row.name, "Sword", "the main hand"); T.eq(model[4].row.name, "Board", "the off hand")
	T.check(model[3].row.label ~= nil and model[4].row.label ~= nil and model[3].row.label ~= model[4].row.label, "each says which hand it is for")
	T.eq(#Window.Model(v, nil, nil), 2, "no pair: no row")
	T.check(Compare.GROUPS[#Compare.GROUPS] == "RANGED", "(the ranged slot is the last group)")
end)

T.case("from a saved list to the window: the pair is found and shown, and a new best buy is said", function()
	T.reset()
	character()
	Alert.Reset()
	local c = NS.Char()
	c.seen = nil
	WORLD.clock = 5000000
	local function arm(loc, dps, name)
		return T.item({ equipLoc = loc, classID = 2, subclassID = loc == "INVTYPE_2HWEAPON" and 8 or 7, name = name,
			raw = { ITEM_MOD_DAMAGE_PER_SECOND_SHORT = dps } })
	end
	WORLD.worn[16] = arm("INVTYPE_2HWEAPON", 30, "Worn Two-Hander")
	WORLD.worn[5] = gear({ name = "Worn Vest", raw = str(10) })
	w.dui("Login")
	local sword = arm("INVTYPE_WEAPON", 28, "Sword")
	local board = T.item({ equipLoc = "INVTYPE_SHIELD", classID = 4, subclassID = 6, name = "Board", raw = str(400) })
	local vest = gear({ name = "Vest", raw = str(12) })
	local ah = w.ah
	ah.rows = {}
	for _, r in ipairs({ { sword, 30000 }, { board, 20000 }, { vest, 20000 } }) do
		ah.rows[#ah.rows + 1] = { itemID = Stats.ItemID(r[1]), link = r[1], buyout = r[2], count = 1 }
	end
	ah.open = true
	w.fire("AUCTION_HOUSE_SHOW"); w.fire("REPLICATE_ITEM_LIST_UPDATE")
	for _ = 1, 600 do
		w.frames(1)
		if NS.Market.State() == "ready" and not NS.Market.Looking() then break end
	end
	local shown = true
	Window.IsShown = function() return shown end
	local lines = #w.chat
	Window.Refresh(true)
	for _ = 1, 400 do
		if not Window.S.running then break end
		w.frames(1)
	end
	local groups = {}
	for i, e in ipairs(Window.S.model) do groups[i] = e.group end
	T.check(table.concat(groups, ","):find("WEAPONS", 1, true), "the pair's row is in the list: " .. table.concat(groups, ","))
	T.check(Window.S.set and Window.S.set.main.name == "Sword" and Window.S.set.off.name == "Board", "the sword and the shield")
	T.eq(#w.chat, lines, "the first scoring of a house says nothing")
	-- a better vest turns up: one line
	local best = gear({ name = "Best Vest", raw = str(30) })
	NS.Fire("PriceChanged", Stats.Key(best), 15000, GetServerTime())
	for _ = 1, 400 do
		w.frames(1)
		if not Window.S.running and #w.chat > lines then break end
	end
	T.eq(#w.chat, lines + 1, "a new best buy for a slot: one line")
	T.check(said():find("Best Vest", 1, true), "naming it: " .. said())
	ah.open = false
	w.fire("AUCTION_HOUSE_CLOSED")
end)

return T.done()
