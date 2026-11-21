-- Glowey's Gear: what a search says, put on top of what the scan said.
--
-- The saved list is the Auction House as the last Full scan saw it. Things sell. Whenever the
-- game shows the auctions of one item (the player opened it on the Buy page, clicked one of our
-- rows, or pressed Check Prices), the result says what each roll of that item costs NOW and
-- which rolls are gone, and that is learned here:
--
--   Check.Apply(itemID, auctions, cover, at)   the core (pure: no game call)
--        auctions = { { key = Stats.Key, price = buyout in copper (0: bid only), own = bool,
--                       id = auctionID }, ... }
--        cover    = { full = every auction of the search is in `auctions`,
--                     plain = the search covered the item's plain (unrolled) form,
--                     rolled = the search covered every roll of the item }
--   Check.CanRun()            -> ok, why        ("nodui" | "closed" | "reading" | "running")
--   Check.Start(itemIDs)      -> started        re-checks those items, one search at a time
--   Check.One(itemID)                           the same for one item (a click on a row)
--   Check.Stop()
--   Check.State()             -> running, done, total
--   Check.Debug()             -> lines for /gear debug
--   fires "PriceChanged" (key, copper, at)  copper 0 = none left;  "CheckProgress"
--
-- WHAT THE GAME GIVES TO TELL WHICH ITEM A RESULT IS. The events ITEM_SEARCH_RESULTS_UPDATED
-- (itemKey, newAuctionID) and ITEM_SEARCH_RESULTS_ADDED (itemKey) name the searched item key
-- (DOC AuctionHouseDocumentation.lua:1465-1471, :1455-1460); its results are read with
-- GetNumItemSearchResults(itemKey) (:519), GetItemSearchResultInfo(itemKey, i) (:374-386) and
-- HasFullItemSearchResults(itemKey) (:746). A result (ItemSearchResultInfo, :1665-1684) has its
-- own itemKey { itemID, itemLevel, itemSuffix } (:1637-1645), auctionID, itemLink,
-- containsOwnerItem and buyoutAmount (the price of one). The result's LINK is what maps it to
-- our key: on this client a roll travels in a link's bonus IDs (confirmed in play for the
-- scan's links: 14,335 of 17,015 items), and the item key's itemSuffix is another number
-- series that our keys do not hold. A result whose item key has a suffix while its link shows
-- no roll cannot be told apart from the plain item: such a result set is used for nothing,
-- and counted (/gear debug).
--
-- WHEN A SEARCH "COVERED" A KEY, so that its absence means "none left" and not "not asked":
--   1. the result set is complete: HasFullItemSearchResults says so, every result had a link,
--      and it was not cut off at our own cap;
--   2. the searched item key carried no suffix and no item level (a search for one suffix or
--      level says nothing about the others or about the plain item): then the plain key is
--      covered;
--   3. for the item's ROLLS, either the search was one we asked Daylight UI for (its search
--      for gear is the game's "sell search" with level and suffix cleared, which returns every
--      level and suffix: DUI DaylightUI_AuctionHouse\Search.lua:39-42, :331, :367; the docs say
--      of SendSellSearchQuery "ItemKey should have its iLVL and suffix cleared before
--      calling", DOC :1046-1048, and the game's own sell frame clears them "so you can compare
--      to similar items", FX Blizzard_AuctionHouseUI\Shared\Blizzard_AuctionHouseUtil.lua
--      :484-495), or the results themselves contain a rolled item (so this kind of search
--      plainly returns rolls). A plain search with a cleared key does not return suffixed gear
--      (Daylight UI's note, "seen in play", Search.lua:42): from such a result no roll is
--      ever marked gone.
-- A key seen in a complete result is re-priced whatever the rest says: every auction of that
-- key that the search could return is in it.
--
-- THE PLAYER'S OWN PURCHASE: AUCTION_HOUSE_PURCHASE_COMPLETED (auctionID) (DOC :1221-1227; the
-- game's own buyout dialog waits for it: FX Blizzard_AuctionHouseUI\Shared\
-- Blizzard_AuctionHouseFrame.lua:15, :31). The auction is taken out of the last result set it
-- was seen in, and its key gets the next lowest price left there, or "none left".
--
-- CHECK PRICES asks Daylight UI's own search for each item on screen, one at a time, through
-- the one adapter below (its Search.Item, which waits its turn on Daylight UI's request line
-- and keeps the game's limit of 100 searches a minute for us: Search.lua:1-3, :48, :413-435). Never beside that line; never while a purchase of Daylight UI's is pending
-- (Buy.Pending, Buy.lua:34, :101); stopped by Stop and by the Auction House closing. Without
-- Daylight UI's Auction House there is no Check Prices: what the player searches by hand in
-- the game's own window is still learned from.
--
-- luacheck: read globals C_AuctionHouse CreateFrame C_Timer GetServerTime issecretvalue

local _, ns = ...
if ns.off or not ns.ok then return end

local Check = {}
ns.Check = Check

local Game, Stats = ns.Game, ns.Stats
local secret = issecretvalue

local READ_MS = 2           -- time in one frame for reading results
local READ_MOST = 600      -- results read of one search at most (beyond that it is not "complete")
local GAP = 0.2            -- seconds between two searches of a run
local ANSWER = 20          -- seconds a search of a run may take before the run goes on without it

local counts = { results = 0, applied = 0, gone = 0, unmappable = 0, sent = 0, answered = 0, failed = 0, purchases = 0 }
Check.counts = counts
-- Why a search of Check Prices failed, counted by cause: Daylight UI's own reason for a search
-- that ended without rows ("timeout", "uncached": no key info came, "error", "closed",
-- "ruleset", "noruleset": its Search.lua:9-15), "refused" (its Search.Item raised an
-- error), "no answer" (its callback never came within ANSWER seconds).
local failedWhy = {}
Check.failedWhy = failedWhy
local function failed(why)
	why = type(why) == "string" and why or "unknown"
	counts.failed = counts.failed + 1
	failedWhy[why] = (failedWhy[why] or 0) + 1
end

local function plain(v)
	if v == nil or (secret and secret(v)) then return nil end
	return v
end

local function Now()
	local ok, t = pcall(GetServerTime)
	if ok and type(plain(t)) == "number" then return t end
	return 0
end

-- ---------------------------------------------------------------------------------------------
-- The core
-- ---------------------------------------------------------------------------------------------
local last = {}        -- itemID -> { auctions = { [auctionID] = { key, price, own } }, full = bool }
local byAuction = {}   -- auctionID -> itemID
local deferred = {}    -- itemID -> { lowest, cover, at }: "gone" marks waiting for the list's index

local function fix(key, copper, at)
	-- (The same answer again within a minute, as when a result set comes page by page and is
	-- read once more at its end: nothing new to tell.)
	local was, wasAt = ns.Market.Fixed(key)
	if was == copper and at - wasAt < 60 then return false end
	if not ns.Market.Fix(key, copper, at) then return false end
	if copper == 0 then counts.gone = counts.gone + 1 else counts.applied = counts.applied + 1 end
	ns.Fire("PriceChanged", key, copper, at)
	return true
end

-- Keys of the item that the list holds and the result does not: gone, where the search
-- covered them.
local function markGone(itemID, lowest, cover, at)
	if not (cover.plain or cover.rolled) then return end
	local keys = ns.Market.KeysOf(itemID)
	if not keys then
		-- (The list's index is being made: done when "MarketIndexed" comes.)
		deferred[itemID] = { lowest = lowest, cover = cover, at = at }
		return
	end
	for i = 1, #keys do
		local key = keys[i]
		if not lowest[key] then
			local rolled = Stats.IsRolled("item:" .. key)
			if (rolled and cover.rolled) or (not rolled and cover.plain) then
				local now = ns.Market.Fixed(key)
				if now ~= 0 then fix(key, 0, at) end
			end
		end
	end
end

function Check.Apply(itemID, auctions, cover, at)
	if not ns.Market.Saved() then return end
	at = at or Now()
	cover = cover or {}
	local lowest, set = {}, { auctions = {}, full = cover.full == true }
	for i = 1, #auctions do
		local a = auctions[i]
		if a.key and a.id then
			set.auctions[a.id] = a
			byAuction[a.id] = itemID
		end
		-- (The player's own auctions are not something to buy; a bid-only auction has no price.)
		if a.key and not a.own and type(a.price) == "number" and a.price > 0 then
			if not lowest[a.key] or a.price < lowest[a.key] then lowest[a.key] = a.price end
		end
	end
	local old = last[itemID]
	for id in pairs(old and old.auctions or {}) do
		if not set.auctions[id] then byAuction[id] = nil end
	end
	last[itemID] = set
	for key, price in pairs(lowest) do fix(key, price, at) end
	markGone(itemID, lowest, cover, at)
end

ns.On("MarketIndexed", function()
	local waiting = deferred
	deferred = {}
	for itemID, d in pairs(waiting) do markGone(itemID, d.lowest, d.cover, d.at) end
end)

-- The player bought an auction.
function Check.Bought(auctionID)
	local itemID = byAuction[auctionID]
	local set = itemID and last[itemID]
	local a = set and set.auctions[auctionID]
	if not a then return false end
	counts.purchases = counts.purchases + 1
	set.auctions[auctionID], byAuction[auctionID] = nil, nil
	local low
	for _, other in pairs(set.auctions) do
		if other.key == a.key and not other.own and type(other.price) == "number" and other.price > 0 then
			if not low or other.price < low then low = other.price end
		end
	end
	if low then
		fix(a.key, low, Now())
	elseif set.full then
		fix(a.key, 0, Now())
	end
	return true
end

-- ---------------------------------------------------------------------------------------------
-- Reading a result set from the game
-- ---------------------------------------------------------------------------------------------
local sell = {}        -- itemID -> true while a search of ours (Daylight UI's sell search) is out

local function AH()
	local a = rawget(_G, "C_AuctionHouse")
	if type(a) ~= "table" or type(a.GetNumItemSearchResults) ~= "function"
		or type(a.GetItemSearchResultInfo) ~= "function" or type(a.HasFullItemSearchResults) ~= "function" then
		return nil
	end
	return a
end

-- Result sets are read by one worker, READ_MS a frame at most (the clock looked at every 10
-- results), one item after another; an item whose results changed while it waited or was
-- being read is simply read afresh. (Reading every waiting item in one go, and arranging a
-- slot again for each corrected key, made a frame of 4.3 ms in play.)
local queue, queued, working = {}, {}, false

local function finishItem(a, state)
	local itemID, key = state.itemID, state.key
	if state.unmappable then
		counts.unmappable = counts.unmappable + 1
		return
	end
	local okF, full = pcall(a.HasFullItemSearchResults, key)
	local cover = {}
	cover.full = okF and plain(full) == true and not state.cut and not state.missing
	-- (A key searched with a level or a suffix covers only that level or suffix.)
	local suffix, level = plain(key.itemSuffix), plain(key.itemLevel)
	cover.plain = cover.full and (suffix == nil or suffix == 0) and (level == nil or level == 0)
	cover.rolled = cover.plain and (state.sell or state.anyRolled)
	Check.Apply(itemID, state.list, cover, Now())
end

-- Reads on from where the state stands until `t0 + READ_MS`; true when the item is through.
local function readSome(a, state, t0)
	local itemID, key = state.itemID, state.key
	if not state.n then
		local okN, n = pcall(a.GetNumItemSearchResults, key)
		n = okN and plain(n) or 0
		if type(n) ~= "number" then n = 0 end
		state.cut = n > READ_MOST
		state.n = state.cut and READ_MOST or n
	end
	local i = state.i
	while i < state.n do
		i = i + 1
		local ok, r = pcall(a.GetItemSearchResultInfo, key, i)
		if ok and type(r) == "table" then
			counts.results = counts.results + 1
			local link = plain(r.itemLink)
			local buyout = plain(r.buyoutAmount)
			if type(link) == "string" and Stats.ItemID(link) == itemID then
				local rolled = Stats.IsRolled(link)
				if rolled then state.anyRolled = true end
				local suffix = type(r.itemKey) == "table" and plain(r.itemKey.itemSuffix) or 0
				-- (The game says this auction is a suffixed item and its link shows no roll: the
				-- link cannot tell it from the plain item.)
				if type(suffix) == "number" and suffix ~= 0 and not rolled then state.unmappable = true end
				state.list[#state.list + 1] = { key = Stats.Key(link), price = type(buyout) == "number" and buyout or 0,
					own = plain(r.containsOwnerItem) == true, id = plain(r.auctionID) }
			else
				state.missing = true
			end
		else
			state.missing = true
		end
		if i % 10 == 0 and Game.Clock() - t0 >= READ_MS then break end
	end
	state.i = i
	return i >= state.n
end

local function work()
	working = false
	local a = AH()
	if not a or not ns.Market.IsOpen() then
		queue, queued = {}, {}
		return
	end
	local t0 = Game.Clock()
	while queue[1] do
		local state = queue[1]
		if queued[state.itemID] ~= state then
			table.remove(queue, 1)   -- (asked for afresh since: the newer state is further back)
		elseif readSome(a, state, t0) then
			table.remove(queue, 1)
			queued[state.itemID] = nil
			finishItem(a, state)
		end
		if Game.Clock() - t0 >= READ_MS then break end
	end
	ns.Perf.Time("check", Game.Clock() - t0)
	if queue[1] then
		working = true
		C_Timer.After(0, work)
	end
end

-- Puts an item's result set in line to be read (again, from its start, when it already was).
-- Whether the search was one of ours is noted now: the mark is taken off when its answer comes.
local function readItem(itemID, key)
	local state = { itemID = itemID, key = key, i = 0, list = {}, anyRolled = false, missing = false, unmappable = false,
		sell = sell[itemID] == true }
	queued[itemID] = state
	queue[#queue + 1] = state
	if not working then
		working = true
		C_Timer.After(0, work)
	end
end

-- A result set for an item key arrived (or grew).
local function onResults(itemKey)
	if type(itemKey) ~= "table" then return end
	local itemID = plain(itemKey.itemID)
	if type(itemID) ~= "number" then return end
	if not ns.Market.Saved() then return end
	-- (Only gear is ours: an instant call on the item ID.)
	local equipLoc = Game.ItemInstant(itemID)
	if not (equipLoc and Stats.GEAR[equipLoc]) then return end
	local key = { itemID = itemID, itemLevel = plain(itemKey.itemLevel) or 0, itemSuffix = plain(itemKey.itemSuffix) or 0,
		battlePetSpeciesID = plain(itemKey.battlePetSpeciesID) or 0 }
	Check.lastKey = Check.lastKey or {}
	Check.lastKey[itemID] = key
	readItem(itemID, key)
end
Check.OnResults = onResults

-- ---------------------------------------------------------------------------------------------
-- Check Prices: Daylight UI's own search, one item at a time
-- ---------------------------------------------------------------------------------------------
-- The one adapter: Daylight UI's Auction House module, its Search.Item and its Buy.Pending, or
-- nil when anything is not as read.
local function Dui()
	local m = ns.Market.DuiAH()
	if type(m) ~= "table" or type(m.Search) ~= "table" or type(m.Search.Item) ~= "function" then return nil end
	return m
end

local function Buying(m)
	local B = m.Buy
	if type(B) ~= "table" or type(B.Pending) ~= "function" then return false end
	local ok, what = pcall(B.Pending)
	return ok and what ~= nil
end

local run   -- { ids, at, total, token }

function Check.State()
	if not run then return false, 0, 0 end
	return true, run.at - 1, run.total
end

function Check.CanRun()
	if run then return false, "running" end
	if not ns.Market.IsOpen() then return false, "closed" end
	if not Dui() then return false, "nodui" end
	if ns.Market.State() == "reading" then return false, "reading" end
	return true
end

function Check.Stop()
	if not run then return end
	for _, itemID in ipairs(run.ids) do sell[itemID] = nil end
	run = nil
	ns.Fire("CheckProgress")
end

local Next

local function advance(token, delay)
	if not run or run.token ~= token then return end
	run.token = token + 1
	run.at = run.at + 1
	ns.Fire("CheckProgress")
	C_Timer.After(delay, Next)
end

Next = function()
	if not run then return end
	local m = Dui()
	if not m or not ns.Market.IsOpen() then return Check.Stop() end
	local itemID = run.ids[run.at]
	if not itemID then return Check.Stop() end
	-- (Daylight UI is in the middle of a purchase: its line is left alone until it is done.)
	if Buying(m) then
		C_Timer.After(0.5, Next)
		return
	end
	local token = run.token
	sell[itemID] = true
	counts.sent = counts.sent + 1
	local ok, started = pcall(m.Search.Item, itemID, function(rows, reason)
		if rows then
			counts.answered = counts.answered + 1
			-- (Read once more now that Daylight UI has every page: this is the complete set.)
			local key = Check.lastKey and Check.lastKey[itemID]
			if key and ns.Market.IsOpen() then readItem(itemID, key) end
		else
			failed(reason)
		end
		sell[itemID] = nil
		advance(token, GAP)
	end)
	if not ok or started == false then
		-- (It could not start, or ended at once: its callback has run, or never will.)
		sell[itemID] = nil
		if not ok then failed("refused") end
		return advance(token, GAP)
	end
	-- (An answer that never comes does not hold the run up for ever.)
	C_Timer.After(ANSWER, function()
		if run and run.token == token then
			failed("no answer")
			sell[itemID] = nil
			advance(token, 0)
		end
	end)
end

function Check.Start(ids)
	local ok = Check.CanRun()
	if not ok or type(ids) ~= "table" then return false end
	local list, seen = {}, {}
	for _, itemID in ipairs(ids) do
		if type(itemID) == "number" and not seen[itemID] then
			seen[itemID] = true
			list[#list + 1] = itemID
		end
	end
	if #list == 0 then return false end
	run = { ids = list, at = 1, total = #list, token = 1 }
	ns.Fire("CheckProgress")
	Next()
	return true
end

-- One item, now: a run of one, or put at the end of the run that is going.
function Check.One(itemID)
	if type(itemID) ~= "number" then return false end
	if run then
		for i = run.at, #run.ids do
			if run.ids[i] == itemID then return true end
		end
		run.ids[#run.ids + 1] = itemID
		run.total = run.total + 1
		return true
	end
	return Check.Start({ itemID })
end

-- ---------------------------------------------------------------------------------------------
-- Events
-- ---------------------------------------------------------------------------------------------
local frame = CreateFrame("Frame")
local LISTEN = { "ITEM_SEARCH_RESULTS_UPDATED", "ITEM_SEARCH_RESULTS_ADDED", "AUCTION_HOUSE_PURCHASE_COMPLETED" }
local function listen(on)
	for _, event in ipairs(LISTEN) do
		if on then pcall(frame.RegisterEvent, frame, event) else pcall(frame.UnregisterEvent, frame, event) end
	end
end
frame:SetScript("OnEvent", function(_, event, a)
	if event == "AUCTION_HOUSE_SHOW" then
		listen(true)
	elseif event == "AUCTION_HOUSE_CLOSED" then
		listen(false)
		Check.Stop()
		-- (Auction IDs mean nothing once the house is closed.)
		last, byAuction, deferred, sell = {}, {}, {}, {}
		queue, queued = {}, {}
		Check.lastKey = nil
	elseif event == "AUCTION_HOUSE_PURCHASE_COMPLETED" then
		if type(plain(a)) == "number" then Check.Bought(a) end
	else
		onResults(a)
	end
end)
for _, event in ipairs({ "AUCTION_HOUSE_SHOW", "AUCTION_HOUSE_CLOSED" }) do pcall(frame.RegisterEvent, frame, event) end

function Check.Debug()
	local fixes, gone = ns.Market.FixCount()
	local running, done, total = Check.State()
	local why = {}
	for reason, n in pairs(failedWhy) do why[#why + 1] = reason .. " " .. n end
	table.sort(why)
	return {
		("prices: %d search results read; %d prices corrected, %d marked as none left (now in force: %d, of them none left: %d); %d purchases of yours seen"):format(
			counts.results, counts.applied, counts.gone, fixes, gone, counts.purchases),
		("prices: Check Prices sent %d searches, %d answered, %d failed%s%s; result sets whose links showed no roll for a suffixed item: %d"):format(
			counts.sent, counts.answered, counts.failed, #why > 0 and (" (" .. table.concat(why, ", ") .. ")") or "", running and (" (running: %d of %d)"):format(done, total) or "", counts.unmappable),
	}
end
