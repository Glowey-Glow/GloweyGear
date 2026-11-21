-- Core.lua on a stand-in for Daylight UI: it registers a well-formed plugin and options page,
-- wires the saved variables to the spec picker, and answers verdicts through the engine.
-- (The stand-in checks the rules Daylight UI's own registry applies to option rows:
-- DaylightUI\Options\Registry.lua:60-110.)
setmetatable(_G, nil)

local function read(rel)
	local handle = assert(io.open(ADDON_ROOT .. "/" .. rel, "r"))
	local source = handle:read("*a")
	handle:close()
	return source
end
local function run(rel, ns) return assert(loadstring(read(rel), "@" .. rel))("GloweyGear", ns) end

-- ---- the game and Daylight UI, as far as Core.lua touches them ---------------------------------
local timers, frames, handlers, commands, settings, registered = {}, {}, {}, {}, {}, {}
DEFAULT_CHAT_FRAME = { lines = {}, AddMessage = function(self, text) self.lines[#self.lines + 1] = text end }
geterrorhandler = function() return function(err) error(err, 0) end end
GetLocale = function() return "enUS" end
C_Timer = { After = function(_, fn) timers[#timers + 1] = fn end }
CreateFrame = function()
	local f = { events = {} }
	function f:RegisterEvent(event) self.events[event] = true end
	function f:SetScript(_, fn) self.script = fn end
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

DaylightUI = {
	API = {
		major = 1, minor = 12,
		GetSetting = function(scope, path) if scope == "GloweyGear" then return settings[path] end end,
		For = function(name)
			return {
				name = name,
				On = function(event, fn) handlers[event] = handlers[event] or {}; table.insert(handlers[event], fn) end,
				RegisterCommand = function(word, fn, help) commands[word] = { fn = fn, help = help } return true end,
			}
		end,
	},
	RegisterPlugin = function(_, name, spec) registered.plugin = { name = name, spec = spec } end,
	RegisterModule = function(_, name, def) registered.module = { name = name, def = def } end,
}
local function dui(event, ...)
	for _, fn in ipairs(handlers[event] or {}) do fn(...) end
end

-- ---- load: the locale table, the real weights, the engine (already in NS), then Core ----------
run("Locales/Locales.lua", NS)
run("Data/Weights.lua", NS)
run("Core.lua", NS)

T.case("it registers as a Daylight UI plugin", function()
	T.eq(NS.ok, true, "Core ran to its end")
	local p = registered.plugin
	T.eq(p.name, "GloweyGear", "under the addon's folder name")
	T.eq(p.spec.title, "Glowey's Gear", "a clean title"); T.check(not p.spec.title:find("|"), "no color codes in the title")
	T.eq(p.spec.needs[1], 1, "API major"); T.eq(p.spec.needs[2], 12, "API minor (tooltip rows are 1.12)")
	T.eq(p.spec.short, "Gear", "the rail name"); T.check(type(p.spec.blurb) == "string" and #p.spec.blurb > 0, "a blurb")
	T.eq(registered.module.def.plugin, "GloweyGear", "its module belongs to the plugin")
	T.eq(#NS.dataProblems, 0, "the weights loaded clean")
end)

T.case("the rail name is one word of at most eight characters in every language", function()
	for _, lang in ipairs({ "deDE", "esES", "frFR", "koKR", "ruRU", "zhCN" }) do
		local value = read("Locales/" .. lang .. ".lua"):match('L%["Gear"%]%s*=%s*"([^"]*)"')
		T.check(value ~= nil, lang .. " has the rail name")
		local chars = 0
		for _ in (value or ""):gmatch("[%z\1-\127\194-\244][\128-\191]*") do chars = chars + 1 end
		T.check(chars >= 1 and chars <= 8, lang .. ": " .. tostring(value) .. " is " .. chars .. " characters")
		T.check(not (value or ""):find("%s"), lang .. ": one word")
	end
end)

T.case("every options row is one Daylight UI accepts", function()
	local def = registered.module.def
	local defaults, pages = def.defaults, def.options.pages
	T.eq(#pages, 1, "one page"); T.eq(pages[1].id, "gear", "its id")
	T.check(type(pages[1].desc) == "string" and not pages[1].desc:find("\n"), "a one-line description")
	local known = { toggle = true, slider = true, dropdown = true, color = true, button = true, text = true }
	local rows = 0
	for _, group in ipairs(pages[1].groups) do
		T.check(type(group.label) == "string" and group.label ~= "", "a group has a label")
		for _, item in ipairs(group.items) do
			rows = rows + 1
			local at = tostring(item.label)
			T.check(known[item.type], at .. ": a known row type")
			T.check(type(item.label) == "string" and item.label ~= "", at .. ": a label")
			T.check(item.desc == nil or type(item.desc) == "string", at .. ": desc is text")
			T.check(item.disabled == nil or type(item.disabled) == "function", at .. ": disabled is a function")
			if item.type == "toggle" or item.type == "slider" or item.type == "dropdown" then
				if item.get or item.set then
					T.check(type(item.get) == "function" and type(item.set) == "function", at .. ": get and set together")
					T.check(type(item.default) == "function", at .. ": a default function")
					T.check(item.values == nil or item.values[item.default()] ~= nil, at .. ": its default is one of its values")
				else
					local d = defaults[item.key]
					T.check(type(item.key) == "string" and d ~= nil, at .. ": a key with a default")
					if item.type == "toggle" then T.eq(type(d), "boolean", at .. ": a boolean default") end
					if item.type == "slider" then
						T.check(type(d) == "number" and item.min < item.max and d >= item.min and d <= item.max, at .. ": default in range")
						T.check(item.step == nil or item.step > 0, at .. ": a step")
					end
					if item.type == "dropdown" then
						T.check(type(item.values) == "table" and item.values[d] ~= nil, at .. ": default is one of its values")
					end
				end
				if item.type == "dropdown" then
					for key, word in pairs(item.values) do
						T.check(type(key) == "string" and type(word) == "string" and word ~= "", at .. ": choice " .. tostring(key))
					end
				end
			end
		end
	end
	T.check(rows >= 11, "the page has its rows (" .. rows .. ")")
	local last = pages[1].groups[#pages[1].groups]
	T.check(last.label ~= nil, "groups end cleanly")
end)

T.case("login, the spec picker and the saved choice", function()
	T.reset()
	WORLD.class, WORLD.level = "DRUID", 30
	WORLD.trees = { { name = "Gleichgewicht", spent = 0 }, { name = "Wilder Kampf", spent = 21 }, { name = "Wiederherstellung", spent = 0 } }
	dui("Login")
	local who = NS.Who()
	T.eq(who.class, "DRUID", "class"); T.eq(who.spec, "FERAL_CAT", "the tree with the points"); T.eq(who.level, 30, "level")
	T.eq(GloweyGearDB.v, 2, "the saved table has its version"); T.eq(type(GloweyGearDB.houses), "table", "and its parts")
	local mine = GloweyGearDB.chars[WORLD.guid]
	T.check(mine ~= nil, "this character's record is kept under its GUID"); T.eq(mine.name, "Tester", "with its name, for a person reading the file")
	T.eq(GloweyGearDB.chars["Test Realm-Tester"], nil, "and not under realm and name")
	T.eq(mine.spec, "auto", "this character starts on Auto"); T.eq(mine.last, "FERAL_CAT", "and remembers what Auto found")
	T.eq(NS.SpecValues.auto, "Auto", "the picker has Auto")
	T.eq(NS.SpecValues.FERAL_CAT, "Wilder Kampf", "a tree's spec shows the game's own tree name")
	T.eq(NS.SpecValues.BALANCE, "Gleichgewicht", "for each tree")
	T.eq(NS.SpecValues.FERAL_BEAR, "Bear", "a variant shows our word"); T.eq(NS.SpecValues.LEVELING, "Leveling", "and so does Leveling")
	-- the picker row writes the character's choice
	local picker
	for _, group in ipairs(registered.module.def.options.pages[1].groups) do
		for _, item in ipairs(group.items) do
			if item.type == "dropdown" and item.get then picker = item end
		end
	end
	T.eq(picker.get(), "auto", "the row reads Auto")
	picker.set("FERAL_BEAR")
	T.eq(mine.spec, "FERAL_BEAR", "the choice is saved for the character"); T.eq(picker.get(), "FERAL_BEAR", "and read back")
	who = NS.Who()
	T.eq(who.spec, "FERAL_BEAR", "and used at once"); T.eq(who.how, "chosen", "as a choice")
	picker.set("auto")
	T.eq(NS.Who().spec, "FERAL_CAT", "back on Auto")
	mine.spec = "GONE"
	T.eq(picker.get(), "auto", "a saved choice that no longer exists reads as Auto")
	mine.spec = "auto"
end)

T.case("before the game has tree names, the picker still has words", function()
	T.reset()
	WORLD.class, WORLD.level, WORLD.trees = "HUNTER", 5, nil
	dui("Login")
	T.eq(NS.SpecValues.BEAST_MASTERY, "Beast Mastery", "the key as words")
	T.eq(NS.Who().spec, "LEVELING", "no talents readable and nothing remembered: the class default")
	T.eq(GloweyGearDB.chars[WORLD.guid].last, "FERAL_CAT", "a default is never written over what Auto last found")
	for _ = 1, 8 do tick() end   -- (the looks for the talent trees after login run out)
	T.eq(#timers, 0, "the looks after login end by themselves")
end)

T.case("verdicts through the engine, settings and events", function()
	T.reset()
	WORLD.class, WORLD.level = "WARRIOR", 60
	WORLD.trees = { { name = "Arms", spent = 31 }, { name = "Fury", spent = 20 }, { name = "Protection", spent = 0 } }
	GloweyGearDB.chars[WORLD.guid].last = nil
	dui("Login")
	local worn = T.item({ equipLoc = "INVTYPE_HEAD", subclassID = 4, raw = { ITEM_MOD_STRENGTH_SHORT = 10 } })
	local better = T.item({ equipLoc = "INVTYPE_HEAD", subclassID = 4, raw = { ITEM_MOD_STRENGTH_SHORT = 15 } })
	WORLD.worn[1] = worn
	WORLD.bags = { better }
	fire("PLAYER_EQUIPMENT_CHANGED"); fire("BAG_UPDATE_DELAYED"); fire("BAG_UPDATE_DELAYED")
	T.eq(#timers, 1, "a burst of events is one refresh")
	local heard = 0
	NS.On("OwnedChanged", function() heard = heard + 1 end)
	tick()
	T.eq(heard, 1, "the others are told once")
	local v = NS.Verdict(better, true)
	T.eq(v.usable, true, "usable"); T.near(v.pct, 50, "the carried helm is 50% better than the worn one")
	T.near(NS.Verdict(better).gain, 0, "seen as something for sale, it is already owned")
	local none, why = NS.Verdict(T.item({ equipLoc = "" }))
	T.eq(none, nil, "not gear"); T.eq(why, "notgear", "says why")
	none, why = NS.Verdict(T.item({ equipLoc = "INVTYPE_HEAD", loaded = false }))
	T.eq(none, nil, "no verdict yet"); T.eq(why, "pending", "not loaded yet")
	settings.enabled = false
	dui("SettingChanged", "GloweyGear", "enabled")
	none, why = NS.Verdict(better, true)
	T.eq(none, nil, "switched off"); T.eq(why, "off", "says so")
	settings.enabled = nil
	dui("SettingChanged", "OtherAddon", "enabled")
	T.eq(NS.Get("enabled"), false, "another addon's setting does not clear our cache")
	dui("SettingChanged", "GloweyGear", "enabled")
	T.eq(NS.Get("enabled"), true, "ours does; unset reads the default")
	T.eq(NS.Get("minGain"), 3, "a default"); settings.maxPrice = 20
	dui("SettingChanged", "GloweyGear", "maxPrice")
	local opts = NS.RankOptions(60)
	T.eq(opts.maxPrice, 200000, "max price in copper"); T.eq(opts.minPct, 3, "smallest gain"); T.eq(opts.mode, "perGold", "mode")
	-- a level-up changes who is scored for
	local changed = 0
	NS.On("WhoChanged", function() changed = changed + 1 end)
	WORLD.level = 61
	fire("PLAYER_LEVEL_UP"); tick()
	T.eq(changed, 1, "WhoChanged fired"); T.eq(NS.Who().level, 61, "the new level")
end)

T.case("in a fight nothing is rebuilt; it happens when the fight ends", function()
	local heard = 0
	NS.On("OwnedChanged", function() heard = heard + 1 end)
	WORLD.combat = true
	fire("BAG_UPDATE_DELAYED"); tick()
	T.eq(heard, 0, "held back in the fight")
	WORLD.combat = false
	fire("PLAYER_REGEN_ENABLED")
	T.eq(heard, 1, "done when it ends")
	fire("PLAYER_REGEN_ENABLED")
	T.eq(heard, 1, "and only once")
end)

T.case("/gear", function()
	T.check(commands.gear ~= nil and type(commands.gear.help) == "string", "registered with a help line")
	DEFAULT_CHAT_FRAME.lines = {}
	commands.gear.fn("")
	T.check(DEFAULT_CHAT_FRAME.lines[1]:find("Scoring gear for Arms, level 61.", 1, true), "says who it scores for: " .. tostring(DEFAULT_CHAT_FRAME.lines[1]))
	local opened = 0
	NS.OpenWindow = function() opened = opened + 1 end
	commands.gear.fn("")
	T.eq(opened, 1, "once the window exists, the bare word opens it")
	local printed = {}
	print = function(...) printed[#printed + 1] = table.concat({ ... }, " ") end
	commands.gear.fn(" debug ")
	T.check(printed[1] and printed[1]:find("WARRIOR.ARMS", 1, true), "debug names the spec and its source")
	T.check(printed[1]:find("wowsims", 1, true), "and where its weights come from")
	NS.OpenWindow = nil
end)

T.case("without Daylight UI the file stands down", function()
	local saved = DaylightUI
	DaylightUI = nil
	local ns = { L = NS.L, Spec = NS.Spec, Compare = NS.Compare, Stats = NS.Stats, Game = NS.Game }
	run("Core.lua", ns)
	T.eq(ns.off, true, "marked off"); T.eq(ns.ok, nil, "and nothing registered")
	DaylightUI = { API = { major = 2 } }
	ns = { L = NS.L }
	run("Core.lua", ns)
	T.eq(ns.off, true, "another API major: off too")
	DaylightUI = saved
end)

T.case("talents not readable at login, readable later (the audit's M5)", function()
	for _ = 1, 8 do tick() end
	T.reset()
	GloweyGearDB.chars = {}
	WORLD.class, WORLD.level, WORLD.trees = "WARRIOR", 60, nil
	local listening = {}
	for _, f in ipairs(frames) do
		for event in pairs(f.events) do listening[event] = true end
	end
	for _, event in ipairs({ "TRAIT_CONFIG_LIST_UPDATED", "TRAIT_CONFIG_UPDATED", "PLAYER_TALENT_UPDATE",
		"ACTIVE_TALENT_GROUP_CHANGED", "PLAYER_LEVEL_UP", "PLAYER_ENTERING_WORLD" }) do
		T.check(listening[event], "listens to " .. event)
	end
	dui("Login")
	local who = NS.Who()
	T.eq(who.spec, "LEVELING", "a first session with no trees yet: the class default"); T.eq(who.how, "default", "found without talents")
	-- the trees arrive with the game's list of builds
	WORLD.trees = { { name = "Arms", spent = 5 }, { name = "Fury", spent = 31 }, { name = "Protection", spent = 15 } }
	local changed = 0
	NS.On("WhoChanged", function() changed = changed + 1 end)
	fire("TRAIT_CONFIG_LIST_UPDATED"); fire("TRAIT_CONFIG_UPDATED"); fire("PLAYER_ENTERING_WORLD")
	T.eq(NS.Who().spec, "LEVELING", "nothing is read inside the event itself")
	tick()
	who = NS.Who()
	T.eq(who.spec, "FURY", "the real spec once the trees are readable"); T.eq(who.how, "talents", "from talents")
	T.eq(changed, 1, "a burst of talent events is one look"); T.eq(NS.SpecValues.FURY, "Fury", "and the picker has the game's names")
	T.eq(GloweyGearDB.chars[WORLD.guid].last, "FURY", "remembered for the next login")
	for _ = 1, 8 do tick() end
	T.eq(changed, 1, "the looks on a timer find nothing left to do")

	-- no event at all: a look on a timer finds the trees
	T.reset()
	GloweyGearDB.chars = {}
	WORLD.class, WORLD.level, WORLD.trees = "WARRIOR", 60, nil
	dui("Login")
	T.eq(NS.Who().spec, "LEVELING", "default again")
	tick()
	T.eq(NS.Who().spec, "LEVELING", "still not readable at the first look")
	WORLD.trees = { { name = "Arms", spent = 31 }, { name = "Fury", spent = 5 }, { name = "Protection", spent = 15 } }
	tick()
	T.eq(NS.Who().spec, "ARMS", "found at the next look, with no event")
	for _ = 1, 8 do tick() end
	T.eq(#timers, 0, "and the looks stop")

	-- in a fight nothing is read; it is when the fight ends
	T.reset()
	GloweyGearDB.chars = {}
	WORLD.class, WORLD.level, WORLD.trees = "WARRIOR", 60, nil
	dui("Login")
	T.eq(NS.Who().spec, "LEVELING", "default before the trees")
	WORLD.trees = { { name = "Arms", spent = 0 }, { name = "Fury", spent = 0 }, { name = "Protection", spent = 40 } }
	WORLD.combat = true
	local before = WORLD.calls.Trees or 0
	fire("TRAIT_CONFIG_LIST_UPDATED"); tick()
	T.eq(NS.Who().spec, "LEVELING", "not read in a fight")
	T.eq((WORLD.calls.Trees or 0), before, "the trait calls are not even made")
	WORLD.combat = false
	fire("PLAYER_REGEN_ENABLED")
	T.eq(NS.Who().spec, "PROTECTION", "read when the fight ends")
	for _ = 1, 8 do tick() end
end)

T.case("characters are kept by GUID, whatever the realm is called", function()
	for _ = 1, 8 do tick() end
	T.reset()
	WORLD.class, WORLD.level = "WARRIOR", 60
	WORLD.trees = { { name = "Arms", spent = 31 }, { name = "Fury", spent = 5 }, { name = "Protection", spent = 15 } }
	-- the game gives no realm name (as on this client since 2026-11-20)
	GloweyGearDB.chars = {}
	WORLD.realm = ""
	dui("Login")
	NS.Who()
	local mine = GloweyGearDB.chars[WORLD.guid]
	T.check(mine ~= nil, "a record under the GUID with an empty realm name")
	T.eq(GloweyGearDB.chars["-Tester"], nil, "and none under a key made of an empty realm")
	mine.spec = "FURY"
	-- another character of the same name on another realm: another GUID, another record
	WORLD.guid = "Player-5555-0BADF00D"
	T.eq(NS.Char().spec, "auto", "the same name on another realm is another character")
	T.check(NS.Char() ~= mine, "with a record of its own")
	WORLD.guid = "Player-4407-00ABCDEF"
	T.eq(NS.Char().spec, "FURY", "and the first keeps its choice")

	-- records saved by an older build under "Realm-Name" are taken over, once, and left in place
	GloweyGearDB.chars = { ["Test Realm-Tester"] = { spec = "PROTECTION", last = "ARMS" }, ["Other Realm-Somebody"] = { spec = "FURY" } }
	WORLD.realm = "Test Realm"
	local c = NS.Char()
	T.eq(c.spec, "PROTECTION", "the record under today's realm name is this character's"); T.eq(c.last, "ARMS", "with what Auto last found")
	T.check(GloweyGearDB.chars["Test Realm-Tester"] ~= nil, "the old record is left where it was")
	-- with no realm name: the only old record that ends in the character's name
	GloweyGearDB.chars = { ["Test Realm-Tester"] = { spec = "FURY" }, ["Test Realm-Somebody"] = { spec = "ARMS" } }
	WORLD.realm = ""
	T.eq(NS.Char().spec, "FURY", "one old record with this name: taken")
	-- two to choose from: none is taken
	GloweyGearDB.chars = { ["Realm A-Tester"] = { spec = "FURY" }, ["Realm B-Tester"] = { spec = "ARMS" } }
	T.eq(NS.Char().spec, "auto", "two old records with this name: Auto, not a guess")
	-- the game does not know the character yet
	WORLD.guid = nil
	T.eq(NS.Char(), nil, "no GUID yet: no record, and nothing written")
	WORLD.guid = "Player-4407-00ABCDEF"
	-- an older saved table is brought to today's version
	GloweyGearDB = { v = 1, chars = { ["Test Realm-Tester"] = { spec = "ARMS" } } }
	WORLD.realm = "Test Realm"
	T.eq(NS.DB().v, 2, "version 1 becomes 2"); T.eq(NS.Char().spec, "ARMS", "and the character's choice comes along")
	for _ = 1, 8 do tick() end
end)

T.case("a setting read before Daylight UI has it is not kept as the default (the audit's L16)", function()
	settings.minGain = nil
	dui("SettingChanged", "GloweyGear", "minGain")
	T.eq(NS.Get("minGain"), 3, "no value yet: the default")
	settings.minGain = 7   -- (the module is switched on later; no SettingChanged comes for that)
	T.eq(NS.Get("minGain"), 7, "the real value is found at the next read")
	settings.minGain = nil
	dui("SettingChanged", "GloweyGear", "minGain")
end)

T.case("item data arriving does not rebuild what is owned unless some of it was waiting (the audit's L5)", function()
	for _ = 1, 8 do tick() end
	T.reset()
	WORLD.class, WORLD.level = "WARRIOR", 60
	WORLD.trees = { { name = "Arms", spent = 31 }, { name = "Fury", spent = 5 }, { name = "Protection", spent = 15 } }
	dui("Login")
	WORLD.worn[1] = T.item({ equipLoc = "INVTYPE_HEAD", subclassID = 4, raw = { ITEM_MOD_STRENGTH_SHORT = 10 } })
	fire("PLAYER_EQUIPMENT_CHANGED"); tick()
	local ctx = NS.Context()
	T.eq(ctx.pending, 0, "everything owned is loaded")
	local told, arrived = 0, 0
	NS.On("OwnedChanged", function() told = told + 1 end)
	NS.On("ItemsArrived", function() arrived = arrived + 1 end)
	local walks = WORLD.calls.BagLinks
	for _ = 1, 5000 do fire("GET_ITEM_INFO_RECEIVED", 123, true) end
	T.eq(#timers, 1, "five thousand arrivals are one timer"); tick()
	T.eq(told, 0, "nobody is told that what is owned changed: it did not")
	T.eq(arrived, 1, "one 'items arrived' for the whole flood")
	T.check(NS.Context() == ctx, "what is owned is not read again"); T.eq(WORLD.calls.BagLinks, walks, "the bags are not walked")
	T.eq(NS.Perf.Sum("itemEvents") >= 5000, true, "and the flood is counted for /gear debug")
	WORLD.combat = true
	fire("GET_ITEM_INFO_RECEIVED", 123, true); tick()
	T.eq(arrived, 1, "in a fight not even that")
	WORLD.combat = false
	-- with an owned item still waiting for its data, it is
	local late = T.item({ equipLoc = "INVTYPE_LEGS", loaded = false, raw = { ITEM_MOD_STRENGTH_SHORT = 8 } })
	WORLD.worn[7] = late
	fire("PLAYER_EQUIPMENT_CHANGED"); tick()
	ctx = NS.Context()
	T.eq(ctx.pending, 1, "one owned item is waiting")
	T.load(late)
	fire("GET_ITEM_INFO_RECEIVED", 124, true); tick()
	T.check(NS.Context() ~= ctx, "its arrival reads what is owned again"); T.eq(NS.Context().pending, 0, "and nothing waits now")
end)

T.case("the pickers keep a chosen order, and dim what Daylight UI has switched off", function()
	local seen = 0
	for _, group in ipairs(registered.module.def.options.pages[1].groups) do
		for _, item in ipairs(group.items) do
			if item.type == "dropdown" then
				seen = seen + 1
				T.check(type(item.order) == "table", tostring(item.label) .. " has an order")
				local listed = {}
				for _, key in ipairs(item.order or {}) do
					listed[key] = true
					T.check(item.values[key] ~= nil, tostring(item.label) .. ": " .. tostring(key) .. " in the order is a choice")
				end
				-- (The spec picker's words pile up over the classes this test file logs in as; in the
				-- game the class never changes. Its order must cover the class's own specs.)
				if item.get then
					for _, key in ipairs(NS.Spec.List(WORLD.class)) do T.check(listed[key], "Spec: " .. key .. " is in the order") end
				else
					for key in pairs(item.values) do T.check(listed[key], tostring(item.label) .. ": the choice " .. tostring(key) .. " is in the order") end
				end
				T.check(item.order[1] ~= nil, "not empty")
				if item.get then T.eq(item.order[1], "auto", "Auto comes first in the spec picker") end
			end
		end
	end
	T.eq(seen, 3, "three pickers")
	local rows = {}
	for _, group in ipairs(registered.module.def.options.pages[1].groups) do
		for _, item in ipairs(group.items) do
			if item.key then rows[item.key] = item end
		end
	end
	local function get(key) return NS.DEFAULTS[key] end
	T.eq(rows.tooltips.disabled(get), false, "with no way to ask, nothing is dimmed")
	local off = {}
	DaylightUI.API.IsModuleEnabled = function(name) return not off[name] end
	T.eq(rows.tooltips.disabled(get), false, "Daylight UI's tooltips on: the switch works")
	off.Tooltip = true
	T.eq(rows.tooltips.disabled(get), true, "Daylight UI's tooltips off: dimmed"); T.eq(rows.bagMarks.disabled(get), false, "the bag switch is another matter")
	off.Bags = true
	T.eq(rows.bagMarks.disabled(get), true, "Daylight UI's bags off: dimmed"); T.eq(rows.bagCorner.disabled(get), true, "and the corner with it")
	DaylightUI.API.IsModuleEnabled = nil
end)

T.case("/gear debug names what the first run needs", function()
	T.reset()
	GloweyGearDB.chars = {}
	WORLD.class, WORLD.level, WORLD.realm = "WARRIOR", 60, ""
	WORLD.trees = { { name = "Arms", spent = 31 }, { name = "Fury", spent = 5 }, { name = "Protection", spent = 15 } }
	dui("Login")
	local link = T.item({ name = "Odd Trinket", equipLoc = "INVTYPE_TRINKET", effects = { equip = 1, use = 1 },
		raw = { ITEM_MOD_STRENGTH_SHORT = 4, ITEM_MOD_BRAND_NEW_SHORT = 2 } })
	NS.Verdict(link)
	local printed = {}
	print = function(...) printed[#printed + 1] = table.concat({ ... }, " ") end
	commands.gear.fn("debug")
	local all = table.concat(printed, "\n")
	T.check(all:find("WARRIOR.ARMS (talents)", 1, true), "who, and how the spec was found:\n" .. all)
	T.check(all:find("realm name not given by the game", 1, true), "that the game gives no realm name")
	T.check(all:find("realm number 4407", 1, true), "the realm number from the GUID")
	T.check(all:find("ITEM_MOD_BRAND_NEW_SHORT x1", 1, true), "a stat name in neither list")
	T.check(all:find("last item: Odd Trinket", 1, true), "the last item looked at")
	T.check(all:find("1 equip, 1 use, 0 proc effect lines", 1, true), "its tooltip's effect lines")
	T.check(all:find("effects not counted: 2", 1, true), "and how many the score leaves out")
	WORLD.trees = nil
	printed = {}
	commands.gear.fn("debug")
	T.check(table.concat(printed, "\n"):find("talent trees: not readable right now", 1, true), "says when the talents cannot be read")
end)

T.case("what our own code costs is counted, and /gear debug says it", function()
	local P = NS.Perf
	WORLD.clock = 5000000
	P.Time("scoring", 1.5); P.Time("scoring", 2)      -- the same frame: they add up
	T.near(P.Max("scoring"), 3.5, "a frame's total")
	WORLD.clock = WORLD.clock + 20
	P.Time("scoring", 1)
	T.near(P.Max("scoring"), 3.5, "the largest frame stands")
	P.Count("paint"); P.Count("paint", 2)
	T.eq(P.Sum("paint") >= 3, true, "things that happen are counted")
	WORLD.clock = WORLD.clock + 30000
	T.near(P.Max("scoring"), 3.5, "still within the minute")
	WORLD.clock = WORLD.clock + 61000
	T.near(P.Max("scoring"), 0, "a minute later it is gone"); T.eq(P.Sum("paint"), 0, "and so are the counts")
	local printed = {}
	print = function(...) printed[#printed + 1] = table.concat({ ... }, " ") end
	P.Time("market", 2.4)
	for _ = 1, 120 do P.Count("itemEvents") end
	commands.gear.fn("debug")
	local all = table.concat(printed, "\n")
	T.check(all:find("longest frame of our own work in the last minute, by part (ms): market 2.4, scoring 0.0", 1, true), "the longest frame by part:\n" .. all)
	T.check(all:find("refreshes", 1, true) and all:find("reads of what is owned", 1, true) and all:find("paints", 1, true), "how often things happened")
	T.check(all:find("120 item-data (2 a second)", 1, true), "item-data events a second")
end)

return T.done()
