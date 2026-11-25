-- Glowey's Gear: the gear that is for sale, read from the Auction House's whole-house list.
--
--   Market.List()     -> { links = { "item:<key>", ... }, prices = { copper, ... }, at, rows, by } | nil
--                        the saved list of this character's Auction House
--   Market.Feed(job)  -> n         adds every saved listing to a Rank.Job
--   Market.Age()      -> seconds since the list was read, or nil
--   Market.State()    -> "none" | "reading", done, total | "ready"
--   Market.CanScan()  -> ok, why     why: "other" (DaylightMogul runs the house and scans it
--                        itself, or another installed addon does full scans: see
--                        Market.Others), "dui" (Daylight UI's Auction House is the one in
--                        use: its Full Scan is the way), "noapi", "closed", "busy" (ours runs)
--   Market.Scan()     -> ok, why   our own scan of the weapons and armor (Sweep.lua; our own
--                        button only, never by itself)
--   Market.Store(items, rows, startedAt, lost)   puts a finished scan of ours in place
--   Market.House()    -> the key the list is saved under
--   Market.IsOpen()   -> an Auction House is open
--   Market.Debug()    -> lines for /gear debug: what Market saw, read and skipped, and why
--   fires "MarketChanged" when a list is saved, "MarketProgress" (done, total) while reading
--   (and once with no values when a read stops without a list).
--
-- THE SOURCE. The game keeps one whole-house list per client ("replicate list"): whoever calls
-- C_AuctionHouse.ReplicateItems() fills it, and every addon can read it with
--   GetNumReplicateItems()          DOC AuctionHouseDocumentation.lua:552
--   GetReplicateItemInfo(index)     DOC :626-654   returns 1 name, 3 count, 10 buyoutPrice,
--                                                   14 owner, 17 itemID, 18 hasAllInfo
--   GetReplicateItemLink(index)     DOC :658-672   nil until the item's data is there
--   event REPLICATE_ITEM_LIST_UPDATE  DOC :1491-1495
-- (DOC = Blizzard_APIDocumentationGenerated, branch forever.) None of the three readers is
-- flagged HasRestrictions and none of their returns carries a secret marker. The game's own
-- Auction House window never touches this list (no use of it anywhere in the client's UI source),
-- so nothing in the client's Lua says how long it lives. What two addons that read it do:
--   * Daylight UI 2.1.2 (DaylightUI_AuctionHouse\Replicate.lua:111-134, :177-201): index from 0, reads
--     250 rows a frame over many frames, reads a row AGAIN by the same index when its item's data
--     arrives, and throws the scan away when the Auction House closes (:297-299).
--   * Auctionator (Source_ModernAH\FullScan\Mixins\Frame.lua, ProcessBatch and its item
--     callbacks): the same: 250 rows every 0.01 s, GetReplicateItemLink(index) again from the
--     item-loaded callback, and "scan failed" on AUCTION_HOUSE_CLOSED.
-- Both rely on: the list stays readable, by stable index, for as long as the Auction House is
-- open after the event; rows without item data (hasAllInfo false) have no link yet and get one
-- once the item loads; the link is the row's own (Daylight UI builds its suffix-aware price key
-- from it, Replicate.lua:130; Auctionator its database key). Neither reads after the window
-- closes, so THAT is unproven either way. The public wiki page for ReplicateItems (read
-- 2026-11-20) adds: the event fires again for every row whose item data arrives after a
-- GetReplicateItemInfo call, about 2,000 a frame at most; `owner` is nil except on one's own
-- auctions; 15 minutes, account-wide, between two successful asks.
--
-- SO THE DESIGN IS FOR THE WORSE CASE:
--   * Reading starts at the game's own event, whoever asked for the list: during Daylight UI's
--     Full Scan, not after it. Daylight UI's "ScanEnded" (when reachable) is only a second
--     trigger for a list not read yet.
--   * The event repeats per loaded item, so it is not "a new list": a list is new when its size
--     or a handful of probe rows differ from the one last read. That also catches a list that is
--     replaced while it is being read (the read starts over).
--   * Rows are read in time slices (4 ms a frame, at most 1,000 rows), cheapest test first:
--     no buyout, not gear (the item's kind is an instant call on the itemID), the player's own
--     auction; only then the link. A gear row whose item has not loaded waits for the item.
--   * The Auction House closing: when every row has been walked, what was read is saved. Mid
--     list, the read goes on only if the game still answers with the same list (size and probe
--     rows unchanged; any blank row after that ends it); otherwise it stops and the saved list
--     stays as it was. /gear debug says which of the two this client does.
--   * Our own ask (Market.Scan) exists only while Daylight UI's Auction House is not the one in
--     use, and at most once in 15 minutes per house (the wiki's figure; Daylight UI assumes the
--     same 900 s and calls it a guess, Scan.lua:26; Auctionator uses 15 minutes too; the client
--     documents none).
--
-- luacheck: read globals C_AuctionHouse CreateFrame C_Timer UnitName
-- luacheck: read globals GetServerTime issecretvalue geterrorhandler time C_AddOns UnitGUID IsLoggedIn

local _, ns = ...
if ns.off or not ns.ok then return end

local Market = {}
ns.Market = Market

local Game, Stats = ns.Game, ns.Stats
local secret = issecretvalue

-- Every figure in one place.
local TUNE = {
	BUDGET_MS = 3,        -- reading time in one frame (the rest of a 4 ms frame is left for what else we do)
	ROWS_A_FRAME = 1000,  -- and never more rows than this (the game answers about 2,000 item loads a frame)
	CLOCK_EVERY = 8,      -- rows between looks at the clock, at most (the read adapts it down: see pump)
	ASKS_A_FRAME = 20,    -- item loads asked of the game in one frame, at most
	TAIL_MS = 1.5,        -- the tail's time in one frame (rows still without a link after the list is saved)
	TAIL_PAUSE = 2,       -- seconds between two passes of the tail
	TAIL_IDLE = 5,        -- passes in a row with nothing new before the tail gives up
	TAIL_MAX_S = 600,     -- and it never works longer than this after a list was saved
	INDEX_MS = 2,         -- time in one frame for indexing a saved list
	CHECK_MS = 1000,      -- how often, at most, a running read looks whether the list was replaced
	ITEM_TRIES = 3,       -- times an item is asked for before its rows are given up
	LOOK = 0.25,          -- seconds between looks while the list settles or items load
	SETTLE_MS = 2000,     -- the list must hold still this long before it counts as whole
	EMPTY_MS = 15000,     -- an empty list gets this long to fill
	ITEM_MS = 15000,      -- no item arriving for this long ends the wait for items
	ITEM_MAX_MS = 300000, -- and the wait never lasts longer than this after the last row was walked
	KEEP_DAYS = 30,       -- a house not read for this long is dropped at login
}
Market.TUNE = TUNE

local function plain(v)
	if v == nil or (secret and secret(v)) then return nil end
	return v
end

local function Now()
	local ok, t = pcall(GetServerTime)
	if ok and type(plain(t)) == "number" then return t end
	return type(time) == "function" and time() or 0
end

local function AH()
	local a = C_AuctionHouse
	if type(a) ~= "table" or type(a.GetNumReplicateItems) ~= "function"
		or type(a.GetReplicateItemInfo) ~= "function" or type(a.GetReplicateItemLink) ~= "function" then
		return nil
	end
	return a
end

-- ---------------------------------------------------------------------------------------------
-- Daylight UI's Auction House (internals: each behind one function, nil when not as read)
-- ---------------------------------------------------------------------------------------------
-- The module's table whether or not its window is the one in use:
-- DaylightUI:GetModule("AuctionHouse") (DaylightUI\Core.lua:721), registered with ns = ns
-- (DaylightUI_AuctionHouse\Module.lua:5-8), .enabled once it runs (DaylightUI\Core.lua:773).
local function DuiModule()
	local D = ns.DUI
	if type(D) ~= "table" or type(D.GetModule) ~= "function" then return nil end
	local ok, mod = pcall(D.GetModule, D, "AuctionHouse")
	if not ok or type(mod) ~= "table" or mod.enabled ~= true or type(mod.ns) ~= "table" then return nil end
	return mod.ns
end

-- Daylight UI's Auction House when it is the one in use, else nil: not when DaylightMogul owns
-- the house (DaylightUI.ahMogul, Module.lua:18), and not when the player keeps the game's own
-- window (the module's "enabled" setting is its window swap: Options.lua:48, Windows\Swap.lua:49;
-- read through the public API.GetSetting). While this is not nil we never ask for the list.
local function DuiAH()
	local D = ns.DUI
	if type(D) ~= "table" or D.ahMogul == true then return nil end
	local m = DuiModule()
	if not m then return nil end
	local ok, on = pcall(ns.API.GetSetting, "AuctionHouse", "enabled")
	if not ok or on ~= true then return nil end
	return m
end
Market.DuiAH = DuiAH

-- Which Auction House this is: Daylight UI's ruleset key ("US-PvE", "US-Realm Name":
-- DaylightUI_AuctionHouse\Ruleset.lua:54) when its module is there, so both name a house the
-- same way. Without it: the realm and the faction, the realm by its NUMBER (Game.RealmID: the
-- game's own realm number, or the one inside the character's GUID), because the game stopped
-- giving realm names on this client on 2026-11-20 and a key made of an empty name would file
-- every realm's list under one house. The realm's name is used only when there is no number.
-- nil when neither is known: nothing is saved rather than saved under a shared key.
local function DuiHouseKey()
	local m = DuiModule()
	local R = m and m.Ruleset
	if type(R) ~= "table" or type(R.Key) ~= "function" then return nil end
	local ok, key = pcall(R.Key)
	if ok and type(key) == "string" and key ~= "" then return key end
	return nil
