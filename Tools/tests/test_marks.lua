-- Marks.lua on a stand-in for Daylight UI and its bags: the words for every verdict, the tooltip
-- row's contract, the bag widget's contract, one verdict per link until something changes,
-- what refreshes, nothing worked out in a fight, and standing down without the bags.
-- (The stand-ins follow DaylightUI\API.lua:1610-1629 for me.AddTooltipLines and
-- DaylightUI_Bags\Plugins.lua:76-117, :172-207 for the Baganator-style calls.)
-- luacheck: ignore 111 112 113 121 122 212
setmetatable(_G, nil)

local function read(rel)
	local handle = assert(io.open(ADDON_ROOT .. "/" .. rel, "r"))
	local source = handle:read("*a")
	handle:close()
	return source
end
local function run(rel, ns) return assert(loadstring(read(rel), "@" .. rel))("GloweyGear", ns) end

-- ---- the game and Daylight UI, as far as Core.lua and Marks.lua touch them ---------------------
local timers, frames, handlers, settings, tipLines, textures
local combat = false
local locale = "enUS"
DEFAULT_CHAT_FRAME = { AddMessage = function() end }
geterrorhandler = function() return function(err) error(err, 0) end end
GetLocale = function() return locale end
UnitName = function() return "Tester" end
GetRealmName = function() return "Test Realm" end
NUM_BAG_SLOTS = 4
C_Timer = { After = function(_, fn) timers[#timers + 1] = fn end }
local function texture()
	textures = textures + 1
	return { SetColorTexture = function() end, SetSize = function() end, SetPoint = function() end }
end
CreateFrame = function(_, _, parent)
	local f = { events = {}, parent = parent, shown = false }
	function f:RegisterEvent(event) self.events[event] = true end
	function f:UnregisterEvent(event) self.events[event] = nil end
	function f:SetScript(_, fn) self.script = fn end
	function f:SetSize(w, h) self.w, self.h = w, h end
	function f:SetParent(p) self.parent = p end
	function f:CreateTexture() return texture() end
	frames[#frames + 1] = f
	return f
end
local function fire(event, ...)
	for _, f in ipairs(frames) do
		if f.events[event] and f.script then f.script(f, event, ...) end
	end
end
local function tick()
	local due = timers
	timers = {}
	for _, fn in ipairs(due) do fn() end
end
local function dui(event, ...)
	for _, fn in ipairs(handlers[event] or {}) do fn(...) end
end
local function set(path, value)
	settings[path] = value
	dui("SettingChanged", "GloweyGear", path)
end

-- Daylight UI's bags: the stand-in records what is registered and how often a repaint is asked.
local bags
local function Shim(own)
	bags = { widgets = {}, repaints = 0 }
	return {
		DaylightUI = own,
		API = {
			RegisterCornerWidget = function(label, id, onUpdate, onInit, position)
				bags.widgets[#bags.widgets + 1] = { label = label, id = id, onUpdate = onUpdate, onInit = onInit,
					corner = position and position.corner, priority = position and position.priority }
			end,
			RequestItemButtonsRefresh = function() bags.repaints = bags.repaints + 1 end,
		},
	}
end

-- A whole plugin from nothing: the locale table, the weights, the engine over the mock game,
-- Core.lua, Marks.lua. opts: shim ("own" Daylight UI's, "other" Baganator itself, nil none),
-- me = false (a Daylight UI with no tooltip lines), lang.
local verdicts, module
local slots = {}
local function boot(opts)
	opts = opts or {}
	timers, frames, handlers, settings, tipLines, textures = {}, {}, {}, {}, {}, 0
	combat, locale = false, opts.lang or "enUS"
	slots = {}
	GloweyGearDB = nil
	Baganator = (opts.shim == "own" and Shim(true)) or (opts.shim == "other" and Shim(nil)) or nil
	if not opts.shim then bags = nil end
	DaylightUI = {
		API = {
			major = 1, minor = 12,
			GetSetting = function(scope, path) if scope == "GloweyGear" then return settings[path] end end,
			Colors = opts.colors and function() return opts.colors end or nil,
			For = function(name)
				local me = {
					name = name,
					On = function(event, fn) handlers[event] = handlers[event] or {}; table.insert(handlers[event], fn) end,
					RegisterCommand = function() return true end,
				}
				if opts.me ~= false then
					me.AddTooltipLines = function(kind, fn)
						tipLines[#tipLines + 1] = { kind = kind, fn = fn }
						return {}
					end
				end
				return me
			end,
		},
		RegisterPlugin = function() end,
		RegisterModule = function(_, _, def) module = def end,
	}
	local game = NS.Game
	NS = { Game = game }
	game.InCombat = function() return combat end
	T.reset()
	run("Locales/Locales.lua", NS)
	if locale ~= "enUS" then run("Locales/" .. locale .. ".lua", NS) end
	run("Data/Weights.lua", NS)
	for _, file in ipairs({ "Stats.lua", "Spec.lua", "Score.lua", "Compare.lua", "Rank.lua" }) do run(file, NS) end
	-- (The shared guide and this plugin's side of it load before Core.lua, as the .toc has them.)
	if opts.guide then
		run("Guide.lua", NS)
		run("GearGuide.lua", NS)
	end
	run("Core.lua", NS)
	run("Marks.lua", NS)
	-- (Every verdict worked out is counted.)
	verdicts = 0
	local real = NS.Verdict
	NS.Verdict = function(...)
		verdicts = verdicts + 1
		return real(...)
	end
	WORLD.class, WORLD.level = "WARRIOR", 60
	WORLD.trees = { { name = "Arms", spent = 31 }, { name = "Fury", spent = 20 }, { name = "Protection", spent = 0 } }
	dui("Login")
	return NS.Marks
end

local function helm(strength, more)
	local def = { equipLoc = "INVTYPE_HEAD", subclassID = 4, raw = { ITEM_MOD_STRENGTH_SHORT = strength } }
	for k, v in pairs(more or {}) do def[k] = v end
	return T.item(def)
end
-- What is owned changed, as the game says it: the events, then Core's short wait.
local function owned()
	fire("BAG_UPDATE_DELAYED")
	tick()   -- Core's 0.3 s
	tick()   -- Marks' own repaint a moment later
end

-- A tooltip, as Daylight UI hands it over: Row collects what would be drawn.
local function tooltip(link, noRow)
	local rows = {}
	local add = function(label, value, color) rows[#rows + 1] = { label = label, value = value, color = color } end
	local lines = { Line = add }
	if not noRow then lines.Row = add end
	tipLines[1].fn(lines, { link = link, itemID = 1, style = "rich" })
	return rows
end

local function widget(corner)
	for _, w in ipairs(bags.widgets) do
		if w.corner == corner then return w end
	end
end
-- One bag slot asked, as Daylight UI's bags do: the frame is made once, then onUpdate.
local function slot(corner, link, bag)
	local w = widget(corner)
	local key = corner .. (bag or 0)
	slots[key] = slots[key] or w.onInit({})
	return w.onUpdate(slots[key], { itemLink = link, itemID = 1, bagID = bag or 0, slotID = 1 }), slots[key]
end

-- ---------------------------------------------------------------------------------------------
T.case("the words for every kind of verdict, in English", function()
	local M = boot()
	local C = M.COLOR
	local function v(t)
		local out = { group = "CHEST", usable = true, gain = 0, score = 10, base = 10, pct = 0 }
		for k, x in pairs(t) do out[k] = x end
		return out
	end
	local text, color, kind = M.Advice(v({ gain = 12, pct = 12.4, replaces = {} }), 3)
	T.eq(text, "+12% over your Chest", "an upgrade"); T.eq(color, C.good, "in the good color"); T.eq(kind, "up", "kind")
	T.eq(M.Text(v({ gain = 12, pct = 12.4, replaces = {} }), 3), "+12%", "its short form")
	T.eq(select(2, M.Text(v({ gain = 12, pct = 12.4, replaces = {} }), 3)), C.good, "the short form's color")

	text, color, kind = M.Advice(v({ gain = 2, pct = 2.5, replaces = {} }), 3)
	T.eq(text, "+2.5% over your Chest", "a gain under Smallest Gain to Show keeps its number"); T.eq(kind, "small", "kind")
	T.eq(color, nil, "in the tooltip's own color"); T.eq(M.Text(v({ gain = 2, pct = 2.5, replaces = {} }), 3), nil, "and has no short form")
	T.eq(select(3, M.Advice(v({ gain = 2, pct = 2.5, replaces = {} }), 0)), "up", "with the smallest gain at 0 it is an upgrade")

	text, color, kind = M.Advice({ group = "FINGER", usable = true, gain = 5, score = 5, base = 0, empty = true }, 3)
	T.eq(text, "Fills your empty Finger slot", "nothing owned for the slot"); T.eq(color, C.good, "good"); T.eq(kind, "empty", "kind")
	T.eq(M.Text({ group = "FINGER", usable = true, gain = 5, score = 5, base = 0, empty = true }, 3), "Empty Slot", "short form")

	-- a slot that holds an item worth nothing to the spec is not empty (the audit's M3)
	local zero = { group = "TRINKET", usable = true, gain = 5, score = 5, base = 0, empty = false, replaces = {} }
	text, color, kind = M.Advice(zero, 3)
	T.eq(text, "Better than your Trinket", "better than something, with nothing to measure a percent against"); T.eq(kind, "better", "kind"); T.eq(color, C.good, "good")
	T.eq(M.Text(zero, 3), "Better", "its short form is not 'Empty Slot'")
	-- beyond what a percent can say (the audit's M2)
	local far = { group = "NECK", usable = true, gain = 15, score = 15, base = 0.07, pct = 340, far = true, empty = false, replaces = {} }
	text, color, kind = M.Advice(far, 3)
	T.eq(text, "Far better than your Neck", "words, not a four-digit percent"); T.eq(kind, "far", "kind"); T.eq(color, C.good, "good")
	T.eq(M.Text(far, 3), "Far Better", "short form")
	-- an empty slot is said in words even when a percent exists
	text, color, kind = M.Advice({ group = "FINGER", usable = true, gain = 5, score = 5, base = 0, pct = 40, empty = true }, 3)
	T.eq(kind, "empty", "empty wins over a percent"); T.eq(text, "Fills your empty Finger slot", "its words"); T.eq(color, C.good, "good")
	-- a dual wielder's off-hand upgrade names the off hand (the audit's M4)
	text = M.Advice({ group = "OFFHAND", offHand = true, usable = true, gain = 8, score = 26, base = 18, pct = 44.4, empty = false, replaces = {} }, 3)
	T.eq(text, "+44% over your Off Hand", "the hand it would go in")

	text, color, kind = M.Advice(v({ gain = -3, pct = -30, replaces = {} }), 3)
	T.eq(text, "No better than your Chest", "not an upgrade"); T.eq(color, C.soft, "soft"); T.eq(kind, "same", "kind")
	T.eq(M.Text(v({ gain = -3, pct = -30, replaces = {} }), 3), nil, "no short form")
	T.eq(select(3, M.Advice(v({ gain = 0, pct = 0, replaces = {} }), 0)), "same", "an equal item is not an upgrade, even at 0")

	text, color, kind = M.Advice({ group = "NECK", usable = true, gain = 0, score = 0, base = 0, empty = true }, 3)
	T.eq(text, "No stats your spec uses", "nothing the weights count"); T.eq(color, C.soft, "soft"); T.eq(kind, "none", "kind")

	text, color, kind = M.Advice(v({ usable = false, reason = "level", atLevel = 40, gain = 9, pct = 90 }), 3)
	T.eq(text, "Wearable at level 40", "later"); T.eq(color, C.wait, "in the waiting color"); T.eq(kind, "later", "kind")

	text, color, kind = M.Advice({ group = "MAINHAND", usable = false, reason = "skill", atLevel = 1, gain = 1 }, 3)
	T.eq(text, "Needs a weapon skill you have not trained", "an untrained weapon"); T.eq(color, C.wait, "waiting"); T.eq(kind, "skill", "kind")
	text, color, kind = M.Advice({ group = "HEAD", usable = false, reason = "profession", atLevel = 1, gain = 1, needLine = 202, needRank = 150, needName = "Engineering" }, 3)
	T.eq(text, "Needs Engineering (150)", "a profession's item"); T.eq(color, C.wait, "waiting"); T.eq(kind, "prof", "kind")
	text = M.Advice({ group = "HEAD", usable = false, reason = "profession", atLevel = 1, gain = 1, needLine = 202, needRank = 150 }, 3)
	T.eq(text, "Needs a profession skill you do not have", "with no name from the game")

	for _, reason in ipairs({ "armor", "weapon", "tool", "lighter", "dualwield" }) do
		T.eq(M.Advice(v({ usable = false, reason = reason }), 3), nil, "no row for: " .. reason)
		T.eq(M.Text(v({ usable = false, reason = reason }), 3), nil, "and no short form")
	end
	T.eq(M.Advice({ usable = false, reason = "armor" }, 3), nil, "not gear at all: nothing")
	T.eq(M.Advice(nil, 3), nil, "no verdict: nothing"); T.eq(M.Text(nil), nil, "no short form either")

	-- every group has a slot word
	for _, group in ipairs(NS.Compare.GROUPS) do
		T.check(M.SlotName(group) ~= "", group .. " has a slot word")
	end
	T.eq(M.SlotName("MAINHAND"), "Main Hand", "the main hand"); T.eq(M.SlotName("NOPE"), "", "an unknown group is empty, not an error")
	INVTYPE_CHEST = "Brust"
	T.eq(M.SlotName("CHEST"), "Brust", "the game's own word when it has one")
	INVTYPE_CHEST = nil
end)

T.case("percents are written whole from 10 up and with one decimal below", function()
	local M = boot()
	T.eq(M.Percent(12.4), "12", "12.4"); T.eq(M.Percent(12.5), "13", "12.5"); T.eq(M.Percent(150), "150", "150")
	T.eq(M.Percent(9.96), "10", "9.96 rounds up to a whole"); T.eq(M.Percent(9.94), "9.9", "9.94")
	T.eq(M.Percent(2.5), "2.5", "2.5"); T.eq(M.Percent(3), "3", "3 has no decimal"); T.eq(M.Percent(2.96), "3", "2.96")
	T.eq(M.Percent(0.04), "0.1", "a real gain never reads 0"); T.eq(M.Percent(0), "0", "zero"); T.eq(M.Percent(nil), "0", "nothing")
end)

T.case("every language fills its holes", function()
	local KEYS = {
		{ "+%s%%", { "12" }, { "12", "%" } },
		{ "+%s%% over your %s", { "12", "SLOT" }, { "12", "%", "SLOT" } },
		{ "Better than your %s", { "SLOT" }, { "SLOT" } },
		{ "Fills your empty %s slot", { "SLOT" }, { "SLOT" } },
		{ "No better than your %s", { "SLOT" }, { "SLOT" } },
		{ "Wearable at level %d", { 40 }, { "40" } },
		{ "No stats your spec uses", {}, {} },
		{ "Needs a weapon skill you have not trained", {}, {} },
		{ "Empty Slot", {}, {} },
		{ "Gear Advice", {}, {} },
	}
	for _, lang in ipairs({ "deDE", "esES", "frFR", "koKR", "ruRU", "zhCN" }) do
		local M = boot({ lang = lang })
		local L = NS.L
		for _, k in ipairs(KEYS) do
			local key, args, want = k[1], k[2], k[3]
			local ok, text = pcall(string.format, L[key], unpack(args))
			T.check(ok, lang .. ": " .. key .. " formats (" .. tostring(text) .. ")")
			if key ~= "+%s%%" then T.check(L[key] ~= key, lang .. ": " .. key .. " is translated") end
			for _, piece in ipairs(want) do
				T.check(ok and text:find(piece, 1, true) ~= nil, lang .. ": " .. key .. " shows " .. piece)
			end
			T.check(ok and not text:find("%%[sd]"), lang .. ": " .. key .. " leaves no hole")
		end
		-- and through the real functions
		local text = M.Advice({ group = "CHEST", usable = true, gain = 1, score = 2, base = 1, pct = 100, replaces = {} }, 3)
		T.check(type(text) == "string" and text:find("100", 1, true) and text:find(M.SlotName("CHEST"), 1, true), lang .. ": the row reads " .. tostring(text))
		text = M.Advice({ group = "CHEST", usable = false, reason = "level", atLevel = 52 }, 3)
		T.check(type(text) == "string" and text:find("52", 1, true), lang .. ": the level reads " .. tostring(text))
	end
end)

T.case("the tooltip row's contract", function()
	local M = boot({ shim = "own" })
	T.eq(#tipLines, 1, "one registration"); T.eq(tipLines[1].kind, "item", "for item tooltips (which Daylight UI also runs on compare tooltips)")
	local worn = helm(10)
	local better = helm(15)
	local worse = helm(5)
	local later = helm(30, { minLevel = 70 })
	local cloth = T.item({ equipLoc = "INVTYPE_HEAD", classID = 4, subclassID = 1, raw = { ITEM_MOD_STRENGTH_SHORT = 99 } })
	local potion = T.item({ equipLoc = "" })
	WORLD.worn[1] = worn
	WORLD.level = 60
	owned()

	local rows = tooltip(better)
	T.eq(#rows, 1, "one row"); T.eq(rows[1].label, "Gear Advice", "its label")
	T.eq(rows[1].value, "+50% over your Head", "the verdict in words"); T.eq(rows[1].color, M.COLOR.good, "its color is a { r, g, b } table")
	T.eq(#rows[1].color, 3, "three numbers")
	rows = tooltip(worse)
	T.eq(rows[1].value, "No better than your Head", "not an upgrade"); T.eq(rows[1].color, M.COLOR.soft, "soft")
	T.eq(#tooltip(worn), 0, "what is worn gets no row")
	T.eq(#tooltip(cloth), 1, "lighter armor is still gear for the class")
	T.eq(#tooltip(potion), 0, "not gear: no row")
	T.eq(#tooltip(T.item({ equipLoc = "INVTYPE_RELIC", classID = 4, subclassID = 8, raw = {} })), 0, "gear the class can never wear: no row")
	rows = tooltip(later)
	T.eq(rows[1] and rows[1].value, "Wearable at level 70", "wearable later"); T.eq(rows[1] and rows[1].color, M.COLOR.wait, "waiting color")
	T.eq(#tooltip(nil), 0, "a secret or missing link: nothing")
	T.eq(#tooltip(T.item({ equipLoc = "INVTYPE_HEAD", loaded = false })), 0, "item data not here yet: nothing, the tooltip fills again")
	T.eq(tooltip(better, true)[1].value, "+50% over your Head", "a Daylight UI without Row gets the same through Line")
	-- nothing breaks on odd arguments
	T.check(pcall(tipLines[1].fn, nil, nil), "no lines, no data")
	T.check(pcall(tipLines[1].fn, {}, { link = better }), "lines with no Row or Line")

	-- an item that is itself in the bags is compared with the rest, not with itself
	WORLD.bags = { better }
	owned()
	T.eq(tooltip(better)[1].value, "+50% over your Head", "hovering the carried copy: still an upgrade over what is worn")
	T.eq(tooltip(worse)[1].value, "No better than your Head", "others are compared with the best owned")

	-- the switches
	set("tooltips", false)
	T.eq(#tooltip(better), 0, "Item Tooltips off: no row")
	set("tooltips", nil)
	T.eq(#tooltip(better), 1, "on again: at once")
	set("enabled", false)
	T.eq(#tooltip(better), 0, "the plugin off: no row")
	set("enabled", nil)
	set("minGain", 60)
	rows = tooltip(better)
	T.eq(rows[1].value, "+50% over your Head", "under a higher smallest gain the number stays"); T.eq(rows[1].color, nil, "but not in the good color")
	set("minGain", nil)
end)

T.case("Daylight UI's ink colors the row when it has them", function()
	local M = boot({ colors = { GOOD = { 0.1, 0.2, 0.3 }, LABEL = { 0.4, 0.5, 0.6 }, WARN = "bad" } })
	T.eq(M.COLOR.good[2], 0.2, "good from GOOD"); T.eq(M.COLOR.soft[3], 0.6, "soft from LABEL")
	T.eq(M.COLOR.wait[1], 1, "a role that is not a color keeps ours")
end)

T.case("one verdict per link until something changes", function()
	local M = boot({ shim = "own" })
	local worn, better, worse = helm(10), helm(15), helm(5)
	WORLD.worn[1] = worn
	WORLD.bags = { better }
	owned()
	verdicts, M.stats.computed = 0, 0
	for _ = 1, 20 do tooltip(better) end
	T.eq(verdicts, 1, "twenty fills of one tooltip are one verdict")
	for _ = 1, 20 do tooltip(worse) end
	T.eq(verdicts, 2, "another link, another one")
	for _ = 1, 20 do tooltip(worn) end
	T.eq(verdicts, 2, "what is worn needs none")
	for _ = 1, 20 do slot("bottom_right", better, 0) end
	T.eq(verdicts, 3, "the bag slot's view of the link is worked out once")
	for _ = 1, 20 do slot("top_left", better, 0); slot("bottom_left", better, 0); slot("top_right", better, 0) end
	T.eq(verdicts, 3, "the corners not in use never ask")
	local calls = WORLD.calls.ItemStats

	-- item data arriving for something else: what is owned reads the same, so nothing is redone
	local before = bags.repaints
	fire("GET_ITEM_INFO_RECEIVED"); tick(); tick()
	for _ = 1, 5 do tooltip(better); slot("bottom_right", better, 0) end
	T.eq(verdicts, 3, "the same things owned: every answer is kept")
	T.eq(bags.repaints, before, "and the bags are left alone")
	T.eq(WORLD.calls.ItemStats, calls, "no item is read again")

	-- what is owned changes
	WORLD.bags = { better, worse }
	owned()
	T.eq(bags.repaints, before + 1, "something new in the bags: one repaint")
	tooltip(better); tooltip(better)
	T.eq(verdicts, 4, "and the answer is worked out again, once")
end)

T.case("what refreshes, and that a burst is one repaint", function()
	local M = boot({ shim = "own" })
	local worn, better = helm(10), helm(15)
	WORLD.worn[1] = worn
	WORLD.bags = { better }
	owned()
	local before = bags.repaints
	M.Refresh(); M.Refresh(); M.Refresh()
	T.eq(#timers, 1, "three requests wait as one")
	tick()
	T.eq(bags.repaints, before + 1, "one repaint")

	-- level
	verdicts = 0
	tooltip(better)
	WORLD.level = 61
	fire("PLAYER_LEVEL_UP"); tick(); tick()
	T.eq(bags.repaints, before + 2, "a level-up repaints the bags")
	tooltip(better)
	T.eq(verdicts, 2, "and the verdict is worked out for the new level")
	-- spec (talents)
	fire("PLAYER_TALENT_UPDATE"); tick(); tick()
	T.eq(bags.repaints, before + 2, "a talent event that leaves the spec as it was repaints nothing")
	local treesWere = WORLD.trees
	WORLD.trees = { { name = "One", spent = 0 }, { name = "Two", spent = 0 }, { name = "Three", spent = 51 } }
	fire("PLAYER_TALENT_UPDATE"); tick(); tick()
	T.eq(bags.repaints, before + 3, "a talent change that changes the spec repaints")
	WORLD.trees = treesWere
	fire("PLAYER_TALENT_UPDATE"); tick(); tick()
	before = before + 1
	-- gear
	WORLD.worn[1] = better
	WORLD.bags = { worn }
	fire("PLAYER_EQUIPMENT_CHANGED"); tick(); tick()
	T.eq(bags.repaints, before + 4, "an equipment change repaints")
	T.eq(#tooltip(better), 0, "the helm now worn has no row")
	T.eq(tooltip(worn)[1].value, "No better than your Head", "the old one, now in the bags, is no upgrade")
	-- settings of ours
	local n = bags.repaints
	for _, path in ipairs({ "minGain", "bestArmor", "bagMarks", "bagCorner", "enabled", "tooltips" }) do
		set(path, settings[path])
		tick()
		n = n + 1
		T.eq(bags.repaints, n, path .. " repaints")
	end
	-- switched off, a change in the bags repaints nothing
	set("enabled", false); tick()
	n = bags.repaints
	WORLD.bags = {}
	owned()
	T.eq(bags.repaints, n, "with the plugin off the bags are left alone")
	set("enabled", nil); tick()
	n = bags.repaints
	for _, path in ipairs({ "maxPrice", "mode", "dock" }) do
		set(path, settings[path])
		tick()
		T.eq(bags.repaints, n, path .. " is not ours: nothing")
	end
end)

T.case("the bag widget's contract", function()
	local M = boot({ shim = "own" })
	T.eq(M.shim, true, "the stand-in was found")
	T.eq(#bags.widgets, 4, "one widget per corner")
	local seen, ids = {}, {}
	for _, w in ipairs(bags.widgets) do
		seen[w.corner] = true
		T.check(not ids[w.id], "ids differ: " .. tostring(w.id)); ids[w.id] = true
		T.check(type(w.id) == "string" and w.id:find("^daylightgear_"), "an id of ours")
		T.eq(w.label, "Gear Advice", "its label"); T.eq(w.priority, 0, "before the marks Daylight UI hooks up at 1")
		T.check(type(w.onUpdate) == "function" and type(w.onInit) == "function", "both functions")
	end
	T.check(seen.top_left and seen.bottom_right and seen.bottom_left and seen.top_right, "Daylight UI's four corner names")

	local worn, better, worse = helm(10), helm(15), helm(5)
	local pending = helm(20, { loaded = false })
	WORLD.worn[1] = worn
	WORLD.bags = { better, worse, pending }
	owned()
	textures = 0
	local shown, frame = slot("bottom_right", better, 0)
	T.eq(shown, true, "an upgrade in the bags: the mark shows in the default corner (bottom right)")
	T.check(type(frame) == "table" and type(frame.SetParent) == "function", "onInit gave a frame Daylight UI can parent")
	T.eq(frame.w, 11, "of the mark's size"); T.eq(textures, 4, "drawn when first shown")
	slot("bottom_right", better, 0)
	T.eq(textures, 4, "and only once")
	T.eq(slot("top_left", better, 0), false, "the other corners say no")
	T.eq(slot("top_right", better, 0), false, "all of them")
	T.eq(slot("bottom_right", worse, 0), false, "no upgrade: false, not nil")
	T.eq(slot("bottom_right", worn, 0), false, "a second copy of what is worn: no mark")
	T.eq(slot("bottom_right", T.item({ equipLoc = "" }), 0), false, "not gear: false")
	T.eq(slot("bottom_right", nil, 0), false, "an empty slot's details: false")
	T.check(pcall(widget("bottom_right").onUpdate, frame, nil), "no details at all does not raise")

	-- pending: nil asks Daylight UI to try again; when the data is in, it answers
	T.eq(slot("bottom_right", pending, 0), nil, "item data not loaded: nil (asked again)")
	T.load(pending)
	fire("GET_ITEM_INFO_RECEIVED"); tick(); tick()
	T.eq(slot("bottom_right", pending, 0), true, "loaded: an upgrade")

	-- the bank: compared with everything worn and carried
	T.eq(slot("bottom_right", pending, -1), false, "a bank copy of the best carried helm is no upgrade")
	T.eq(slot("bottom_right", helm(40), -1), true, "a better one in the bank is")

	-- small gains are not marked
	T.eq(slot("bottom_right", better, 0), false, "no longer the best carried: no mark")
	T.eq(slot("bottom_right", pending, 0), true, "the best carried one has it")
	set("minGain", 150); tick()
	T.eq(slot("bottom_right", pending, 0), false, "under Smallest Gain to Show: no mark")
	set("minGain", nil); tick()

	-- the switches, live
	local n = bags.repaints
	set("bagCorner", "bottom_left"); tick()
	T.eq(bags.repaints, n + 1, "Bag Corner asks for a repaint")
	T.eq(slot("bottom_right", pending, 0), false, "the old corner lets go")
	T.eq(slot("bottom_left", pending, 0), true, "the new one shows it, with no reload")
	set("bagCorner", "middle"); tick()
	T.eq(slot("bottom_right", pending, 0), true, "a corner that is not one: the default")
	set("bagCorner", nil); tick()
	set("bagMarks", false); tick()
	T.eq(slot("bottom_right", pending, 0), false, "Bag Slots off: no mark")
	set("bagMarks", nil); tick()
	T.eq(slot("bottom_right", pending, 0), true, "on again")
	set("enabled", false); tick()
	T.eq(slot("bottom_right", pending, 0), false, "the plugin off: no mark")
	set("enabled", nil); tick()
end)

T.case("in a fight nothing is worked out", function()
	local M = boot({ shim = "own" })
	local worn, better, other = helm(10), helm(15), helm(18)
	WORLD.worn[1] = worn
	WORLD.bags = { better }
	owned()
	tooltip(better); slot("bottom_right", better, 0)
	verdicts = 0
	local items, repaints = WORLD.calls.ItemInstant, bags.repaints
	combat = true
	T.eq(tooltip(better)[1].value, "+50% over your Head", "what was known before the fight still shows")
	T.eq(slot("bottom_right", better, 0), true, "on the bag slot too")
	T.eq(#tooltip(other), 0, "an item not seen before: no row in a fight")
	T.eq(slot("bottom_right", other, 0), false, "and no mark (false: Daylight UI is not asked to try again)")
	T.eq(verdicts, 0, "no verdict was worked out"); T.eq(WORLD.calls.ItemInstant, items, "and no item was read")
	M.Refresh(); tick()
	T.eq(bags.repaints, repaints, "a refresh in a fight does not repaint the bags")
	T.eq(#tooltip(better), 0, "and nothing is worked out again until it ends")
	T.eq(verdicts, 0, "still none")
	combat = false
	fire("PLAYER_REGEN_ENABLED"); tick()
	T.eq(bags.repaints, repaints + 1, "the fight ends: one repaint")
	T.eq(tooltip(other)[1].value, "+20% over your Head", "and the answers come (against the best owned, the carried helm)")
	T.eq(slot("bottom_right", other, 0), true, "on the bags too")
	local n = bags.repaints
	fire("PLAYER_REGEN_ENABLED"); tick()
	T.eq(bags.repaints, n, "a fight with nothing put off repaints nothing")
end)

T.case("without Daylight UI's bags there is no mark, and no error", function()
	local M = boot({})
	T.eq(M.shim, false, "no stand-in: no bag mark")
	local worn, better = helm(10), helm(15)
	WORLD.worn[1] = worn
	owned()
	T.eq(tooltip(better)[1].value, "+50% over your Head", "the tooltip row works all the same")
	local waiting = #timers
	M.Refresh(); M.Refresh()
	T.eq(#timers, waiting, "a refresh schedules nothing")
	combat = true; tooltip(helm(30)); combat = false
	T.check(pcall(fire, "PLAYER_REGEN_ENABLED"), "the end of a fight is quiet too")

	M = boot({ shim = "other" })
	T.eq(M.shim, false, "Baganator itself (not Daylight UI's stand-in) is left alone")
	T.eq(#bags.widgets, 0, "nothing registered with it")

	Baganator = { DaylightUI = true, API = { RegisterCornerWidget = "no" } }
	M = boot({ shim = nil })
	T.eq(M.shim, false, "a stand-in that changed shape: no mark, no error")
	Baganator = nil

	M = boot({ shim = "own", me = false })
	T.eq(#tipLines, 0, "a Daylight UI without tooltip lines: no row")
	T.eq(M.shim, true, "the bag mark still registers")
	M.Register()
	T.eq(#bags.widgets, 4, "registering twice adds nothing")
end)

T.case("with no weights for the class nothing shows", function()
	local M = boot({ shim = "own" })
	WORLD.class = "MONK"
	fire("PLAYER_TALENT_UPDATE"); tick(); tick()
	local link = helm(15)
	T.eq(#tooltip(link), 0, "no row"); T.eq(slot("bottom_right", link, 0), false, "no mark")
	T.check(M.Lookup("tip", link) == false, "and the answer is kept as nothing")
end)

T.case("the guide: the welcome, the tour and the Help card", function()
	InCombatLockdown = function() return combat end
	UIParent = {}
	boot({ guide = true })
	local Guide = NS.Guide
	T.check(type(NS.Pad) == "table" and type(NS.Pad.Follow) == "function", "Guide.lua brings the controller helper")
	T.check(type(Guide) == "table", "and the guide")
	-- the Help card is on the options page, with the shared file's own rows
	local help
	for _, group in ipairs(module.options.pages[1].groups) do
		if group.label == "Help" then help = group end
	end
	T.check(help ~= nil, "a Help group on the page")
	T.eq(help and help.items[1].label, "Retake Tour", "Retake Tour"); T.eq(help and help.items[2].label, "What's New", "What's New")
	T.eq(help and #help.items, 2, "and nothing to revert")
	for _, item in ipairs(help and help.items or {}) do
		T.eq(item.type, "button", item.label .. " is a button"); T.check(type(item.func) == "function", "with something to do")
	end
	-- first launch: nothing answered yet, and the saved table is the plugin's own
	fire("ADDON_LOADED", "GloweyGear")
	T.eq(Guide.Welcoming(), true, "a new player has the welcome waiting")
	T.eq(type(GloweyGearDB.guide), "table", "the guide keeps its keys in GloweyGearDB")
	T.eq(GloweyGearDB.v, 2, "which Core.lua still reads as its own")
	T.eq(Guide.Running(), false, "no tour runs by itself")
end)

T.case("an effect the score leaves out is said on the tooltip, in words (the audit's M1)", function()
	T.reset()
	WORLD.class, WORLD.level = "WARRIOR", 60
	WORLD.trees = { { name = "Arms", spent = 31 }, { name = "Fury", spent = 20 }, { name = "Protection", spent = 0 } }
	WORLD.worn[13] = T.item({ equipLoc = "INVTYPE_TRINKET", raw = { ITEM_MOD_STRENGTH_SHORT = 5 } })
	WORLD.worn[14] = T.item({ equipLoc = "INVTYPE_TRINKET", raw = { ITEM_MOD_STRENGTH_SHORT = 5 } })
	fire("PLAYER_EQUIPMENT_CHANGED"); tick(); tick()
	local function tip(link)
		local rows, texts = {}, {}
		local lines = {
			Row = function(label, value, color) rows[#rows + 1] = { label = label, value = value, color = color } end,
			Text = function(text, color) texts[#texts + 1] = { text = text, color = color } end,
		}
		tipLines[1].fn(lines, { link = link, itemID = 1, style = "rich" })
		return rows, texts
	end
	local counted = T.item({ equipLoc = "INVTYPE_TRINKET", raw = { ITEM_MOD_STRENGTH_SHORT = 9, ITEM_MOD_CRIT_RATING_SHORT = 14 }, effects = { equip = 1 } })
	local rows, texts = tip(counted)
	T.eq(#rows, 1, "the Gear Advice row"); T.eq(#texts, 0, "and nothing more for an item that is fully counted")
	local use = T.item({ equipLoc = "INVTYPE_TRINKET", raw = { ITEM_MOD_STRENGTH_SHORT = 9 }, effects = { use = 1 } })
	rows, texts = tip(use)
	T.eq(#rows, 1, "the row"); T.eq(#texts, 1, "and one more line")
	T.eq(texts[1].text, "Gear Advice does not count this item's special effect.", "in plain words")
	T.eq(texts[1].text, NS.Marks.NOTE, "the one sentence, shared with the window")
	local equip = T.item({ equipLoc = "INVTYPE_TRINKET", raw = { ITEM_MOD_STRENGTH_SHORT = 9 }, effects = { equip = 1 } })
	rows, texts = tip(equip)
	T.eq(#rows, 1, "the row"); T.eq(#texts, 1, "an Equip effect the stat call did not answer is said too")
	local blind = T.item({ equipLoc = "INVTYPE_TRINKET", raw = { ITEM_MOD_STRENGTH_SHORT = 9 } })
	rows, texts = tip(blind)
	T.eq(#rows, 1, "the row"); T.eq(#texts, 0, "when the game gives no line types, nothing is claimed")
	-- an older Daylight UI without lines.Text: the row still shows, nothing breaks
	local got = {}
	tipLines[1].fn({ Row = function(label, value) got[#got + 1] = value end }, { link = use, itemID = 1 })
	T.eq(#got, 1, "the row alone")
	-- asked once per item
	local calls = WORLD.calls.ItemEffects
	tip(use); tip(use); tip(equip)
	T.eq(WORLD.calls.ItemEffects, calls, "the tooltip's lines are counted once and kept")
end)

T.case("a verdict too long for the card's row goes on a line of its own, under its label", function()
	-- Daylight UI's Rich card for an item is 290 wide at most, 258 inside; a row keeps its value
	-- whole and cuts the LABEL to what is left (DaylightUI_Tooltip\Rich\Panel.lua:34, :25,
	-- :766-777). "Needs a weapon skill you have not trained" left no room for "Gear Advice".
	local M = boot({ shim = "own" })
	T.check(M.Fits("Gear Advice", "+12% over your Chest"), "a short verdict fits beside its label")
	T.check(not M.Fits("Gear Advice", "Needs a weapon skill you have not trained"), "a long one does not")
	T.check(M.Fits("x", "y", function() return 100 end), "measured widths are used when there are any: 100 + 100 fits")
	T.check(not M.Fits("x", "y", function() return 130 end), "130 + 130 does not")
	T.check(not M.Fits("장비 조언", "훈련하지 않은 무기 숙련이 필요합니다"), "wide characters count wide")
	-- every verdict sentence in every language: whichever layout is chosen, nothing is cut
	local longest = 0
	for _, lang in ipairs({ "enUS", "deDE", "esES", "frFR", "koKR", "ruRU", "zhCN" }) do
		local Ml = boot({ shim = "own", lang = lang })
		local L = NS.L
		local label = L["Gear Advice"]
		for _, key in ipairs({ "+%s%% over your %s", "Far better than your %s", "Better than your %s", "Fills your empty %s slot",
			"No better than your %s", "No stats your spec uses", "Wearable at level %d", "Needs a weapon skill you have not trained" }) do
			local text = L[key]:gsub("%%s%%%%", "12%%%%"):gsub("%%s", "Main Hand"):gsub("%%d", "60"):gsub("%%%%", "%%")
			local w = Ml.Width(label) + Ml.Width(text)
			if Ml.Fits(label, text) then
				T.check(w <= Ml.ROW_ROOM, lang .. ": a verdict kept in the row is within the row's room (" .. text .. ")")
				longest = math.max(longest, w)
			end
		end
	end
	T.check(longest > 0, "some verdicts do stay in the row")
	-- the two layouts, as the tooltip gets them
	boot({ shim = "own" })
	WORLD.class, WORLD.level = "WARRIOR", 60
	WORLD.worn[1] = helm(10)
	owned()
	local function tip(link)
		local rows, texts = {}, {}
		tipLines[1].fn({
			Row = function(label, value, color) rows[#rows + 1] = { label = label, value = value, color = color } end,
			Text = function(text, color) texts[#texts + 1] = { text = text, color = color } end,
		}, { link = link, itemID = 1, style = "rich" })
		return rows, texts
	end
	local rows, texts = tip(helm(15))
	T.eq(#rows, 1, "a short verdict: one row"); T.eq(rows[1].label, "Gear Advice", "label on the left")
	T.eq(rows[1].value, "+50% over your Head", "value on the right"); T.eq(#texts, 0, "and no line besides")
	-- a weapon for an empty hand: a sentence too long for the row
	local sword = T.item({ equipLoc = "INVTYPE_WEAPON", classID = 2, subclassID = 7, raw = { ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 10 } })
	rows, texts = tip(sword)
	T.eq(#rows, 1, "a long verdict: the label has a row to itself"); T.eq(rows[1].label, "Gear Advice", "the label")
	T.eq(rows[1].value, "", "with no value beside it")
	T.eq(#texts, 1, "and the sentence on a line of its own, where it can wrap")
	T.eq(texts[1] and texts[1].text, "Fills your empty Main Hand slot", "the whole sentence")
	T.check(texts[1] and texts[1].color ~= nil, "in the verdict's color")
	-- an older Daylight UI without lines.Text: the row as before, rather than nothing
	local got = {}
	tipLines[1].fn({ Row = function(label, value) got[#got + 1] = value end }, { link = sword, itemID = 1 })
	T.eq(got[1], "Fills your empty Main Hand slot", "without lines.Text the row carries the sentence")
end)

return T.done()
