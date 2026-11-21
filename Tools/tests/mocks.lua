-- The test world for Glowey's Gear's engine (Tools/tests/run.py loads this, then Stats.lua,
-- Spec.lua, Score.lua, Compare.lua and Rank.lua unchanged, then one test file).
--
-- NS is the addon's namespace. NS.Game here stands in for Game.lua: the same functions, answered
-- from the WORLD table a test fills in. What the mock enforces, so a pass means something:
--   * AN ITEM IS ONLY KNOWN BY ITS FULL LINK. Stats come from WORLD.items["<id>:<suffix>"], so a
--     test that drops the suffix from a link gets the base item's stats, as the game would give.
--   * ITEMS LOAD LATE. An item made with loaded = false answers nil to ItemInfo and ItemStats
--     until T.load(link); ItemInstant answers at once, as the game's instant call does.
--   * EVERY GAME CALL IS COUNTED (WORLD.calls), so a test can prove a cache is used.
--   * THE ENGINE MAY NOT TOUCH GLOBALS: any global it sets or reads that is not plain Lua 5.1
--     raises an error (strict mode at the end of this file).
--
-- luacheck: globals NS WORLD T T_ident ADDON_ROOT
-- luacheck: ignore 111 112 113

NS = {}
WORLD = {
	items = {},          -- "<id>:<roll>" -> { name, quality, minLevel, equipLoc, classID, subclassID, sellPrice, raw, unique, loaded }
	class = "WARRIOR",
	level = 60,
	trees = nil,         -- { { name, spent }, ... } or nil
	skills = nil,        -- { [skill line] = true }; nil = the game cannot list skills
	spells = {},         -- [spell ID] = true
	worn = {},           -- [slot] = link
	bags = {},           -- { link, ... }
	speed = {},          -- "<id>:<roll>" -> seconds
	effects = {},        -- "<id>:<roll>" -> { equip, use, proc } tooltip effect lines; absent = the game cannot say
	calls = {},          -- function name -> times called
	requested = {},      -- item IDs the plugin asked the game to load, in order
	noCacheCall = nil,   -- true: the game cannot say whether an item is cached
	combat = false,      -- InCombat()
	clock = 0,           -- Clock(), in milliseconds
	guid = "Player-4407-00ABCDEF", name = "Tester", realm = "Test Realm", realmID = nil, faction = "Alliance",
}

local function called(name) WORLD.calls[name] = (WORLD.calls[name] or 0) + 1 end

