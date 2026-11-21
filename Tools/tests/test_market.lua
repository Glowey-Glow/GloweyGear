-- Market.lua on a stand-in Auction House (mocks.lua, T.world): the whole-house list read in
-- slices, late item data, rows left out, a list replaced or closed part way, Daylight UI's scan
-- never doubled by one of ours, the 15-minute guard, and what is saved.
-- The globals stay locked: Market.lua may read only what T.world() gave it.
-- luacheck: read globals GetServerTime

local w = T.world()
w.load("Market.lua")
local Market, Stats = NS.Market, NS.Stats
local ah = w.ah

local changed, progress = 0, {}
NS.On("MarketChanged", function() changed = changed + 1 end)
NS.On("MarketProgress", function(done, total) progress[#progress + 1] = { done, total } end)

w.dui("Login")

local function gear(def)
	def = def or {}
	def.equipLoc = def.equipLoc or "INVTYPE_CHEST"
	return T.item(def)
end
local function junk() return T.item({ equipLoc = "", classID = 7 }) end
local function row(link, buyout, more)
	local r = { itemID = Stats.ItemID(link), link = link, buyout = buyout, count = 1 }
	for k, v in pairs(more or {}) do r[k] = v end
	ah.rows[#ah.rows + 1] = r
	return r
end
local function fresh()
	T.reset()
	ah.rows, ah.calls = {}, { info = 0, link = 0, ask = 0 }
	changed, progress = 0, {}
	w.clockStep = 0.05
end
local function open()
	ah.open = true
	w.fire("AUCTION_HOUSE_SHOW")
end
local function close(keepList)
	ah.open = false
	if not keepList then ah.rows = {} end
	w.fire("AUCTION_HOUSE_CLOSED")
end
local function listArrives() w.fire("REPLICATE_ITEM_LIST_UPDATE") end
-- Runs frames until no read is going (at most `limit` seconds).
local function settle(limit)
	-- (An event is looked at once a second at most: wait for the look that is due.)
	for _ = 1, 60 do
		if not Market.Looking() then break end
		w.frames(1)
	end
	for _ = 1, (limit or 30) * 50 do
		if Market.State() ~= "reading" then return true end
		w.frames(1)
	end
	return Market.State() ~= "reading"
end
local function saved() return DaylightGearDB.houses[Market.House()] end
local function priceOf(link)
	local list = Market.List()
	local want = "item:" .. Stats.Key(link)
	for i, l in ipairs(list and list.links or {}) do
		if l == want then return list.prices[i] end
	end
	return nil
end
local function debugText() return table.concat(Market.Debug(), "\n") end

T.case("nothing yet", function()
	fresh()
	T.eq(Market.State(), "none", "no list"); T.eq(Market.List(), nil, "List is nil"); T.eq(Market.Age(), nil, "no age")
	T.eq(Market.House(), "US-PvE", "the house is named as Daylight UI names it")
	local n = 0
	T.eq(Market.Feed({ Add = function() n = n + 1 end }), nil, "nothing to feed"); T.eq(n, 0, "and nothing was added")
	T.eq(Market.Saved(), nil, "nothing saved")
end)

T.case("thousands of rows are read in slices; the cheapest listing per item is kept", function()
	fresh()
	local links = {}
	for i = 1, 200 do links[i] = gear() end
	local other = junk()
	for i = 1, 6000 do
		if i % 6 == 0 then
			local k = (i / 6 - 1) % 200 + 1
			-- five listings per item: 500, 400, 300, 200, 100 copper more than k
			row(links[k], k + 500 - math.floor((i / 6 - 1) / 200) * 100)
		else
			row(other, 77)
		end
	end
	open()
	listArrives()
	T.eq(Market.State(), "none", "the event alone starts nothing in the same frame")
	w.frames(1)
	local state, _, total = Market.State()
	T.eq(state, "reading", "reading from the next frame on"); T.eq(total, 6000, "the list's size")
	w.frames(1)
	local _, done = Market.State()
	T.check(done > 0 and done <= 1000, "at most 1,000 rows in a frame (" .. tostring(done) .. ")")
	w.clockStep = 0.5   -- a slow machine: the 4 ms budget ends a slice long before 1,000 rows
	w.frames(1)
	local _, done2 = Market.State()
	T.check(done2 - done > 0 and done2 - done <= 180, "a slice stops at its time budget (" .. tostring(done2 - done) .. " rows)")
	w.clockStep = 0.05
	T.eq(changed, 0, "nothing saved while it reads")
	T.check(settle(), "the read ends")
	T.eq(changed, 1, "MarketChanged once"); T.eq(Market.State(), "ready", "ready")
	local list = Market.List()
	T.eq(#list.links, 200, "one entry per distinct item"); T.eq(#list.prices, 200, "with its price")
	T.eq(list.rows, 6000, "rows read"); T.eq(list.by, "dui", "read from Daylight UI's scan")
	T.eq(priceOf(links[1]), 101, "the cheapest of five listings"); T.eq(priceOf(links[200]), 300, "for every item")
	T.eq(ah.calls.link, 1000, "a link is asked only for gear rows with a buyout")
	T.eq(ah.calls.ask, 0, "and the list was never asked for by us")
	T.check(#progress > 5 and progress[#progress][1] == 6000, "progress was told")
	local e = saved()
	T.eq(type(e.at), "number", "saved: when"); T.eq(e.rows, 6000, "saved: rows"); T.eq(e.by, "dui", "saved: by")
	T.eq(#e.items, 200, "saved: items")
	for i = 1, #e.items do
		T.check(type(e.items[i]) == "string" and e.items[i]:match("^[%d:%-]+#%d+#%d+%.%d+%.%d+%.%d+$"), "saved as key#copper#facts: " .. tostring(e.items[i]))
	end
	T.check(Market.Age() >= 0 and Market.Age() < 5, "its age")
	local job = { n = 0, Add = function(self, link, price, classID, subclassID, loc, minLevel)
		self.n = self.n + 1
		T.check(link:match("^item:%d") and price > 0, "fed as an item string and a price")
		T.check(classID == 4 and type(subclassID) == "number" and loc == "INVTYPE_CHEST" and type(minLevel) == "number",
			"with what is known of the item without asking the game")
	end }
	T.eq(Market.Feed(job), nil, "Feed says the list is through"); T.eq(job.n, 200, "and adds each")
	-- in slices: fed until the caller says the frame's time is up, and picked up where it stopped
	local part = { n = 0, Add = function(self) self.n = self.n + 1 end }
	local looks = 0
	local at = Market.Feed(part, 1, function() looks = looks + 1 return looks >= 2 end)
	T.eq(at, 50, "stopped at the second look (one every 25 entries)"); T.eq(part.n, 49, "with 49 fed")
	at = Market.Feed(part, at)
	T.eq(at, nil, "the rest in one go"); T.eq(part.n, 200, "every entry exactly once")
	T.check(Market.List() == list, "the decoded list is kept until the next one")
end)

T.case("echoes of the event after a read start nothing", function()
	local calls = ah.calls.info
	for _ = 1, 500 do listArrives() end
	w.frames(3)
	T.eq(Market.State(), "ready", "still ready"); T.eq(changed, 1, "no second list")
	T.check(ah.calls.info - calls < 60, "one cheap look for a frame of events (" .. (ah.calls.info - calls) .. " calls)")
	T.check(debugText():find("reads started 1, started over 0", 1, true), "debug counts one read: " .. debugText())
end)

T.case("rows left out: no buyout, not gear, the player's own, a roll only in the name, a wrong link", function()
	fresh()
	local a, b, c, d = gear(), gear(), gear(), gear()
	local base = gear({ id = 5001, name = "Plain Band", equipLoc = "INVTYPE_FINGER" })
	gear({ id = 5002, name = "Jade Ring", equipLoc = "INVTYPE_FINGER" })
	local rolled = gear({ id = 5002, suffix = 1204, name = "Jade Ring of the Bear", equipLoc = "INVTYPE_FINGER" })
	gear({ id = 5003, name = "Onyx Ring", equipLoc = "INVTYPE_FINGER" })
	row(a, 100); row(a, 0)                         -- bid only
	row(b, 200, { owner = "Tester" })              -- the player's own
	row(c, 300, { owner = "Somebody" })            -- someone else's with a name (older clients)
	row(junk(), 5)
	row(base, 400)
	row(rolled, 500)
	-- a roll the link only names: the fields are the plain item's
	row(T.link(5003, "", "Onyx Ring of the Bear"), 600)
	-- a link that is another item's
	row(d, 700, { itemID = 4 })
	T.item({ id = 4, equipLoc = "INVTYPE_HEAD" })
	open(); listArrives(); w.frames(1)
	T.check(settle(), "read")
	T.eq(#Market.List().links, 4, "a, c, the plain band and the rolled ring")
	T.eq(priceOf(a), 100, "a at its buyout"); T.eq(priceOf(b), nil, "own auction left out"); T.eq(priceOf(c), 300, "another seller's kept")
	T.eq(priceOf(rolled), 500, "a roll with its suffix in the link is its own item")
	T.check(Stats.Key(rolled) ~= Stats.Key(T.link(5002, "", "Jade Ring")), "keyed apart from the plain item")
	local text = debugText()
	for _, reason in ipairs({ "no buyout 1", "not gear 1", "own auction 1", "roll only in the name 1", "no link 1" }) do
		T.check(text:find(reason, 1, true), "debug says: " .. reason .. "\n" .. text)
	end
	T.check(text:find("1 with bonus IDs", 1, true), "debug counts the link shapes: the roll travels as a bonus ID\n" .. text)
	T.check(text:find("a rolled link: ||cff", 1, true), "and shows one, escaped")
	T.check(text:find("rows with an owner 2", 1, true), "and whether owners are named")
end)

T.case("item data that arrives late", function()
	fresh()
	local now, later, never, refused = gear(), gear(), gear(), gear()
	row(now, 10)
	local r1 = row(later, 20, { late = true })
	local r1b = row(later, 15, { late = true })
	row(never, 30, { late = true })
	local r3 = row(refused, 40, { late = true })
	row(junk(), 5, { late = true })    -- not gear: never waited for
	open(); listArrives(); w.frames(3)
	T.eq(Market.State(), "reading", "waits for the items")
	T.eq(WORLD.calls.RequestItem, 3, "each missing gear item asked for once")
	T.eq(ah.calls.link, 5, "a link is asked for every gear row (it is what tells whether the row can be read yet)")
	w.advance(4)
	T.eq(Market.State(), "reading", "still waiting after the settle time")
	r1.late, r1b.late = nil, nil
	w.fire("ITEM_DATA_LOAD_RESULT", Stats.ItemID(later), true)
	w.fire("GET_ITEM_INFO_RECEIVED", Stats.ItemID(refused), false)
	T.eq(r3.late, true, "(the refused one never loads)")
	w.frames(2)
	T.eq(changed, 0, "one item is still out")
	T.check(settle(20), "the wait ends by itself")
	T.eq(changed, 1, "saved")
	T.eq(priceOf(now), 10, "the loaded row"); T.eq(priceOf(later), 15, "the late rows, cheapest")
	T.eq(priceOf(never), nil, "what never loaded is left out"); T.eq(priceOf(refused), nil, "and what the game refused")
	T.check(debugText():find("item never loaded 2", 1, true), "debug counts them: " .. debugText())
end)

T.case("blank rows that fill in, and a list that grows while it is read", function()
	fresh()
	local a, b, c = gear(), gear(), gear()
	row(a, 10)
	local blank = row(b, 20, { blank = true })
	open(); listArrives(); w.frames(2)
	T.eq(Market.State(), "reading", "settling")
	blank.blank = nil
	row(c, 30)
	T.check(settle(), "read")
	T.eq(#Market.List().links, 3, "the filled row and the new row are both in"); T.eq(Market.List().rows, 3, "rows")
end)

T.case("a list replaced while it is read is read from the start", function()
	fresh()
	local old, new = {}, {}
	for i = 1, 30 do old[i] = gear() end
	for i = 1, 3000 do row(old[(i - 1) % 30 + 1], 1000 + i) end
	open(); listArrives(); w.frames(2)
	local _, done = Market.State()
	T.check(done > 0 and done < 3000, "part way (" .. tostring(done) .. ")")
	ah.rows = {}
	for i = 1, 20 do new[i] = gear() end
	for i = 1, 3000 do row(new[(i - 1) % 20 + 1], 50 + i) end
	listArrives()
	T.check(settle(), "read")
	T.eq(changed, 1, "one list saved")
	T.eq(#Market.List().links, 20, "only the new list's items"); T.eq(priceOf(old[1]), nil, "nothing of the old one")
	T.eq(priceOf(new[1]), 51, "the new one's prices")
	T.check(debugText():find("started over 1", 1, true), "debug says it started over")
end)

T.case("closed part way: the list gone keeps the old one", function()
	local before = Market.List()
	local kept = #before.links
	ah.rows = {}
	changed, progress = 0, {}
	for _ = 1, 3000 do row(gear(), 9) end
	listArrives(); w.frames(2)
	T.eq(Market.State(), "reading", "a new list is being read")
	close()
	w.frames(2)
	T.eq(Market.State(), "ready", "the read stopped"); T.eq(changed, 0, "nothing saved")
	T.check(Market.List() == before and #Market.List().links == kept, "the old list stands")
	T.eq(progress[#progress][1], nil, "the window is told the read ended")
	w.advance(3)
	local text = debugText()
	T.check(text:find("the Auction House closed", 1, true), "debug says why: " .. text)
	T.check(text:find("2 s later: 0 rows", 1, true), "and what the game still had")
end)

T.case("closed part way: a list the game still holds is read to its end", function()
	fresh()
	local items = {}
	for i = 1, 40 do items[i] = gear() end
	for i = 1, 3000 do row(items[(i - 1) % 40 + 1], 100 + i) end
	open(); listArrives(); w.frames(2)
	close(true)
	T.check(settle(), "read")
	T.eq(changed, 1, "saved"); T.eq(#Market.List().links, 40, "whole")
	w.advance(3)
	local text = debugText()
	T.check(text:find("finished after the Auction House closed", 1, true), "debug says so: " .. text)
	T.check(text:find("2 s later: 3000 rows, row 0 readable, its link readable", 1, true), "and what the game still had")
end)

T.case("closed after every row was walked: saved at once", function()
	fresh()
	row(gear(), 10); row(gear(), 20)
	open(); listArrives(); w.frames(3)
	T.eq(Market.State(), "reading", "settling")
	close()
	w.advance(0.5)   -- (its next look, a quarter second away)
	T.eq(changed, 1, "saved"); T.eq(#Market.List().links, 2, "both rows")
end)

T.case("Daylight UI's ScanEnded reads a list the game's event did not announce", function()
	fresh()
	T.eq(Market.Hook(), true, "hooked")
	row(gear(), 10)
	open()
	w.ahmodFire("ScanStarted", "US-PvE")
	w.ahmodFire("ScanEnded", false, "stopped")
	w.frames(2)
	T.eq(Market.State() ~= "reading", true, "a stopped scan starts nothing")
	w.ahmodFire("ScanEnded", true, "done", 1, {})
	w.frames(1)
	T.eq(Market.State(), "reading", "a finished scan does")
	T.check(settle(), "read"); T.eq(#Market.List().links, 1, "saved")
end)

T.case("never a scan of our own while Daylight UI's Auction House is in use", function()
	fresh()
	open()
	local ok, why = Market.CanScan()
	T.eq(ok, false, "CanScan is false"); T.eq(why, "dui", "because of Daylight UI")
	ok, why = Market.Scan()
	T.eq(ok, false, "Scan refuses"); T.eq(why, "dui", "and says why"); T.eq(ah.calls.ask, 0, "nothing was asked of the game")
end)

T.case("our own read: only when allowed, once in 15 minutes", function()
	fresh()
	DaylightGearDB.houses = {}
	Market.Prune()
	close()
	w.settings.AuctionHouse.enabled = false     -- the player keeps the game's own window
	local ok, why = Market.CanScan()
	T.eq(ok, false, "closed"); T.eq(why, "closed", "says closed")
	open()
	T.eq(Market.CanScan(), true, "allowed at the open Auction House")
	ah.ready = false
	ok, why = Market.Scan()
	T.eq(ok, false, "the game is not taking messages"); T.eq(why, "throttled", "says so"); T.eq(ah.calls.ask, 0, "nothing sent")
	ah.ready = true
	T.eq(Market.Scan(), true, "asked"); T.eq(ah.calls.ask, 1, "once")
	local state, done, total = Market.State()
	T.eq(state, "reading", "waiting for the list"); T.eq(done, 0, "0"); T.eq(total, 0, "of 0")
	ok, why = Market.Scan()
	T.eq(ok, false, "not twice"); T.eq(why, "busy", "busy")
	local a = gear()
	row(a, 123)
	listArrives(); w.frames(1)
	T.check(settle(), "read")
	T.eq(Market.List().by, "own", "the list is our own"); T.eq(priceOf(a), 123, "with its row")
	local left
	ok, why, left = Market.CanScan()
	T.eq(ok, false, "not again"); T.eq(why, "cooldown", "cooldown"); T.check(left > 800 and left <= 900, "about 15 minutes left (" .. tostring(left) .. ")")
	T.eq(Market.Scan(), false, "Scan refuses too"); T.eq(ah.calls.ask, 1, "still one ask")
	w.time = w.time + 901
	T.eq(Market.CanScan(), true, "allowed again after 15 minutes")
	-- an ask that gets no answer frees the state after its wait
	T.eq(Market.Scan(), true, "asked again")
	w.advance(91)
	T.eq(Market.State(), "ready", "no answer: back to the saved list")
	T.eq(select(2, Market.CanScan()), "cooldown", "but the ask still counts")
	-- another addon's scan, with Daylight UI's house not in use
	w.time = w.time + 901
	ah.rows = {}
	row(gear(), 5); row(gear(), 6)
	listArrives(); w.frames(1)
	T.check(settle(), "read"); T.eq(Market.List().by, "other", "somebody else's scan is read too")
	T.eq(select(2, Market.CanScan()), "cooldown", "and counts for the game's limit")
	-- DaylightMogul owning the house also frees our own read
	w.settings.AuctionHouse.enabled = true
	T.eq(select(2, Market.CanScan()), "dui", "Daylight UI's house back in use")
	-- DaylightMogul runs the house: it scans it itself, and ours would spend the scan it needs
	w.DUI.ahMogul = true
	T.eq(Market.DuiAH(), nil, "Daylight UI's own house is not the one in use")
	local offered, reason = Market.CanScan()
	T.eq(offered, false, "no scan of ours is offered beside DaylightMogul's"); T.eq(reason, "other", "and the reason says so")
	w.DUI.ahMogul = nil
end)

T.case("the house key without Daylight UI's module", function()
	local mod = w.ahmod
	w.ahmod = nil
	T.eq(Market.House(), "realm4407-Alliance", "the realm's number (from the GUID) and the faction")
	T.eq(Market.DuiAH(), nil, "Daylight UI's Auction House is not reachable")
	w.ahmod = { enabled = true, ns = { Ruleset = { Key = function() error("changed") end } } }
	T.eq(Market.House(), "realm4407-Alliance", "an adapter that fails falls back")
	-- the game gives no realm name (this client since 2026-11-20): the key does not change, and
	-- two realms or two factions never share a house
	WORLD.realm = ""
	T.eq(Market.House(), "realm4407-Alliance", "an empty realm name changes nothing")
	WORLD.faction = "Horde"
	T.eq(Market.House(), "realm4407-Horde", "the other faction is another house")
	WORLD.guid = "Player-5555-0BADF00D"
	T.eq(Market.House(), "realm5555-Horde", "another realm is another house")
	WORLD.realmID = 77
	T.eq(Market.House(), "realm77-Horde", "the game's own realm number wins over the GUID's")
	WORLD.realmID, WORLD.guid = nil, nil
	T.eq(Market.House(), nil, "no number and no name: nothing is saved rather than saved under a shared key")
	WORLD.realm = "Test Realm"
	T.eq(Market.House(), "Test Realm-Horde", "a name alone will do when there is no number")
	WORLD.guid, WORLD.faction = "Player-4407-00ABCDEF", "Alliance"
	w.ahmod = mod
	T.eq(Market.House(), "US-PvE", "back")
end)

T.case("what is saved, and old houses pruned at login", function()
	local now = GetServerTime()
	DaylightGearDB.houses = {
		["US-PvE"] = { at = now - 100, rows = 9, by = "dui", items = { "1001#500", "1002::::::::::::1:12745#70000", "broken", "#5", "1003#0" } },
		["US-Old"] = { at = now - 31 * 86400, rows = 1, by = "dui", items = { "1#1" } },
		["US-Asked"] = { asked = now - 5 },
		["US-Recent"] = { at = now - 29 * 86400, rows = 1, by = "own", items = {} },
		junk = "text",
	}
	w.dui("Login")
	local houses = DaylightGearDB.houses
	T.check(houses["US-PvE"] ~= nil and houses["US-Recent"] ~= nil and houses["US-Asked"] ~= nil, "recent houses stay")
	T.eq(houses["US-Old"], nil, "a house not read for 30 days goes"); T.eq(houses.junk, nil, "and what is not a house")
	local list = Market.List()
	T.eq(#list.links, 2, "only well-formed entries are listed")
	T.eq(list.links[1], "item:1001", "an item string"); T.eq(list.prices[1], 500, "its copper")
	T.eq(list.links[2], "item:1002::::::::::::1:12745", "a roll's key is its item string"); T.eq(list.prices[2], 70000, "its copper")
	T.eq(Stats.Key(list.links[2]), "1002::::::::::::1:12745", "which reads back as the same roll (bonus count in field 13)")
	T.check(Stats.IsRolled(list.links[2]), "and is a roll")
	T.eq(Market.Age(), 100, "age from the saved time")
	T.eq(Market.State(), "ready", "ready from the saved list alone")
end)

T.case("a price above 2^31 copper is saved and read back whole (the audit's L7)", function()
	fresh()
	local dear = gear()
	local price = 3000000000   -- 300,000 gold
	row(dear, price)
	open(); listArrives(); w.frames(1)
	T.check(settle(), "read")
	local entry = saved()
	T.check(entry.items[1]:find("#3000000000#", 1, true), "written in full: " .. tostring(entry.items[1]))
	T.eq(priceOf(dear), price, "and read back")
end)

T.case("a blank row answers 0 or nil for its item, and both are read again", function()
	fresh()
	local a, b, c = gear(), gear(), gear()
	row(a, 10)
	local zero = row(b, 20, { blank = true })       -- itemID 0, as the docs type it
	local none = row(c, 30, { blank = "nil" })      -- itemID nil
	open(); listArrives(); w.frames(2)
	T.eq(Market.State(), "reading", "settling")
	zero.blank, none.blank = nil, nil
	T.check(settle(), "read")
	T.eq(#Market.List().links, 3, "all three rows are in once they fill")
end)

T.case("items get time to load", function()
	T.check(Market.TUNE.ITEM_MAX_MS >= 120000, "the longest wait for item data is at least Daylight UI's two minutes (the audit's L6)")
	T.check(Market.TUNE.ITEM_MS < Market.TUNE.ITEM_MAX_MS, "and a shorter one for 'nothing arrives any more'")
end)

T.case("a row is read as soon as it has a link, whatever 'hasAllInfo' says", function()
	-- A real house lost 27,689 of 85,406 gear rows while rows were only read once the game set
	-- hasAllInfo. The row's link is all that is needed, and it is there as soon as the item is.
	fresh()
	local a, b = gear(), gear()
	local r = row(a, 10)
	row(b, 20)
	local house = rawget(_G, "C_AuctionHouse")
	local info = house.GetReplicateItemInfo
	house.GetReplicateItemInfo = function(index)
		local t = { info(index) }
		if ah.rows[index + 1] == r then t[18] = false end   -- hasAllInfo false, but the link is there
		return unpack(t, 1, 18)
	end
	open(); listArrives(); w.frames(1)
	T.check(settle(), "read")
	house.GetReplicateItemInfo = info
	T.eq(priceOf(a), 10, "the row with a link is kept"); T.eq(priceOf(b), 20, "like any other")
	T.eq(saved().lost, 0, "nothing lost")
	T.check(not debugText():find("item never loaded", 1, true), "and nothing skipped for it")
end)

T.case("gear that could not be read is counted and saved with the list", function()
	fresh()
	local ok, never, never2 = gear(), gear(), gear()
	row(ok, 10)
	row(never, 20, { late = true }); row(never, 25, { late = true }); row(never2, 30, { late = true })
	open(); listArrives(); w.frames(3)
	T.eq(WORLD.calls.RequestItem, 2, "each missing item asked for")
	T.check(settle(60), "the wait ends by itself")
	local e = saved()
	T.eq(#e.items, 1, "the readable one is saved"); T.eq(e.lost, 2, "two items could not be read"); T.eq(e.lostRows, 3, "in three rows")
	T.check(debugText():find("gear items that could not be read: 2 (3 rows)", 1, true), "debug says so: " .. debugText())
	T.eq(Market.List().lost, 2, "and the list carries the count for the window")
end)

T.case("item loads are asked for at a measured pace", function()
	fresh()
	for _ = 1, 300 do row(gear(), 10, { late = true }) end
	open(); listArrives(); w.frames(2)
	T.check((WORLD.calls.RequestItem or 0) <= 2 * Market.TUNE.ASKS_A_FRAME, "not 300 in one frame (" .. tostring(WORLD.calls.RequestItem) .. ")")
	w.frames(20)
	T.eq(WORLD.calls.RequestItem, 300, "all of them within a few frames, each once")
	close(); w.advance(1)
end)

T.case("the list event is nearly free, however often it comes", function()
	-- 97,376 list events came in one real scan (one per item the game loaded).
	fresh()
	for _ = 1, 30 do row(gear(), 10) end
	open(); listArrives(); w.frames(1)
	T.check(settle(), "read")
	local rows, counts = ah.calls.info, ah.calls.link
	-- echoes with no read running: 5,000 events over two seconds
	for _ = 1, 100 do
		for _ = 1, 50 do listArrives() end
		w.frames(1)
	end
	T.eq(changed, 1, "no new read: it is the list already read")
	T.check(ah.calls.info - rows <= 3 * 4, "the list is looked at about once a second, a few rows each time (" .. (ah.calls.info - rows) .. " row reads for 5,000 events)")
	T.eq(ah.calls.link, counts, "and no link is asked for")
	-- echoes while a read runs: the "was it replaced" check is rare too
	fresh()
	for _ = 1, 4000 do row(gear({ id = 61000 }), 10) end
	open(); listArrives()
	for _ = 1, 60 do if not Market.Looking() then break end w.frames(1) end
	w.frames(1)
	T.eq(Market.State(), "reading", "reading")
	rows = ah.calls.info
	for _ = 1, 3 do
		for _ = 1, 500 do listArrives() end
		w.frames(1)
	end
	T.check(ah.calls.info - rows <= 3 * Market.TUNE.ROWS_A_FRAME + 30, "1,500 events in three frames cost no extra row reads (" .. (ah.calls.info - rows) .. ")")
	T.check(settle(), "and the read ends")
	-- a long list keeps a fixed, small number of probe rows
	local probes = 0
	for index = 0, 232540 do
		if index < 3 or (index % 1000 == 500 and index < 20000) then probes = probes + 1 end
	end
	T.eq(probes, 23, "23 probe rows for a house of 232,540 rows, not 235")
end)

T.case("the saved form: facts with each item, old entries still read", function()
	local key, copper, classID, sub, level, loc = Market.Parse("7444::::::::::::1:12751#70000#4.3.28.8")
	T.eq(key, "7444::::::::::::1:12751", "key"); T.eq(copper, 70000, "copper"); T.eq(classID, 4, "item class")
	T.eq(sub, 3, "subclass"); T.eq(level, 28, "required level"); T.eq(loc, "INVTYPE_FEET", "equip location")
	key, copper, classID = Market.Parse("1001#500")
	T.eq(key, "1001", "an entry with no facts: key"); T.eq(copper, 500, "copper"); T.eq(classID, nil, "and no facts")
	T.eq(Market.Parse("broken"), nil, "junk"); T.eq(Market.Parse("#5"), nil, "no key"); T.eq(Market.Parse("1003#0"), nil, "no price")
	key, copper, classID = Market.Parse("1004#77#4.3.28.99")
	T.eq(key, "1004", "facts that name no equip location are dropped"); T.eq(copper, 77, "the price kept"); T.eq(classID, nil, "and the entry kept without them")
	T.eq(Market.LOCS[8], "INVTYPE_FEET", "the equip location numbers are fixed"); T.eq(#Market.LOCS, 23, "one for each gear location")
	for i, loc2 in ipairs(Market.LOCS) do T.check(Stats.GEAR[loc2], loc2 .. " (" .. i .. ") is gear") end
	-- the required level is read while the scan has the item, and saved
	fresh()
	local boots = gear({ equipLoc = "INVTYPE_FEET", subclassID = 3, minLevel = 28 })
	row(boots, 70000)
	open(); listArrives(); w.frames(1)
	T.check(settle(), "read")
	T.check(saved().items[1]:find("#70000#4.3.28.8", 1, true), "class 4, subclass 3, level 28, location 8: " .. saved().items[1])
end)

T.case("a big list is saved over several frames, and nothing reads half of it", function()
	fresh()
	for i = 1, 3000 do row(gear({ id = 70000 + i }), 100 + i) end
	open(); listArrives()
	w.clockStep = 0.2     -- (a clock look costs 0.2 ms here: the saving is cut into many slices)
	local frames, half = 0, false
	for _ = 1, 4000 do
		w.frames(1)
		frames = frames + 1
		if Market.State() ~= "reading" then break end
		local e = saved()
		-- (whatever was saved before stays in place, whole, until the new list is)
		if e and #e.items > 1 and #e.items < 3000 then half = true end
		if e and #e.items == 3000 then half = true end
	end
	w.clockStep = 0.05
	T.eq(Market.State(), "ready", "saved in the end"); T.eq(#saved().items, 3000, "all 3,000 items")
	T.eq(changed, 1, "MarketChanged once, when the list is whole")
	T.check(not half, "while it was being saved, nobody could see half a list")
	T.check(frames > 100, "and the saving took its time in slices (" .. frames .. " frames in all)")
end)

T.case("why a row gave no link is counted by cause", function()
	fresh()
	local fine, quiet, refused, nolink = gear(), gear(), gear(), gear()
	row(fine, 10)
	row(quiet, 20, { late = true })
	row(refused, 30, { late = true }); row(refused, 31, { late = true })
	row(nolink, 40, { late = true })
	open(); listArrives(); w.frames(3)
	w.fire("ITEM_DATA_LOAD_RESULT", Stats.ItemID(refused), false)
	-- the item arrives, as often as it is asked for, and its row still has no link
	for _ = 1, Market.TUNE.ITEM_TRIES + 1 do
		w.fire("ITEM_DATA_LOAD_RESULT", Stats.ItemID(nolink), true)
		w.advance(0.6)
	end
	T.check(settle(40), "the wait ends by itself")
	local text = debugText()
	T.check(text:find("by cause: nolink 1, quiet 1, refused 2", 1, true), "each cause counted: " .. text)
	T.eq(saved().lostRows, 4, "four rows"); T.eq(saved().lost, 3, "of three items")
	close(); w.advance(1)
	-- the Auction House closing while rows wait
	fresh()
	row(gear(), 10); row(gear(), 20, { late = true })
	open(); listArrives(); w.frames(3)
	close(true)
	T.check(settle(40), "the read ends")
	T.check(debugText():find("by cause: closed 1", 1, true), "cut off by the Auction House closing: " .. debugText())
	ah.rows = {}
end)

T.case("the quiet clock starts when the walk ends, not before", function()
	-- Arrivals that stop while the list is still being walked must not end the wait the
	-- moment the walk is through: the rows walked last would get no time at all.
	fresh()
	local early = gear()
	row(early, 5, { late = true })
	for _ = 1, 40000 do row(junk(), 7) end
	local last = gear()
	local r = row(last, 9, { late = true })
	w.clockStep = 0.5   -- a slow machine: the walk takes many seconds
	open(); listArrives()
	local walked
	for _ = 1, 5000 do
		w.frames(1)
		local _, done, total = Market.State()
		if done and total and done >= total then walked = true break end
	end
	T.check(walked, "the walk ended")
	w.clockStep = 0.05
	T.check(w.time - 1000 > 0, "time passed")
	w.advance(5)
	T.eq(Market.State(), "reading", "five seconds after the walk the read still waits for the last row")
	r.late = nil
	w.fire("ITEM_DATA_LOAD_RESULT", Stats.ItemID(last), true)
	T.check(settle(40), "then it ends")
	T.eq(priceOf(last), 9, "and the row walked last was read")
	close(); w.advance(1)
end)

T.case("rows given up are asked for again after the list is saved, and join it", function()
	fresh()
	local added = {}
	NS.On("MarketAdded", function(key, copper, what) added[#added + 1] = key .. "=" .. copper .. " " .. what end)
	local fine, late1, late2, never = gear(), gear(), gear(), gear()
	row(fine, 10)
	local a = row(late1, 20, { late = true })
	local b = row(late2, 30, { late = true })
	local b2 = row(late2, 25, { late = true })
	local c = row(fine, 8, { late = true })
	row(never, 40, { late = true })
	open(); listArrives(); w.frames(3)
	T.check(settle(40), "the wait ends and the list is saved without them")
	T.eq(#saved().items, 1, "one item saved"); T.eq(saved().lost, 4 - 1, "three items lost (one of them also has a row that was read)")
	T.eq(saved().lostRows, 5, "in five rows")
	local working, left = Market.Tail()
	T.eq(working, true, "the tail is at work"); T.eq(left, 5, "on five rows")
	T.eq(changed, 1, "saved once")
	-- their links come, late
	a.late, b.late, b2.late, c.late = nil, nil, nil, nil
	w.advance(4)
	T.eq(priceOf(late1), 20, "a row read late joins the saved list"); T.eq(priceOf(late2), 25, "at its cheapest listing")
	T.eq(priceOf(fine), 8, "a cheaper listing of an item already there lowers its price")
	T.eq(#added, 4, "the window is told of each change (two new items, one of them twice, one cheaper): " .. table.concat(added, "; "))
	T.eq(changed, 1, "without the list counting as a new one")
	T.eq(saved().lostRows, 1, "one row still out"); T.eq(saved().lost, 1, "of one item")
	local _, key2, facts = saved().items[2]:match("^([^#]+)#(%d+)#(.+)$")
	T.check(key2 ~= nil and facts ~= nil, "a row added late is saved with its facts, like any other: " .. saved().items[2])
	local reads = ah.calls.info
	w.advance(30)
	working = Market.Tail()
	T.eq(working, false, "it gives up when nothing more arrives")
	local calls = ah.calls.info
	w.advance(30)
	T.eq(ah.calls.info, calls, "and reads nothing after"); T.check(calls - reads <= 20, "a pass is one read per row still out (" .. (calls - reads) .. ")")
	T.check(debugText():find("the tail read 4 more rows (3 items)", 1, true) and debugText():find("nothing more arrived", 1, true),
		"/gear debug says what it did and why it stopped: " .. debugText())
	-- stops when the Auction House closes
	fresh()
	row(gear(), 10); local late = row(gear(), 20, { late = true })
	open(); listArrives(); w.frames(3)
	T.check(settle(40), "saved")
	T.eq(Market.Tail(), true, "the tail is at work")
	close(true)
	w.advance(3)
	T.eq(Market.Tail(), false, "the Auction House closed: it stops")
	late.late = nil
	local n = ah.calls.info
	w.advance(10)
	T.eq(ah.calls.info, n, "and reads no row after")
	T.check(debugText():find("the Auction House closed", 1, true), "debug says why")
	ah.rows = {}
end)

return T.done()
