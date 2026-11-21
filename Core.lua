-- Glowey's Gear: a Daylight UI plugin.
-- Scores gear for your spec, compares it with what you wear and carry, and (from the second
-- half of stage 1 on) lists the best upgrades for sale on the Auction House by improvement per
-- gold, with the same verdict on item tooltips and bag slots.
--
-- This file: the namespace's shared pieces (settings, saved variables, a small event bus, chat
-- output), the wiring between the game's events and the engine (who the player is, what they
-- own), and the registration with Daylight UI with the first options page.
-- The engine itself is Stats.lua, Spec.lua, Score.lua, Compare.lua and Rank.lua (pure Lua,
-- tested offline: Tools/tests); every game call it needs is in Game.lua. ARCHITECTURE.md has
-- the whole map. Built on DaylightUI.API only; nothing of Daylight UI's is copied.
--
-- luacheck: read globals CreateFrame C_Timer geterrorhandler
-- luacheck: read globals DEFAULT_CHAT_FRAME

local ADDON, ns = ...
local L = ns.L

local DUI = _G.DaylightUI
local API = DUI and DUI.API
if not API or API.major ~= 1 then
	ns.off = true
	return
end

ns.ADDON, ns.DUI, ns.API = ADDON, DUI, API
local me = API.For(ADDON)
ns.me = me

function ns.Print(text)
	DEFAULT_CHAT_FRAME:AddMessage("|cff5fd38dGlowey's Gear|r: " .. tostring(text))
end

local function try(fn, ...)
	local ok, err = pcall(fn, ...)
	if not ok then geterrorhandler()(err) end
	return ok
end

-- ---------------------------------------------------------------------------------------------
-- A bus between this plugin's files
-- ---------------------------------------------------------------------------------------------
--   "WhoChanged"    the class, spec, level or weights in use changed
--   "OwnedChanged"  what is worn or carried changed: verdicts are stale
--   "ItemsArrived"  item data came in for something (at most once a second)
--   "Setting"       (path) a setting of ours changed
local listeners = {}

