-- Glowey's Gear: our own scan of the Auction House's weapons and armor (Scan the Auction House).
--
--   Sweep.Possible()  -> the client has the calls the scan needs
--   Sweep.Start()     -> ok, why     starts a scan, or goes on with a paused one
--   Sweep.Pause()                    stops sending; Start goes on where it stopped
--   Sweep.Running()   -> a scan is sending (not paused, not done)
--   Sweep.Progress()  -> nil | { step = "browse" | "search" | "save", done, total, found, paused,
--                        closed }   for the window's bar
--   Sweep.Debug()     -> lines for /gear debug
--   fires "SweepProgress" while it works, and "SweepChanged" when it starts, pauses or ends.
--
-- WHY NOT THE WHOLE-HOUSE LIST. C_AuctionHouse.ReplicateItems is answered once in 15 minutes
-- for every addon of the account together, and an ask inside that time is dropped without a
-- word (no event, no error): with another scanner about, our button did nothing. A browse search
-- has no such limit, so the scan is made of the same searches the game's own Auction House sends
-- when a category is clicked (Blizzard_AuctionHouseUI, branch forever: Camelot\
-- Blizzard_AuctionData.lua builds the Weapons and Armor categories; Shared\
-- Blizzard_AuctionHouseFrame.lua:794-824 sends one; Shared\Blizzard_AuctionHouseBrowseResultsFrame
-- .lua:70-127 reads the pages and asks for more), one category at a time, every page of it.
-- Everything else in the house (trade goods, consumables, ...) is never asked for.
--
-- THE CALLS (DOC = Blizzard_APIDocumentationGenerated\AuctionHouseDocumentation.lua, forever):
--   SendBrowseQuery(query)           DOC :1021   query: searchString, sorts, filters (the
--                                                quality filters), itemClassFilters
--   GetBrowseResults()               DOC :216    every result so far: BrowseResultInfo
--                                                (itemKey, totalQuantity, minPrice, containsOwnerItem)
--   HasFullBrowseResults()           DOC :722    false while more pages wait
--   RequestMoreBrowseResults()       DOC :951    the next page
--   events AUCTION_HOUSE_BROWSE_RESULTS_UPDATED (the first page), _ADDED (addedBrowseResults),
--          AUCTION_HOUSE_BROWSE_FAILURE                                    DOC :1135-1155
--   GetItemKeySampleLink(itemKey)    DOC :358    "a link for an item in this key's results"
--   GetItemKeyRequiredLevel(itemKey)             the level the game's browse list shows
--   SendSearchQuery(itemKey, sorts, separateOwnerItems)   DOC :1031  "restricted to 100 calls per
--                                                minute": one item's own listings, with links
--   GetNumItemSearchResults / GetItemSearchResultInfo     DOC :519, :374
--   events ITEM_SEARCH_RESULTS_UPDATED / _ADDED (itemKey)                  DOC :1453-1470
--   IsThrottledMessageSystemReady()  DOC :825    the game takes a message now
--
-- A RESULT is one item KEY (item, level, suffix) with its cheapest price, not one listing. A
-- plain key is its item. A key with a suffix is a rolled item ("... of the Bear"), whose stats
-- are in the link's bonus ID, which the key does not carry (Forever's itemSuffix is a number of
-- the Auction House's own: "4567:14303", seen by Daylight UI). Its link comes, in this order:
--   1. GetItemKeySampleLink: what the game's own browse list shows in the row's tooltip;
--   2. a link learned before for this item and suffix (saved: GloweyGearDB.akeys);
--   3. the same suffix on two other items with the same bonus and never a different one
--      (GloweyGearDB.atails): the roll is the suffix's, not the item's;
--   4. else, once the categories are all read, a search for that one key (step 2 of the scan),
--      paced under the game's 100 a minute; every link learned there serves 2 and 3 at once.
-- A key whose link never comes is left out and counted.
--
-- PACE. One message at a time: the next only when the answer to the last is in, the game says it
-- takes messages, and TUNE.GAP (TUNE.SEARCH_GAP for searches) has gone by. An answer that does
-- not come in TUNE.WAIT seconds sends the same message again, TUNE.TRIES times in all. A browse
-- search sent by someone else (the player in the game's window, another addon) while ours is
-- out replaces ours in the game: ours is sent again from its first page once things are quiet.
-- The Auction House closing pauses the scan; Scan again goes on from the category it was in.
--
-- luacheck: read globals C_AuctionHouse C_Timer Enum hooksecurefunc CreateFrame

local _, ns = ...
if ns.off or not ns.ok then return end

local Market, Stats, Game = ns.Market, ns.Stats, ns.Game
local L = ns.L

local Sweep = {}
ns.Sweep = Sweep

local TUNE = {
	GAP = 0.5,           -- seconds between two browse messages of ours, at least
	SEARCH_GAP = 0.7,    -- seconds between two item searches (the game allows 100 a minute)
	WAIT = 20,           -- seconds an answer may take before the message is sent again
	SEARCH_WAIT = 8,     -- the same for an item search
	TRIES = 3,           -- times one message is sent before its category or item is given up
	FAILED_PAUSE = 3,    -- seconds to wait after the game says a browse search failed
	QUIET = 2,           -- seconds without someone else's search before ours is sent again
	TICK = 0.1,          -- seconds between two looks at what to send next
	RESUME_S = 1800,     -- a paused scan older than this starts over instead
	BUDGET_MS = 3,       -- time in one frame for making the saved strings at the end
}
Sweep.TUNE = TUNE

local plain = Market.Plain
local function Clock() return Game.Clock() / 1000 end

local function AH()
	local a = C_AuctionHouse
	if type(a) ~= "table" then return nil end
	for _, name in ipairs({ "SendBrowseQuery", "GetBrowseResults", "HasFullBrowseResults", "RequestMoreBrowseResults" }) do
		if type(a[name]) ~= "function" then return nil end
	end
	return a
end

local function E(group, name)
	local t = type(Enum) == "table" and Enum[group]
	local v = type(t) == "table" and t[name] or nil
	return type(v) == "number" and v or nil
end

-- ---------------------------------------------------------------------------------------------
-- The categories: the game's own Weapons and Armor, as Camelot\Blizzard_AuctionData.lua makes them
-- ---------------------------------------------------------------------------------------------
local WEAPONS = { "Axe1H", "Mace1H", "Sword1H", "Dagger", "Unarmed", "Wand", "Axe2H", "Mace2H", "Sword2H",
	"Polearm", "Staff", "Bows", "Crossbow", "Guns", "Thrown", "Generic" }
local ARMOR_KINDS = { "Plate", "Mail", "Leather", "Cloth" }
local ARMOR_SLOTS = { "IndexHeadType", "IndexShoulderType", "IndexChestType", "IndexWaistType", "IndexLegsType",
	"IndexFeetType", "IndexWristType", "IndexHandType" }
local MISC_SLOTS = { "IndexNeckType", "IndexFingerType", "IndexTrinketType", "IndexHoldableType" }
local RELICS = { "Shield", "Idol", "Libram", "Totem" }

function Sweep.Categories()
	local out = {}
	local W, A = E("ItemClass", "Weapon"), E("ItemClass", "Armor")
	if W then
		for _, name in ipairs(WEAPONS) do
			local sub = E("ItemWeaponSubclass", name)
			if sub then out[#out + 1] = { { classID = W, subClassID = sub } } end
		end
	end
	if A then
		local robe = E("InventoryType", "IndexRobeType")
		for _, kind in ipairs(ARMOR_KINDS) do
			local sub = E("ItemArmorSubclass", kind)
			for _, slot in ipairs(sub and ARMOR_SLOTS or {}) do
				local inv = E("InventoryType", slot)
				if inv then
					local filters = { { classID = A, subClassID = sub, inventoryType = inv } }
					-- (Robes are chest pieces in the game's own list too.)
					if slot == "IndexChestType" and robe then
						filters[2] = { classID = A, subClassID = sub, inventoryType = robe }
					end
					out[#out + 1] = filters
				end
			end
		end
		local cloth, cloak = E("ItemArmorSubclass", "Cloth"), E("InventoryType", "IndexCloakType")
		if cloth and cloak then out[#out + 1] = { { classID = A, subClassID = cloth, inventoryType = cloak } } end
		local generic = E("ItemArmorSubclass", "Generic")
		for _, slot in ipairs(generic and MISC_SLOTS or {}) do
			local inv = E("InventoryType", slot)
			if inv then out[#out + 1] = { { classID = A, subClassID = generic, inventoryType = inv } } end
		end
		for _, name in ipairs(RELICS) do
			local sub = E("ItemArmorSubclass", name)
			if sub then out[#out + 1] = { { classID = A, subClassID = sub } } end
		end
	end
	return out
end

-- Every quality, as the game's own search sends them by default (AUCTION_HOUSE_DEFAULT_FILTERS).
local function Qualities()
	local out = {}
	for _, name in ipairs({ "PoorQuality", "CommonQuality", "UncommonQuality", "RareQuality", "EpicQuality",
		"LegendaryQuality", "ArtifactQuality" }) do
		local v = E("AuctionHouseFilter", name)
		if v then out[#out + 1] = v end
	end
	return out
end

local function Sorts(first, second)
	local out = {}
	for _, name in ipairs({ first, second }) do
		local v = E("AuctionHouseSortOrder", name)
		if v then out[#out + 1] = { sortOrder = v, reverseSort = false } end
	end
	return out
end

function Sweep.Possible()
	return AH() ~= nil and E("ItemClass", "Weapon") ~= nil
end

-- ---------------------------------------------------------------------------------------------
-- Links of rolled keys, learned and kept
-- ---------------------------------------------------------------------------------------------
local function Learned()
	local db = ns.DB()
	if type(db.akeys) ~= "table" then db.akeys = {} end
	if type(db.atails) ~= "table" then db.atails = {} end
	return db.akeys, db.atails
end

-- A real link of one item with one suffix: kept for the item, and its roll for the suffix.
local function Learn(id, suffix, key)
	if suffix == 0 then return end
	local keys, tails = Learned()
	keys[id .. ":" .. suffix] = key
	local idText = tostring(id)
	if key:sub(1, #idText) ~= idText then return end
	local tail = key:sub(#idText + 1)
	if tail == "" then return end
	local t = tails[suffix]
	if type(t) ~= "table" then
		tails[suffix] = { t = tail, n = 1, last = id }
	elseif t.t ~= tail then
		t.bad = true
	elseif t.last ~= id then
		t.n, t.last = (t.n or 1) + 1, id
	end
end

local function SampleKey(a, k, id)
	if type(a.GetItemKeySampleLink) ~= "function" then return nil end
	local ok, link = pcall(a.GetItemKeySampleLink, k)
	link = ok and plain(link) or nil
	if type(link) ~= "string" or Stats.ItemID(link) ~= id then return nil end
	return Stats.Key(link)
end

-- The saved key for one result's item key, or nil when only a search can tell.
local function KeyFor(a, k, id, suffix, sample)
	local key = sample and SampleKey(a, k, id)
	if key then
		Learn(id, suffix, key)
		return key
	end
	if suffix == 0 then return tostring(id) end
	local keys, tails = Learned()
	key = keys[id .. ":" .. suffix]
	if type(key) == "string" then return key end
	local t = tails[suffix]
	if type(t) == "table" and not t.bad and (t.n or 0) >= 2 and type(t.t) == "string" then
		return id .. t.t
	end
	return nil
end

-- ---------------------------------------------------------------------------------------------
-- The scan
-- ---------------------------------------------------------------------------------------------
local s            -- the scan: nil, or see Start
local mine = false -- a message of ours is being sent (the hook below tells ours from others')

local function changed() ns.Fire("SweepChanged") end
local function moved() ns.Fire("SweepProgress") end

local function RequiredLevel(a, k)
	if type(a.GetItemKeyRequiredLevel) ~= "function" then return nil end
	local ok, level = pcall(a.GetItemKeyRequiredLevel, k)
	level = ok and plain(level) or nil
	return type(level) == "number" and level or nil
end

local function keep(key, price, id, a, k)
	local was = s.best[key]
	if not was then
		s.order[#s.order + 1] = key
		s.facts[key] = Market.Facts(id, RequiredLevel(a, k))
	end
	if not was or price < was then s.best[key] = price end
end

-- One browse result.
local function take(a, r)
	s.rows = s.rows + 1
	local k = type(r) == "table" and r.itemKey
	if type(k) ~= "table" then return end
	local id = plain(k.itemID)
	if type(id) ~= "number" or id <= 0 then return end
	local suffix = plain(k.itemSuffix) or 0
	local price = plain(r.minPrice)
	if type(price) ~= "number" or price <= 0 then return end
	-- (Only the player's own listing: nothing to buy.)
	if plain(r.containsOwnerItem) == true and (plain(r.totalQuantity) or 0) <= 1 then
		s.own = s.own + 1
		return
	end
	local equipLoc = Game.ItemInstant(id)
	if not (equipLoc and Stats.GEAR[equipLoc]) then
		s.notGear = s.notGear + 1
		return
	end
	local key = KeyFor(a, k, id, suffix, true)
	if key then return keep(key, price, id, a, k) end
	local p = id .. ":" .. suffix
	local was = s.pending[p]
	if was then
		if price < was.price then was.price = price end
		return
	end
	local item = { k = { itemID = id, itemLevel = plain(k.itemLevel) or 0, itemSuffix = suffix,
		battlePetSpeciesID = plain(k.battlePetSpeciesID) or 0 }, id = id, suffix = suffix, price = price }
	s.pending[p] = item
	s.searches[#s.searches + 1] = item
end

local function after(seconds) s.nextAt = Clock() + seconds end

local function nextCategory()
	s.qi, s.tries, s.waiting, s.more, s.inQuery = s.qi + 1, 0, nil, nil, nil
	after(TUNE.GAP)
	moved()
end

local function nextSearch()
	s.si, s.tries, s.waiting = s.si + 1, 0, nil
	after(TUNE.SEARCH_GAP)
	moved()
end

local finish

-- A page of the category in hand. Pages can also come without our asking: the game's own browse
-- list shows our results while it is open, and asks for the next page itself when it is scrolled.
-- Those are read the same (a page lost would be listings never seen); only who asks next differs.
local function onBrowse(event, added)
	if not s or s.paused or s.step ~= "browse" or not s.inQuery then return end
	local a = AH()
	if not a then return end
	if event == "AUCTION_HOUSE_BROWSE_FAILURE" then
		s.waiting = nil
		s.failures = s.failures + 1
		after(TUNE.FAILED_PAUSE)
		return
	end
	local list = added
	if event == "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED" or type(list) ~= "table" then
		local ok, all = pcall(a.GetBrowseResults)
		list = ok and all or {}
	end
	for i = 1, #list do take(a, list[i]) end
	s.pages = s.pages + 1
	local asked = s.waiting == "page"
	s.waiting = nil
	local ok, full = pcall(a.HasFullBrowseResults)
	if ok and full == false then
		s.more = true
		if asked then after(TUNE.GAP) end
		moved()
	else
		nextCategory()
	end
end

local function sameKey(x, y)
	return type(x) == "table" and type(y) == "table" and plain(x.itemID) == y.itemID
		and (plain(x.itemSuffix) or 0) == y.itemSuffix
end

local function onSearch(k)
	if not s or s.paused or s.step ~= "search" or s.waiting ~= "search" then return end
	local item = s.searches[s.si]
	if not item or not sameKey(k, item.k) then return end
	local a = AH()
	local ok, n = pcall(a.GetNumItemSearchResults, item.k)
	n = ok and plain(n) or 0
	local key
	for i = 1, (type(n) == "number" and n or 0) do
		local got, info = pcall(a.GetItemSearchResultInfo, item.k, i)
		local link = got and type(info) == "table" and plain(info.itemLink) or nil
		if type(link) == "string" and Stats.ItemID(link) == item.id then
			key = Stats.Key(link)
			if key then break end
		end
	end
	if key then
		Learn(item.id, item.suffix, key)
		keep(key, item.price, item.id, a, item.k)
		s.named = s.named + 1
	else
		s.lost = s.lost + 1
	end
	nextSearch()
end

-- The next message, when it is time for one.
local function send()
	local a = AH()
	if not a then return end
	if type(a.IsThrottledMessageSystemReady) == "function" then
		local ok, ready = pcall(a.IsThrottledMessageSystemReady)
		if ok and ready == false then return end
	end
	if s.step == "browse" then
		local filters = s.categories[s.qi]
		if not filters then
			s.step, s.si, s.tries = "search", 1, 0
			changed()
			return
		end
		s.tries = s.tries + 1
		if s.tries > TUNE.TRIES then
			s.skipped = s.skipped + 1
			return nextCategory()
		end
		mine = true
		local ok
		if s.more then
			ok = pcall(a.RequestMoreBrowseResults)
		else
			ok = pcall(a.SendBrowseQuery, { searchString = "", sorts = s.browseSorts, filters = s.qualities,
				itemClassFilters = filters })
		end
		mine = false
		if not ok then return after(TUNE.FAILED_PAUSE) end
		s.sent = s.sent + 1
		s.inQuery = true
		s.waiting, s.deadline = "page", Clock() + TUNE.WAIT
	elseif s.step == "search" then
		local item = s.searches[s.si]
		if not item then return finish() end
		-- (Named meanwhile by a link learned from another item's search.)
		local key = KeyFor(a, item.k, item.id, item.suffix, false)
		if key then
			keep(key, item.price, item.id, a, item.k)
			s.named = s.named + 1
			s.si, s.tries = s.si + 1, 0
			return moved()
		end
		s.tries = s.tries + 1
		if s.tries > TUNE.TRIES or type(a.SendSearchQuery) ~= "function" then
			s.lost = s.lost + 1
			return nextSearch()
		end
		mine = true
		local ok = pcall(a.SendSearchQuery, item.k, s.searchSorts, false)
		mine = false
		if not ok then return after(TUNE.FAILED_PAUSE) end
		s.sent = s.sent + 1
		s.waiting, s.deadline = "search", Clock() + TUNE.SEARCH_WAIT
	end
end

local ticking = false
local function tick()
	ticking = false
	if not s or s.paused or s.step == "save" or s.step == "done" then return end
	if not Market.IsOpen() then return Sweep.Pause(true) end
	local now = Clock()
	if s.waiting then
		-- (No answer in time: the same message again; the try is counted when it is sent.)
		if now >= s.deadline then
			s.timeouts = s.timeouts + 1
			s.waiting = nil
			if s.step == "browse" then s.more, s.inQuery = nil, nil end
		end
	elseif now >= (s.nextAt or 0) then
		send()
	end
	if s and not s.paused and s.step ~= "save" and s.step ~= "done" and not ticking then
		ticking = true
		C_Timer.After(TUNE.TICK, tick)
	end
end

local function run()
	if ticking then return end
	ticking = true
	C_Timer.After(0, tick)
end

-- The saved strings, a slice a frame, then the list in place.
local function saveSome()
	if not s or s.step ~= "save" then return end
	local t0 = Game.Clock()
	local order, items = s.order, s.items
	local i = #items
	while i < #order do
		i = i + 1
		local key = order[i]
		local facts = s.facts[key]
		-- (%.0f, not %d: stock Lua 5.1's %d stops at 2^31 copper.)
		items[i] = key .. "#" .. ("%.0f"):format(s.best[key]) .. (facts and ("#" .. facts) or "")
		if i % 50 == 0 and Game.Clock() - t0 >= TUNE.BUDGET_MS then break end
	end
	if i < #order then return C_Timer.After(0, saveSome) end
	s.step = "done"
	s.ended = Market.Now()
	Market.Store(items, s.rows, s.startedAt, s.lost)
	ns.Print(L["Scan finished: %d weapons and armor for sale."]:format(#items))
	changed()
end

finish = function()
	s.step, s.items, s.waiting = "save", {}, nil
	changed()
	C_Timer.After(0, saveSome)
end

function Sweep.Running()
	return s ~= nil and not s.paused and s.step ~= "done"
end

function Sweep.Start()
	local a = AH()
	if not a or not Sweep.Possible() then return false, "noapi" end
	if not Market.IsOpen() then return false, "closed" end
	if s and s.step ~= "done" and s.paused and Market.Now() - s.pausedAt < TUNE.RESUME_S then
		s.paused, s.waiting, s.more, s.tries = false, nil, nil, 0
		after(0)
		changed()
		run()
		return true
	end
	if Sweep.Running() then return false, "busy" end
	s = {
		step = "browse", categories = Sweep.Categories(), qi = 1, si = 1, tries = 0,
		qualities = Qualities(), browseSorts = Sorts("Price", "Name"), searchSorts = Sorts("Buyout", "Bid"),
		best = {}, facts = {}, order = {}, pending = {}, searches = {},
		rows = 0, own = 0, notGear = 0, named = 0, lost = 0, pages = 0, sent = 0, skipped = 0, timeouts = 0,
		failures = 0, redone = 0, startedAt = Market.Now(), nextAt = 0,
	}
	if #s.categories == 0 then
		s = nil
		return false, "noapi"
	end
	changed()
	run()
	return true
end

-- Stops sending; Start goes on from the category (or item) it was at. `closed`: because the
-- Auction House closed.
function Sweep.Pause(closed)
	if not s or s.paused or s.step == "done" or s.step == "save" then return end
	s.paused, s.closed, s.pausedAt = true, closed == true, Market.Now()
	-- (The page that was out is asked for again: the category starts over from its first page.)
	s.waiting, s.more, s.tries, s.inQuery = nil, nil, 0, nil
	changed()
end

function Sweep.Progress()
	if not s or s.step == "done" then return nil end
	local p = { step = s.step, found = #s.order, paused = s.paused == true, closed = s.closed == true }
	if s.step == "browse" then
		p.done, p.total = s.qi - 1, #s.categories
	elseif s.step == "search" then
		p.done, p.total = s.si - 1, #s.searches
	else
		p.done, p.total = #s.items, #s.order
	end
	return p
end

-- Someone else's browse search while ours is out: the game answers theirs now, so ours goes
-- again from its first page once they have been quiet for TUNE.QUIET.
local function foreign()
	if mine or not s or s.paused or s.step ~= "browse" then return end
	if s.waiting or s.more or s.inQuery then
		s.waiting, s.more, s.tries, s.inQuery = nil, nil, 0, nil
		s.redone = s.redone + 1
	end
	after(TUNE.QUIET)
end
if type(hooksecurefunc) == "function" and type(C_AuctionHouse) == "table"
	and type(C_AuctionHouse.SendBrowseQuery) == "function" then
	pcall(hooksecurefunc, C_AuctionHouse, "SendBrowseQuery", foreign)
end

local frame = CreateFrame("Frame")
frame:SetScript("OnEvent", function(_, event, a1)
	if event == "AUCTION_HOUSE_CLOSED" then
		Sweep.Pause(true)
	elseif event == "ITEM_SEARCH_RESULTS_UPDATED" or event == "ITEM_SEARCH_RESULTS_ADDED" then
		onSearch(a1)
	else
		onBrowse(event, a1)
	end
end)
for _, event in ipairs({ "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED", "AUCTION_HOUSE_BROWSE_RESULTS_ADDED",
	"AUCTION_HOUSE_BROWSE_FAILURE", "ITEM_SEARCH_RESULTS_UPDATED", "ITEM_SEARCH_RESULTS_ADDED", "AUCTION_HOUSE_CLOSED" }) do
	pcall(frame.RegisterEvent, frame, event)
end

function Sweep.Debug()
	local out = {}
	local function add(text, ...) out[#out + 1] = "scan: " .. text:format(...) end
	local keys, tails = Learned()
	local nKeys, nTails = 0, 0
	for _ in pairs(keys) do nKeys = nKeys + 1 end
	for _, t in pairs(tails) do if type(t) == "table" and not t.bad and (t.n or 0) >= 2 then nTails = nTails + 1 end end
	if not s then
		add("none this session; rolled links known: %d items, %d rolls by suffix", nKeys, nTails)
		return out
	end
	add("%s%s: category %d of %d, %d pages, %d results read (%d not gear, %d only yours), %d items kept",
		s.step, s.paused and (s.closed and " (paused: Auction House closed)" or " (paused)") or "",
		math.min(s.qi, #s.categories), #s.categories, s.pages, s.rows, s.notGear, s.own, #s.order)
	add("rolled items searched: %d of %d, %d named, %d with no link; categories given up %d",
		math.max(0, s.si - 1), #s.searches, s.named, s.lost, s.skipped)
	add("messages sent %d, no answer in time %d, failures %d, started over for someone else's search %d",
		s.sent, s.timeouts, s.failures, s.redone)
	add("rolled links known: %d items, %d rolls by suffix", nKeys, nTails)
	return out
end