end

local function ReadHouse()
	local key = DuiHouseKey()
	if key then return key end
	local faction = Game.Faction() or "Neutral"
	local id = Game.RealmID()
	if id then return "realm" .. id .. "-" .. faction end
	local realm = Game.Realm()
	if realm then return realm .. "-" .. faction end
	return nil
end

-- The key is asked for on every look at the saved list (several times a paint of the window),
-- and reading it is two protected calls into Daylight UI's module: it is kept once known, and
-- read again (Market.ForgetHouse) at login, on entering the world, when the game's rules change,
-- when an addon loads (Daylight UI's module may come later) and when the Auction House opens.
-- Not known yet (nil) is never kept.
local houseKey
function Market.House()
	if houseKey then return houseKey end
	houseKey = ReadHouse()
	return houseKey
end

function Market.ForgetHouse()
	houseKey = nil
end

-- ---------------------------------------------------------------------------------------------
-- What Market saw (for /gear debug: one run in the game answers the open questions)
-- ---------------------------------------------------------------------------------------------
local function freshRun()
	return { read = 0, gear = 0, kept = 0, skip = {}, lost = {}, rolledSuffix = 0, rolledBonus = 0, unrolled = 0 }
end
local dbg = { events = 0, eventsClosed = 0, starts = 0, restarts = 0, duiStarted = 0, duiEnded = 0, run = freshRun() }

local function skipped(run, why)
	run.skip[why] = (run.skip[why] or 0) + 1
end

-- A gear row that could not be read, and why, kept apart by cause so one /gear debug settles
-- which it is:
--   "refused"  the game said no data is coming for the item (its load event came with false)
--   "nolink"   the item arrived, as often as it was asked for, and the row still gave no link
--   "quiet"    the wait ended because nothing had arrived for ITEM_MS
--   "cap"      the wait ended at ITEM_MAX_MS after the last row was walked
--   "closed"   the Auction House closed while the row was waiting
--   "unasked"  the wait ended before the item had even been asked for
-- Such a row is not thrown away: its index goes on the job's tail list, and after the list is
-- saved the tail keeps asking for it for as long as the Auction House stays open (see Tail).
local function lose(j, itemID, index, why)
	local run = j.run
	run.lost[why] = (run.lost[why] or 0) + 1
	skipped(run, "item never loaded")
	j.lost[itemID] = true
	local n = #j.tailRows + 1
	j.tailRows[n], j.tailIDs[n] = index, itemID
end

-- ---------------------------------------------------------------------------------------------
-- The saved lists
-- ---------------------------------------------------------------------------------------------
-- One string per distinct item, cheapest listing:
--     "<Stats.Key>#<copper>#<item class>.<subclass>.<required level>.<equip location>"
--     "7444::::::::::::1:12751#70000#4.3.28.8"
-- The part after the second # is what lets a later session, or another character, drop most of
-- a house WITHOUT asking the game anything: a level 33 shaman never looks at plate, at a bow,
-- or at a level 40 mace (Rank.lua weighs these facts before any game call). The equip location
-- is a number from the list below, which must only ever grow at its end. A string with no
-- facts (an older save, or an item the game could not describe) still reads: it is simply
-- weighed the slow way. About 45 bytes an item: 16,159 items are about 0.7 MB in memory and
-- 0.6 MB in the saved-variables file. A table per item would be five times that.
local LOCS = { "INVTYPE_HEAD", "INVTYPE_NECK", "INVTYPE_SHOULDER", "INVTYPE_CHEST", "INVTYPE_ROBE", "INVTYPE_WAIST",
	"INVTYPE_LEGS", "INVTYPE_FEET", "INVTYPE_WRIST", "INVTYPE_HAND", "INVTYPE_FINGER", "INVTYPE_TRINKET", "INVTYPE_CLOAK",
	"INVTYPE_WEAPON", "INVTYPE_SHIELD", "INVTYPE_2HWEAPON", "INVTYPE_WEAPONMAINHAND", "INVTYPE_WEAPONOFFHAND",
	"INVTYPE_HOLDABLE", "INVTYPE_RANGED", "INVTYPE_RANGEDRIGHT", "INVTYPE_THROWN", "INVTYPE_RELIC" }
local LOC_CODE = {}
for code, loc in ipairs(LOCS) do LOC_CODE[loc] = code end
Market.LOCS = LOCS

-- One saved string taken apart: key, copper, classID, subclassID, minLevel, equipLoc (the last
-- four nil when the string carries no facts); nil for what is no entry.
local function Parse(text)
	local key, copper, facts = tostring(text):match("^([^#]+)#(%d+)#?(.*)$")
	copper = tonumber(copper)
	if not key or not copper or copper <= 0 then return nil end
	if facts ~= "" then
		local classID, subclassID, minLevel, code = facts:match("^(%d+)%.(%d+)%.(%d+)%.(%d+)$")
		local loc = LOCS[tonumber(code) or 0]
		if loc then return key, copper, tonumber(classID), tonumber(subclassID), tonumber(minLevel), loc end
	end
	return key, copper
end
Market.Parse = Parse

local decoded, decodedFrom   -- Market.List()'s answer and the saved entry it was made from

local function Houses()
	return ns.DB().houses
end

local function Entry(make)
	local key = Market.House()
	if not key then return nil end
	local houses = Houses()
	local e = houses[key]
	if type(e) ~= "table" then
		if not make then return nil end
		e = {}
		houses[key] = e
	end
	return e, key
end

-- The saved list of this house, as it is kept: { at, rows, by, items = { string, ... }, lost,
-- lostRows } or nil. Costs nothing: nothing is taken apart.
function Market.Saved()
	local e = Entry()
	if not e or type(e.items) ~= "table" or type(e.at) ~= "number" then return nil end
	return e
end

-- The whole list taken apart at once (the tests, small lists). The window does not use this
-- for a real house: it feeds a job a slice at a time (Market.Feed).
function Market.List()
	local e = Market.Saved()
	if not e then return nil end
	if decodedFrom == e.items then return decoded end
	local links, prices, n = {}, {}, 0
	for i = 1, #e.items do
		local key, copper = Parse(e.items[i])
		if key then
			n = n + 1
			links[n], prices[n] = "item:" .. key, copper
		end
	end
	decoded = { links = links, prices = prices, at = e.at, rows = e.rows or 0, by = e.by, lost = e.lost or 0 }
	decodedFrom = e.items
	return decoded
end

-- ---------------------------------------------------------------------------------------------
-- Corrections: what a search said since the list was read
-- ---------------------------------------------------------------------------------------------
-- The saved list is a picture of the house at the scan. Items sell, and a search made later
-- (the player's own, or a check of ours: Check.lua) says what one costs NOW, or that none is
-- left. That is kept beside the list, per key, with the server's time it was learned:
--     e.fixP[key] = copper (0: none for sale any more)      e.fixT[key] = when
-- A correction counts only while it is newer than the list itself (e.readAt, when the read of
-- the list began): a new scan replaces older corrections, never newer ones. The list's own
-- strings are not touched, so nothing has to be found and rewritten.
local function ReadAt(e) return tonumber(e.readAt) or tonumber(e.at) or 0 end

-- The correction for a key that is in force: copper (0 = gone), when; nil when there is none.
function Market.Fixed(key)
	local e = Market.Saved()
	local at = e and type(e.fixT) == "table" and e.fixT[key]
	if not at or at <= ReadAt(e) then return nil end
	return e.fixP[key], at
end

-- Takes a correction in. Returns true when it is now the one in force (it is newer than the
-- list and than any correction before it).
function Market.Fix(key, copper, at)
	local e = Market.Saved()
	if not e or type(key) ~= "string" or type(copper) ~= "number" or copper < 0 then return false end
	at = tonumber(at) or Now()
	if at <= ReadAt(e) then return false end
	if type(e.fixT) ~= "table" or type(e.fixP) ~= "table" then e.fixT, e.fixP = {}, {} end
	if e.fixT[key] and e.fixT[key] > at then return false end
	e.fixT[key], e.fixP[key] = at, math.floor(copper)
	local idx = Market.Index()
	if idx and not idx.pos[key] and not idx.extra[key] then
		-- (A key the list does not have: a new listing. Filed under its item.)
		idx.extra[key] = true
		local id = Stats.ItemID("item:" .. key)
		if id then
			idx.byItem[id] = idx.byItem[id] or {}
			idx.byItem[id][#idx.byItem[id] + 1] = key
		end
	end
	return true
end

-- How many corrections are in force, and how many of them say "none left".
function Market.FixCount()
	local e = Market.Saved()
	local n, gone = 0, 0
	local floor = e and ReadAt(e) or 0
	for key, at in pairs(e and type(e.fixT) == "table" and e.fixT or {}) do
		if at > floor then
			n = n + 1
			if e.fixP[key] == 0 then gone = gone + 1 end
		end
	end
	return n, gone
end

-- ---------------------------------------------------------------------------------------------
-- An index of the saved list: where a key is, and which keys an item has
-- ---------------------------------------------------------------------------------------------
-- Needed only when something has to be looked up by item (a search result says which rolls of
-- an item are still for sale) or by key (a row read late). Made from the read's own data when
-- a list is saved, else from the saved strings in slices of INDEX_MS a frame; "MarketIndexed"
-- says when it is there. Dropped with the list it was made for.
local listIndex, listIndexing

local function indexSome()
	local e = Market.Saved()
	local w = listIndexing
	if not w or not e or w.of ~= e.items then
		listIndexing = nil
		return
	end
	local t0 = Game.Clock()
	local items, idx = e.items, w.idx
	local pos, byItem = idx.pos, idx.byItem
	local i = w.at
	while i <= #items do
		local key, id = tostring(items[i]):match("^((%d+)[^#]*)#")
		if key then
			pos[key] = i
			id = tonumber(id)
			local keys = byItem[id]
			if not keys then
				keys = {}
				byItem[id] = keys
			end
			keys[#keys + 1] = key
		end
		i = i + 1
		if i % 25 == 0 and Game.Clock() - t0 >= TUNE.INDEX_MS then break end
	end
	w.at = i
	if i <= #items then
		ns.Perf.Time("market", Game.Clock() - t0)
		return C_Timer.After(0, indexSome)
	end
	-- (Keys that only a correction knows are part of the picture too.)
	for key, at in pairs(type(e.fixT) == "table" and e.fixT or {}) do
		if at > ReadAt(e) and not pos[key] then
			idx.extra[key] = true
			local id = tonumber(key:match("^(%d+)"))
			if id then
				byItem[id] = byItem[id] or {}
				byItem[id][#byItem[id] + 1] = key
			end
		end
	end
	listIndex, listIndexing = idx, nil
	ns.Perf.Time("market", Game.Clock() - t0)
	ns.Fire("MarketIndexed")
end

-- The listIndex of the list in place, or nil while it is being made (it is started then).
function Market.Index()
	local e = Market.Saved()
	if not e then return nil end
	if listIndex and listIndex.of == e.items then return listIndex end
	listIndex = nil
	if not listIndexing or listIndexing.of ~= e.items then
		listIndexing = { of = e.items, at = 1, idx = { of = e.items, pos = {}, byItem = {}, extra = {} } }
		C_Timer.After(0, indexSome)
	end
	return nil
end

-- The keys the list (and its corrections) hold for an item, or nil while the index is made.
function Market.KeysOf(itemID)
	local idx = Market.Index()
	if not idx then return nil end
	return idx.byItem[itemID] or {}
end

-- The list's own price for a key (not a correction's), or nil; nil too while the index is made.
function Market.ListPrice(key)
	local idx = Market.Index()
	local e = Market.Saved()
	local at = idx and idx.pos[key]
	if not at then return nil end
	local _, copper = Parse(e.items[at])
	return copper
end

-- A row read after the list was saved (the tail): put in the list when it is a new item or a
-- cheaper listing of one. Returns "new", "cheaper" or nil.
function Market.Merge(key, copper, facts)
	local e = Market.Saved()
	local idx = Market.Index()
	if not e or not idx or type(key) ~= "string" or type(copper) ~= "number" or copper <= 0 then return nil end
	local text = key .. "#" .. ("%.0f"):format(copper) .. (facts and ("#" .. facts) or "")
	local at = idx.pos[key]
	if not at then
		at = #e.items + 1
		e.items[at] = text
		idx.pos[key] = at
		local id = tonumber(key:match("^(%d+)"))
		if id then
			idx.byItem[id] = idx.byItem[id] or {}
			if not idx.extra[key] then idx.byItem[id][#idx.byItem[id] + 1] = key end
		end
		idx.extra[key] = nil
		decoded, decodedFrom = nil, nil
		return "new"
	end
	local _, was = Parse(e.items[at])
	if was and copper >= was then return nil end
	e.items[at] = text
	decoded, decodedFrom = nil, nil
	return "cheaper"
end

-- Adds saved listings to a Rank.Job, from entry `from` on, until `stop()` says the frame's time
-- is up (looked at every 25 entries; no `stop` = all of them). Returns the next entry to feed,
-- or nil when the list is through. The job drops what the character cannot use as it is added.
-- A correction in force (Market.Fixed) stands in for the list's price, or leaves the item out
-- when it says none is left; keys only a correction knows are fed after the list's own.
local fedFix = {}
function Market.Feed(job, from, stop)
	local e = Market.Saved()
	if not e or type(job) ~= "table" then return nil end
	local items = e.items
	local fixT, fixP = type(e.fixT) == "table" and e.fixT or nil, e.fixP
	local floor = ReadAt(e)
	local i = from or 1
	if i == 1 then
		for key in pairs(fedFix) do fedFix[key] = nil end
	end
	while i <= #items do
		local key, copper, classID, subclassID, minLevel, loc = Parse(items[i])
		if key then
			local at = fixT and fixT[key]
			if at and at > floor then
				fedFix[key] = true
				copper = fixP[key]
				if copper > 0 then job:Add("item:" .. key, copper, classID, subclassID, loc, minLevel, at) end
			else
				job:Add("item:" .. key, copper, classID, subclassID, loc, minLevel)
			end
		end
		i = i + 1
		if stop and i % 25 == 0 and stop() then break end
	end
	if i <= #items then return i end
	for key, at in pairs(fixT or fedFix) do
		if fixT and at > floor and not fedFix[key] and fixP[key] > 0 then
			job:Add("item:" .. key, fixP[key], nil, nil, nil, nil, at)
		end
	end
	return nil
end

function Market.Age()
	local e = Market.Saved()
	if not e then return nil end
	return math.max(0, Now() - e.at)
end

-- Houses not read (or asked) for KEEP_DAYS go; so does anything that is not a house entry.
function Market.Prune()
	local houses = Houses()
	local now = Now()
	for key, e in pairs(houses) do
		local last = type(e) == "table" and math.max(tonumber(e.at) or 0, tonumber(e.asked) or 0) or 0
		if last <= 0 or now - last > TUNE.KEEP_DAYS * 86400 then houses[key] = nil end
	end
	decoded, decodedFrom = nil, nil
end

-- ---------------------------------------------------------------------------------------------
-- Reading the list
-- ---------------------------------------------------------------------------------------------
local frame = CreateFrame("Frame")
local ITEM_EVENTS = { "ITEM_DATA_LOAD_RESULT", "GET_ITEM_INFO_RECEIVED" }
local open = false     -- the Auction House is open
local job              -- the read in progress
local asking           -- our own ask is out: { at = clock }
local lastPrint        -- the size and probe rows of the list last read to its end
local me               -- the player's name, for rows of their own

local function Count()
	local a = AH()
	if not a then return 0 end
	local ok, n = pcall(a.GetNumReplicateItems)
	n = ok and plain(n) or nil
	return type(n) == "number" and n or 0
end

-- itemID, buyout, count, owner, hasAllInfo, name of one row (index from 0); itemID nil for a
-- row the game has nothing for (yet).
local function Row(index)
	local ok, name, _, count, _, _, _, _, _, _, buyout, _, _, _, owner, _, _, itemID, hasAllInfo =
		pcall(C_AuctionHouse.GetReplicateItemInfo, index)
	if not ok then return nil end
	itemID = plain(itemID)
	if type(itemID) ~= "number" or itemID <= 0 then return nil end
	return itemID, plain(buyout), plain(count), plain(owner), plain(hasAllInfo) == true, plain(name)
end

local function Link(index)
	local ok, link = pcall(C_AuctionHouse.GetReplicateItemLink, index)
	link = ok and plain(link) or nil
	if type(link) == "string" and link ~= "" then return link end
	return nil
end

-- A few rows remembered as the list is read: enough to tell this list from the next one.
-- (Three at the start and one every 1,000 rows up to row 20,000: at most 23, however long the
-- list. A house has had 232,540 rows; a probe every 1,000 of those was 235 row reads per look.)
local function IsProbe(index)
	return index < 3 or (index % 1000 == 500 and index < 20000)
end

-- Whether the game's list is still the one these probes were taken from.
local function SameList(print)
	if not print or Count() ~= print.total then return false end
	for index, was in pairs(print.probes) do
		local itemID, buyout = Row(index)
		if itemID ~= was[1] or buyout ~= was[2] then return false end
	end
	return true
end

local schedule

local function tell(done, total)
	ns.Fire("MarketProgress", done, total)
end

local function itemEvents(on)
	for _, event in ipairs(ITEM_EVENTS) do
		if on then pcall(frame.RegisterEvent, frame, event) else pcall(frame.UnregisterEvent, frame, event) end
	end
end

local function stop(j, why)
	if job ~= j then return end
	job = nil
	itemEvents(false)
	dbg.run.ended, dbg.run.ms = why, Game.Clock() - j.began
end

-- Ends a read with nothing saved: the saved list stays as it was.
local function abort(j, why)
	if job ~= j then return end
	stop(j, why)
	tell()
end

local function newJob(by)
	local run = freshRun()
	dbg.run = run
	dbg.starts = dbg.starts + 1
	job = {
		by = by, run = run, house = Market.House(), began = Game.Clock(),
		total = Count(), next = 0,
		ready = {}, head = 1, tail = 0,           -- rows to read again (their item arrived, or they were blank)
		waiting = {}, nWaiting = 0,               -- itemID -> { index, ... } waiting for the item
		tries = {}, lost = {},                    -- itemID -> times asked; itemID -> given up
		got = {},                                 -- itemID -> a row of it was read
		tailRows = {}, tailIDs = {},              -- the rows given up, and their items (see Tail)
		startedAt = Now(),                        -- the server's time when the read began
		toAsk = {}, askHead = 1, askTail = 0,     -- item IDs to ask the game for, in order
		every = TUNE.CLOCK_EVERY,                 -- rows between looks at the clock (adapts)
		facts = {},                               -- key -> "class.subclass.level.location" (see finish)
		blank = {}, blanks = 0,
		kind = {},                                -- itemID -> true (gear) | false
		best = {}, named = {},                    -- key -> lowest buyout; key -> checked for a roll in the name only
		order = {},                               -- the keys, in the order they were first kept
		probes = {},
	}
	run.total = job.total
	itemEvents(true)
	schedule(job, 0)
	tell(0, job.total)
	return job
end

-- Which scan filled the list: ours when our ask is out, Daylight UI's when its Auction House is
-- the one in use, else some other addon's.
local function whose()
	if asking then return "own" end
	if DuiAH() then return "dui" end
	return "other"
end

local function restart(j, why)
	if job ~= j then return end
	stop(j, why)
	dbg.restarts = dbg.restarts + 1
	newJob(j.by)
end

-- A gear row whose link the game does not give yet: its item is asked for (at a measured pace:
-- pump sends ASKS_A_FRAME a frame) and the row is read again when the item arrives. An item
-- that arrived and whose row still has no link is asked for again, ITEM_TRIES times in all.
local function wait(j, itemID, index)
	local entry = j.waiting[itemID]
	if entry then
		entry[#entry + 1] = index
		return
	end
	local tries = (j.tries[itemID] or 0) + 1
	if tries > TUNE.ITEM_TRIES then return lose(j, itemID, index, "nolink") end
	j.tries[itemID] = tries
	local now = Game.Clock()
	if j.nWaiting == 0 then j.lastArrival = now end
	j.waiting[itemID] = { index }
	j.nWaiting = j.nWaiting + 1
	j.askTail = j.askTail + 1
	j.toAsk[j.askTail] = itemID
end

-- Whether a link names a roll ("... of the Bear") only in its text, with nothing in its fields
-- to tell it from the plain item: its stats could not be read back from the saved key, so such
-- a row is left out (and counted: /gear debug). Asked once per key.
local function NamedOnly(j, key, link, itemID)
	local known = j.named[key]
	if known ~= nil then return known end
	local only = false
	if not Stats.IsRolled(link) then
		local shown = link:match("|h%[(.-)%]|h")
		local base = shown and Game.ItemInfo("item:" .. itemID) or nil
		only = type(base) == "string" and shown ~= base and shown:sub(1, #base) == base
	end
	j.named[key] = only
	return only
end

local function read(j, index, again)
	local run = j.run
	local itemID, buyout, _, owner, hasAllInfo = Row(index)
	if not again then run.read = run.read + 1 end
	if not itemID then
		-- (May only not be there yet: read again while the list settles.)
		j.blank[#j.blank + 1] = index
		return
	end
	if IsProbe(index) and not j.probes[index] then j.probes[index] = { itemID, buyout } end
	if type(buyout) ~= "number" or buyout <= 0 then return skipped(run, "no buyout") end
	local gear = j.kind[itemID]
	if gear == nil then
		-- (An instant call on the itemID: no wait, no link needed.)
		local equipLoc = Game.ItemInstant(itemID)
		gear = equipLoc ~= nil and Stats.GEAR[equipLoc] == true
		j.kind[itemID] = gear
	end
	if not gear then return skipped(run, "not gear") end
	if owner ~= nil then
		run.owners = (run.owners or 0) + 1
		if owner == me then return skipped(run, "own auction") end
	end
	-- The row's LINK is all that is needed of it (the item and its roll), and the game gives a
	-- link as soon as it has the item, whatever "hasAllInfo" says. So the link is asked for
	-- first; only a row with no link waits for its item. (Waiting on hasAllInfo alone lost a
	-- third of the gear rows of a real house: 27,689 of 85,406.)
	local link = Link(index)
	if not link then
		if hasAllInfo then return skipped(run, "no link") end
		if j.failed and j.failed[itemID] then return lose(j, itemID, index, "refused") end
		return wait(j, itemID, index)
	end
	if Stats.ItemID(link) ~= itemID then return skipped(run, "no link") end
	local key = Stats.Key(link)
	if not key then return skipped(run, "bad link") end
	if NamedOnly(j, key, link, itemID) then
		run.namedOnly = run.namedOnly or link
		return skipped(run, "roll only in the name")
	end
	run.gear = run.gear + 1
	j.got[itemID] = true
	local was = j.best[key]
	if not was then
		run.kept = run.kept + 1
		-- (What the links look like, counted per distinct item: field 7 a suffix, field 13 bonus IDs.)
		local body = key .. ":::::::::::::"
		local n, suffix, bonus = 0, nil, nil
		for field in body:gmatch("([^:]*):") do
			n = n + 1
			if n == 7 then suffix = field elseif n == 13 then bonus = field end
		end
		if suffix ~= "" and suffix ~= "0" then
			run.rolledSuffix = run.rolledSuffix + 1
			run.sample = run.sample or link
		elseif bonus ~= "" and bonus ~= "0" then
			run.rolledBonus = run.rolledBonus + 1
			run.sample = run.sample or link
		else
			run.unrolled = run.unrolled + 1
		end
	end
	if not was or buyout < was then j.best[key] = buyout end
	-- What can be known of the item without loading it again, kept with it (see finish): its
	-- item class, subclass, required level and equip location. The first two and the last are
	-- an instant call on the item ID; the level is in the item's data, which the game has now.
	if not was then
		j.order[#j.order + 1] = key
		local equipLoc, classID, subclassID = Game.ItemInstant(itemID)
		local code = equipLoc and LOC_CODE[equipLoc]
		if code and type(classID) == "number" and type(subclassID) == "number" then
			local _, _, minLevel = Game.ItemInfo(link)
			j.facts[key] = ("%d.%d.%d.%d"):format(classID, subclassID, tonumber(minLevel) or 0, code)
		end
	end
end

-- The list is whole: saved for this house, cheapest listing per item.
local function finish(j)
	if job ~= j then return end
	local house = Market.House()
	if not house or house ~= j.house then return abort(j, "the house changed") end
	if j.total <= 0 then
		lastPrint = { total = 0, probes = {} }
		return abort(j, "the list stayed empty")
	end
	-- The strings are made over the next frames (save, below): a house of 16,159 items is too
	-- much string work for one. Until then the job stays, and State() says "reading".
	j.saving = { at = 0, items = {} }
	schedule(j, 0)
end

-- One slice of the saving: strings for the next items, in the order they were first read (no
-- sort: nothing depends on the order, and sorting 16,000 strings is a frame lost). Then, when
-- all are made, the list is put in place in one step.
local function save(j, t0)
	local sv = j.saving
	local order, items = j.order, sv.items
	local i = sv.at
	while i < #order do
		i = i + 1
		local key = order[i]
		local facts = j.facts[key]
		-- (%.0f, not %d: stock Lua 5.1's %d stops at 2^31 copper, 214,748 gold.)
		items[i] = key .. "#" .. ("%.0f"):format(j.best[key]) .. (facts and ("#" .. facts) or "")
		if i % 50 == 0 and Game.Clock() - t0 >= TUNE.BUDGET_MS then break end
	end
	sv.at = i
	if i < #order then return schedule(j, 0) end
	local house = Market.House()
	if not house or house ~= j.house then return abort(j, "the house changed") end
	-- (An item counts as not read when NO row of it could be read.)
	local lost = 0
	j.counted = {}
	for itemID in pairs(j.lost) do
		if not j.got[itemID] then
			lost = lost + 1
			j.counted[itemID] = true
		end
	end
	local e = Entry(true)
	e.at, e.rows, e.by, e.items = Now(), j.total, j.by, items
	-- (How many gear items for sale could not be read, so the window can say so.)
	e.lost, e.lostRows = lost, j.run.skip["item never loaded"] or 0
	-- When the read BEGAN: a price corrected by a search after that moment is newer than what
	-- this list says and is kept; one corrected before it is older and goes (Market.Fix).
	e.readAt = j.startedAt
	for key, at in pairs(type(e.fixT) == "table" and e.fixT or {}) do
		if at <= e.readAt then e.fixT[key], e.fixP[key] = nil, nil end
	end
	decoded, decodedFrom = nil, nil
	-- (The index of the new list is made when first asked for, in slices: making it here, in
	-- the frame that puts the list in place, was a frame of 7.9 ms for 15,620 items.)
	lastPrint = { total = j.total, probes = j.probes }
	stop(j, j.afterClose and "saved (finished after the Auction House closed)" or "saved")
	ns.Fire("MarketChanged")
	-- Rows that never gave a link: asked for again, in the background, while the house is open.
	if #j.tailRows > 0 and open and not j.afterClose then Market.StartTail(j) end
end

local function giveUpWaiting(j, why)
	-- (Items whose ask never went out are told apart from those that got no answer.)
	local unasked = {}
	for i = j.askHead, j.askTail do
		if j.toAsk[i] then unasked[j.toAsk[i]] = true end
	end
	for itemID, entry in pairs(j.waiting) do
		j.waiting[itemID] = nil
		for i = 1, #entry do lose(j, itemID, entry[i], unasked[itemID] and "unasked" or why) end
	end
	j.nWaiting = 0
	j.toAsk, j.askHead, j.askTail = {}, 1, 0
end

local pumpNow

local function pump(j)
	j.scheduled = false
	if job ~= j then return end
	local t0 = Game.Clock()
	pumpNow(j, t0)
	ns.Perf.Time("market", Game.Clock() - t0)
end

pumpNow = function(j, t0)
	if j.saving then return save(j, t0) end
	-- The Auction House closed: see the top of this file.
	if j.closed and not j.afterClose then
		local walked = j.next >= j.total and j.head > j.tail
		if walked and #j.blank == 0 then
			giveUpWaiting(j, "closed")
			return finish(j)
		end
		if not SameList({ total = j.total, probes = j.probes }) then return abort(j, "the Auction House closed") end
		j.afterClose = true
	end
	-- (The list event comes once per item the game loads, tens of thousands of times in a scan:
	-- whether the list was REPLACED is looked at once a second at most, not once per event.)
	if j.check and t0 - (j.checkedAt or 0) >= TUNE.CHECK_MS then
		j.check, j.checkedAt = false, t0
		local size = Count()
		if size < j.total or not SameList({ total = size, probes = j.probes }) then
			if j.afterClose then return abort(j, "the Auction House closed") end
			return restart(j, "the list was replaced")
		end
		if size > j.total then j.total, j.stillAt = size, nil end
	end

	-- Item loads asked for at a measured pace, oldest first.
	local sent = 0
	while sent < TUNE.ASKS_A_FRAME and j.askHead <= j.askTail do
		local itemID = j.toAsk[j.askHead]
		j.toAsk[j.askHead] = nil
		j.askHead = j.askHead + 1
		if j.waiting[itemID] then
			Game.RequestItem(itemID)
			sent = sent + 1
		end
	end

	-- Rows, until the frame's time is up. The clock is looked at every `every` rows, and that
	-- number adapts: halved when a group took more than a quarter of the budget (a row is
	-- dearer than thought: the look comes sooner), doubled when it took a sixteenth or less.
	local start, n = t0, 0
	local groupAt, every = t0, j.every
	while n < TUNE.ROWS_A_FRAME do
		if j.head <= j.tail then
			local index = j.ready[j.head]
			j.ready[j.head] = nil
			j.head = j.head + 1
			read(j, index, true)
		elseif j.next < j.total then
			read(j, j.next)
			j.next = j.next + 1
		else
			break
		end
		n = n + 1
		if n % every == 0 then
			local now = Game.Clock()
			local took = now - groupAt
			groupAt = now
			if took > TUNE.BUDGET_MS / 4 and every > 1 then
				every = math.max(1, math.floor(every / 2))
			elseif took < TUNE.BUDGET_MS / 16 and every < TUNE.CLOCK_EVERY then
				every = math.min(TUNE.CLOCK_EVERY, every * 2)
			end
			if now - start >= TUNE.BUDGET_MS then break end
		end
	end
	j.every = every
	if j.head > j.tail then j.ready, j.head, j.tail = {}, 1, 0 end
	if j.afterClose and #j.blank > 0 then return abort(j, "the Auction House closed") end
	tell(j.next, j.total)
	if j.next < j.total or j.head <= j.tail then return schedule(j, 0) end

	-- Every row walked. The list may still grow, items may still load, blank rows may fill.
	local now = Game.Clock()
	local size = Count()
	if size > j.total and not j.afterClose then
		j.total, j.stillAt = size, nil
		return schedule(j, 0)
	end
	if j.nWaiting > 0 then
		-- Items still loading. The wait ends when nothing has arrived for ITEM_MS (and every
		-- ask is out), or ITEM_MAX_MS after the walk ended; the Auction House closing ends it
		-- too (above), and what was read by then is saved.
		j.walkedAt = j.walkedAt or now
		local asksOut = j.askHead > j.askTail
		-- (The quiet clock counts from the walk's end at the earliest: arrivals stopping while
		-- the walk was still going must not end the wait the moment the walk is through.)
		local quietFrom = math.max(j.lastArrival or now, j.walkedAt)
		local ends = math.min(quietFrom + TUNE.ITEM_MS, j.walkedAt + TUNE.ITEM_MAX_MS)
		if not asksOut or now < ends then return schedule(j, asksOut and TUNE.LOOK or 0) end
		giveUpWaiting(j, now >= j.walkedAt + TUNE.ITEM_MAX_MS and "cap" or "quiet")
	end
	if #j.blank ~= j.blanks then j.blanks, j.stillAt = #j.blank, nil end
	j.stillAt = j.stillAt or now
	if now - j.stillAt >= (j.total > 0 and TUNE.SETTLE_MS or TUNE.EMPTY_MS) then
		for _ = 1, #j.blank do skipped(j.run, "blank row") end
		return finish(j)
	end
	local blank = j.blank
	j.blank = {}
	for i = 1, #blank do
		j.tail = j.tail + 1
		j.ready[j.tail] = blank[i]
	end
	schedule(j, TUNE.LOOK)
end

schedule = function(j, delay)
	if j.scheduled or job ~= j then return end
	j.scheduled = true
	C_Timer.After(delay, function()
		-- (A row that raises ends the read, reported, instead of leaving it running forever.)
		local ok, err = pcall(pump, j)
		if not ok then
			abort(j, "error: " .. tostring(err))
			geterrorhandler()(err)
		end
	end)
end

-- ---------------------------------------------------------------------------------------------
-- The tail: rows that gave no link in time
-- ---------------------------------------------------------------------------------------------
-- In two real scans a quarter of the gear rows (24,156 of 87,674, then 27,689 of 85,406) never
-- gave a link before the read ended. Whatever the cause in a given run (the split by cause is
-- in /gear debug), such rows are not dropped any more. The list is saved without them, so the
-- window can work, and then the tail goes over them again for as long as the Auction House
-- stays open and the game still serves the same list: each row is read again by its index
-- (reading a row is what makes the game fetch that row's item: the public wiki's page for
-- ReplicateItems says the list event "will also fire for each auction item that was cached
-- from the server after calling GetReplicateItemInfo"), and one that has a link now is put in
-- the saved list (Market.Merge), with "MarketAdded" telling the window. TAIL_MS a frame, a
-- pause between passes, and it gives up after TAIL_IDLE passes that brought nothing.
local tail

local function tailStop(why)
	if not tail then return end
	-- (What is left, said honestly: how many items those rows are, and how many of those have
	-- no listing in the saved list at all.)
	local items, unlisted = 0, 0
	local seen = {}
	for i = 1, tail.n do
		local id = tail.rows[i] and tail.ids[i]
		if id and not seen[id] then
			seen[id] = true
			items = items + 1
			if tail.counted[id] and not tail.seen[id] then unlisted = unlisted + 1 end
		end
	end
	dbg.tail = { got = tail.got, items = tail.gotItems, left = tail.n - tail.done, passes = tail.pass, why = why,
		leftItems = items, unlisted = unlisted }
	tail = nil
end

local function tailStep()
	local t = tail
	if not t then return end
	t.scheduled = false
	if job then return tailStop("a new read began") end
	if not open then return tailStop("the Auction House closed") end
	-- (The window is scoring the new list: its 3 ms and the tail's 1.5 ms are not spent in one
	-- frame. The tail waits its turn.)
	local W = ns.Window
	if W and W.S and W.S.running and W.IsShown() then
		t.scheduled = true
		return C_Timer.After(0.25, tailStep)
	end
	if t.pass > 0 and t.at == 1 and Now() - t.began >= TUNE.TAIL_MAX_S then return tailStop("its ten minutes were up") end
	local e = Market.Saved()
	if not e or e.items ~= t.items then return tailStop("the list was replaced") end
	local t0 = Game.Clock()
	if t.at == 1 then
		if not SameList(t.print) then return tailStop("the game's list changed") end
		if not Market.Index() then
			t.scheduled = true
			return C_Timer.After(0.2, tailStep)
		end
	end
	local rows, ids = t.rows, t.ids
	local asked = 0
	while t.at <= t.n do
		local i = t.at
		local index = rows[i]
		if index then
			local itemID, buyout, _, owner = Row(index)
			if itemID ~= ids[i] then return tailStop("the game's list changed") end
			local link = Link(index)
			if link and Stats.ItemID(link) == itemID then
				rows[i] = false
				t.done, t.got = t.done + 1, t.got + 1
				e.lostRows = math.max(0, (e.lostRows or 0) - 1)
				if not t.seen[itemID] then
					t.seen[itemID] = true
					t.gotItems = t.gotItems + 1
					if t.counted[itemID] then e.lost = math.max(0, (e.lost or 0) - 1) end
				end
				if type(buyout) == "number" and buyout > 0 and not (owner ~= nil and owner == me) then
					local key = Stats.Key(link)
					if key then
						local equipLoc, classID, subclassID = Game.ItemInstant(itemID)
						local code = equipLoc and LOC_CODE[equipLoc]
						local facts, known
						if code and type(classID) == "number" and type(subclassID) == "number" then
							local _, _, minLevel = Game.ItemInfo(link)
							minLevel = tonumber(minLevel) or 0
							facts = ("%d.%d.%d.%d"):format(classID, subclassID, minLevel, code)
							known = { classID, subclassID, equipLoc, minLevel }
						end
						local what = Market.Merge(key, buyout, facts)
						if what then ns.Fire("MarketAdded", key, buyout, what, known) end
					end
				end
				t.gotPass = t.gotPass + 1
			elseif asked < TUNE.ASKS_A_FRAME and not t.askedPass[itemID] then
				-- (Its item asked for once a pass, in case that is what the row waits for.)
				t.askedPass[itemID] = true
				asked = asked + 1
				Game.RequestItem(itemID)
			end
		end
		t.at = i + 1
		if Game.Clock() - t0 >= TUNE.TAIL_MS then break end
	end
	ns.Perf.Time("market", Game.Clock() - t0)
	if t.at <= t.n then
		t.scheduled = true
		return C_Timer.After(0, tailStep)
	end
	-- A pass is through.
	t.pass = t.pass + 1
	if t.done >= t.n then return tailStop("every row was read") end
	t.idle = t.gotPass == 0 and t.idle + 1 or 0
	if t.idle >= TUNE.TAIL_IDLE then return tailStop("nothing more arrived") end
	t.at, t.gotPass, t.askedPass = 1, 0, {}
	t.scheduled = true
	C_Timer.After(TUNE.TAIL_PAUSE, tailStep)
end

function Market.StartTail(j)
	local e = Market.Saved()
	if not e then return end
	tail = { rows = j.tailRows, ids = j.tailIDs, n = #j.tailRows, at = 1, done = 0, got = 0, gotItems = 0, gotPass = 0,
		pass = 0, idle = 0, seen = {}, askedPass = {}, counted = j.counted or {}, items = e.items, print = { total = j.total, probes = j.probes },
		scheduled = true, began = Now() }
	dbg.tail = nil
	C_Timer.After(TUNE.TAIL_PAUSE, tailStep)
end

-- Whether the tail is at work, and how many rows it still has.
function Market.Tail()
	if not tail then return false, 0 end
	return true, tail.n - tail.done
end

-- The game's event with no read running: a new list (read it), or an echo of the one already
-- read (an item loaded: nothing to do). THE EVENT ITSELF DOES ALMOST NOTHING: it comes once for
-- every item the game loads while anybody's scan is read (97,376 times in one real scan), so
-- the handler is two counters and a flag. Whether the list is a new one is looked at once a
-- second at most, by the timer below.
local looking = false
local function look()
	looking = false
	dbg.lookedAt = Game.Clock()
	if job or not open or not AH() then return end
	-- (An empty list at the event is waited on: the event can come before the rows do.)
	if SameList(lastPrint) then return end
	local by = whose()
	asking = nil
	newJob(by)
end

local function onListEvent()
	dbg.events = dbg.events + 1
	if not open then dbg.eventsClosed = dbg.eventsClosed + 1 end
	if job then
		job.check = true
		return
	end
	if looking then return end
	looking = true
	-- (The first event after a quiet spell is looked at on the next frame, so a new scan is
	-- picked up at once; echoes after that, once a second.)
	local since = Game.Clock() - (dbg.lookedAt or -1e9)
	C_Timer.After(since >= TUNE.CHECK_MS and 0 or (TUNE.CHECK_MS - since) / 1000, look)
end

-- Whether a look at the list is due (an event came and has not been looked at yet).
function Market.Looking() return looking end

local function itemArrived(itemID, success)
	local j = job
	if not j then return end
	local entry = j.waiting[itemID]
	if not entry then return end
	j.waiting[itemID] = nil
	j.nWaiting = j.nWaiting - 1
	j.lastArrival = Game.Clock()
	if success == false then
		-- (No data is coming: later rows of it are given up at once.)
		j.failed = j.failed or {}
		j.failed[itemID] = true
		for i = 1, #entry do lose(j, itemID, entry[i], "refused") end
	else
		for i = 1, #entry do
			j.tail = j.tail + 1
			j.ready[j.tail] = entry[i]
		end
	end
	-- (A timer for the settle look may be out: the next one picks these up; ask for a slice now.)
	if not j.scheduled then schedule(j, 0) end
end

-- What the game still answers a moment after the Auction House closed (debug only: three calls).
local function probeAfterClose()
	if open or not AH() then return end
	local n = Count()
	dbg.afterClose = { rows = n }
	if n > 0 then
		dbg.afterClose.row = Row(0) ~= nil
		dbg.afterClose.link = Link(0) ~= nil
	end
end

local function onClosed()
	open = false
	asking = nil
	dbg.closedWith = Count()
	if job then
		job.closed = true
		if not job.scheduled then schedule(job, 0) end
	end
	C_Timer.After(2, probeAfterClose)
end

local function onShown()
	open = true
	houseKey = nil
	local okN, name = pcall(UnitName, "player")
	name = okN and plain(name) or nil
	if type(name) == "string" then me = name end
	Market.Hook()
end

frame:SetScript("OnEvent", function(_, event, a, b)
	if event == "REPLICATE_ITEM_LIST_UPDATE" then
		ns.Perf.Count("listEvents")
		onListEvent()
	elseif event == "AUCTION_HOUSE_SHOW" then
		onShown()
	elseif event == "AUCTION_HOUSE_CLOSED" then
		onClosed()
	else
		itemArrived(a, b)
	end
end)
-- (Counted for /gear debug where the event is cheapest to count: Core's own frame.)
-- DOC AuctionHouseDocumentation.lua:1493 (the list), :1171 and :1159 (shown, closed).
for _, event in ipairs({ "REPLICATE_ITEM_LIST_UPDATE", "AUCTION_HOUSE_SHOW", "AUCTION_HOUSE_CLOSED" }) do
	pcall(frame.RegisterEvent, frame, event)
end

-- Daylight UI's own word that its Full Scan started or ended: the module's private callbacks,
-- ns.On(name, fn) (DaylightUI_AuctionHouse\Base.lua:21-25); "ScanStarted" fired at Scan.lua:198,
-- "ScanEnded" (ok, sentence, total, info) at :156 and :94. Only listened to: a second trigger for
-- a list the game's event has not already made us read. Without it the game's event is enough.
local hooked = false
function Market.Hook()
	if hooked then return true end
	local m = DuiModule()
	if not m or type(m.On) ~= "function" then return false end
	local ok = pcall(function()
		m.On("ScanStarted", function() dbg.duiStarted = dbg.duiStarted + 1 end)
		m.On("ScanEnded", function(done)
			dbg.duiEnded = dbg.duiEnded + 1
			dbg.duiEndedOk = done == true
			if done == true and not job and not looking then
				looking = true
				C_Timer.After(0, look)
			end
		end)
	end)
	hooked = ok
	return ok
end

-- ---------------------------------------------------------------------------------------------
-- State, and our own ask
-- ---------------------------------------------------------------------------------------------
-- Whether an Auction House is open (any window: the game's events say so).
function Market.IsOpen() return open end

function Market.State()
	if job then return "reading", job.next, job.total end
	if asking then return "reading", 0, 0 end
	if Market.Saved() then return "ready" end
	return "none"
end

-- DaylightMogul runs the Auction House: it scans the whole house itself, and the game allows
-- everybody together one such scan in about fifteen minutes. A scan of ours would spend the one
-- it needs, so none is offered; the list it fetches is read like any other.
local function MogulOwns()
	local D = ns.DUI
	return type(D) == "table" and D.ahMogul == true
end

-- Other Auction House addons whose full scan asks for the game's whole-house list (the folder ->
-- its name for the window). That list is the one Gear reads, whoever asked for it, and the game
-- allows everybody together one such ask in about fifteen minutes: so while one of these is
-- installed and enabled for this character, ours is not offered and its scan is the way. Daylight
-- UI's Auction House is not here: DuiAH() above knows whether its window (and so its Full Scan) is
-- the one in use. Read from each addon's own code (2026-11-24 downloads):
--   Auctionator 353          Source_ModernAH/FullScan/Mixins/Frame.lua:19-49 ReplicateItems, but
--                            only with its "replicate scan" option on (Source/Config/Main.lua:12, :89:
--                            replicate_scan_3, off by default); otherwise its scan is a browse
--                            (IncrementalScan), which never fills the list: then ours is offered.
--   AuctionMaster 11.8.4     src/scan/Scan.lua:691 ReplicateItems (its scan button)
--   AHDB 2.8.3 (AuctionDB)   Scan.lua:77 ReplicateItems, by itself on opening the house (on by default)
--   Auctioneer 4.0.9         CoreScan.lua:580, :756-757 every scan is ReplicateItems
--   ForeverForge Auction     Market.lua:1328-1347 ReplicateItems, 3 s after opening (on by default)
-- Not here, as their prices don't come from such a scan: TradeSkillMaster (its DB prices come from
-- the TSM desktop app; LibTSMService/Source/Auction/Internal/FullScan.lua:48-50 returns early on
-- this client) and Oribos Exchange (its data ships with the addon; it sends no Auction House
-- requests).
local function AuctionatorReplicates()
	local A = rawget(_G, "Auctionator")
	local C = type(A) == "table" and A.Config or nil
	if type(C) ~= "table" or type(C.Get) ~= "function" or type(C.Options) ~= "table" or C.Options.REPLICATE_SCAN == nil then
		return true     -- (not loaded yet, or another version: counted, as before)
	end
	local ok, on = pcall(C.Get, C.Options.REPLICATE_SCAN)
	if not ok then return true end
	return on == true
end

local SCANNERS = {
	{ "DaylightMogul", "Daylight Mogul" },
	{ "Auctionator", "Auctionator", AuctionatorReplicates },
	{ "AuctionLite", "AuctionLite" },
	{ "AuctionMaster", "AuctionMaster" },
	{ "AuctionDB", "Auction House DataBase" },
	{ "Auc-Advanced", "Auctioneer" },
	{ "ForeverForge_Auction", "ForeverForge Auction" },
}
Market.SCANNERS = SCANNERS

-- The names of the ones running for this character, in SCANNERS' order. Running = loaded (every
-- one of them loads at login when it's on), or a load-on-demand one ticked for this character
-- (asked by GUID, as the game's own addon list asks: by name it answered for all characters, so
-- an Auctionator switched off here still counted and our scan was never offered). Read once
-- logged in (an addon switched on or off counts from the next reload, as the game loads it;
-- `again` reads anew); before that, read on each ask. An option that decides whether it fills
-- the list (Auctionator's) is read each time.
local scanners
local function Running(A, name)
	if type(A.IsAddOnLoaded) == "function" then
		local ok, loaded = pcall(A.IsAddOnLoaded, name)
		if ok and loaded then return true end
	end
	if type(A.IsAddOnLoadOnDemand) ~= "function" or type(A.GetAddOnEnableState) ~= "function" then return false end
	local okD, lod = pcall(A.IsAddOnLoadOnDemand, name)
	if not (okD and lod) then return false end
	local okG, guid = pcall(UnitGUID, "player")
	guid = okG and plain(guid) or nil
	local okS, state = pcall(A.GetAddOnEnableState, name, guid)
	return okS and type(state) == "number" and state > 0
end
function Market.Others(again)
	if not scanners or again then
		local list = {}
		local A = C_AddOns
		if type(A) == "table" and type(A.DoesAddOnExist) == "function" then
			for _, sc in ipairs(SCANNERS) do
				local okE, exists = pcall(A.DoesAddOnExist, sc[1])
				if okE and exists and Running(A, sc[1]) then list[#list + 1] = sc end
			end
		end
		local okL, inGame = pcall(IsLoggedIn)
		scanners = (okL and inGame) and list or nil
		if not scanners then
			local names = {}
			for _, sc in ipairs(list) do
				if not sc[3] or sc[3]() then names[#names + 1] = sc[2] end
			end
			return names
		end
	end
	local names = {}
	for _, sc in ipairs(scanners) do
		if not sc[3] or sc[3]() then names[#names + 1] = sc[2] end
	end
	return names
end

function Market.CanScan()
	if DuiAH() then return false, "dui" end
	if MogulOwns() or #Market.Others() > 0 then return false, "other" end
	local S = ns.Sweep
	if not S or not S.Possible() then return false, "noapi" end
	if not open then return false, "closed" end
	if S.Running() then return false, "busy" end
	return true
end

-- Our own scan: Sweep.lua goes through the Auction House's weapon and armor categories, page by
-- page (it replaced an ask for the game's whole-house list, which the game answers once in 15
-- minutes for every addon together and otherwise ignores without a word). A scan that was
-- paused (the Auction House closed, or Stop Scan) goes on where it stopped.
function Market.Scan()
	local ok, why = Market.CanScan()
	if not ok then return false, why end
	return ns.Sweep.Start()
end

-- What can be known of an item without loading it, as a saved string carries it (see Parse):
-- "class.subclass.level.location", or nil.
function Market.Facts(itemID, minLevel)
	local equipLoc, classID, subclassID = Game.ItemInstant(itemID)
	local code = equipLoc and LOC_CODE[equipLoc]
	if not code or type(classID) ~= "number" or type(subclassID) ~= "number" then return nil end
	return ("%d.%d.%d.%d"):format(classID, subclassID, tonumber(minLevel) or 0, code)
end

-- A finished scan of ours put in place as this house's list: items are saved strings (see
-- Parse), rows how many results the scan read, startedAt the server's time it began. Corrections
-- older than the scan go, as with any new list.
function Market.Store(items, rows, startedAt, lost)
	local e = Entry(true)
	if not e then return false end
	e.at, e.rows, e.by, e.items = Now(), rows or #items, "own", items
	e.lost, e.lostRows = lost or 0, 0
	e.readAt = startedAt or e.at
	for key, at in pairs(type(e.fixT) == "table" and e.fixT or {}) do
		if at <= e.readAt then e.fixT[key], e.fixP[key] = nil, nil end
	end
	decoded, decodedFrom = nil, nil
	ns.Fire("MarketChanged")
	return true
end

function Market.Now() return Now() end
Market.Plain = plain

-- ---------------------------------------------------------------------------------------------
-- /gear debug
-- ---------------------------------------------------------------------------------------------
function Market.Debug()
	local out = {}
	local function add(text, ...) out[#out + 1] = "market: " .. text:format(...) end
	local m = DuiModule()
	add("house %s; Daylight UI's Auction House %s; scan events hooked: %s; Auction House open: %s",
		tostring(Market.House()), DuiAH() and "in use" or (m and "loaded, not the one in use" or "not reachable"),
		tostring(hooked), tostring(open))
	add("list events heard %d (%d while closed); Daylight UI scans started %d, ended %d%s; our own asks %d%s",
		dbg.events, dbg.eventsClosed, dbg.duiStarted, dbg.duiEnded,
		dbg.duiEndedOk ~= nil and (dbg.duiEndedOk and " (done)" or " (stopped)") or "",
		dbg.asked or 0, dbg.askTimedOut and " (one got no answer)" or "")
	local run = dbg.run
	add("reads started %d, started over %d; last read: %s", dbg.starts, dbg.restarts,
		run.ended and ("%s in %d ms"):format(run.ended, run.ms or 0) or (job and "running" or "none yet"))
	add("last read: list of %d rows, %d read, %d gear rows with a link, %d distinct items kept",
		run.total or 0, run.read, run.gear, run.kept)
	local why = {}
	for reason, n in pairs(run.skip) do why[#why + 1] = reason .. " " .. n end
	table.sort(why)
	add("rows skipped: %s; rows with an owner %d", #why > 0 and table.concat(why, ", ") or "none", run.owners or 0)
	-- Why gear rows gave no link in time, by cause (see `lose`), and what the tail did about them.
	local lostBy = {}
	for reason, n in pairs(run.lost or {}) do lostBy[#lostBy + 1] = reason .. " " .. n end
	table.sort(lostBy)
	add("rows with no link in time, by cause: %s", #lostBy > 0 and table.concat(lostBy, ", ") or "none")
	if tail then
		add("the tail is asking again: %d of %d rows read since (%d items), pass %d", tail.got, tail.n, tail.gotItems, tail.pass + 1)
	elseif dbg.tail then
		add("the tail read %d more rows (%d items) in %d passes, %d left; it stopped because: %s", dbg.tail.got, dbg.tail.items,
			dbg.tail.passes, dbg.tail.left, dbg.tail.why)
		add("the rows left are listings of %d items the game never gave a link for; %d of those items have no listing in the saved list",
			dbg.tail.leftItems or 0, dbg.tail.unlisted or 0)
	end
	local fixes, gone = Market.FixCount()
	add("prices corrected by searches since the list was read: %d (%d of them: none left)", fixes, gone)
	add("kept items by link: %d plain, %d with a suffix field, %d with bonus IDs", run.unrolled, run.rolledSuffix,
		run.rolledBonus)
	if run.sample then add("a rolled link: %s", (run.sample:gsub("|", "||"))) end
	if run.namedOnly then add("a roll only in the name (left out): %s", (run.namedOnly:gsub("|", "||"))) end
	if job then
		add("now: row %d of %d, %d items loading (%d asks not sent yet), %d blank rows, clock looked at every %d rows",
			job.next, job.total, job.nWaiting, job.askTail - job.askHead + 1, #job.blank, job.every)
	end
	if dbg.afterClose then
		add("when the Auction House closed the list had %d rows; 2 s later: %d rows, row 0 %s, its link %s",
			dbg.closedWith or 0, dbg.afterClose.rows, dbg.afterClose.row and "readable" or "not readable",
			dbg.afterClose.link and "readable" or "not readable")
	else
		add("the Auction House has not closed after a list yet (rows in the game's list now: %d)", Count())
	end
	local e, key = Entry()
	if e and type(e.items) == "table" then
		local bytes, withFacts = 0, 0
		for i = 1, #e.items do
			bytes = bytes + #e.items[i]
			if select(2, e.items[i]:gsub("#", "#")) >= 2 then withFacts = withFacts + 1 end
		end
		add("saved for %s: %d items (%d with facts, %d KB) from %d rows, by %s, %d s ago; gear items that could not be read: %d (%d rows)",
			tostring(key), #e.items, withFacts, math.floor(bytes / 1024 + 0.5), e.rows or 0,
			tostring(e.by), math.max(0, Now() - (e.at or 0)), e.lost or 0, e.lostRows or 0)
	else
		add("nothing saved for this house")
	end
	add("other addons with a full scan: %s", #Market.Others() > 0 and table.concat(Market.Others(), ", ") or "none")
	local ok, whyNot, left = Market.CanScan()
	add("our own read: %s", ok and "available" or (tostring(whyNot) .. (left and (" (" .. math.ceil(left) .. " s)") or "")))
	return out
end

-- (When the house key may have changed: see Market.House.)
local houseFrame = CreateFrame("Frame")
houseFrame:SetScript("OnEvent", function() houseKey = nil end)
for _, event in ipairs({ "PLAYER_ENTERING_WORLD", "GAME_RULES_CHANGED", "ADDON_LOADED" }) do
	pcall(houseFrame.RegisterEvent, houseFrame, event)
end

ns.me.On("Login", function()
	houseKey = nil
	Market.Prune()
	Market.Hook()
end)