function ns.On(name, fn)
	local list = listeners[name]
	if not list then
		list = {}
		listeners[name] = list
	end
	list[#list + 1] = fn
end

function ns.Fire(name, ...)
	local list = listeners[name]
	if not list then return end
	for i = 1, #list do try(list[i], ...) end
end

-- ---------------------------------------------------------------------------------------------
-- What our own code costs (for /gear debug)
-- ---------------------------------------------------------------------------------------------
-- ns.Perf.Time(part, ms) adds time a part of the plugin just used; within one frame the times of
-- a part add up, and the largest such frame total of the last minute is kept. ns.Perf.Count
-- (name, n) counts things that happen. Both are kept in six ten-second buckets, so "the last
-- minute" costs a handful of numbers and no table is made while the game runs.
-- Parts: "market" (reading the Auction House's list), "scoring", "paint", "context" (reading
-- what is owned), "marks" (bag and tooltip answers). A frame is told from the next by
-- Game.Time(), which is the same for everything in one frame.
local Perf = { max = {}, count = {}, cur = {} }
ns.Perf = Perf
local BUCKET = 10

local function slot(store, name)
	local s = store[name]
	if not s then
		s = { 0, 0, 0, 0, 0, 0, at = 0 }
		store[name] = s
	end
	local now = math.floor(ns.Game.Time() / BUCKET)
	if now ~= s.at then
		-- (Buckets older than a minute are emptied as time moves on.)
		for b = s.at + 1, math.min(now, s.at + 6) do s[b % 6 + 1] = 0 end
		s.at = now
	end
	return s, now % 6 + 1
end

function Perf.Time(name, ms)
	local c = Perf.cur[name]
	if not c then
		c = { frame = -1, sum = 0 }
		Perf.cur[name] = c
	end
	local frame = ns.Game.Time()
	if c.frame ~= frame then c.frame, c.sum = frame, 0 end
	c.sum = c.sum + ms
	local s, i = slot(Perf.max, name)
	if c.sum > s[i] then s[i] = c.sum end
end

function Perf.Count(name, n)
	local s, i = slot(Perf.count, name)
	s[i] = s[i] + (n or 1)
end

-- The largest frame total of a part, and how often a thing happened, in the last minute.
function Perf.Max(name)
	local s = slot(Perf.max, name)
	return math.max(s[1], s[2], s[3], s[4], s[5], s[6])
end
function Perf.Sum(name)
	local s = slot(Perf.count, name)
	return s[1] + s[2] + s[3] + s[4] + s[5] + s[6]
end

function Perf.Lines()
	local out = {}
	out[1] = ("longest frame of our own work in the last minute, by part (ms): market %.1f, scoring %.1f, paint %.1f, context %.1f, marks %.1f, price checks %.1f"):format(
		Perf.Max("market"), Perf.Max("scoring"), Perf.Max("paint"), Perf.Max("context"), Perf.Max("marks"), Perf.Max("check"))
	out[2] = ("in the last minute: %d refreshes, %d new jobs, %d reads of what is owned, %d paints, %d full arranges, %d bag repaints"):format(
		Perf.Sum("refresh"), Perf.Sum("job"), Perf.Sum("context"), Perf.Sum("paint"), Perf.Sum("arrange"), Perf.Sum("bags"))
	out[3] = ("events in the last minute: %d item-data (%.0f a second), %d Auction House list"):format(
		Perf.Sum("itemEvents"), Perf.Sum("itemEvents") / 60, Perf.Sum("listEvents"))
	return out
end

-- ---------------------------------------------------------------------------------------------
-- Settings (in Daylight UI's profile, under this plugin's name)
-- ---------------------------------------------------------------------------------------------
local DEFAULTS = {
	enabled = true,
	minGain = 3,            -- percent: smaller gains are not shown
	bestArmor = false,      -- only the heaviest armor type the class wears now
	maxPrice = 50,          -- gold per item; 0 = no limit
	mode = "perGold",       -- "perGold" | "biggest"
	tooltips = true,        -- (second half) a row on item tooltips
	bagMarks = true,        -- (second half) a corner mark on bag slots
	bagCorner = "bottom_right", -- one of Daylight UI's four corner names. Its bags draw the bind tag top left, the
	-- item level bottom left and the equipment-set mark top right (DaylightUI_Bags\Items.lua:499-500,
	-- :686-696 in Daylight UI 2.1.2);
	-- bottom right holds only stack counts, which gear never has.
	dock = true,            -- (second half) the window docks to Daylight UI's Auction House
	questPick = true,       -- (stage 2) a chat line naming the best reward of a quest with a choice
	questSell = false,      -- (stage 2) with no upgrade among them, which sells for most. Off: Daylight UI's
	-- quest window already marks that reward with a coin (DaylightUI\Npc\Window.lua:32, :292)
	alert = true,           -- (stage 2) one chat line when a scan finds a better buy for a slot
	yieldBags = false,      -- (stage 2) another addon marks bag upgrades and ours stands down
	yieldTips = false,      -- (stage 2) the same for the tooltip row
}
ns.DEFAULTS = DEFAULTS

local cache, NONE = {}, {}

function ns.Get(path)
	local v = cache[path]
	if v ~= nil then
		if v == NONE then return nil end
		return v
	end
	local ok, value = pcall(API.GetSetting, ADDON, path)
	if not ok or value == nil then
		-- (Daylight UI answers nil for a module it has not switched on yet. The default is
		-- given, and not kept: the next read asks again, so the real value is found as soon
		-- as it is there.)
		return DEFAULTS[path]
	end
	cache[path] = value == nil and NONE or value
	return value
end

-- Writes a setting of ours through Daylight UI (its options page and "SettingChanged" follow).
function ns.SetSetting(path, value)
	local D = ns.DUI
	if type(D) ~= "table" or type(D.Set) ~= "function" then return false end
	return (pcall(D.Set, D, ADDON, path, value))
end

-- The ranking options as Rank.Arrange takes them.
function ns.RankOptions(level)
	return { mode = ns.Get("mode"), maxPrice = (tonumber(ns.Get("maxPrice")) or 0) * 10000,
		minPct = tonumber(ns.Get("minGain")) or 0, level = level, alternatives = 10 }
end

-- ---------------------------------------------------------------------------------------------
-- Saved variables: GloweyGearDB (what is not a setting)
-- ---------------------------------------------------------------------------------------------
--   v            the shape's version, for Migrate
--   updateCheck  Update.lua's switch (false = off)
--   chars        [<character GUID>] = { spec = "auto" | "<SPEC KEY>", last = "<SPEC KEY>", name = "Name" }
--   houses       (Market.lua) one saved gear list per Auction House
local DB_VERSION = 2

local function Migrate(db)
	-- Steps run oldest first; each leaves db.v at its own number.
	--   v1 -> v2: characters are kept by GUID, not by "Realm-Name" (the game stopped giving
	--   realm names on 2026-11-20, which turned every key into "-Name"). The old records stay
	--   where they are; ns.Char() copies a character's own into its GUID record when it can
	--   tell which one that is.
	if type(db.v) ~= "number" or db.v > DB_VERSION or db.v < 2 then db.v = DB_VERSION end
	if type(db.chars) ~= "table" then db.chars = {} end
	if type(db.houses) ~= "table" then db.houses = {} end
	return db
end

local migrated   -- the table Migrate has been through this session
function ns.DB()
	local db = _G.GloweyGearDB
	if type(db) ~= "table" then
		db = { v = DB_VERSION }
		_G.GloweyGearDB = db
	end
	if migrated ~= db then
		Migrate(db)
		migrated = db
	end
	return db
end

-- The record a character had under the old "Realm-Name" key, when exactly one can be its own:
-- the one under today's realm name when the game gives one, else the only old record that ends
-- in "-<Name>". Two to choose from: none is taken (a wrong spec is worse than Auto).
local function OldRecord(chars, name)
	local realm = ns.Game.Realm()
	if realm and type(chars[realm .. "-" .. name]) == "table" then return chars[realm .. "-" .. name] end
	local found, count = nil, 0
	local tail = "-" .. name
	for key, record in pairs(chars) do
		if type(key) == "string" and type(record) == "table" and not key:find("^Player%-")
			and key:sub(-#tail) == tail then
			found, count = record, count + 1
		end
	end
	if count == 1 then return found end
	return nil
end

-- This character's own table, or nil while the game does not know the character yet. Kept by
-- GUID (Game.Guid), which stays the same whatever the game says the realm is called.
function ns.Char()
	local guid = ns.Game.Guid()
	if not guid then return nil end
	local chars = ns.DB().chars
	local c = chars[guid]
	if type(c) ~= "table" then
		c = { spec = "auto" }
		local name = ns.Game.Name()
		local old = name and OldRecord(chars, name)
		if old then
			if type(old.spec) == "string" then c.spec = old.spec end
			if type(old.last) == "string" then c.last = old.last end
		end
		c.name = name
		chars[guid] = c
	end
	return c
end

-- ---------------------------------------------------------------------------------------------
-- Who the player is, and what they own (kept until something changes)
-- ---------------------------------------------------------------------------------------------
local Spec, Compare, Stats = ns.Spec, ns.Compare, ns.Stats

Spec.GetChoice = function()
	local c = ns.Char()
	return c and c.spec or "auto"
end
Spec.GetLast = function()
	local c = ns.Char()
	return c and c.last or nil
end
Spec.SetLast = function(key)
	local c = ns.Char()
	if c then c.last = key end
end

local who, whoWhy, context

-- { class, spec, level, weights, how }, or nil and why ("noclass", "noweights", "nolevel").
function ns.Who()
	if who == nil and whoWhy == nil then
		who, whoWhy = Spec.Current()
		if who == nil and whoWhy == nil then whoWhy = "noweights" end
		-- (For the hit cap: Compare.lua's header.)
		if who then who.hitMod = ns.HitMod() end
	end
	return who, whoWhy
end

-- The hit the character has that is not on gear (talents, mostly): { melee = , spell = } in
-- percent, kept per character. Read from the game only out of a fight (the calls are secret
-- in one): at login and when talents or the level change (not more often: a buff that gives
-- hit would be taken for the character's own each time). A hunter's is the ranged figure. A
-- value outside 0 to 30 is not believed.
function ns.HitMod()
	local c = ns.Char()
	return c and type(c.hit) == "table" and c.hit or nil
end

-- Reads it; true when it changed.
function ns.ReadHitMod()
	if ns.Game.InCombat() then return false end
	local c = ns.Char()
	local melee, ranged, spell = ns.Game.HitModifiers()
	if not c or not melee then return false end
	if ns.Game.Class() == "HUNTER" then melee = ranged end
	if melee < 0 or melee > 30 or spell < 0 or spell > 30 then return false end
	local old = c.hit
	if type(old) == "table" and old.melee == melee and old.spell == spell then return false end
	c.hit = { melee = melee, spell = spell }
	return true
end

-- What is worn and carried, scored for ns.Who(): a Compare context, or nil when there is no one
-- to score for. Never built in a fight (the last one stands until the fight ends): nothing
-- read here is secret, but a fight is no time to walk the bags.
function ns.Context()
	if context then return context end
	local w = ns.Who()
	if not w then return nil end
	if ns.Game.InCombat() then return nil end
	local t0 = ns.Game.Clock()
	context = Compare.FromGame(w, { bestArmor = ns.Get("bestArmor") == true })
	Perf.Time("context", ns.Game.Clock() - t0)
	Perf.Count("context")
	return context
end

-- The verdict on one item: Compare.Evaluate's table (a shared one: read it, do not keep it), or
-- nil and why ("off", "noweights"..., "pending", "notgear", "busy" in a fight with nothing kept).
-- carried = true for an item that is itself in the bags: its own copy is left out of what it is
-- compared with.
local verdict = {}
local excludeOpts = {}
function ns.Verdict(link, carried)
	if ns.Get("enabled") == false then return nil, "off" end
	local ctx = ns.Context()
	if not ctx then
		local _, why = ns.Who()
		return nil, why or "busy"
	end
	local rec, why = Stats.Of(link)
	if not rec then return nil, why end
	ns.lastSeen = rec
	local opts
	if carried then
		excludeOpts.exclude = rec.key
		opts = excludeOpts
	end
	return Compare.Evaluate(rec, ctx, opts, verdict)
end

local function WhoChanged()
	who, whoWhy, context = nil, nil, nil
	ns.Fire("WhoChanged")
end

local function OwnedChanged()
	context = nil
	ns.Fire("OwnedChanged")
end

-- Bag and equipment events come in bursts (a vendor run fires dozens): one refresh a moment
-- after the last of them, and never in a fight (it runs when the fight ends).
local DELAY = 0.3
local waiting, afterFight = false, false
local function Soon()
	if waiting then return end
	waiting = true
	C_Timer.After(DELAY, function()
		waiting = false
		if ns.Game.InCombat() then
			afterFight = true
			return
		end
		OwnedChanged()
	end)
end

-- Item data arriving. At an Auction House these events come by the tens of thousands (the
-- game sends one for every item anybody's code makes it load), so one event costs a counter
-- and two tests here, and nothing else:
--   * what is owned is read again only when some owned item was still waiting for its data;
--   * otherwise the others hear one "ItemsArrived" a second at most, which only Marks.lua uses,
--     and only when a bag or tooltip answer of its own was waiting;
--   * the window does not listen here at all: a list being scored hears about its own parked
--     items itself, by item ID (Window.lua).
local itemsSoon = false
local function ItemArrived()
	Perf.Count("itemEvents")
	if context and context.pending > 0 then return Soon() end
	if itemsSoon then return end
	itemsSoon = true
	C_Timer.After(1, function()
		itemsSoon = false
		if not ns.Game.InCombat() then ns.Fire("ItemsArrived") end
	end)
end

-- The spec picker's words: the game's own tree names once it has them, ours for the specs that
-- are not simply a tree (Spec.VARIANTS; design/data-format.md, section 8).
local VARIANT = { LEVELING = L["Leveling"], FERAL_BEAR = L["Bear"] }
local specValues = { auto = L["Auto"] }
local specOrder = { "auto" }   -- Auto first, then the data's own order (not by the alphabet)
local function SpecNames()
	local class = ns.Game.Class()
	if not class then return end
	local trees = ns.Game.Trees()
	local list = Spec.List(class)
	for i = #specOrder, #list + 2, -1 do specOrder[i] = nil end
	for i, key in ipairs(list) do
		specOrder[i + 1] = key
		local label, ours = Spec.Label(class, key, trees)
		if ours then label = VARIANT[key] or label end
		-- (Before the game has tree names: the key as words, "BEAST_MASTERY" -> "Beast Mastery".)
		specValues[key] = label or key:lower():gsub("_", " "):gsub("(%a)(%a*)", function(a, b) return a:upper() .. b end)
	end
end
ns.SpecValues = specValues

-- WHEN THE TALENTS ARE READ. The trees come from the trait system (Game.Trees), and the game
-- may not have them at login: the list of builds arrives with TRAIT_CONFIG_LIST_UPDATED. Until
-- they are readable the spec is the last one found for the character, or the class default, so
-- on a first session a level 60 could sit on "Leveling". Three things close that gap:
--   * the events below, each of which asks again a moment later;
--   * a few looks on a timer after login, in case no event comes (Recheck);
--   * nothing is read in a fight: a look that falls in one waits for the fight's end.
-- Event names, each checked in the generated docs:
--   TRAIT_CONFIG_LIST_UPDATED, TRAIT_CONFIG_UPDATED   DOC SharedTraitsDocumentation.lua:867, :873
--   PLAYER_TALENT_UPDATE, ACTIVE_TALENT_GROUP_CHANGED DOC SpecializationInfoDocumentation.lua:503, :447
--   PLAYER_LEVEL_UP                                   DOC UnitDocumentation.lua:3832
--   PLAYER_ENTERING_WORLD                             DOC SystemDocumentation.lua:136
local whoAfterFight = false
local function ReadWho()
	if ns.Game.InCombat() then
		whoAfterFight = true
		return
	end
	SpecNames()
	local hitChanged = ns.ReadHitMod()
	-- Read afresh; the others are told only when the answer is another one (the same spec,
	-- level and weights leave every verdict as it was, and what is owned need not be read again).
	local old = who
	who, whoWhy = nil, nil
	local new = ns.Who()
	if old and new and old.class == new.class and old.spec == new.spec and old.level == new.level
		and old.weights == new.weights and not hitChanged then
		return
	end
	context = nil
	ns.Fire("WhoChanged")
end

local LOOKS = { 1, 3, 8, 20 }   -- seconds after login, while the trees are still not readable
local function Recheck(i)
	local delay = LOOKS[i]
	if not delay then return end
	C_Timer.After(delay, function()
		if ns.Game.InCombat() then
			whoAfterFight = true
		elseif ns.Game.Trees() then
			local w = ns.Who()
			-- (Readable now. Read again only if the answer so far was made without them.)
			if not w or w.how ~= "talents" then ReadWho() end
			return
		end
		Recheck(i + 1)
	end)
end

local frame = CreateFrame("Frame")
local EVENTS = {
	TRAIT_CONFIG_LIST_UPDATED = "who", TRAIT_CONFIG_UPDATED = "who", PLAYER_TALENT_UPDATE = "who",
	ACTIVE_TALENT_GROUP_CHANGED = "who", PLAYER_LEVEL_UP = "who", PLAYER_ENTERING_WORLD = "who",
	-- Weapon skills learned change what can be wielded (DOC SkillInfoDocumentation.lua:105).
	SKILL_LINES_CHANGED = "owned",
	-- Worn and carried: DOC PaperDollInfoDocumentation.lua:386, ContainerDocumentation.lua:677.
	PLAYER_EQUIPMENT_CHANGED = "owned", BAG_UPDATE_DELAYED = "owned",
	-- Item data arriving turns "pending" items into records (DOC ItemDocumentation.lua:1815).
	GET_ITEM_INFO_RECEIVED = "item",
	PLAYER_REGEN_ENABLED = "fight",
}
for event in pairs(EVENTS) do pcall(frame.RegisterEvent, frame, event) end
local whoSoon = false
frame:SetScript("OnEvent", function(_, event)
	local kind = EVENTS[event]
	if kind == "who" then
		-- (PLAYER_LEVEL_UP comes before UnitLevel changes on some clients: a moment later. A
		-- burst of these events is one look.)
		if whoSoon then return end
		whoSoon = true
		C_Timer.After(0.1, function()
			whoSoon = false
			ReadWho()
		end)
	elseif kind == "owned" then
		Soon()
	elseif kind == "item" then
		ItemArrived()
	elseif kind == "fight" then
		if whoAfterFight then
			whoAfterFight = false
			ReadWho()
		end
		if afterFight then
			afterFight = false
			OwnedChanged()
		end
	end
end)

-- ---------------------------------------------------------------------------------------------
-- The data, and login
-- ---------------------------------------------------------------------------------------------
ns.dataProblems = Spec.Load(ns.WeightData)

me.On("Login", function()
	ns.DB()
	SpecNames()
	ns.ReadHitMod()
	WhoChanged()
	-- (Worked out now, out of a fight, rather than at the first question.)
	ns.Who()
	if not ns.Game.Trees() then Recheck(1) end
end)

me.On("SettingChanged", function(scope, path)
	if scope ~= ADDON then return end
	cache = {}
	if path == "bestArmor" or path == "enabled" then context = nil end
	ns.Fire("Setting", path)
end)

-- ---------------------------------------------------------------------------------------------
-- /gear
-- ---------------------------------------------------------------------------------------------
-- Stage 1, first half: says who it scores for. The second half makes the bare word open the
-- Upgrades for Sale window (Window.lua sets ns.OpenWindow).
local function Status()
	local w, why = ns.Who()
	if not w then
		if why == "noweights" then
			ns.Print(L["No stat weights for your class yet, so there is no gear advice."])
		else
			ns.Print(L["Your character isn't ready yet. Try again in a moment."])
		end
		return
	end
	ns.Print(L["Scoring gear for %s, level %d."]:format(specValues[w.spec] or w.spec, w.level))
end

local function Debug()
	local w = ns.Who()
	if w then
		local info = Spec.Info(w.class, w.spec)
		print(("spec %s.%s (%s), level %d; weights: %s, confidence %s%s"):format(w.class, w.spec, tostring(w.how), w.level,
			tostring(info.source), tostring(info.confidence),
			info.sourcePath and (", " .. info.sourcePath .. " @ " .. tostring(info.sourceCommit):sub(1, 10)) or ""))
	end
	-- The hit cap, as Compare.lua counts it.
	local ctx = ns.Context()
	if ctx and ctx.hit then
		local h = ctx.hit
		print(("hit: %s %.2f%% of %d (%.2f%% not from gear), spell %.2f%% of %d (%.2f%% not from gear)%s"):format(
			h.ranged and "ranged" or "melee", h.have.HIT, h.cap.HIT, h.mod.HIT, h.have.SPELL_HIT, h.cap.SPELL_HIT, h.mod.SPELL_HIT,
			h.dual and ("; dual wielding: from %d%% to %d%% hit counts for %d%% of its weight"):format(h.cap.HIT, h.cap.DUAL,
				Compare.DUAL_SHARE * 100) or ""))
	elseif ctx then
		print("hit: this spec's weights do not value hit, so no cap is worked out")
	end
	if ns.Overlap then
		for _, surface in ipairs({ "bags", "tips" }) do
			print(("other addons on %s: %s"):format(surface, ns.Overlap.Describe(surface)))
		end
	end
	if not ns.Game.Trees() then print("talent trees: not readable right now (the spec above was found without them)") end
	print(("character: %s, realm name %s, realm number %s, faction %s; saved under its GUID: %s"):format(
		tostring(ns.Game.Name()), ns.Game.Realm() and ("\"" .. ns.Game.Realm() .. "\"") or "not given by the game",
		tostring(ns.Game.RealmID()), tostring(ns.Game.Faction()), ns.Char() and "yes" or "no"))
	for _, problem in ipairs(ns.dataProblems) do print("weights: " .. problem) end
	local unknown = {}
	for key, n in pairs(Stats.unknown) do unknown[#unknown + 1] = key .. " x" .. n end
	table.sort(unknown)
	print("item records kept: " .. Stats.Cached() .. "; stat keys with no mapping: " .. (#unknown > 0 and table.concat(unknown, ", ") or "none"))
	-- The last item a verdict was asked for (hover one, then type /gear debug): its key, what
	-- the stat call gave, and how many effect lines its tooltip data has.
	local seen = ns.lastSeen
	if seen then
		local names = {}
		for key, value in pairs(seen.stats) do names[#names + 1] = ("%s %.4g"):format(key, value) end
		table.sort(names)
		local n = Stats.Uncounted(seen)
		local e = seen.effects
		print(("last item: %s; key %s; stats: %s"):format(tostring(seen.name), tostring(seen.key), #names > 0 and table.concat(names, ", ") or "none"))
		print(e and ("its tooltip: %d equip, %d use, %d proc effect lines; bonuses the stat call gave: %d; effects not counted: %d"):format(
			e.equip, e.use, e.proc, seen.counted or 0, n) or "its tooltip: the game gave no effect line types")
		local fields = ns.Game.ItemEffectFields and ns.Game.ItemEffectFields(seen.link)
		if fields and #fields > 0 then print("fields on its effect lines: " .. table.concat(fields, ", ")) end
	end
	-- What our own code cost in the last minute, and what the window's job is doing.
	for _, line in ipairs(Perf.Lines()) do print(line) end
	if ns.Window and ns.Window.Debug then
		for _, line in ipairs(ns.Window.Debug()) do print(line) end
	end
	-- What searches corrected since the list was read (Check.lua).
	if ns.Check and ns.Check.Debug then
		for _, line in ipairs(ns.Check.Debug()) do print(line) end
	end
	-- What Market.lua saw of the Auction House's list: events, rows read, rows skipped and why.
	if ns.Market and ns.Market.Debug then
		for _, line in ipairs(ns.Market.Debug()) do print(line) end
	end
end

local function Command(rest)
	rest = type(rest) == "string" and rest:lower():match("^%s*(%S*)") or ""
	if rest == "debug" then return Debug() end
	if type(ns.OpenWindow) == "function" then return ns.OpenWindow() end
	Status()
end
-- /gear, its own command; /dui gear does the same through Daylight UI.
local slashes = rawget(_G, "SlashCmdList")
if type(slashes) == "table" then
	rawset(_G, "SLASH_GLOWEYGEAR1", "/gear")
	slashes.GLOWEYGEAR = function(msg) Command(msg) end
end
pcall(function()
	me.RegisterCommand("gear", Command, L["Gear advice for your spec"])
end)

-- ---------------------------------------------------------------------------------------------
-- Options and registration
-- ---------------------------------------------------------------------------------------------
local MODES = { perGold = L["Most per Gold"], biggest = L["Biggest Gain"] }
local CORNERS = { top_left = L["Top Left"], top_right = L["Top Right"], bottom_left = L["Bottom Left"],
	bottom_right = L["Bottom Right"] }

local function Off(get) return get("enabled") == false end

-- The two surfaces that are Daylight UI's: with its tooltips or its bags switched off there is
-- nothing for the switch to act on, so it is dimmed (API.IsModuleEnabled, DUI DaylightUI\API.lua
-- :897-900; the modules register as "Tooltip" and "Bags": DaylightUI_Tooltip\Module.lua:9,
-- DaylightUI_Bags\Module.lua:5). An API without the call dims nothing.
local function ModuleOff(name)
	if type(API.IsModuleEnabled) ~= "function" then return false end
	local ok, on = pcall(API.IsModuleEnabled, name)
	return ok and on == false
end
ns.ModuleOff = ModuleOff
local function NoTooltips() return ModuleOff("Tooltip") end
local function NoBags() return ModuleOff("Bags") end

local pages = {
	{ id = "gear", label = L["Gear Advice"],
	  desc = L["Scores gear for your spec and finds the best upgrades for your gold."],
	  groups = {
		{ label = L["Gear Advice"], items = {
			{ type = "toggle", key = "enabled", label = L["Show Gear Advice"],
			  desc = L["Scores gear for your spec and compares it with what you wear and carry."] },
			{ type = "dropdown", label = L["Spec"], values = specValues, order = specOrder,
			  desc = L["Which spec to score gear for. Auto follows the talent tree you have the most points in."],
			  get = function()
				local choice = Spec.GetChoice()
				return specValues[choice] and choice or "auto"
			  end,
			  set = function(value)
				local c = ns.Char()
				if not c then return end
				c.spec = value
				WhoChanged()
			  end,
			  default = function() return "auto" end, disabled = Off },
			{ type = "slider", key = "minGain", label = L["Smallest Gain to Show"], min = 0, max = 20, step = 1,
			  desc = L["Upgrades smaller than this many percent are left out."], disabled = Off },
			{ type = "toggle", key = "bestArmor", label = L["Only My Best Armor Type"],
			  desc = L["Leaves out armor lighter than the heaviest type your class wears at your level."], disabled = Off },
		} },
		{ label = L["Upgrades for Sale"], items = {
			{ type = "slider", key = "maxPrice", label = L["Max Price per Item"], min = 0, max = 1000, step = 5,
			  desc = L["In gold. Items that cost more are never suggested. 0 means no limit."], disabled = Off },
			{ type = "dropdown", key = "mode", label = L["Best Pick"], values = MODES, order = { "perGold", "biggest" },
			  desc = L["Most per Gold: the most improvement for each gold spent. Biggest Gain: the biggest improvement within your max price."],
			  disabled = Off },
			{ type = "toggle", key = "dock", label = L["Dock to the Auction House"],
			  desc = L["The Upgrades for Sale window sits against Daylight UI's Auction House window while that is open."], disabled = Off },
			{ type = "toggle", key = "alert", label = L["Chat Alert"],
			  desc = L["One chat line when the Auction House has a better buy for a slot than last time."], disabled = Off },
		} },
		{ label = L["Quest Rewards"], items = {
			{ type = "toggle", key = "questPick", label = L["Best Reward in Chat"],
			  desc = L["When a quest lets you choose a reward, a chat line names the biggest upgrade."], disabled = Off },
			{ type = "toggle", key = "questSell", label = L["Vendor Value Hint"],
			  desc = L["With no upgrade among the rewards, names the one that sells for the most."],
			  disabled = function(get) return get("enabled") == false or get("questPick") == false end },
		} },
		{ label = L["Shows On"], items = {
			{ type = "toggle", key = "tooltips", label = L["Item Tooltips"],
			  desc = L["One row on a gear tooltip says whether the item is better than yours, and by how much."],
			  disabled = function(get) return get("enabled") == false or NoTooltips() end },
			{ type = "toggle", key = "bagMarks", label = L["Bag Slots"],
			  desc = L["A small mark on bag and bank slots that hold an upgrade."],
			  disabled = function(get) return get("enabled") == false or NoBags() end },
			{ type = "dropdown", key = "bagCorner", label = L["Bag Corner"], values = CORNERS,
			  order = { "top_left", "top_right", "bottom_left", "bottom_right" },
			  desc = L["Which corner of the slot the mark sits in."],
			  disabled = function(get) return get("enabled") == false or get("bagMarks") == false or NoBags() end },
		} },
		{ label = L["Other Addons"], items = {
			{ type = "toggle", key = "yieldBags", label = L["Leave Bag Marks to Them"],
			  desc = L["Another addon marks upgrades in your bags, and Gear Advice shows no mark of its own."],
			  disabled = function(get) return get("enabled") == false or not ns.Overlap or #ns.Overlap.Rivals("bags") == 0 end },
			{ type = "toggle", key = "yieldTips", label = L["Leave Tooltips to Them"],
			  desc = L["Another addon adds upgrade lines to tooltips, and Gear Advice adds no row of its own."],
			  disabled = function(get) return get("enabled") == false or not ns.Overlap or #ns.Overlap.Rivals("tips") == 0 end },
			{ type = "button", label = L["Ask Again"], text = L["Show"],
			  desc = L["Opens the question about addons that do the same as Gear Advice."],
			  func = function() if ns.Overlap then ns.Overlap.Show(true) end end },
		} },
		{ label = L["About the Numbers"], items = {
			{ type = "text", label = L["Stat weights are starting values, not final answers. Level 60 weights for many specs are based on the WoWSims simulator (wowsims.com); the rest, and all weights below level 60, are our own."] },
		} },
	  } },
}

-- The "Tell Me When a Newer Version Is Out" switch (Update.lua), on the first page.
if ns.UpdateGroup then table.insert(pages[1].groups, ns.UpdateGroup()) end
-- Help: Retake Tour and What's New (Guide.lua, GearGuide.lua).
if ns.Guide and ns.Guide.HelpGroup then table.insert(pages[1].groups, ns.Guide.HelpGroup()) end

local ok, err = pcall(function()
	DUI:RegisterPlugin(ADDON, {
		title = "Glowey's Gear",
		icon = "Interface\AddOns\\" .. ADDON .. "\Media\icon-glyph.png",
		needs = { 1, 12 },
		short = L["Gear"],
		color = { 0.37, 0.83, 0.55 },
		blurb = L["Gear advice for your spec, and the best upgrades for sale by improvement per gold."],
	})
	DUI:RegisterModule(ADDON, { plugin = ADDON, label = L["Gear"], defaults = DEFAULTS, options = { pages = pages } })
end)
if not ok then geterrorhandler()(err) end

ns.ok = true
