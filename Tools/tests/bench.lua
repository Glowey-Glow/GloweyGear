-- A benchmark, not a test: how much work Glowey's Gear does per frame at an Auction House the
-- size of a real one. Run by Tools/tests/bench.py; prints a table. Not part of the suite.
--
-- THE HOUSE is the owner's, from a /gear debug paste of 2026-11-20: 232,540 rows, of which
-- 147,112 are not gear and 85,406 are gear rows (57,717 read with a link, 27,689 whose item never
-- loaded), 16,159 distinct gear items (2,687 plain, 13,472 rolled), and tens of thousands of
-- list and item-data events.
--
-- THE GAME is the stand-in world of mocks.lua with a price on every call, because the real
-- client's calls are not free. The prices are ASSUMPTIONS (nobody measured this client), set
-- on the high side of what such calls cost on the mainline family:
--   item kind (instant)      0.002 ms      item info, cached       0.008 ms
--   item info, not cached    0.030 ms      (and it makes the game load the item, as the real
--                                           call does: an item-data event follows)
--   item stats               0.025 ms      unique check            0.003 ms
--   "is it cached"           0.001 ms      ask to load an item     0.005 ms
--   tooltip effect lines     0.150 ms      a replicate row         0.006 ms
--   a replicate row's link   0.010 ms      the list's size         0.002 ms
--   a worn link              0.003 ms      the bags (per walk)     0.300 ms
--   setting a text           0.020 ms      dressing the window     0.500 ms (API.Skin)
-- To those is added the real time the plugin's own Lua took (os.clock), so a frame's figure is
-- "game calls at the assumed prices + our own code as measured here" (lupa's Lua 5.1 on this
-- machine; the game's own Lua is of the same family and speed).
-- The game answers at most 40 item loads a frame (2,000 a second), each 0.2 to 3 s after it
-- was asked for; one item in ten that needs loading never arrives.
--
-- luacheck: globals NS WORLD T T_ident ADDON_ROOT BENCH_OLD
-- luacheck: ignore 111 112 113 121 122 211 212 213 311 411 421 431 432 542

setmetatable(_G, nil)   -- (a benchmark: the plugin may read any global the game would have)
-- (A fine clock from bench.py: os.clock ticks in whole milliseconds on Windows.)
local NOW = BENCH_CLOCK or os.clock
local w = T.world()
local real0 = NOW()
local function charge(ms) w.spent = w.spent + ms end
NS.Game.Clock = function() return w.time * 1000 + w.spent + (NOW() - real0) * 1000 end

-- ---- the item cache, and the game loading items ------------------------------------------------
local cached, kind, asked, due = {}, {}, {}, {}
local counts = {}
local function count(name, n) counts[name] = (counts[name] or 0) + (n or 1) end
local function idOf(link) return type(link) == "number" and link or tonumber(tostring(link):match("item:(%d+)")) end
local function request(id)
	if cached[id] or asked[id] then return end
	asked[id] = true
	count("loads asked")
	if kind[id] == "late" then
		due[#due + 1] = { at = w.time + 0.2 + (id * 7919 % 2800) / 1000, id = id }
	end
end

local G = NS.Game
local base = { ItemInstant = G.ItemInstant, ItemInfo = G.ItemInfo, ItemStats = G.ItemStats, ItemUnique = G.ItemUnique,
	WornLink = G.WornLink, BagLinks = G.BagLinks, ItemEffects = G.ItemEffects }
G.ItemInstant = function(link) charge(0.002); count("ItemInstant"); return base.ItemInstant(link) end
G.ItemInfo = function(link)
	count("ItemInfo")
	local id = idOf(link)
	if id and not cached[id] then
		charge(0.030)
		request(id)
		return nil
	end
	charge(0.008)
	return base.ItemInfo(link)
end
G.ItemStats = function(link)
	count("ItemStats")
	local id = idOf(link)
	if id and not cached[id] then charge(0.010) return nil end
	charge(0.025)
	return base.ItemStats(link)
end
G.ItemUnique = function(link) charge(0.003); return base.ItemUnique(link) end
G.ItemCached = function(link) charge(0.001); count("ItemCached"); local id = idOf(link); return id ~= nil and cached[id] == true end
G.RequestItem = function(id) charge(0.005); count("RequestItem"); request(id) end
G.ItemEffects = function(link) charge(0.150); count("ItemEffects"); return 0, 0, 0 end
G.WornLink = function(slot) charge(0.003); return base.WornLink(slot) end
G.BagLinks = function(out) charge(0.300); count("context builds"); return base.BagLinks(out) end
G.Time = function() return w.time end

-- ---- Daylight UI's pieces the window is built from --------------------------------------------
local function text(parent)
	local t = w.widget(parent)
	local set = t.SetText
	t.SetText = function(self, value) charge(0.020); count("texts set"); return set(self, value) end
	t.GetStringHeight = function() return 13 end
	t.GetStringWidth = function(self) return #(tostring(self.words or "")) * 6 end
	return t
end
local API = w.DUI.API
API.Skin = function() charge(0.500); count("skins") end
API.Text = function(parent) return text(parent) end
API.Button = function(parent)
	local b = w.widget(parent)
	b.text = text(b)
	b.FitWidth = function() end
	return b
end
API.Close = function(parent) return w.widget(parent) end
API.Colors = function() return {} end
API.Accent = function() return 1, 1, 1 end
API.Media = function() return "x" end
rawset(_G, "UIParent", w.widget())
rawset(_G, "GameTooltip", w.widget())
rawset(_G, "C_Item", { GetItemIconByID = function() return 1 end })
rawset(_G, "ITEM_QUALITY_COLORS", {})
rawset(_G, "GetMoneyString", function(copper) return copper .. "c" end)
rawset(_G, "UISpecialFrames", {})
rawset(_G, "DaylightUIAuctionHouse", false)
rawset(_G, "Baganator", false)
rawset(_G, "NUM_BAG_SLOTS", 4)

-- (Which timer callbacks the time goes to, by where they were defined.)
SPENT_BY = {}
do
	local after = C_Timer.After
	C_Timer.After = function(delay, fn)
		local info = debug.getinfo(fn, "S")
		local name = info.short_src .. ":" .. info.linedefined
		return after(delay, function()
			local s0, r0 = w.spent, NOW()
			fn()
			local e = SPENT_BY[name] or { 0, 0, 0, 0 }
			local took = (w.spent - s0) + (NOW() - r0) * 1000
			e[1], e[2] = e[1] + took, e[2] + 1
			if took > e[3] then e[3], e[4] = took, w.time end
			SPENT_BY[name] = e
		end)
	end
end
w.load("Marks.lua")
w.load("Market.lua")
w.load("Window.lua")
local Window, Market, Stats = NS.Window, NS.Market, NS.Stats
SEG = {}
local function seg(tbl, name, label)
	local fn = tbl and tbl[name]
	if not fn then return end
	tbl[name] = function(...)
		local s0, r0 = w.spent, NOW()
		local a, b, c = fn(...)
		local e = SEG[label] or { 0, 0 }
		e[1], e[2] = e[1] + (w.spent - s0) + (NOW() - r0) * 1000, e[2] + 1
		SEG[label] = e
		return a, b, c
	end
end
seg(NS.Market, "Feed", "Market.Feed"); seg(NS.Market, "State", "Market.State"); seg(NS.Market, "Saved", "Market.Saved")
seg(NS, "Context", "ns.Context"); seg(NS.Perf, "Time", "Perf.Time"); seg(NS.Stats, "Read", "Stats.Read"); seg(NS.Compare, "Evaluate", "Compare.Evaluate")
seg(NS.Stats, "Key", "Stats.Key"); seg(NS.Rank, "Arrange", "Rank.Arrange")

-- ---- the house ---------------------------------------------------------------------------------
local SLOTS = {
	{ "INVTYPE_HEAD", 4, 1 }, { "INVTYPE_HEAD", 4, 2 }, { "INVTYPE_HEAD", 4, 3 }, { "INVTYPE_HEAD", 4, 4 },
	{ "INVTYPE_CHEST", 4, 1 }, { "INVTYPE_CHEST", 4, 2 }, { "INVTYPE_CHEST", 4, 3 }, { "INVTYPE_CHEST", 4, 4 },
	{ "INVTYPE_LEGS", 4, 1 }, { "INVTYPE_LEGS", 4, 2 }, { "INVTYPE_LEGS", 4, 3 }, { "INVTYPE_LEGS", 4, 4 },
	{ "INVTYPE_FEET", 4, 2 }, { "INVTYPE_HAND", 4, 3 }, { "INVTYPE_WAIST", 4, 1 }, { "INVTYPE_WRIST", 4, 2 },
	{ "INVTYPE_SHOULDER", 4, 3 }, { "INVTYPE_CLOAK", 4, 1 }, { "INVTYPE_FINGER", 4, 0 }, { "INVTYPE_NECK", 4, 0 },
	{ "INVTYPE_TRINKET", 4, 0 }, { "INVTYPE_SHIELD", 4, 6 }, { "INVTYPE_HOLDABLE", 4, 0 },
	{ "INVTYPE_WEAPON", 2, 7 }, { "INVTYPE_WEAPON", 2, 4 }, { "INVTYPE_WEAPON", 2, 0 }, { "INVTYPE_WEAPON", 2, 15 },
	{ "INVTYPE_2HWEAPON", 2, 8 }, { "INVTYPE_2HWEAPON", 2, 10 }, { "INVTYPE_2HWEAPON", 2, 1 },
	{ "INVTYPE_RANGED", 2, 2 }, { "INVTYPE_RANGEDRIGHT", 2, 19 },
}
local STATS = { "ITEM_MOD_STRENGTH_SHORT", "ITEM_MOD_AGILITY_SHORT", "ITEM_MOD_STAMINA_SHORT", "ITEM_MOD_INTELLECT_SHORT",
	"ITEM_MOD_SPIRIT_SHORT", "ITEM_MOD_CRIT_RATING_SHORT", "ITEM_MOD_ATTACK_POWER_SHORT", "ITEM_MOD_SPELL_POWER_SHORT" }
local DISTINCT, PLAIN = 16159, 2687
local links, gearIDs = {}, {}
do
	local id, n = 30000, 0
	while n < DISTINCT do
		id = id + 1
		local slot = SLOTS[id % #SLOTS + 1]
		local level = 1 + (id * 37) % 60
		local rolls = n < PLAIN and 1 or 6
		gearIDs[#gearIDs + 1] = id
		-- a third of the items need loading at the scan; a tenth of those never arrive
		if id % 3 == 0 then kind[id] = (id % 30 == 0) and "never" or "late" else cached[id] = true end
		-- (the game knows every item by its bare ID too, whatever rolls are for sale)
		if rolls > 1 then T.item({ id = id, name = "Item " .. id, equipLoc = slot[1], classID = slot[2], subclassID = slot[3], minLevel = level }) end
		for r = 1, rolls do
			if n >= DISTINCT then break end
			n = n + 1
			local raw = { RESISTANCE0_NAME = slot[2] == 4 and level * 3 or nil,
				ITEM_MOD_DAMAGE_PER_SECOND_SHORT = slot[2] == 2 and (level * 0.6 + r) or nil }
			raw[STATS[(id + r) % #STATS + 1]] = 2 + (level * (3 + r)) % 23
			raw[STATS[(id + 3 * r) % #STATS + 1]] = 1 + (level + r) % 17
			links[n] = T.item({ id = id, roll = rolls > 1 and (12700 + r) or nil, name = "Item " .. id .. " " .. r,
				equipLoc = slot[1], classID = slot[2], subclassID = slot[3], minLevel = level, linkLevel = 33, raw = raw })
		end
	end
end
for id = 1, 400 do T.item({ id = id, equipLoc = "", classID = 7 }) cached[id] = true end

local ah = w.ah
local ROWS, GEAR_ROWS = 232540, 85406
local rowItem, rowLink, rowPrice = {}, {}, {}
do
	local every = ROWS / GEAR_ROWS
	local g, nextGear = 0, 0
	for i = 0, ROWS - 1 do
		if i >= nextGear and g < GEAR_ROWS then
			g = g + 1
			nextGear = nextGear + every
			local link = links[(g * 7) % DISTINCT + 1]
			rowItem[i], rowLink[i], rowPrice[i] = idOf(link), link, 500 + (g * 131) % 900000
		else
			rowItem[i], rowPrice[i] = i % 400 + 1, 100 + i % 5000
		end
	end
end
local listRows = 0
rawset(_G, "C_AuctionHouse", {
	GetNumReplicateItems = function() charge(0.002) return listRows end,
	GetReplicateItemInfo = function(index)
		charge(0.006)
		count("replicate rows")
		local id = rowItem[index]
		if not id or index >= listRows then return nil, nil, 0, -1, false, 0, nil, 0, 0, 0, 0, nil, nil, nil, nil, 0, 0, false end
		local known = cached[id] == true
		return known and "Item" or "", nil, 1, 2, true, 1, nil, 0, 0, rowPrice[index], 0, nil, nil, nil, nil, 0, id, known
	end,
	GetReplicateItemLink = function(index)
		charge(0.010)
		count("replicate links")
		local id = rowItem[index]
		if not id or not cached[id] then return nil end
		return rowLink[index] or ("|cffffffff|Hitem:" .. id .. "::::::::33:1489:::::::|h[Junk]|h|r")
	end,
	ReplicateItems = function() end,
	IsThrottledMessageSystemReady = function() return true end,
})

-- ---- frames, and what each cost -----------------------------------------------------------------
local frames = {}
local function frame()
	real0 = NOW()
	local arrived = 0
	w.spent = 0
	if #due > 0 then
		local rest = {}
		for _, d in ipairs(due) do
			if d.at <= w.time and arrived < 40 then
				arrived = arrived + 1
				cached[d.id] = true
				count("item events", 2)
				w.fire("GET_ITEM_INFO_RECEIVED", d.id, true)
				w.fire("ITEM_DATA_LOAD_RESULT", d.id, true)
			else
				rest[#rest + 1] = d
			end
		end
		due = rest
	end
	local before = w.spent
	w.frames(1)            -- (sets w.spent to 0, runs the timers that are due)
	local mid = w.spent + (NOW() - real0) * 1000
	w.update()
	local ms = before + w.spent + (NOW() - real0) * 1000
	PROBE = PROBE or { timers = 0, update = 0, n = 0 }
	PROBE.timers, PROBE.update, PROBE.n = PROBE.timers + mid, PROBE.update + (ms - before - mid), PROBE.n + 1
	frames[#frames + 1] = ms
	return ms
end

local report = {}
local BENCH_DETAIL = BENCH_DETAIL == true   -- (bench.py --detail: where the time went, by timer and by part)
local function measure(name, seconds, stop, each)
	frames, counts = {}, {}
	collectgarbage("collect")
	local n = math.ceil(seconds / 0.02)
	local ran = 0
	for i = 1, n do
		if each then each(i) end
		frame()
		ran = i
		if stop and i % 25 == 0 and stop() then break end
	end
	local total, worst, over4, over16, busy = 0, 0, 0, 0, 0
	for _, ms in ipairs(frames) do
		total = total + ms
		if ms > worst then worst = ms end
		if ms > 4.5 then over4 = over4 + 1 end
		if ms > 16 then over16 = over16 + 1 end
		if ms > 0.05 then busy = busy + 1 end
	end
	local line = ("%-34s %6.1f s  %7d frames busy  total %8.0f ms  worst frame %7.1f ms  >4.5 ms: %5d  >16 ms: %5d"):format(
		name, ran * 0.02, busy, total, worst, over4, over16)
	local extra = {}
	for _, key in ipairs({ "context builds", "skins", "texts set", "ItemInfo", "ItemStats", "ItemCached", "RequestItem",
		"loads asked", "item events", "replicate rows", "replicate links", "ItemEffects" }) do
		if counts[key] then extra[#extra + 1] = key .. " " .. counts[key] end
	end
	report[#report + 1] = line
	report[#report + 1] = "      " .. table.concat(extra, ", ")
	for where, e in pairs(SPENT_BY) do
		if BENCH_DETAIL and e[1] > 5 then report[#report + 1] = ("      timer %s: %.0f ms in %d calls (%.2f each; dearest %.1f at %.1f s)"):format(where, e[1], e[2], e[1] / e[2], e[3], e[4]) end
	end
	for where, e in pairs(SEG) do if BENCH_DETAIL and e[1] > 5 then report[#report + 1] = ("      part %s: %.0f ms in %d calls"):format(where, e[1], e[2]) end end
	for k in pairs(SPENT_BY) do SPENT_BY[k] = nil end
	for k in pairs(SEG) do SEG[k] = nil end
	if BENCH_DETAIL then
		table.sort(frames, function(a, b) return a > b end)
		local top = {}
		for i = 1, math.min(8, #frames) do top[i] = ("%.1f"):format(frames[i]) end
		report[#report + 1] = "      dearest frames: " .. table.concat(top, " ") .. "; median busy frame " .. ("%.1f"):format(frames[math.max(1, math.floor(busy / 2))] or 0)
	end
	return total, worst
end

local function character(class, level, trees, wornLevel)
	WORLD.class, WORLD.level, WORLD.trees = class, level, trees
	WORLD.worn, WORLD.bags = {}, {}
	local slots = { [1] = "INVTYPE_HEAD", [2] = "INVTYPE_NECK", [3] = "INVTYPE_SHOULDER", [5] = "INVTYPE_CHEST", [6] = "INVTYPE_WAIST",
		[7] = "INVTYPE_LEGS", [8] = "INVTYPE_FEET", [9] = "INVTYPE_WRIST", [10] = "INVTYPE_HAND", [11] = "INVTYPE_FINGER",
		[13] = "INVTYPE_TRINKET", [15] = "INVTYPE_CLOAK" }
	local n = 900000
	for slot, loc in pairs(slots) do
		n = n + 1
		cached[n] = true
		WORLD.worn[slot] = T.item({ id = n, equipLoc = loc, classID = 4, subclassID = 0,
			raw = { ITEM_MOD_STAMINA_SHORT = wornLevel, ITEM_MOD_STRENGTH_SHORT = wornLevel, ITEM_MOD_INTELLECT_SHORT = wornLevel } })
	end
	for i = 1, 20 do
		n = n + 1
		cached[n] = true
		WORLD.bags[i] = T.item({ id = n, equipLoc = "INVTYPE_HEAD", classID = 4, subclassID = 1, raw = { ITEM_MOD_STAMINA_SHORT = i } })
	end
	DaylightGearDB.chars = {}
	w.dui("Login")
end

local function job() return Window.S.job end
local function scoringDone()
	local j = job()
	if not j or Window.S.running or Window.S.stale then return false end
	return true
end
local function jobLine()
	local j = job()
	if not j then return "      no job" end
	local parked = j.nParked or j.pending or 0
	return ("      job: %d in the queue, %d looked at, %d upgrades, %d waiting for data, %s given up; running: %s; item records kept %d; Lua memory %.1f MB"):format(
		j.n or 0, j.seen or 0, #j.rows, parked, tostring(j.gaveUp or "n/a"), tostring(Window.S.running), Stats.Cached(),
		collectgarbage("count") / 1024)
end

-- ================================================================================================
-- 1. The level 33 Enhancement shaman at Daylight UI's Auction House, as in the owner's report
-- ================================================================================================
local SHAMAN = { { name = "Elemental", spent = 0 }, { name = "Enhancement", spent = 24 }, { name = "Restoration", spent = 0 } }
character("SHAMAN", 33, SHAMAN, 12)
ah.open = true
w.fire("AUCTION_HOUSE_SHOW")
if not Window.Open() and not Window.frame then error("the window could not be built on the stand-in") end

-- 1a. Daylight UI's Full scan: the list arrives, and the game echoes the event for every item
--     it loads (97,376 of them in the owner's run).
listRows = ROWS
w.fire("REPLICATE_ITEM_LIST_UPDATE")
measure("1a. the scan is read (window up)", 240, function() return Market.State() ~= "reading" and scoringDone() end,
	function(i)
		-- Daylight UI's own reader loads items too: the list event echoes for each, 40 a frame
		if i < 2400 then
			for _ = 1, 40 do w.fire("REPLICATE_ITEM_LIST_UPDATE") end
			count("list events", 40)
		end
	end)
report[#report + 1] = ("      market: %s; saved items %d"):format(tostring(Market.State()), Market.List() and #Market.List().links or 0)
report[#report + 1] = jobLine()
do
	local e = DaylightGearDB.houses[Market.House()]
	local bytes = 0
	for _, s in ipairs(e and e.items or {}) do bytes = bytes + #s + 17 end   -- (17: a Lua string's own header, about)
	report[#report + 1] = ("      saved list: %d strings, about %.0f KB in memory, %.0f KB in the saved-variables file"):format(
		e and #e.items or 0, bytes / 1024, (bytes - 17 * (e and #e.items or 0) + 4 * (e and #e.items or 0)) / 1024)
end

-- 1b. Item-data events keep coming for items that are nothing of ours (Daylight UI browsing):
--     5,000 over five seconds, the window still up.
measure("1b. a flood of 5,000 item events", 8, nil, function(i)
	if i <= 250 then
		for k = 1, 20 do w.fire("GET_ITEM_INFO_RECEIVED", 700000 + i * 20 + k, true) end
		count("item events", 20)
	end
end)
report[#report + 1] = jobLine()

-- 1c. Next session: the saved list, nothing cached, the window opens at the Auction House.
Stats.Forget()
for _, id in ipairs(gearIDs) do
	asked[id] = nil
	if kind[id] then cached[id] = nil end
	-- (a new session: two items in three are not in the client's cache any more, and one in
	-- seventeen never comes back at all)
	if not kind[id] and id % 3 ~= 1 then kind[id], cached[id] = "late", nil end
	if id % 17 == 0 then kind[id], cached[id] = "never", nil end
end
due = {}
listRows = 0
Window.S.job, Window.S.sig = nil, nil
Window.Refresh(true)
collectgarbage("collect")
local memBefore = collectgarbage("count")
measure("1c. a new session, cold cache", 120, scoringDone)
report[#report + 1] = jobLine()
collectgarbage("collect")
report[#report + 1] = ("      the job and the records it kept: about %.0f KB of Lua memory"):format(collectgarbage("count") - memBefore)

-- 1d. The same with the window folded away: nothing should run.
Stats.Forget()
for _, id in ipairs(gearIDs) do asked[id] = nil if kind[id] then cached[id] = nil end end
due = {}
Window.Close()
Window.S.job, Window.S.sig = nil, nil
if Window.Dirty then Window.Dirty(true) end
measure("1d. the window closed", 6, nil, function(i)
	if i <= 100 then for k = 1, 20 do w.fire("GET_ITEM_INFO_RECEIVED", 800000 + i * 20 + k, true) end end
end)

-- ================================================================================================
-- 2. A level 60 dual wielder and a level 14 caster on the same saved list (warm cache)
-- ================================================================================================
for _, id in ipairs(gearIDs) do if kind[id] ~= "never" then cached[id] = true end end
Stats.Forget()
character("WARRIOR", 60, { { name = "Arms", spent = 5 }, { name = "Fury", spent = 31 }, { name = "Protection", spent = 15 } }, 30)
Window.Open()
Window.S.job, Window.S.sig = nil, nil
Window.Refresh(true)
measure("2a. level 60 dual wielder, warm", 60, scoringDone)
report[#report + 1] = jobLine()
Stats.Forget()
character("MAGE", 14, { { name = "Arcane", spent = 0 }, { name = "Fire", spent = 5 }, { name = "Frost", spent = 0 } }, 4)
Window.S.job, Window.S.sig = nil, nil
Window.Refresh(true)
measure("2b. level 14 mage, warm", 60, scoringDone)
report[#report + 1] = jobLine()

-- 3. One control change at the end (Max Price), and one repaint
do
	real0 = NOW()
	w.spent = 0
	w.set("maxPrice", 20)
	report[#report + 1] = ("3.  a Max Price change: %.2f ms"):format(w.spent + (NOW() - real0) * 1000)
end

if NS.Perf and NS.Perf.Lines then
	report[#report + 1] = "    /gear debug's own counters after the run:"
	for _, line in ipairs(NS.Perf.Lines()) do report[#report + 1] = "      " .. line end
end

return table.concat(report, "\n")
