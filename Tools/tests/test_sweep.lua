-- Sweep.lua on a stand-in Auction House (mocks.lua: ah.browse, browse pages, item searches): every
-- weapon and armor category is asked for, every page of it, at the game's pace; rolled items get
-- their own link; the scan pauses with the Auction House and goes on where it stopped; an answer
-- that never comes, or someone else's search, sends ours again; what is saved.

-- luacheck: globals C_AuctionHouse

local w = T.world()
w.load("Market.lua")
w.load("Sweep.lua")
local Market, Sweep, Stats = NS.Market, NS.Sweep, NS.Stats
local ah = w.ah
local A = C_AuctionHouse

local changed = 0
NS.On("MarketChanged", function() changed = changed + 1 end)

-- When each message of ours went out (w.time), to check the pace.
local sent = {}
local realSend, realMore = A.SendBrowseQuery, A.RequestMoreBrowseResults
A.SendBrowseQuery = function(q) sent[#sent + 1] = w.time; return realSend(q) end
A.RequestMoreBrowseResults = function() sent[#sent + 1] = w.time; return realMore() end
-- (Sweep.lua hooked the table's function when it loaded; ours wraps that, so its hook still sees
-- every call.)

local PLATE_CHEST = { classID = 4, subClassID = 4, inv = 5 }
local SWORD = { classID = 2, subClassID = 7 }

-- An item in the house: def as T.item's; where = PLATE_CHEST or SWORD; returns its row and link.
local function sale(def, where, price, more)
	def = def or {}
	def.equipLoc = def.equipLoc or (where == SWORD and "INVTYPE_WEAPON" or "INVTYPE_CHEST")
	local link = T.item(def)
	local id = Stats.ItemID(link)
	-- (The plain item too, so the item's kind is known from its ID alone, as in the game.)
	if def.roll then T.item({ id = id, equipLoc = def.equipLoc }) end
	local r = { itemID = id, suffix = more and more.suffix or 0, price = price, classID = where.classID,
		subClassID = where.subClassID, inv = where.inv }
	for k, v in pairs(more or {}) do r[k] = v end
	ah.browse[#ah.browse + 1] = r
	return r, link
end

local function fresh()
	T.reset()
	ah.browse, ah.samples, ah.results, ah.queries = {}, {}, {}, {}
	ah.silent, ah.searchSilent, ah.ready, ah.page, ah.delay = nil, nil, true, 3, 0.1
	ah.calls.browse, ah.calls.more, ah.calls.search, ah.calls.ask = 0, 0, 0, 0
	GloweyGearDB.houses, GloweyGearDB.akeys, GloweyGearDB.atails = {}, {}, {}
	sent = {}
	changed = 0
	w.settings.AuctionHouse.enabled = false   -- the game's own window: our scan is the way
	ah.open = true
	w.fire("AUCTION_HOUSE_SHOW")
end

-- Runs until the scan is done (at most `limit` seconds of game time).
local function finish(limit)
	for _ = 1, (limit or 300) * 50 do
		if not Sweep.Progress() then return true end
		w.frames(1)
	end
	return Sweep.Progress() == nil
end

local function priceOf(key)
	local e = Market.Saved()
	for _, text in ipairs(e and e.items or {}) do
		local k, copper = Market.Parse(text)
		if k == key then return copper end
	end
	return nil
end

T.case("the categories are the game's weapons and armor, nothing else", function()
	local cats = Sweep.Categories()
	T.check(#cats >= 40, "every weapon type and every armor type and slot: " .. #cats)
	for _, filters in ipairs(cats) do
		for _, f in ipairs(filters) do
			T.check(f.classID == 2 or f.classID == 4, "only weapons (2) and armor (4)")
		end
	end
	local robes = false
	for _, filters in ipairs(cats) do
		if #filters == 2 and filters[2].inventoryType == 20 then robes = true end
	end
	T.check(robes, "robes go with the chest pieces, as in the game's own list")
end)

T.case("a whole scan: every page, the cheapest of each item, saved as our own list", function()
	fresh()
	local plain = {}
	for i = 1, 7 do plain[i] = sale(nil, PLATE_CHEST, 1000 + i * 10) end           -- three pages
	local cheap = sale({ id = plain[1].itemID }, PLATE_CHEST, 500)                   -- a second listing, cheaper
	local sword = sale(nil, SWORD, 7000)
	local _, rolled = sale({ roll = 12756 }, SWORD, 900, { suffix = 14303 })
	ah.samples[Stats.ItemID(rolled) .. ":14303"] = rolled
	sale(nil, SWORD, 50, { own = true, qty = 1 })                                    -- only the player's own
	local shirt = sale({ equipLoc = "INVTYPE_BODY" }, PLATE_CHEST, 5)                -- not gear Gear scores
	T.eq(Market.Scan(), true, "the scan starts")
	T.eq(Sweep.Running(), true, "and runs")
	T.check(finish(), "and ends")
	T.eq(ah.calls.ask, 0, "the whole-house list is never asked for")
	T.eq(ah.calls.browse, #Sweep.Categories(), "one search per category")
	T.check(ah.calls.more >= 2, "and the next pages asked for: " .. ah.calls.more)
	local e = Market.Saved()
	T.check(e ~= nil, "a list is saved"); T.eq(e.by, "own", "as our own")
	T.eq(changed, 1, "MarketChanged once")
	T.eq(priceOf(tostring(cheap.itemID)), 500, "the cheapest listing of an item")
	T.eq(priceOf(tostring(plain[7].itemID)), 1070, "the last page read too")
	T.eq(priceOf(tostring(sword.itemID)), 7000, "weapons too")
	T.eq(priceOf(Stats.Key(rolled)), 900, "a rolled item under its own roll")
	T.eq(priceOf(tostring(shirt.itemID)), nil, "what Gear doesn't score is left out")
	T.eq(#e.items, 9, "7 chest pieces, the sword and the rolled one")
	local _, _, classID, subclassID, minLevel = Market.Parse(e.items[1])
	T.eq(classID, 4, "kept with its facts"); T.eq(subclassID, 0, "subclass"); T.eq(minLevel, 12, "and level")
	T.check(w.chat[#w.chat]:find("9", 1, true), "it says how many: " .. tostring(w.chat[#w.chat]))
	-- the pace: never two messages closer than the gap
	for i = 2, #sent do
		T.check(sent[i] - sent[i - 1] >= Sweep.TUNE.GAP - 0.001, "the gap between two messages")
	end
	T.eq(Market.CanScan(), true, "and it can be run again at once: no 15-minute limit")
end)

T.case("rolled items without a sample link: searched, learned, and learned once for all", function()
	fresh()
	local _, a = sale({ roll = 12756 }, SWORD, 100, { suffix = 501 })
	local _, b = sale({ roll = 12756 }, SWORD, 200, { suffix = 501 })
	local _, c = sale({ roll = 12756 }, SWORD, 300, { suffix = 501 })
	ah.results[Stats.ItemID(a)] = { { link = a, buyout = 100 } }
	ah.results[Stats.ItemID(b)] = { { link = b, buyout = 200 } }
	T.eq(Market.Scan(), true, "started")
	T.check(finish(), "ended")
	T.eq(ah.calls.search, 2, "two searches: the third item's roll was known by then")
	T.eq(priceOf(Stats.Key(a)), 100, "the first, by its search")
	T.eq(priceOf(Stats.Key(b)), 200, "the second, by its search")
	T.eq(priceOf(Stats.Key(c)), 300, "the third, by the roll the suffix was seen with twice")
	-- the next scan needs no search at all
	ah.calls.search = 0
	T.eq(Market.Scan(), true, "again")
	T.check(finish(), "ended")
	T.eq(ah.calls.search, 0, "learned rolls are kept")
end)

T.case("a rolled item no search can name is left out and counted", function()
	fresh()
	sale({ roll = 12756 }, SWORD, 100, { suffix = 777 })
	T.eq(Market.Scan(), true, "started")
	T.check(finish(), "ended")
	T.eq(#Market.Saved().items, 0, "nothing kept")
	T.eq(Market.Saved().lost, 1, "and counted")
end)

T.case("the game not taking messages: the scan waits", function()
	fresh()
	sale(nil, SWORD, 100)
	ah.ready = false
	T.eq(Market.Scan(), true, "started")
	w.advance(5)
	T.eq(ah.calls.browse, 0, "nothing sent while the game is busy")
	ah.ready = true
	T.check(finish(), "goes on when it takes messages again")
end)

T.case("the Auction House closes: paused, then on from where it was", function()
	fresh()
	for _ = 1, 4 do sale(nil, SWORD, 100) end
	T.eq(Market.Scan(), true, "started")
	w.advance(8)
	local before = Sweep.Progress()
	T.check(before.done > 0 and before.done < before.total, "part way: " .. before.done .. " of " .. before.total)
	ah.open = false
	w.fire("AUCTION_HOUSE_CLOSED")
	local p = Sweep.Progress()
	T.eq(p.paused, true, "paused"); T.eq(p.closed, true, "because it closed")
	local n = ah.calls.browse
	w.advance(10)
	T.eq(ah.calls.browse, n, "nothing sent while closed")
	T.eq(Market.Saved(), nil, "nothing saved yet")
	T.eq((Market.Scan()), false, "can't go on while closed")
	ah.open = true
	w.fire("AUCTION_HOUSE_SHOW")
	T.eq(Market.Scan(), true, "goes on")
	T.eq(Sweep.Progress().done, p.done, "from the category it was in")
	T.check(finish(), "and ends")
	T.eq(#Market.Saved().items, 4, "with everything")
end)

T.case("Stop Scan pauses; a pause older than half an hour starts over", function()
	fresh()
	sale(nil, SWORD, 100)
	T.eq(Market.Scan(), true, "started")
	w.advance(6)
	Sweep.Pause()
	T.eq(Sweep.Running(), false, "paused")
	local n = ah.calls.browse
	w.advance(5)
	T.eq(ah.calls.browse, n, "nothing sent")
	w.time = w.time + Sweep.TUNE.RESUME_S + 1
	T.eq(Market.Scan(), true, "started again")
	T.eq(Sweep.Progress().done, 0, "from the first category")
	T.check(finish(), "and ends")
end)

T.case("an answer that never comes: sent again, then the category is given up", function()
	fresh()
	sale(nil, SWORD, 100)
	ah.silent = true
	T.eq(Market.Scan(), true, "started")
	w.advance(Sweep.TUNE.WAIT + 2)
	T.eq(ah.calls.browse, 2, "sent again after the wait")
	ah.silent = nil
	T.check(finish(), "goes on")
	T.eq(#Market.Saved().items, 1, "and reads what the house has")
	ah.silent = true
	fresh()
	ah.silent = true
	local cats = #Sweep.Categories()
	sale(nil, SWORD, 100)
	T.eq(Market.Scan(), true, "started")
	w.advance(Sweep.TUNE.WAIT * (Sweep.TUNE.TRIES + 1) + 5)
	T.check(Sweep.Progress().done >= 1, "the first category given up after its tries")
	T.check(ah.calls.browse >= Sweep.TUNE.TRIES and ah.calls.browse <= cats * Sweep.TUNE.TRIES, "tries counted")
	Sweep.Pause()
	ah.silent = nil
end)

T.case("someone else's browse search: ours is sent again once they are quiet", function()
	fresh()
	for _ = 1, 7 do sale(nil, PLATE_CHEST, 100) end
	T.eq(Market.Scan(), true, "started")
	-- up to the plate chest category, its first page read
	for _ = 1, 3000 do
		local p = Sweep.Progress()
		if ah.queries[#ah.queries] and ah.queries[#ah.queries].itemClassFilters[1].inventoryType == 5
			and ah.cur and ah.cur.at > 0 then break end
		if not p then break end
		w.frames(1)
	end
	local n = ah.calls.browse
	A.SendBrowseQuery({ searchString = "linen", sorts = {}, itemClassFilters = {} })   -- the player
	w.advance(Sweep.TUNE.QUIET + 1)
	T.eq(ah.calls.browse, n + 2, "theirs, then ours again")
	T.check(finish(), "and the scan ends")
	T.eq(#Market.Saved().items, 7, "with every chest piece")
end)

T.case("a page the game's own list asks for is read too", function()
	fresh()
	for _ = 1, 5 do sale(nil, SWORD, 100) end
	T.eq(Market.Scan(), true, "started")
	for _ = 1, 3000 do
		if ah.cur and ah.cur.at > 0 and ah.cur.at < #ah.cur.match then break end
		w.frames(1)
	end
	realMore()   -- the game's browse list, scrolled (not through our wrapper: not ours)
	T.check(finish(), "ends")
	T.eq(#Market.Saved().items, 5, "with every page")
end)

T.case("learned rolled links not met for a month are dropped at login", function()
	fresh()
	local today = math.floor(Market.Now() / 86400)
	GloweyGearDB.akeys = { ["1:2"] = "1::::::2", ["3:4"] = "3::::::4", ["5:6"] = "5::::::6" }
	GloweyGearDB.aseen = { ["1:2"] = today - 31, ["3:4"] = today - 2, ["7:8"] = today }
	GloweyGearDB.atails = { [2] = { t = "x", n = 2, d = today - 40 }, [4] = { t = "y", n = 2 } }
	Sweep.Prune()
	T.eq(GloweyGearDB.akeys["1:2"], nil, "a link not met for a month goes")
	T.eq(GloweyGearDB.akeys["3:4"], "3::::::4", "a recent one stays")
	T.eq(GloweyGearDB.aseen["5:6"], today, "one from before the days were noted is given today")
	T.eq(GloweyGearDB.aseen["7:8"], nil, "a date with no link goes")
	T.eq(GloweyGearDB.atails[2], nil, "an old roll goes"); T.eq(GloweyGearDB.atails[4].d, today, "an undated roll is given today")
end)

T.case("AHDB's busy flag: set while the sweep sends, cleared at the end, another addon's left alone", function()
	rawset(_G, "AuctionDB", { LastPrice = function() end })
	fresh()
	sale({}, PLATE_CHEST, 1000)
	T.check(Sweep.Start(), "started")
	T.eq(rawget(_G, "AuctionDB").ahBusy, true, "set while it runs")
	T.check(finish(), "finished")
	T.eq(rawget(_G, "AuctionDB").ahBusy, nil, "cleared when it ended")
	fresh()
	rawget(_G, "AuctionDB").ahBusy = true    -- another addon's
	T.check(Sweep.Start(), "started again")
	T.check(finish(), "finished again")
	T.eq(rawget(_G, "AuctionDB").ahBusy, true, "another addon's flag left as it was")
	rawset(_G, "AuctionDB", nil)
end)

return T.done()
