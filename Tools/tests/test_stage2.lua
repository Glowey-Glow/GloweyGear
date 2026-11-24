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
w.load("Sweep.lua")
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
	w.settings.GloweyGear = {}
	w.dui("SettingChanged", "GloweyGear", "enabled")
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
	Quest.Forget()
	WORLD.items[T_ident(big)].loaded = false
	Stats.Forget()
	w.fire("QUEST_COMPLETE")
	w.advance(0.5)
	T.eq(#w.chat, lines + 1, "a reward is still loading: nothing yet")
	T.load(big)
	w.advance(1)
	T.eq(#w.chat, lines + 2, "then the line")
	w.fire("QUEST_FINISHED")
	local before = #w.chat
	w.fire("QUEST_COMPLETE")
	w.advance(1)
	T.eq(#w.chat, before, "L8: the same page opened again says nothing new")
	Quest.Forget()
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
-- (Daylight UI's modules, and whether its bags took our corner mark: what "ours shows" depends on.)
local modules = {}
NS.API.IsModuleEnabled = function(name) return modules[name] ~= false end
local loadedAsks = 0
rawset(_G, "C_AddOns", { IsAddOnLoaded = function(name)
	loadedAsks = loadedAsks + 1
	return addons[name] == true
end })
local function polestar(theirs, counter)
	rawset(_G, "Polestar", { Get = function(path) return theirs[path] end, Set = function(path, value)
		counter.n = counter.n + 1
		-- (As Polestar stores it: a value equal to its default is kept as nil.)
		if value == true then theirs[path] = nil else theirs[path] = value end
	end })
end
local function fresh()
	T.reset()
	character()
	GloweyGearDB.overlap = nil
	addons, modules = {}, {}
	NS.Marks.shim = true
	w.set("yieldBags", false); w.set("yieldTips", false); w.set("tooltips", true); w.set("bagMarks", true); w.set("enabled", true)
	GloweyGearDB.overlap = nil
	Overlap.Changed()
end
local function on(v) return v == nil or v == true end   -- Polestar's default is on

T.case("who else marks upgrades, and whose switch is flipped", function()
	fresh()
	T.eq(#Overlap.Rivals("bags"), 0, "no other addon: no rival"); T.eq(#Overlap.Unasked(), 0, "nothing to ask")
	w.set("yieldBags", true)
	T.eq(Overlap.Yields("bags"), false, "with no rival ours never stands down, whatever the setting")
	fresh()
	local theirs, sets = { ["gear.rewards"] = true }, { n = 0 }
	polestar(theirs, sets)
	addons = { Polestar = true, Pawn = true, CheapUpgrades = true }
	Overlap.Changed()
	local bags, tips = Overlap.Rivals("bags"), Overlap.Rivals("tips")
	T.eq(#bags, 2, "Polestar and Pawn mark Daylight UI's bags (Polestar through the Baganator-style call)")
	T.eq(bags[1].name, "Polestar", "Polestar"); T.eq(bags[1].can, true, "has a switch"); T.eq(bags[2].can, false, "Pawn has none")
	T.eq(#tips, 3, "all three add to tooltips"); T.eq(tips[1].name, "Polestar", "Polestar"); T.eq(tips[1].can, true, "has a switch we may flip")
	T.eq(table.concat(Overlap.Unasked(), ","), "bags,tips", "both surfaces are to be asked about")
	Overlap.Apply()
	T.eq(sets.n, 0, "not answered yet: Polestar's settings are left alone")
	T.check(Overlap.What("tips"):find("Polestar", 1, true) and Overlap.What("tips"):find("Pawn", 1, true), "the row names them: " .. Overlap.What("tips"))
	-- the answer "ours" for bags, with our mark really in Daylight UI's bags
	Overlap.Choose("bags", false)
	T.eq(theirs["gear.bagArrows"], false, "ours on bags: Polestar's bag arrows are switched off")
	T.eq(on(theirs["gear.tooltip"]), true, "its tooltip line is another question: untouched")
	-- M5: without Daylight UI's bags our mark is nowhere, so Polestar's arrows are given back
	NS.Marks.shim = false
	Overlap.Changed(); Overlap.Apply()
	T.eq(on(theirs["gear.bagArrows"]), true, "M5: our mark does not show (no Daylight UI bags): Polestar keeps its arrows")
	NS.Marks.shim = true
	Overlap.Changed(); Overlap.Apply()
	T.eq(theirs["gear.bagArrows"], false, "with them back, taken again")
	w.set("bagMarks", false)
	T.eq(on(theirs["gear.bagArrows"]), true, "M5: our Bag Slots switch off: Polestar keeps its arrows")
	w.set("bagMarks", true)
	-- "ours" for tooltips
	Overlap.Choose("tips", false)
	T.eq(theirs["gear.tooltip"], false, "ours: Polestar's tooltip line is switched off")
	T.eq(theirs["gear.rewards"], true, "and nothing else of Polestar's")
	T.eq(#Overlap.Unasked(), 0, "everything answered")
	-- reversed: theirs
	Overlap.Choose("tips", true)
	T.eq(on(theirs["gear.tooltip"]), true, "theirs: Polestar's line is put back as it was")
	T.eq(Overlap.Yields("tips"), true, "and ours stands down"); T.eq(w.settings.GloweyGear.yieldTips, true, "the setting follows")
	w.set("yieldTips", false)
	T.eq(theirs["gear.tooltip"], false, "the options page reverses it again")
	-- a value the player had already switched off is not turned on when ours yields
	fresh()
	theirs, sets = { ["gear.tooltip"] = false }, { n = 0 }
	polestar(theirs, sets)
	addons = { Polestar = true }
	Overlap.Changed()
	Overlap.Choose("tips", false); Overlap.Choose("tips", true)
	T.eq(theirs["gear.tooltip"], false, "what the player had off stays off")
	-- a new rival on a surface asks again
	addons.ForeverLevelingBiS = true
	Overlap.Changed()
	T.eq(table.concat(Overlap.Unasked(), ","), "bags,tips", "a new addon is a new question")
	-- a Polestar whose table is not as read: no switch, never an error
	rawset(_G, "Polestar", { Get = "no" })
	Overlap.Changed()
	T.eq(Overlap.Rivals("tips")[1].can, false, "Polestar without its Get and Set: treated as having no switch")
	Overlap.Apply()
	rawset(_G, "Polestar", false)
end)

T.case("M5: another addon's switch is taken only while ours really shows there", function()
	fresh()
	local theirs, sets = {}, { n = 0 }
	polestar(theirs, sets)
	addons = { Polestar = true, Pawn = true }
	Overlap.Changed()
	Overlap.Choose("tips", false)
	T.eq(theirs["gear.tooltip"], false, "ours shows on tooltips: Polestar's line is off")
	-- our own tooltip row switched off: Polestar's line comes back, and nothing is asked
	w.set("tooltips", false)
	T.eq(on(theirs["gear.tooltip"]), true, "our Item Tooltips off: Polestar's line is given back")
	T.eq(#Overlap.Rivals("tips"), 0, "no overlap on a surface where ours does not show")
	w.set("tooltips", true)
	T.eq(theirs["gear.tooltip"], false, "on again: taken again (the question was answered)")
	-- Daylight UI's Tooltip module off: the same
	modules.Tooltip = false
	Overlap.Changed(); Overlap.Apply()
	T.eq(on(theirs["gear.tooltip"]), true, "Daylight UI's tooltips off: given back")
	modules.Tooltip = nil
	Overlap.Changed(); Overlap.Apply()
	T.eq(theirs["gear.tooltip"], false, "and taken when they are on again")
	-- Show Gear Advice off: everything is given back and nothing is asked
	w.set("enabled", false)
	T.eq(on(theirs["gear.tooltip"]), true, "Show Gear Advice off: given back")
	GloweyGearDB.overlap.asked = {}
	T.eq(#Overlap.Unasked(), 0, "L10: with Gear Advice off no question is asked")
	w.set("enabled", true)
	-- bags: no mark of ours without Daylight UI's bags, so no overlap there
	T.eq(#Overlap.Rivals("bags"), 2, "with Daylight UI's bags: Polestar and Pawn are rivals")
	NS.Marks.shim = false
	Overlap.Changed()
	T.eq(#Overlap.Rivals("bags"), 0, "without them our mark is nowhere: no rival, no question")
	NS.Marks.shim = true
	Overlap.Changed()
	-- never in a fight
	GloweyGearDB.overlap = nil
	theirs["gear.tooltip"] = nil
	Overlap.Changed()
	local before = sets.n
	WORLD.combat = true
	Overlap.Choose("tips", false)
	T.eq(sets.n, before, "L10: nothing of another addon's is switched in a fight")
	WORLD.combat = false
	w.advance(4)
	T.eq(theirs["gear.tooltip"], false, "it is done when the fight is over")
	rawset(_G, "Polestar", false)
end)

T.case("L9: what was taken is remembered per character; L11: asking whether ours yields is cheap", function()
	fresh()
	-- character A, Polestar profile X
	local x, y, sets = {}, {}, { n = 0 }
	polestar(x, sets)
	addons = { Polestar = true }
	Overlap.Changed()
	Overlap.Choose("tips", false)
	T.eq(x["gear.tooltip"], false, "A: profile X switched off")
	-- character B, Polestar profile Y
	WORLD.guid = "Player-4407-00BBBBBB"
	polestar(y, sets)
	Overlap.Changed(); Overlap.Apply()
	T.eq(y["gear.tooltip"], false, "B: profile Y switched off too")
	Overlap.Choose("tips", true)
	T.eq(on(y["gear.tooltip"]), true, "B reverses: Y is put back")
	-- A logs in again: X must be put back as well
	WORLD.guid = "Player-4407-00ABCDEF"
	polestar(x, sets)
	Overlap.Changed(); Overlap.Apply()
	T.eq(on(x["gear.tooltip"]), true, "A's profile X is put back when A next logs in, not left off for good")
	-- cheap
	addons.Pawn = true
	w.set("yieldBags", true)
	Overlap.Changed()
	T.eq(Overlap.Yields("bags"), true, "ours yields on bags")
	loadedAsks = 0
	for _ = 1, 500 do Overlap.Yields("bags") end
	T.eq(loadedAsks, 0, "500 bag slots ask nothing of the game and build nothing: the answer is kept")
	rawset(_G, "Polestar", false)
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
	Overlap.Changed()
	w.set("yieldTips", true)
	rows = {}
	NS.Marks.OnItemTooltip(lines, { link = better })
	T.eq(#rows, 0, "tooltips left to another addon: no row of ours")
	addons = {}
	Overlap.Changed()
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

T.case("M4: choices that arrive late, with no event; L8: a page reopened, and a choice with no link", function()
	T.reset()
	character()
	Quest.Forget()
	WORLD.worn[5] = gear({ name = "Worn Vest", raw = str(10) })
	local small, big = gear({ name = "Small", raw = str(12) }), gear({ name = "Big", raw = str(20) })
	w.dui("Login")
	-- the page arrives before its choices (count 0), and no QUEST_ITEM_UPDATE follows
	WORLD.quest = {}
	local lines = #w.chat
	w.fire("QUEST_COMPLETE")
	w.advance(1)
	T.eq(#w.chat, lines, "no choices yet: nothing to say")
	WORLD.quest = { { link = small }, { link = big } }
	w.advance(1.5)
	T.eq(#w.chat, lines + 1, "the choices came late and with no event: the line still comes")
	T.check(said():find("Big", 1, true), "naming the best: " .. said())
	-- the look does not go on for ever on a page with no choice
	w.fire("QUEST_FINISHED")
	WORLD.quest = {}
	w.fire("QUEST_COMPLETE")
	w.advance(30)
	local looks = WORLD.calls.QuestChoices
	w.advance(30)
	T.eq(WORLD.calls.QuestChoices, looks, "a page with no choice is given up after a few seconds")
	w.fire("QUEST_FINISHED")
	-- the same page opened again: not said twice
	WORLD.quest = { { link = small }, { link = big } }
	w.fire("QUEST_COMPLETE")
	w.advance(2)
	T.eq(#w.chat, lines + 1, "the same rewards again: the line is not repeated")
	T.eq(Quest.Best(), Stats.Key(big), "but the tooltip still knows the pick")
	w.fire("QUEST_FINISHED")
	-- a choice that never gets a link (a currency) does not silence the page
	local other, best = gear({ name = "Other", raw = str(13) }), gear({ name = "Best", raw = str(30) })
	WORLD.quest = { { link = other }, { link = nil }, { link = best } }
	w.fire("QUEST_COMPLETE")
	w.advance(12)
	T.eq(#w.chat, lines + 2, "the two real items are still compared")
	T.check(said():find("Best", 1, true), "and the best of them named: " .. said())
	w.fire("QUEST_FINISHED")
end)

T.case("L7: no news after a change of settings or of what is owned; news inside the quiet minute is kept", function()
	T.reset()
	character()
	Alert.Reset()
	local c = NS.Char()
	c.seen = nil
	WORLD.clock = 9000000
	local lines = #w.chat
	local a, b = row("1", 10, 2, "HEAD"), row("2", 30, 3, "HEAD")
	Alert.Check(view({ HEAD = { a } }), "owned-1")
	-- Max Price raised: a dearer, better item becomes the pick. It was for sale all along.
	w.set("maxPrice", 500)
	Alert.Check(view({ HEAD = { b } }), "owned-1")
	T.eq(#w.chat, lines, "after a Max Price change the new pick is not news")
	w.set("minGain", 1)
	Alert.Check(view({ HEAD = { row("3", 40, 4, "HEAD") } }), "owned-1")
	T.eq(#w.chat, lines, "nor after a Smallest Gain change")
	-- what is owned changed (a piece sold or banked)
	Alert.Check(view({ HEAD = { row("4", 50, 5, "HEAD") } }), "owned-2")
	T.eq(#w.chat, lines, "nor after a change of what is owned")
	-- real news
	Alert.Check(view({ HEAD = { row("5", 60, 6, "HEAD") } }), "owned-2")
	T.eq(#w.chat, lines + 1, "the same settings and gear, a better item: news")
	-- a second piece of news inside the quiet minute is held, and said when the minute is over
	Alert.Check(view({ HEAD = { row("5", 60, 6, "HEAD") }, LEGS = { row("6", 20, 7, "LEGS") } }), "owned-2")
	T.eq(#w.chat, lines + 1, "inside the minute: not yet")
	WORLD.clock = WORLD.clock + 61000
	w.advance(62)
	T.eq(#w.chat, lines + 2, "the minute over: the news that was held is said")
	T.check(said():find("|Hitem:6|h", 1, true), "it is the held one: " .. said())
	w.set("maxPrice", 50); w.set("minGain", 3)
end)

T.case("L12: Check Prices asks about both items of a pair; a pair's item with an uncounted effect is marked", function()
	local m = { key = "1001", link = "item:1001", name = "Sword", quality = 2, price = 300 }
	local o = { key = "1002", link = "item:1002", name = "Board", quality = 2, price = 200 }
	Window.S.model = Window.Model({ groups = {} }, nil, { main = m, off = o, gain = 5, price = 500, pct = 8 })
	local ids = Window.ShownItems()
	table.sort(ids)
	T.eq(table.concat(ids, ","), "1001,1002", "both items of the closed pair row are checked")
	Window.S.model = {}
end)

T.case("the overlap window is built from Daylight UI's widgets and filled", function()
	fresh()
	addons = { Pawn = true }
	Overlap.Changed()
	local made = { switches = 0, buttons = {} }
	local A = NS.API
	local function text()
		local t = w.widget()
		t.GetStringHeight = function() return 14 end
		return t
	end
	A.Skin = function() end
	A.Text = function() return text() end
	A.Close = function() return w.widget() end
	A.Colors = function() return { VALUE = { 1, 1, 1 }, TEXT = { 1, 1, 1 } } end
	A.Button = function(_, label)
		local b = w.widget()
		made.buttons[label] = b
		return b
	end
	A.Switch = function()
		made.switches = made.switches + 1
		local sw = w.widget()
		sw.SetOn = function(value) sw.on = value end
		return sw
	end
	rawset(_G, "UIParent", w.widget())
	T.eq(Overlap.Show(false), true, "there is something to ask: the window shows")
	T.eq(made.switches, 2, "one switch per surface")
	T.check(made.buttons[L["Apply"]] and made.buttons[L["Ask Me Later"]], "Apply and Ask Me Later")
	local frame = rawget(_G, "GloweyGearOverlap") or w.frames_[#w.frames_]
	T.check(frame ~= nil, "a frame was made")
	-- Apply with the switches as they stand: both surfaces answered "ours"
	made.buttons[L["Apply"]]:Click()
	T.eq(#Overlap.Unasked(), 0, "Apply answers what was shown")
	T.eq(Overlap.Yields("bags"), false, "ours by default")
	T.eq(Overlap.Show(false), false, "nothing left to ask: no window")
	WORLD.combat = true
	T.eq(Overlap.Show(true), false, "never opened in a fight")
	WORLD.combat = false
	A.Skin, A.Text, A.Close, A.Button, A.Switch, A.Colors = nil, nil, nil, nil, nil, nil
	rawset(_G, "UIParent", {})
end)

-- ---- the first run in the game: a rival feature that is off is no rival ----------------------
T.case("a rival's feature the player turned off is no rival: ours shows, nothing is asked, nothing is taken", function()
	fresh()
	-- Polestar is loaded, its gear advice switched off by the player (as in the owner's game)
	local theirs, sets = { ["gear.enabled"] = false }, { n = 0 }
	polestar(theirs, sets)
	addons = { Polestar = true }
	Overlap.Changed()
	T.eq(#Overlap.Rivals("bags"), 0, "bags: no rival"); T.eq(#Overlap.Rivals("tips"), 0, "tooltips: no rival")
	T.eq(#Overlap.Unasked(), 0, "nothing to ask")
	-- even with "theirs" chosen at some earlier time, ours shows
	w.set("yieldBags", true); w.set("yieldTips", true)
	T.eq(Overlap.Yields("bags"), false, "theirs is off: ours shows on bags, whatever was chosen")
	T.eq(Overlap.Yields("tips"), false, "and on tooltips")
	Overlap.Apply()
	T.eq(sets.n, 0, "and nothing of Polestar's is written")
	T.check(Overlap.Describe("tips"):find("Polestar's is off (by the player)", 1, true) and Overlap.Describe("tips"):find("ours shows", 1, true),
		"debug says so: " .. Overlap.Describe("tips"))
	-- the tooltip row is there
	WORLD.worn[5] = gear({ name = "Worn Vest", raw = str(10) })
	local better = gear({ name = "Better", raw = str(20) })
	w.dui("Login")
	local rows = {}
	NS.Marks.OnItemTooltip({ Row = function(label, value) rows[#rows + 1] = label .. ": " .. value end, Text = function() end }, { link = better })
	T.eq(#rows, 1, "the Gear Advice row shows")
	-- only one of its two switches off: no rival there, a rival on the other surface
	fresh()
	theirs = { ["gear.tooltip"] = false }
	polestar(theirs, sets)
	addons = { Polestar = true }
	Overlap.Changed()
	T.eq(#Overlap.Rivals("tips"), 0, "its tooltip line off: no rival on tooltips")
	T.eq(#Overlap.Rivals("bags"), 1, "its bag arrows on: a rival on bags")
	rawset(_G, "Polestar", false)
end)

T.case("the truth table: never a surface with neither, and the words for each state", function()
	-- theirs: on, or off by the player; the answer: none, ours, theirs. After Apply, per surface:
	-- ours shows or theirs is on (or both, before an answer).
	for _, theirsOn in ipairs({ true, false }) do
		for _, answer in ipairs({ "none", "ours", "theirs" }) do
			fresh()
			local theirs, sets = { ["gear.tooltip"] = theirsOn and true or false }, { n = 0 }
			polestar(theirs, sets)
			addons = { Polestar = true }
			Overlap.Changed()
			if answer ~= "none" and #Overlap.Rivals("tips") > 0 then Overlap.Choose("tips", answer == "theirs") end
			if answer == "theirs" then w.set("yieldTips", true) end
			Overlap.Changed(); Overlap.Apply()
			local oursShows = not Overlap.Yields("tips")
			local theirsShows = on(theirs["gear.tooltip"])
			local what = (theirsOn and "theirs on" or "theirs off by the player") .. ", answer " .. answer
			T.check(oursShows or theirsShows, what .. ": one of the two shows")
			if not theirsOn then
				T.eq(oursShows, true, what .. ": ours shows"); T.eq(theirs["gear.tooltip"], false, what .. ": theirs stays off, never turned on by us")
			elseif answer == "none" then
				T.eq(oursShows and theirsShows, true, what .. ": both show until the question is answered")
				T.check(Overlap.Describe("tips"):find("not asked yet", 1, true), "said so: " .. Overlap.Describe("tips"))
			elseif answer == "ours" then
				T.eq(oursShows, true, what .. ": ours shows"); T.eq(theirsShows, false, what .. ": theirs switched off")
				T.check(Overlap.Describe("tips"):find("Polestar's switched off by us", 1, true) and Overlap.Describe("tips"):find("ours shows", 1, true),
					"said so: " .. Overlap.Describe("tips"))
			else
				T.eq(oursShows, false, what .. ": ours stands down"); T.eq(theirsShows, true, what .. ": theirs on")
				T.check(Overlap.Describe("tips"):find("Polestar's is on", 1, true) and Overlap.Describe("tips"):find("you chose theirs: ours stands down", 1, true),
					"said so: " .. Overlap.Describe("tips"))
			end
		end
	end
	-- "theirs" chosen, then the player turns theirs off: ours comes back by itself
	fresh()
	local theirs, sets = {}, { n = 0 }
	polestar(theirs, sets)
	addons = { Polestar = true }
	Overlap.Changed()
	Overlap.Choose("tips", true)
	T.eq(Overlap.Yields("tips"), true, "theirs chosen and on: ours stands down")
	theirs["gear.tooltip"] = false
	w.advance(2)
	T.eq(Overlap.Yields("tips"), false, "the player turns theirs off: ours is back within a moment, with no setting of ours touched")
	theirs["gear.tooltip"] = nil
	theirs["gear.enabled"] = false
	w.advance(2)
	T.eq(Overlap.Yields("tips"), false, "the same with Polestar's whole gear part off")
	-- "ours" chosen (we switched theirs off), then the player turns Polestar's gear part off:
	-- what we took is given back, and stays off under their own master switch
	fresh()
	theirs = {}
	polestar(theirs, sets)
	addons = { Polestar = true }
	Overlap.Changed()
	Overlap.Choose("tips", false)
	T.eq(theirs["gear.tooltip"], false, "taken")
	T.eq(#Overlap.Rivals("tips"), 1, "switched off by us, it is still the rival the answer is about (not asked again)")
	T.check(not table.concat(Overlap.Unasked(), ","):find("tips", 1, true), "tooltips are not asked about again")
	rawset(_G, "Polestar", false)
end)

T.case("a quest reward's tooltip that comes without a link still gets its row", function()
	T.reset()
	character()
	addons = {}
	Overlap.Changed()
	WORLD.worn[5] = gear({ name = "Worn Vest", raw = str(10) })
	local reward = gear({ name = "Reward", raw = str(20) })
	w.dui("Login")
	WORLD.quest = { { link = gear({ name = "Other", raw = str(1) }) }, { link = reward } }
	local rows = {}
	local lines = { Row = function(label, value) rows[#rows + 1] = label .. ": " .. value end, Text = function() end }
	NS.Marks.OnItemTooltip(lines, { link = nil, itemID = Stats.ItemID(reward) })
	T.eq(#rows, 1, "the link is found among the quest's rewards by the item's ID")
	T.check(rows[1] and rows[1]:find("+100%", 1, true), "and the row is the reward's: " .. tostring(rows[1]))
	rows = {}
	NS.Marks.OnItemTooltip(lines, { link = nil, itemID = 424242 })
	T.eq(#rows, 0, "an item that is no reward of the page: no row, no error")
	NS.Marks.OnItemTooltip(lines, { link = nil })
	T.eq(#rows, 0, "nothing at all to go by: no row")
	WORLD.quest = nil
end)

T.case("rows trickling in after the list was scored paint once a second at most", function()
	T.reset()
	character()
	WORLD.worn[5] = gear({ name = "Worn Vest", raw = str(10) })
	w.dui("Login")
	local ah = w.ah
	ah.rows = { { itemID = 1, link = gear({ name = "First", raw = str(12) }), buyout = 20000, count = 1 } }
	ah.rows[1].itemID = Stats.ItemID(ah.rows[1].link)
	ah.open = true
	w.fire("AUCTION_HOUSE_SHOW"); w.fire("REPLICATE_ITEM_LIST_UPDATE")
	for _ = 1, 600 do
		w.frames(1)
		if NS.Market.State() == "ready" and not NS.Market.Looking() then break end
	end
	Window.IsShown = function() return true end
	Window.Refresh(true)
	for _ = 1, 400 do
		if not Window.S.running then break end
		w.frames(1)
	end
	local job, before = Window.S.job, NS.Perf.Sum("show")
	-- the tail: ten rows a frame for six seconds (3,000 rows)
	for f = 1, 300 do
		for i = 1, 10 do
			local link = gear({ raw = str(11 + (f * 10 + i) % 40) })
			NS.Fire("MarketAdded", Stats.Key(link), 20000 + f, "new", { 4, 4, "INVTYPE_CHEST", 0 })
		end
		w.frames(1)
	end
	w.advance(3)
	T.check(Window.S.job == job, "the same job throughout")
	local paints = NS.Perf.Sum("show") - before
	T.check(paints >= 2 and paints <= 10, "3,000 rows over six seconds: a handful of paints, not one per batch (" .. paints .. ")")
	T.check(#job.rows > 1000, "and the rows did come in (" .. #job.rows .. ")")
	T.eq(Window.S.running, false, "the job is at rest at the end")
	ah.open = false
	w.fire("AUCTION_HOUSE_CLOSED")
end)

return T.done()