-- "<id>:<roll>" of a link or an item string, the way the game tells two items apart: the item
-- ID, and its roll, which is the bonus IDs (fields 13 on, as this client writes them) or, for
-- an old-style link, the suffix in field 7 (written "s<suffix>"). Enchant, link level, spec,
-- context and modifiers do not make another item.
local function ident(link)
	if type(link) == "number" then return link .. ":" end
	local body = tostring(link):match("item:([%-%d:]+)")
	if not body then return nil end
	local f, n = {}, 0
	for field in (body .. ":"):gmatch("([^:]*):") do
		n = n + 1
		f[n] = field
	end
	local roll = ""
	local count = tonumber(f[13] or "") or 0
	if count > 0 then
		local ids = {}
		for i = 1, count do ids[#ids + 1] = tonumber(f[13 + i]) or 0 end
		table.sort(ids)
		roll = table.concat(ids, ".")
	elseif (f[7] or "") ~= "" and f[7] ~= "0" then
		roll = "s" .. f[7]
	end
	return (f[1] or "") .. ":" .. roll
end
T_ident = ident

local function item(link)
	local id = ident(link)
	return id and WORLD.items[id] or nil
end

local Game = {}
NS.Game = Game

function Game.ItemInstant(link)
	called("ItemInstant")
	local it = item(link)
	if not it then return nil end
	return it.equipLoc, it.classID, it.subclassID
end

function Game.ItemInfo(link)
	called("ItemInfo")
	local it = item(link)
	if not it or it.loaded == false then return nil end
	return it.name, it.quality, it.minLevel, it.sellPrice
end

function Game.ItemStats(link)
	called("ItemStats")
	local it = item(link)
	if not it or it.loaded == false then return nil end
	return it.raw
end

function Game.ItemSpeed(link)
	local id = ident(link)
	return id and WORLD.speed[id] or nil
end

function Game.ItemEffects(link)
	called("ItemEffects")
	local id = ident(link)
	local e = id and WORLD.effects[id]
	if not e then return nil end
	return e.equip or 0, e.use or 0, e.proc or 0
end

function Game.ItemUnique(link)
	local it = item(link)
	return it and it.unique == true or false
end

function Game.RequestItem(itemID)
	called("RequestItem")
	WORLD.requested[#WORLD.requested + 1] = itemID
end
-- (The game has an item's data once it is "loaded" here; an item it knows nothing of is not.)
function Game.ItemCached(link)
	called("ItemCached")
	if WORLD.noCacheCall then return nil end
	local it = item(link)
	return it ~= nil and it.loaded ~= false
end
function Game.Time() return WORLD.clock / 1000 end
function Game.Class() return WORLD.class end
function Game.Level() return WORLD.level end
function Game.Trees()
	called("Trees")
	return WORLD.trees
end
function Game.KnowsSkill(line)
	if WORLD.skills == nil then return nil end
	return WORLD.skills[line] == true
end
function Game.KnowsSpell(id) return WORLD.spells[id] == true end
function Game.WornLink(slot) return WORLD.worn[slot] end
function Game.BagLinks(out)
	called("BagLinks")
	out = out or {}
	for _, link in ipairs(WORLD.bags) do out[#out + 1] = link end
	return out
end
function Game.InCombat() return WORLD.combat == true end
-- WORLD.hitMod = { melee, ranged, spell } (percent); nil = the game does not say (a fight).
function Game.HitModifiers()
	called("HitModifiers")
	local m = WORLD.hitMod
	if not m or WORLD.combat then return nil end
	return m[1], m[2], m[3]
end
function Game.Clock() return WORLD.clock end
function Game.Guid() return WORLD.guid end
function Game.Name() return WORLD.name end
function Game.Realm()
	if WORLD.realm == "" then return nil end
	return WORLD.realm
end
function Game.Faction() return WORLD.faction end
function Game.RealmID()
	if WORLD.realmID then return WORLD.realmID end
	return WORLD.guid and tonumber(WORLD.guid:match("^Player%-(%d+)%-")) or nil
end

-- ---------------------------------------------------------------------------------------------
-- The test's tools
-- ---------------------------------------------------------------------------------------------
T = { checks = 0, failed = {}, case_name = "(no case)" }

-- Makes an item and returns its link. def: { id, name, equipLoc, classID, subclassID, minLevel,
-- quality, sellPrice, raw = { ITEM_MOD_... = n }, unique, loaded, effects = { equip, use, proc },
--   roll (or suffix: the same thing) = a bonus ID, the way this client writes "of the Bear";
--   oldSuffix = a suffix in field 7, the pre-bonus-ID way;
--   linkLevel, enchant, context, modifiers = "28:4522" : fields that do NOT make another item }
local nextID = 1000
function T.item(def)
	nextID = nextID + 1
	local id = def.id or nextID
	local roll = def.roll or def.suffix
	local which = roll and tostring(roll) or (def.oldSuffix and ("s" .. def.oldSuffix)) or ""
	WORLD.items[id .. ":" .. which] = {
		name = def.name or ("Item " .. id), quality = def.quality or 2, minLevel = def.minLevel or 0,
		equipLoc = def.equipLoc or "INVTYPE_CHEST", classID = def.classID or 4,
		subclassID = def.subclassID == nil and 0 or def.subclassID, sellPrice = def.sellPrice or 0,
		raw = def.raw or {}, unique = def.unique, loaded = def.loaded,
	}
	if def.effects then WORLD.effects[id .. ":" .. which] = def.effects end
	return T.link(id, roll, def.name, def.linkLevel, def.enchant, def)
end

-- A link as this client writes one (shapes taken from links the game itself saved):
--   item:7444::::::::33:1489:::1:12751::::::             a roll: one bonus ID in fields 13-14
--   item:7448::::::::33:1489::1:1:12751::::::            the same with an item context (field 12)
--   item:7445::::::::33:1489::1:1:12751:1:28:4522:::::   and one modifier (type 28) after the roll
-- Fields: 1 item, 2 enchant, 7 suffix, 8 unique ID, 9 link level, 10 spec, 12 context,
-- 13 bonus count, 14.. bonus IDs, then modifier count and (type, value) pairs.
-- more = { oldSuffix, context, modifiers = "28:4522" }.
function T.link(id, roll, name, linkLevel, enchant, more)
	more = more or {}
	local suffix, unique = "", ""
	if more.oldSuffix then suffix, unique = tostring(more.oldSuffix), "1977" end
	local bonus = (roll and roll ~= "") and ("1:" .. tostring(roll)) or ""
	local mods = ""
	if more.modifiers then
		local _, colons = tostring(more.modifiers):gsub(":", "")
		mods = ((colons + 1) / 2) .. ":" .. more.modifiers
	end
	return ("|cff1eff00|Hitem:%d:%s:::::%s:%s:%s:1489::%s:%s:%s:::::|h[%s]|h|r"):format(id, enchant or "", suffix, unique,
		linkLevel or "60", more.context or "", bonus, mods, name or ("Item " .. id))
end

function T.load(link)
	local it = item(link)
	if it then it.loaded = true end
end

function T.case(name, fn)
	T.case_name = name
	local ok, err = pcall(fn)
	if not ok then T.failed[#T.failed + 1] = name .. ": error: " .. tostring(err) end
	T.case_name = "(no case)"
end

function T.check(cond, what)
	T.checks = T.checks + 1
	if not cond then T.failed[#T.failed + 1] = T.case_name .. ": " .. tostring(what) end
end

function T.eq(got, want, what)
	T.checks = T.checks + 1
	if got ~= want then
		T.failed[#T.failed + 1] = ("%s: %s: got %s, want %s"):format(T.case_name, tostring(what), tostring(got), tostring(want))
	end
end

function T.near(got, want, what)
	T.checks = T.checks + 1
	if type(got) ~= "number" or math.abs(got - want) > 1e-9 then
		T.failed[#T.failed + 1] = ("%s: %s: got %s, want %s"):format(T.case_name, tostring(what), tostring(got), tostring(want))
	end
end

-- Starts a case from nothing: no items cached, nothing worn or carried.
function T.reset()
	WORLD.items, WORLD.worn, WORLD.bags, WORLD.speed, WORLD.effects = {}, {}, {}, {}, {}
	WORLD.combat, WORLD.clock, WORLD.hitMod = false, 0, nil
	WORLD.guid, WORLD.name, WORLD.realm, WORLD.realmID, WORLD.faction = "Player-4407-00ABCDEF", "Tester", "Test Realm", nil, "Alliance"
	WORLD.class, WORLD.level, WORLD.trees, WORLD.skills, WORLD.spells = "WARRIOR", 60, nil, nil, {}
	WORLD.calls, WORLD.requested, WORLD.noCacheCall = {}, {}, nil
	if NS.Stats then
		NS.Stats.Forget()
		NS.Stats.unknown = {}
	end
	if NS.Score then NS.Score.Fresh() end
end

function T.done()
	if #T.failed > 0 then
		error(#T.failed .. " failed:\n  " .. table.concat(T.failed, "\n  "), 0)
	end
	return "ok, " .. T.checks .. " checks"
end

-- ---------------------------------------------------------------------------------------------
-- The game and Daylight UI around the engine (test_market.lua, test_window.lua)
-- ---------------------------------------------------------------------------------------------
-- T.world() puts stand-ins for what Core.lua, Market.lua and Window.lua read into the globals
-- (with rawset, so the lock below still catches every global they were NOT given), then loads
-- the locale table, the real weights and Core.lua. It returns the handles a test drives:
--   w.frames(n) / w.advance(seconds)   time passes: a frame is 20 ms, timers run when due
--   w.fire(event, ...)                 a game event, to every frame registered for it
--   w.dui(event, ...)                  one of Daylight UI's events (Login, SettingChanged)
--   w.settings[scope][path]            Daylight UI's settings (w.set writes one and tells)
--   w.ah                               the Auction House: { open, rows = { row, ... } }, a row
--                                      { itemID, buyout, count, owner, link, late = true (no
--                                      item data yet), blank = true }; w.ah.calls counts
--   w.ahmod                            Daylight UI's Auction House module (ns.On, ns.Ruleset)
--   w.load(rel)                        loads one more of the addon's files into NS
--   w.clockStep                        milliseconds one look at the clock costs (default 0.05)
--   w.widget(parent)                   a stand-in frame, texture or text: shown state, scripts,
--                                      points and sizes are real, every other method does nothing
--   w.update()                         every frame's OnUpdate, once
function T.world()
	local w = { time = 1000, spent = 0, clockStep = 0.05, timers = {}, frames_ = {}, handlers = {}, commands = {},
		settings = { DaylightGear = {}, AuctionHouse = { enabled = true } }, printed = {}, set_ = {} }
	local function def(name, value) rawset(_G, name, value) end

	local function read(rel)
		local handle = assert(io.open(ADDON_ROOT .. "/" .. rel, "r"))
		local source = handle:read("*a")
		handle:close()
		return source
	end
	function w.load(rel) return assert(loadstring(read(rel), "@" .. rel))("DaylightGear", NS) end

	-- time
	NS.Game.Clock = function()
		w.spent = w.spent + w.clockStep
		return w.time * 1000 + w.spent
	end
	def("C_Timer", { After = function(delay, fn) w.timers[#w.timers + 1] = { at = w.time + (delay or 0), fn = fn } end })
	function w.frames(n)
		for _ = 1, n or 1 do
			w.time, w.spent = w.time + 0.02, 0
			local due, rest = {}, {}
			for _, t in ipairs(w.timers) do
				if t.at <= w.time then due[#due + 1] = t else rest[#rest + 1] = t end
			end
			w.timers = rest
			for _, t in ipairs(due) do t.fn() end
		end
	end
	function w.advance(seconds) w.frames(math.ceil(seconds / 0.02)) end
	def("GetServerTime", function() return 1700000000 + math.floor(w.time) end)

	-- frames and events (a frame answers any method; the few that matter are real)
	local function widget(parent)
		local f = { events = {}, scripts = {}, shown = true, points = {}, parent = parent }
		function f:RegisterEvent(event) self.events[event] = true end
		function f:UnregisterEvent(event) self.events[event] = nil end
		function f:SetScript(name, fn) self.scripts[name] = fn end
		function f:GetScript(name) return self.scripts[name] end
		function f:Show()
			if self.shown then return end
			self.shown = true
			if self.scripts.OnShow then self.scripts.OnShow(self) end
		end
		function f:Hide()
			if not self.shown then return end
			self.shown = false
			if self.scripts.OnHide then self.scripts.OnHide(self) end
		end
		function f:SetShown(on) if on then self:Show() else self:Hide() end end
		function f:IsShown() return self.shown end
		function f:IsVisible() return self.shown end
		function f:GetParent() return self.parent end
		function f:SetText(text) self.words = text end
		function f:GetText() return self.words end
		function f:SetPoint(...) self.points[#self.points + 1] = { ... } end
		function f:ClearAllPoints() self.points = {} end
		function f:SetScale(scale) self.scale = scale end
		function f:GetScale() return self.scale or 1 end
		function f:GetEffectiveScale() return self.scale or 1 end
		function f:SetWidth(width) self.width = width end
		function f:SetHeight(height) self.height = height end
		function f:SetSize(width, height) self.width, self.height = width, height end
		function f:GetWidth() return self.width or 0 end
		function f:GetHeight() return self.height or 0 end
		function f:CreateTexture() return widget(self) end
		function f:CreateFontString() return widget(self) end
		function f:Click() if self.scripts.OnClick then self.scripts.OnClick(self, "LeftButton") end end
		-- (Any other method, named as the game names them, does nothing; a plain field is nil.)
		return setmetatable(f, { __index = function(_, key)
			if type(key) == "string" and key:match("^%u") then return function() end end
			return nil
		end })
	end
	w.widget = widget
	def("CreateFrame", function(_, name, parent)
		local f = widget(parent)
		f.name = name
		w.frames_[#w.frames_ + 1] = f
		return f
	end)
	-- every frame's OnUpdate, once (a frame of the game)
	function w.update()
		for _, f in ipairs(w.frames_) do
			if f.scripts.OnUpdate then f.scripts.OnUpdate(f, 0.02) end
		end
	end
	function w.fire(event, ...)
		for _, f in ipairs(w.frames_) do
			if f.events[event] and f.scripts.OnEvent then f.scripts.OnEvent(f, event, ...) end
		end
	end

	-- the game's odds and ends
	def("DEFAULT_CHAT_FRAME", { lines = {}, AddMessage = function(self, text) self.lines[#self.lines + 1] = text end })
	w.chat = DEFAULT_CHAT_FRAME.lines
	def("geterrorhandler", function() return function(err) error(err, 0) end end)
	def("GetLocale", function() return "enUS" end)
	def("UnitName", function() return "Tester" end)
	def("GetRealmName", function() return "Test Realm" end)
	def("UnitFactionGroup", function() return "Alliance" end)
	def("issecretvalue", false)
	def("DaylightGearDB", {})
	def("print", function(...)
		local parts = {}
		for i = 1, select("#", ...) do parts[i] = tostring((select(i, ...))) end
		w.printed[#w.printed + 1] = table.concat(parts, " ")
	end)

	-- the Auction House's whole-house list
	local ah = { open = false, rows = {}, calls = { info = 0, link = 0, ask = 0 }, ready = true, results = {} }
	w.ah = ah
	def("C_AuctionHouse", {
		GetNumReplicateItems = function() return #ah.rows end,
		GetReplicateItemInfo = function(index)
			ah.calls.info = ah.calls.info + 1
			local r = ah.rows[index + 1]
			-- (A row not there yet. The docs give itemID as a number that is never nil, so the
			-- stand-in answers 0; blank = "nil" asks for the nil some clients have been seen to give.)
			if not r or r.blank then
				local id = 0
				if r and r.blank == "nil" then id = nil end
				return nil, nil, 0, -1, false, 0, nil, 0, 0, 0, 0, nil, nil, nil, nil, 0, id, false
			end
			local known = not r.late
			return known and (r.name or "Item") or "", nil, r.count or 1, 2, true, 1, nil, 0, 0, r.buyout or 0, 0, nil, nil,
				r.owner, nil, 0, r.itemID, known
		end,
		GetReplicateItemLink = function(index)
			ah.calls.link = ah.calls.link + 1
			local r = ah.rows[index + 1]
			if not r or r.blank or r.late then return nil end
			return r.link
		end,
		ReplicateItems = function() ah.calls.ask = ah.calls.ask + 1 end,
		-- one item's search results: ah.results[itemID] = { full = bool, { link =, buyout =, own =, id =, suffix = }, ... }
		GetNumItemSearchResults = function(key) return #(ah.results[key.itemID] or {}) end,
		GetItemSearchResultInfo = function(key, i)
			local r = (ah.results[key.itemID] or {})[i]
			if not r then return nil end
			return { itemKey = { itemID = key.itemID, itemLevel = 0, itemSuffix = r.suffix or 0 }, auctionID = r.id, itemLink = r.link,
				buyoutAmount = r.buyout, containsOwnerItem = r.own == true, quantity = 1 }
		end,
		HasFullItemSearchResults = function(key) return (ah.results[key.itemID] or {}).full ~= false end,
		IsThrottledMessageSystemReady = function() return ah.ready end,
	})

	-- Daylight UI
	local modListeners = {}
	w.ahmod = { enabled = true, ns = {
		On = function(name, fn) modListeners[name] = modListeners[name] or {}; table.insert(modListeners[name], fn) end,
		Ruleset = { Key = function() return w.ruleset end },
	} }
	w.ruleset = "US-PvE"
	-- Daylight UI's one-item search and its purchases: asked searches wait in w.searches until the
	-- test answers them (w.answer); w.buying is what Buy.Pending says.
	w.searches = {}
	w.ahmod.ns.Search = { Item = function(itemID, onDone)
		w.searches[#w.searches + 1] = { itemID = itemID, onDone = onDone }
		return true
	end }
	w.ahmod.ns.Buy = { Pending = function() return w.buying end }
	function w.answer(rows, reason)
		local q = table.remove(w.searches, 1)
		if not q then return nil end
		if rows ~= nil then w.fire("ITEM_SEARCH_RESULTS_UPDATED", { itemID = q.itemID, itemLevel = 0, itemSuffix = 0 }) end
		q.onDone(rows, reason, {})
		return q.itemID
	end
	function w.ahmodFire(name, ...)
		for _, fn in ipairs(modListeners[name] or {}) do fn(...) end
	end
	local dui
	dui = {
		API = {
			major = 1, minor = 12,
			GetSetting = function(scope, path) return w.settings[scope] and w.settings[scope][path] end,
			For = function(name)
				return {
					name = name,
					On = function(event, fn) w.handlers[event] = w.handlers[event] or {}; table.insert(w.handlers[event], fn) end,
					RegisterCommand = function(word, fn, help) w.commands[word] = { fn = fn, help = help } return true end,
				}
			end,
		},
		RegisterPlugin = function() end,
		RegisterModule = function() end,
		GetModule = function(_, name) if name == "AuctionHouse" then return w.ahmod end end,
		Set = function(_, scope, path, value)
			w.set_[#w.set_ + 1] = { scope, path, value }
			w.settings[scope] = w.settings[scope] or {}
			w.settings[scope][path] = value
			w.dui("SettingChanged", scope, path, value)
			return true
		end,
	}
	w.DUI = dui
	def("DaylightUI", dui)
	function w.dui(event, ...)
		for _, fn in ipairs(w.handlers[event] or {}) do fn(...) end
	end
	function w.set(path, value) dui:Set("DaylightGear", path, value) end

	w.load("Locales/Locales.lua")
	w.load("Data/Weights.lua")
	w.load("Core.lua")
	return w
end

-- ---------------------------------------------------------------------------------------------
-- Strict globals: the engine is pure Lua. Anything it reads or sets beyond Lua 5.1's own names
-- and the three tables above is a hidden dependency on the game, and fails the test.
-- ---------------------------------------------------------------------------------------------
setmetatable(_G, {
	__index = function(_, name) error("the engine read the global '" .. tostring(name) .. "'", 2) end,
	__newindex = function(_, name) error("the engine set the global '" .. tostring(name) .. "'", 2) end,
})
