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
run("MyWeights.lua", NS)
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
	T.eq(#pages, 2, "two pages"); T.eq(pages[1].id, "gear", "its id"); T.eq(pages[2].id, "weights", "and Stat Weights")
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
	-- a bag burst that moves no gear: what is owned is not built again; a weapon skill learned is
	fire("BAG_UPDATE_DELAYED"); tick()
	T.check(NS.Context() == ctx, "no gear moved: the same context")
	WORLD.bags = { T.item({ equipLoc = "INVTYPE_FEET", raw = { ITEM_MOD_STRENGTH_SHORT = 2 } }) }
	fire("BAG_UPDATE_DELAYED"); tick()
	T.check(NS.Context() ~= ctx, "a piece of gear came into the bags: built again")
	ctx = NS.Context()
	fire("SKILL_LINES_CHANGED"); tick()
	T.check(NS.Context() ~= ctx, "a weapon skill learned: built again")
	WORLD.bags = {}
	fire("BAG_UPDATE_DELAYED"); tick()
	ctx = NS.Context()
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
	fire("GET_ITEM_INFO_RECEIVED", 123, true); tick()
	T.check(NS.Context() == ctx, "something else arrived: the waiting item is looked at, nothing is built")
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

-- ---- the player's own stat weights (MyWeights.lua) ------------------------------------------
local function weightRows()
	local page = registered.module.def.options.pages[2]
	local rows, byLabel = {}, {}
	for _, group in ipairs(page.groups) do
		for _, item in ipairs(group.items) do
			rows[#rows + 1] = item
			local label = type(item.label) == "string" and item.label or "(text)"
			byLabel[label] = item
		end
	end
	return page, rows, byLabel
end

-- The rules Daylight UI's registry applies to a page's rows (Options/Registry.lua:56-110), and that
-- Host.lua draws them; returns how many sliders and custom rows the page has.
local function checkRows(rows)
	local known = { toggle = true, slider = true, dropdown = true, button = true, text = true, custom = true }
	local sliders, customs = 0, 0
	for _, item in ipairs(rows) do
		local at = tostring(item.label)
		T.check(known[item.type], at .. ": a known row type")
		if item.type == "text" then
			T.eq(type(item.label), "function", "the status line is worked out when drawn")
		elseif item.type == "custom" then
			customs = customs + 1
			T.eq(item.label, "", "the grid: an empty label, as Daylight UI's own custom rows have")
			T.check(type(item.build) == "function" and type(item.update) == "function" and type(item.height) == "function",
				"the grid: build, update and height")
		else
			T.check(type(item.label) == "string" and item.label ~= "", at .. ": a label")
		end
		T.check(item.desc == nil or type(item.desc) == "string", at .. ": desc is text")
		if item.type == "slider" then
			sliders = sliders + 1
			T.check(type(item.get) == "function" and type(item.set) == "function" and type(item.default) == "function",
				at .. ": get, set and default (Daylight UI's reset arrow)")
			T.check(type(item.min) == "number" and type(item.max) == "number" and item.min < item.max and item.step > 0, at .. ": a range")
			T.eq(item.unit, nil, at .. ": no unit (Daylight UI takes only %, px and x)")
		elseif item.type == "toggle" or item.type == "dropdown" then
			T.check(type(item.get) == "function" and type(item.set) == "function", at .. ": get and set together")
		elseif item.type == "button" then
			T.eq(item.confirm, true, at .. ": asks first"); T.check(type(item.func) == "function", at .. ": does something")
		end
	end
	return sliders, customs
end

T.case("the Stat Weights page has only rows Daylight UI and Host.lua draw", function()
	local page, rows = weightRows()
	T.check(type(page.desc) == "string" and not page.desc:find("\n") and #page.desc <= 70, "a one-line description")
	local sliders, customs = checkRows(rows)
	T.eq(customs, 0, "no grid on a host that does not say it takes one (Host.CustomRows)")
	T.eq(sliders, #NS.MyWeights.LIST, "one slider for every stat the editor knows")
	for _, s in ipairs(NS.MyWeights.LIST) do
		T.check(NS.Stats.KEYS[s[1]], s[1] .. " is a stat the scorer reads")
		T.check(not s[1]:find("_SPEED$"), "speeds are left out: nothing reads them yet")
	end
end)

T.case("own weights: set, scored, shown, reverted", function()
	T.reset()
	GloweyGearDB = nil
	WORLD.class, WORLD.level = "WARRIOR", 60
	WORLD.trees = { { name = "Arms", spent = 31 }, { name = "Fury", spent = 20 }, { name = "Protection", spent = 0 } }
	dui("Login")
	for _ = 1, 8 do tick() end
	local _, rows, by = weightRows()
	local status
	for _, item in ipairs(rows) do if item.type == "text" then status = item end end
	local str, hit, armor = by["Strength"], by["Hit, per 1%"], by["Armor, per 100"]
	T.check(str and hit and armor, "rows for Strength, Hit (per 1%) and Armor (per 100)")
	local rec = NS.Spec.Weights("WARRIOR", "ARMS", 60)
	local who = NS.Who()
	T.eq(who.spec, "ARMS", "scoring Arms"); T.eq(who.custom, 0, "with no weights of the player's own")
	T.eq(who.weights, rec, "the recommendation's own table")
	T.near(hit.get(), rec.HIT, "a slider shows the recommendation"); T.near(hit.default(), rec.HIT, "which is its default")
	T.eq(str.hidden(), false, "a stat the spec weights is listed")
	T.eq(by["Fire Resistance"].hidden(), true, "one it leaves at nothing is not")
	by["Show Every Stat"].set(true)
	T.eq(by["Fire Resistance"].hidden(), false, "Show Every Stat lists it")
	by["Show Every Stat"].set(false)
	T.check(status.label():find("Every weight for Arms is Glowey's recommendation.", 1, true), "the status line: " .. status.label())
	T.check(by["Revert This Spec"].disabled(), "nothing to revert yet"); T.check(by["Revert Every Spec"].disabled(), "anywhere")

	-- set two weights
	hit.set(12)
	T.eq(GloweyGearDB.weights.WARRIOR.ARMS.HIT, 12, "saved under class and spec, only the stat set")
	T.eq(GloweyGearDB.weights.WARRIOR.ARMS.STR, nil, "the rest are not written")
	who = NS.Who()
	T.eq(who.custom, 1, "scored at once with one of the player's own"); T.eq(who.weights.HIT, 12, "the player's number")
	T.eq(who.weights.STR, rec.STR, "the others stay the recommendation's")
	T.check(who.weights ~= rec, "a table of its own"); T.check(rec.HIT ~= 12, "the shipped data is not changed")
	T.eq(NS.Who().weights, who.weights, "the same table until something changes")
	armor.set(1)   -- shown per 100 armor
	T.near(GloweyGearDB.weights.WARRIOR.ARMS.ARMOR, 0.01, "Armor is saved per point")
	T.near(armor.get(), 1, "and shown per 100")
	T.check(status.label():find("Your own weights for Arms: Hit, Armor.", 1, true), "the status line names them: " .. status.label())
	local fired = 0
	NS.On("WhoChanged", function() fired = fired + 1 end)
	tick()
	T.check(fired >= 1, "the others hear WhoChanged after the change, to score again")

	-- level: the player's number stands, the rest slide
	WORLD.level = 30
	NS.WeightsChanged(); tick()
	who = NS.Who()
	T.eq(who.weights.HIT, 12, "a weight set by hand is used at every level")
	T.near(who.weights.STA, NS.Spec.Weights("WARRIOR", "ARMS", 30).STA, "the others follow the recommendation for the level")
	WORLD.level = 60
	NS.WeightsChanged(); tick()

	-- back on the recommendation by value: no longer the player's own
	hit.set(rec.HIT)
	T.eq(GloweyGearDB.weights.WARRIOR.ARMS.HIT, nil, "set back to the recommendation, it is dropped")
	T.check(not by["Revert This Spec"].disabled(), "Armor still to revert")
	-- 0 is a real choice
	str.set(0)
	T.eq(GloweyGearDB.weights.WARRIOR.ARMS.STR, 0, "a 0 is kept"); T.eq(NS.Who().weights.STR, 0, "and scored as worth nothing")

	str.set(rec.STR)
	T.eq(GloweyGearDB.weights.WARRIOR.ARMS.STR, nil, "back on the recommendation")
	T.eq(by["Revert One Stat"], nil, "no Revert One Stat dropdown: each box has its own revert arrow")

	-- another spec
	local edit = by["Spec to Edit"]
	T.eq(edit.get(), "ARMS", "the editor opens on the spec being scored")
	T.check(edit.values.FURY ~= nil and edit.values.auto == nil, "it lists the class's specs, not Auto")
	edit.set("FURY")
	T.near(hit.get(), NS.Spec.Weights("WARRIOR", "FURY", 60).HIT, "the sliders show Fury's")
	hit.set(3)
	T.eq(GloweyGearDB.weights.WARRIOR.FURY.HIT, 3, "Fury's own")
	T.eq(NS.Who().spec, "ARMS", "editing Fury does not change the spec scored")
	T.near(NS.Who().weights.HIT, rec.HIT, "nor Arms' weights")

	-- revert this spec (Fury), then every spec
	by["Revert This Spec"].func()
	T.eq(GloweyGearDB.weights.WARRIOR.FURY, nil, "Fury is the recommendation again")
	T.check(GloweyGearDB.weights.WARRIOR.ARMS ~= nil, "Arms keeps its own")
	edit.set("ARMS")
	T.check(not by["Revert Every Spec"].disabled(), "something to revert")
	by["Revert Every Spec"].func()
	T.eq(next(GloweyGearDB.weights), nil, "every spec is the recommendation again")
	who = NS.Who()
	T.eq(who.custom, 0, "scored with the recommendation"); T.eq(who.weights, NS.Spec.Weights("WARRIOR", "ARMS", 60), "its own table")
	T.check(by["Revert Every Spec"].disabled(), "nothing left to revert")

	-- a broken saved value is never scored
	GloweyGearDB.weights = { WARRIOR = { ARMS = { HIT = "lots", STR = -2, NOT_A_STAT = 4, CRIT = 9 } } }
	NS.WeightsChanged()
	who = NS.Who()
	T.eq(who.custom, 1, "only the good one counts"); T.eq(who.weights.CRIT, 9, "it")
	T.eq(who.weights.HIT, NS.Spec.Weights("WARRIOR", "ARMS", 60).HIT, "a word is not a weight")
	T.eq(who.weights.NOT_A_STAT, nil, "an unknown key is left out")
	GloweyGearDB.weights = {}
	NS.WeightsChanged(); tick()
end)

T.case("Stat Weights as a grid of boxes: what a box takes, saves and shows", function()
	local MW = NS.MyWeights
	-- typed numbers: 0 or more, up to four decimals, a comma as the decimal mark
	local good = { ["12"] = 12, ["0.55"] = 0.55, [".5"] = 0.5, ["5."] = 5, ["1,25"] = 1.25, [" 3 "] = 3,
		["0"] = 0, ["1.2345"] = 1.2345, ["0000.1"] = 0.1 }
	for text, want in pairs(good) do T.near(MW.Parse(text), want, "takes '" .. text .. "'") end
	for _, text in ipairs({ "", " ", ".", "-1", "+2", "1.23456", "abc", "1.2.3", "1e3", "0x10", "1,2,3", "inf", "nan", "12a" }) do
		T.eq(MW.Parse(text), nil, "refuses '" .. text .. "'")
	end
	T.eq(MW.Parse(nil), nil, "refuses nothing")
	T.eq(MW.Format(0.55), "0.55", "shows 0.55"); T.eq(MW.Format(1), "1", "1 without decimals")
	T.eq(MW.Format(12.5), "12.5", "no trailing zeros"); T.eq(MW.Format(100), "100", "100 keeps its zeros")
	T.eq(MW.Format(0), "0", "0"); T.eq(MW.Format(0.12344), "0.1234", "at most four decimals")

	-- columns: as many as fit, two-line labels at most, the shortest grid
	T.eq(MW.Columns(900, 20, function() return 1 end), 3, "a wide page: three columns")
	T.eq(MW.Columns(560, 20, function() return 1 end), 2, "Host.lua's window width: two")
	T.eq(MW.Columns(200, 20, function() return 1 end), 1, "a narrow one: one")
	T.eq(MW.Columns(520, 20, function(i, w) return (i % 5 == 0 and w < 200) and 2 or 1 end), 2,
		"a few labels on two lines still beat one long column")
	T.eq(MW.Columns(900, 20, function(_, w) return w < 400 and 3 or 1 end), 1,
		"never a label on three lines when fewer columns keep it shorter")

	-- a page on a host that takes custom rows (Host.CustomRows): the grid, the sliders behind it
	local oldHost, oldApi = NS.Host, NS.API
	NS.Host = { CustomRows = function() return true end }
	NS.API = setmetatable({ Input = function() end }, { __index = oldApi })
	local page = MW.Page()
	local rows, grid, sliders = {}, nil, {}
	for _, group in ipairs(page.groups) do
		for _, item in ipairs(group.items) do
			rows[#rows + 1] = item
			if item.type == "custom" then grid = item end
			if item.type == "slider" then sliders[#sliders + 1] = item end
		end
	end
	local nSliders, customs = checkRows(rows)
	T.eq(customs, 1, "one grid row"); T.eq(nSliders, #MW.LIST, "the sliders stay, as a fallback")
	T.eq(grid.noSearch, nil, "custom rows are never searched anyway (Registry.lua:443)")
	T.reset()
	GloweyGearDB = nil
	WORLD.class, WORLD.level = "WARRIOR", 60
	WORLD.trees = { { name = "Arms", spent = 31 }, { name = "Fury", spent = 20 }, { name = "Protection", spent = 0 } }
	dui("Login")
	for _ = 1, 8 do tick() end
	T.eq(grid.hidden(), false, "the grid shows")
	for _, s in ipairs(sliders) do T.eq(s.hidden(), true, s.label .. ": its slider is put away") end
	T.check(not page.groups[1].items[4].label:find("Revert One"), "no Revert One Stat row")
	-- a host without custom rows (Daylight UI before 2.2.5): no grid, the sliders
	NS.Host = { CustomRows = function() return false end }
	local plain = MW.Page()
	for _, item in ipairs(plain.groups[1].items) do T.check(item.type ~= "custom", "no grid without custom rows") end
	T.eq(sliders[1].hidden(), false, "the sliders are back")
	NS.Host, NS.API = oldHost, oldApi
	MW.Page()   -- (as Core registered it)

	-- what a box saves
	local rec = NS.Spec.Weights("WARRIOR", "ARMS", 60)
	local shown, mine = MW.Display("HIT")
	T.eq(shown, MW.Format(rec.HIT), "a box shows the recommendation"); T.eq(mine, false, "plain, not the player's own")
	T.eq(MW.Commit("HIT", "12"), true, "12 is taken")
	T.eq(GloweyGearDB.weights.WARRIOR.ARMS.HIT, 12, "and saved for the edited spec")
	shown, mine = MW.Display("HIT")
	T.eq(shown, "12", "the box shows it"); T.eq(mine, true, "as the player's own (the accent, the revert arrow)")
	T.eq(NS.Who().weights.HIT, 12, "and it is scored")
	for _, bad in ipairs({ "abc", "-3", "1.23456", "" }) do
		T.eq(MW.Commit("HIT", bad), false, "'" .. bad .. "' is refused")
		T.eq(GloweyGearDB.weights.WARRIOR.ARMS.HIT, 12, "and the weight stays")
	end
	T.eq(MW.Commit("HIT", "12.0"), true, "the same number again"); T.eq(GloweyGearDB.weights.WARRIOR.ARMS.HIT, 12, "changes nothing")
	T.eq(MW.Commit("HIT", MW.Format(rec.HIT)), true, "the recommendation's own number")
	T.eq(GloweyGearDB.weights.WARRIOR, nil, "puts the stat back on the recommendation")
	T.eq(MW.Commit("ARMOR", "0.1234"), true, "four decimals, per 100 armor")
	T.near(GloweyGearDB.weights.WARRIOR.ARMS.ARMOR, 0.001234, "saved per point with nothing lost")
	T.eq((MW.Display("ARMOR")), "0.1234", "and shown per 100 as typed")
	T.eq(MW.Commit("STR", "0"), true, "0 is a weight"); T.eq(GloweyGearDB.weights.WARRIOR.ARMS.STR, 0, "kept as 0")
	T.eq(MW.Commit("STR", "1,5"), true, "a comma works as the decimal mark"); T.near(GloweyGearDB.weights.WARRIOR.ARMS.STR, 1.5, "1.5")
	T.eq(MW.Commit("NOT_A_STAT", "1"), false, "an unknown stat is refused")
	MW.RevertAll()
	tick()
end)

T.case("/gear says when the player's own weights are in use", function()
	NS.MyWeights.Set("WARRIOR", "ARMS", "CRIT", 20)
	tick()
	DEFAULT_CHAT_FRAME.lines = {}
	local open = NS.OpenWindow
	NS.OpenWindow = nil
	commands.gear.fn("")
	T.check(DEFAULT_CHAT_FRAME.lines[1]:find("with your own stat weights", 1, true), "says so: " .. tostring(DEFAULT_CHAT_FRAME.lines[1]))
	local printed = {}
	print = function(...) printed[#printed + 1] = table.concat({ ... }, " ") end
	commands.gear.fn("debug")
	T.check(table.concat(printed, "\n"):find("your own weights: CRIT 20", 1, true), "debug lists them")
	NS.MyWeights.RevertAll()
	tick()
	NS.OpenWindow = open
end)

return T.done()
