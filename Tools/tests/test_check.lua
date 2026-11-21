-- Check.lua on the stand-in world (mocks.lua, T.world): what a search result says is put on top
-- of the saved list, key by key; "none left" only where the search covered the key; the
-- player's own auctions and purchases; which of a correction and a scan is the newer; the
-- window moving a row without scoring again; and Check Prices asking Daylight UI's search one
-- item at a time, never during a purchase, and stopping when the Auction House closes.
-- The globals stay locked: the files may read only what T.world() and the lines below gave them.
-- luacheck: read globals UISpecialFrames GetServerTime

local w = T.world()
w.load("Market.lua")
w.load("Check.lua")
rawset(_G, "UIParent", {})
rawset(_G, "GameTooltip", {})
rawset(_G, "C_Item", {})
rawset(_G, "ITEM_QUALITY_COLORS", {})
rawset(_G, "GetMoneyString", function(copper) return copper .. "c" end)
rawset(_G, "UISpecialFrames", {})
rawset(_G, "DaylightUIAuctionHouse", false)
w.load("Window.lua")
local Window, Market, Check, Stats = NS.Window, NS.Market, NS.Check, NS.Stats
local ah = w.ah

w.dui("Login")

local function gear(def)
	def.equipLoc = def.equipLoc or "INVTYPE_CHEST"
	def.subclassID = def.subclassID or 4
	return T.item(def)
end
local function str(n) return { ITEM_MOD_STRENGTH_SHORT = n } end
local function waitRead()
	for _ = 1, 60 do
		if not Market.Looking() then break end
		w.frames(1)
	end
	for _ = 1, 600 do
		w.frames(1)
		if Market.State() == "ready" and not Market.Looking() then break end
	end
end
-- A character, and a saved list read through Market from a stand-in Auction House.
local function setup(rowsFor)
	if ah.open then
		ah.open = false
		w.fire("AUCTION_HOUSE_CLOSED")
	end
	DaylightGearDB.houses = {}
	WORLD.class, WORLD.level = "WARRIOR", 60
	WORLD.trees = { { name = "Arms", spent = 31 }, { name = "Fury", spent = 20 }, { name = "Protection", spent = 0 } }
	WORLD.worn, WORLD.bags = {}, {}
	w.settings.DaylightGear = {}
	w.settings.AuctionHouse = { enabled = true }
	w.searches, w.buying = {}, nil
	w.dui("Login")
	ah.rows, ah.results = {}, {}
	for _, r in ipairs(rowsFor) do
		ah.rows[#ah.rows + 1] = { itemID = Stats.ItemID(r[1]), link = r[1], buyout = r[2], count = 1 }
	end
	ah.open = true
	w.fire("AUCTION_HOUSE_SHOW")
	w.fire("REPLICATE_ITEM_LIST_UPDATE")
	waitRead()
	for k in pairs(Check.counts) do Check.counts[k] = 0 end
	if not Market.Saved() or #Market.Saved().items ~= #rowsFor then T.check(false, "SETUP: " .. tostring(Market.State()) .. " " .. table.concat(Market.Debug(), " | ")) end
end
local function key(link) return Stats.Key(link) end
local function results(link, list, full)
	local set = { full = full }
	for i, r in ipairs(list) do set[i] = r end
	ah.results[Stats.ItemID(link)] = set
end
-- The game says: results for this item's key (cleared unless told otherwise).
local function searched(link, suffix, level)
	w.fire("ITEM_SEARCH_RESULTS_UPDATED", { itemID = Stats.ItemID(link), itemLevel = level or 0, itemSuffix = suffix or 0 })
	w.frames(3)
end
local function fixed(link) return (Market.Fixed(key(link))) end
local function rolls()
	-- (The item itself, which the game knows by its ID, and two rolls of it.)
	local base = Stats.ItemID(gear({ name = "Vest", raw = {} }))
	local bear = gear({ id = base, roll = 1201, name = "Vest of the Bear", raw = str(30) })
	local tiger = gear({ id = base, roll = 1202, name = "Vest of the Tiger", raw = str(25) })
	return bear, tiger
end
local onScreen = false
local function show(on)
	onScreen = on
	Window.IsShown = function() return onScreen end
	if on and Window.S.stale then Window.Refresh(Window.S.force) end
end
local function scored()
	for _ = 1, 400 do
		if not Window.S.running and not (Window.S.stale and Window.IsShown()) then return true end
		w.frames(1)
	end
	return not Window.S.running
end
local function shownNames()
	local t = {}
	for i, e in ipairs(Window.S.model) do t[i] = e.row.name .. "=" .. e.row.price end
	return table.concat(t, ",")
end

T.case("a result re-prices the key it shows and no other; two rolls of one item stay apart", function()
	T.reset()
	local bear, tiger = rolls()
	local plainItem = gear({ name = "Plain Vest", raw = str(20) })
	setup({ { bear, 500 }, { tiger, 600 }, { plainItem, 700 } })
	T.eq(fixed(bear), nil, "nothing corrected yet")
	-- part of a result set (more pages to come): what is seen is re-priced, nothing is "gone"
	results(bear, { { link = bear, buyout = 450, id = 11 }, { link = bear, buyout = 470, id = 12 } }, false)
	searched(bear)
	T.eq(fixed(bear), 450, "the Bear costs what the cheapest auction asks"); T.eq(fixed(tiger), nil, "the Tiger is not touched")
	T.eq(fixed(plainItem), nil, "nor another item")
	local _, at = Market.Fixed(key(bear))
	T.eq(at, GetServerTime(), "with the server's time it was learned")
	T.eq(Check.counts.applied, 1, "one correction"); T.eq(Check.counts.gone, 0, "none gone")
	-- a price that went UP (the cheap ones sold) is a correction like any other
	results(bear, { { link = bear, buyout = 900, id = 13 } }, false)
	searched(bear)
	T.eq(fixed(bear), 900, "the cheaper ones sold: the price went up")
	-- a link with an enchant, a context and a modifier is the same key
	results(bear, { { link = T.link(Stats.ItemID(bear), 1201, "Vest of the Bear", 33, 1900, { context = 1, modifiers = "28:5253" }), buyout = 800, id = 14 } }, false)
	searched(bear)
	T.eq(fixed(bear), 800, "the link's other fields do not make another item")
end)

T.case("gone only when the search covered the key", function()
	T.reset()
	local bear, tiger = rolls()
	local plainItem = gear({ name = "Plain Vest", raw = str(20) })
	setup({ { bear, 500 }, { tiger, 600 }, { plainItem, 700 } })
	-- not complete: nothing is gone
	results(plainItem, {}, false)
	searched(plainItem)
	T.eq(fixed(plainItem), nil, "an unfinished result set marks nothing gone")
	-- a search for one suffix or one level: says nothing about the plain item
	results(plainItem, {}, true)
	searched(plainItem, 77)
	T.eq(fixed(plainItem), nil, "a search for one suffix covers no other key")
	searched(plainItem, 0, 45)
	T.eq(fixed(plainItem), nil, "nor does a search for one item level")
	-- complete, cleared key: the plain item is covered
	searched(plainItem)
	T.eq(fixed(plainItem), 0, "complete and cleared: none left")
	-- an empty answer to a plain search says nothing about ROLLS (such a search returns none)
	results(bear, {}, true)
	searched(bear)
	T.eq(fixed(bear), nil, "a search not known to return rolls marks no roll gone"); T.eq(fixed(tiger), nil, "neither roll")
	-- a complete result that itself holds a roll plainly covers the rolls
	results(bear, { { link = bear, buyout = 480, id = 21 } }, true)
	searched(bear)
	T.eq(fixed(bear), 480, "the Bear re-priced"); T.eq(fixed(tiger), 0, "and the Tiger, absent from a complete set of rolls, is gone")
	T.eq(Check.counts.gone, 2, "two marked gone in all")
	-- listed again later
	results(bear, { { link = bear, buyout = 480, id = 21 }, { link = tiger, buyout = 333, id = 22 } }, true)
	w.advance(61)
	searched(bear)
	T.eq(fixed(tiger), 333, "an item seen again is for sale again")
end)

T.case("a suffixed result whose link shows no roll is used for nothing", function()
	T.reset()
	local bear, tiger = rolls()
	setup({ { bear, 500 }, { tiger, 600 } })
	results(bear, { { link = T.link(Stats.ItemID(bear), nil, "Vest of the Bear"), buyout = 5, id = 31, suffix = 1201 } }, true)
	searched(bear)
	T.eq(fixed(bear), nil, "not re-priced from a link that cannot tell the roll"); T.eq(fixed(tiger), nil, "and nothing marked gone")
	T.eq(Check.counts.unmappable, 1, "counted for /gear debug")
	T.check(table.concat(Check.Debug(), "\n"):find("showed no roll for a suffixed item: 1", 1, true), "and said there")
end)

T.case("the player's own auctions are not prices", function()
	T.reset()
	local vest = gear({ name = "Vest", raw = str(20) })
	setup({ { vest, 700 } })
	results(vest, { { link = vest, buyout = 100, id = 41, own = true }, { link = vest, buyout = 650, id = 42 } }, true)
	searched(vest)
	T.eq(fixed(vest), 650, "the cheapest auction of another player")
	results(vest, { { link = vest, buyout = 100, id = 41, own = true }, { link = vest, buyout = 0, id = 43 } }, true)
	w.advance(61)
	searched(vest)
	T.eq(fixed(vest), 0, "only the player's own and a bid-only auction left: none to buy")
end)

T.case("the player's purchase re-prices at once", function()
	T.reset()
	local vest = gear({ name = "Vest", raw = str(20) })
	setup({ { vest, 700 } })
	results(vest, { { link = vest, buyout = 600, id = 51 }, { link = vest, buyout = 650, id = 52 } }, true)
	searched(vest)
	T.eq(fixed(vest), 600, "the cheapest")
	w.fire("AUCTION_HOUSE_PURCHASE_COMPLETED", 51)
	T.eq(fixed(vest), 650, "bought: the next one is the price now")
	w.fire("AUCTION_HOUSE_PURCHASE_COMPLETED", 999)
	T.eq(fixed(vest), 650, "an auction never seen changes nothing")
	w.fire("AUCTION_HOUSE_PURCHASE_COMPLETED", 52)
	T.eq(fixed(vest), 0, "the last one bought: none left")
	T.eq(Check.counts.purchases, 2, "two purchases seen")
	-- from an unfinished result set the last purchase proves nothing about the rest
	local other = gear({ name = "Other", raw = str(21) })
	setup({ { other, 700 } })
	results(other, { { link = other, buyout = 600, id = 61 } }, false)
	searched(other)
	w.fire("AUCTION_HOUSE_PURCHASE_COMPLETED", 61)
	T.eq(fixed(other), 600, "more pages may hold more: not marked gone")
end)

T.case("a correction and a scan: the newer one wins, either way", function()
	T.reset()
	local vest = gear({ name = "Vest", raw = str(20) })
	setup({ { vest, 700 } })
	local e = Market.Saved()
	T.eq(Market.Fix(key(vest), 5, e.readAt), false, "a correction as old as the list is not taken")
	T.eq(Market.Fix(key(vest), 5, e.readAt - 100), false, "nor an older one"); T.eq(fixed(vest), nil, "the list stands")
	w.advance(2)
	T.eq(Market.Fix(key(vest), 500, GetServerTime()), true, "a newer one is")
	T.eq(Market.Fix(key(vest), 400, GetServerTime() - 1), false, "an older correction never replaces a newer one")
	T.eq(fixed(vest), 500, "the newer stands")
	-- fed to a job with its corrected price, and with when
	local got = {}
	Market.Feed({ Add = function(_, link, price, _, _, _, _, at) got[link] = { price, at } end })
	T.eq(got["item:" .. key(vest)][1], 500, "a job is fed the corrected price"); T.check(got["item:" .. key(vest)][2] ~= nil, "and when it was checked")
	-- gone: not fed
	w.advance(2)
	Market.Fix(key(vest), 0, GetServerTime())
	got = {}
	Market.Feed({ Add = function(_, link, price) got[link] = price end })
	T.eq(got["item:" .. key(vest)], nil, "an item with none left is not fed")
	-- a key only a correction knows is fed too
	local new = gear({ name = "New", raw = str(40) })
	Market.Fix(key(new), 123, GetServerTime())
	got = {}
	Market.Feed({ Add = function(_, link, price) got[link] = price end })
	T.eq(got["item:" .. key(new)], 123, "a listing the scan never saw is fed from its correction")
	local n, gone = Market.FixCount()
	T.eq(n, 2, "two corrections in force"); T.eq(gone, 1, "one of them: none left")
	-- a NEW scan replaces them all
	w.advance(5)
	ah.rows[1].buyout = 800
	ah.rows[#ah.rows + 1] = { itemID = Stats.ItemID(new), link = new, buyout = 900, count = 1 }
	w.fire("REPLICATE_ITEM_LIST_UPDATE")
	waitRead()
	T.eq(#Market.Saved().items, 2, "a new list was read")
	T.eq(fixed(vest), nil, "the fresher scan overrides the older correction"); T.eq(fixed(new), nil, "both")
	T.eq(Market.FixCount(), 0, "none in force")
	got = {}
	Market.Feed({ Add = function(_, link, price) got[link] = price end })
	T.eq(got["item:" .. key(vest)], 800, "the scan's price"); T.eq(got["item:" .. key(new)], 900, "for both")
	-- a correction learned WHILE a scan is being read is newer than that scan's beginning: kept
	w.advance(5)
	for i = 1, 3000 do ah.rows[#ah.rows + 1] = { itemID = 1, link = nil, buyout = 0, count = 1, blank = i > 2990 } end
	w.fire("REPLICATE_ITEM_LIST_UPDATE")
	w.advance(1.5)
	T.eq(Market.State(), "reading", "a new read is under way")
	T.eq(Market.Fix(key(vest), 750, GetServerTime()), true, "a search during the read")
	for i = #ah.rows, 1, -1 do
		if ah.rows[i].blank then ah.rows[i].blank = nil end
	end
	waitRead()
	T.eq(Market.State(), "ready", "the read ended")
	T.eq(fixed(vest), 750, "the scan that began earlier does not override it")
end)

T.case("the window moves the row, drops what is gone and scores nothing again", function()
	T.reset()
	local a, b = gear({ name = "A", raw = str(30) }), gear({ name = "B", raw = str(20) })
	local legs = gear({ name = "Legs", raw = str(20), equipLoc = "INVTYPE_LEGS" })
	show(false)
	setup({ { a, 90000 }, { b, 20000 }, { legs, 20000 } })
	show(true)
	T.check(scored(), "scored")
	Window.S.selected = "CHEST"
	Window.Rearrange()
	T.eq(shownNames(), "B=20000,A=90000,Legs=20000", "B leads the chest slot; A is its alternative")
	local job = Window.S.job
	local stats, seen, jobs, paints = WORLD.calls.ItemStats, job.seen, NS.Perf.Sum("job"), NS.Perf.Sum("reprice")
	results(a, { { link = a, buyout = 18000, id = 71 } }, true)
	results(b, { { link = b, buyout = 21000, id = 72 } }, true)
	w.fire("ITEM_SEARCH_RESULTS_UPDATED", { itemID = Stats.ItemID(a), itemLevel = 0, itemSuffix = 0 })
	w.fire("ITEM_SEARCH_RESULTS_UPDATED", { itemID = Stats.ItemID(b), itemLevel = 0, itemSuffix = 0 })
	w.frames(4)
	T.eq(shownNames(), "A=18000,B=21000,Legs=20000", "A leads at its new price")
	T.check(Window.S.job == job, "the same job"); T.eq(job.seen, seen, "nothing scored again"); T.eq(WORLD.calls.ItemStats, stats, "no item read")
	T.eq(NS.Perf.Sum("job"), jobs, "no new job"); T.eq(NS.Perf.Sum("reprice"), paints + 1, "two prices, one repaint")
	T.check(Window.CheckedText(job.byKey[key(a)].checkedAt) == NS.L["Price checked just now."], "the row says its price was checked")
	T.eq(Window.CheckedText(job.byKey[key(legs)].checkedAt), nil, "a row not checked says nothing")
	-- sold
	results(a, {}, true)
	w.advance(61)
	searched(a)
	T.eq(shownNames(), "B=21000,Legs=20000", "A dropped out"); T.eq(Window.Facts().gone, 1, "and is counted")
	T.check(Window.SubText(Window.Facts()):find(NS.L["%d is no longer for sale."]:format(1), 1, true), "the line under the title says so: " .. Window.SubText(Window.Facts()))
	T.eq(job.seen, seen, "still nothing scored again")
	-- a refresh (new job from the saved list) keeps the truth: A stays out, B at its price
	Window.Refresh(true)
	T.check(scored(), "scored again from the saved list")
	Window.S.selected = "CHEST"
	Window.Rearrange()
	T.eq(shownNames(), "B=21000,Legs=20000", "a new job reads the corrections with the list")
	T.check(Window.S.job.byKey[key(b)].checkedAt ~= nil, "and still knows B's price was checked")
	-- a listing the scan never had
	local new = gear({ name = "New", raw = str(50) })
	results(new, { { link = new, buyout = 15000, id = 81 } }, true)
	searched(new)
	T.check(scored(), "the new item is scored")
	Window.Rearrange()
	T.eq(shownNames(), "New=15000,B=21000,Legs=20000", "a new listing joins the list")
end)

T.case("times in words", function()
	T.reset()
	T.eq(Window.CheckedText(nil), nil, "no time, no words")
	T.eq(Window.CheckedText(1000, 1030), NS.L["Price checked just now."], "under a minute")
	T.eq(Window.CheckedText(1000, 1000 + 185), NS.L["Price checked %d min ago."]:format(3), "minutes")
	T.eq(Window.CheckedText(1000, 1000 + 7300), NS.L["Price checked %d h ago."]:format(2), "hours")
end)

T.case("Check Prices: one search at a time through Daylight UI, never during a purchase", function()
	T.reset()
	local bear, tiger = rolls()
	local b, c = gear({ name = "B", raw = str(20) }), gear({ name = "C", raw = str(10), equipLoc = "INVTYPE_LEGS" })
	show(false)
	setup({ { bear, 500 }, { tiger, 600 }, { b, 700 }, { c, 800 } })
	show(true)
	T.check(scored(), "scored")
	Window.S.selected = "CHEST"
	Window.Rearrange()
	local ids = Window.ShownItems()
	T.eq(#ids, 3, "three items on screen (two rolls of one item are one search)")
	T.eq(Check.CanRun(), true, "it can run")
	T.eq(Check.Start(ids), true, "started"); T.eq(#w.searches, 1, "one search out")
	T.eq(Check.Start(ids), false, "not twice at once")
	w.advance(2)
	T.eq(#w.searches, 1, "the next waits for the answer")
	local running, done, total = Check.State()
	T.eq(running, true, "running"); T.eq(done, 0, "none done"); T.eq(total, 3, "of three")
	T.check(Window.SubText(Window.Facts()):find(NS.L["Checking prices: %d of %d."]:format(1, 3), 1, true), "the window says how far it is")
	-- the first answer: only the Bear is left of that item; Daylight UI's search covers every roll
	local first = w.searches[1].itemID
	T.eq(first, ids[1], "in the order shown")
	results(bear, { { link = bear, buyout = 450, id = 91 } }, true)
	results(b, { { link = b, buyout = 710, id = 92 } }, true)
	results(c, {}, true)
	w.buying = "item"
	T.eq(w.answer({}), first, "answered")
	w.advance(3)
	T.eq(#w.searches, 0, "a purchase of Daylight UI's is pending: nothing is sent")
	w.buying = nil
	w.advance(1)
	T.eq(#w.searches, 1, "the purchase is over: the next goes out")
	w.answer({})
	w.advance(1)
	T.eq(#w.searches, 1, "and the third")
	-- (a search that fails is passed over)
	w.answer(nil, "timeout")
	w.advance(1)
	T.eq(Check.State(), false, "the run ended"); T.eq(#w.searches, 0, "nothing more sent")
	T.eq(Check.counts.sent, 3, "three sent"); T.eq(Check.counts.answered, 2, "two answered"); T.eq(Check.counts.failed, 1, "one failed")
	local byItem = { [Stats.ItemID(bear)] = true }
	if byItem[ids[1]] or byItem[ids[2]] then
		T.eq(fixed(bear), 450, "the Bear re-priced"); T.eq(fixed(tiger), 0, "the Tiger gone: our search covers every roll")
	end
	T.eq(fixed(c), nil, "the search that failed marked nothing gone")
	local debug = table.concat(Check.Debug(), "\n")
	T.check(debug:find("sent 3 searches, 2 answered, 1 failed", 1, true), "/gear debug counts them: " .. debug)
end)

T.case("Check Prices stops on Stop and when the Auction House closes", function()
	T.reset()
	local a, b = gear({ name = "A", raw = str(30) }), gear({ name = "B", raw = str(20) })
	show(false)
	setup({ { a, 500 }, { b, 600 } })
	T.eq(Check.Start({ Stats.ItemID(a), Stats.ItemID(b) }), true, "started")
	Check.Stop()
	T.eq(Check.State(), false, "stopped")
	w.answer({})
	w.advance(2)
	T.eq(#w.searches, 0, "the late answer of a stopped run sends nothing more")
	T.eq(Check.Start({ Stats.ItemID(a), Stats.ItemID(b) }), true, "started again")
	ah.open = false
	w.fire("AUCTION_HOUSE_CLOSED")
	T.eq(Check.State(), false, "the Auction House closed: stopped")
	w.searches = {}
	w.advance(30)
	T.eq(#w.searches, 0, "and nothing is sent after")
	local ok, why = Check.CanRun()
	T.eq(ok, false, "not with the Auction House closed"); T.eq(why, "closed", "and why")
	ah.open = true
	w.fire("AUCTION_HOUSE_SHOW")
	w.settings.AuctionHouse.enabled = false
	ok, why = Check.CanRun()
	T.eq(ok, false, "not without Daylight UI's Auction House"); T.eq(why, "nodui", "and why")
	T.eq(Check.Start({ Stats.ItemID(a) }), false, "no run"); T.eq(#w.searches, 0, "and no search sent beside it")
	-- what the player searches by hand in the game's own window is still learned from
	results(a, { { link = a, buyout = 444, id = 95 } }, true)
	searched(a)
	T.eq(fixed(a), 444, "a result that passes by is used all the same")
	w.settings.AuctionHouse.enabled = true
end)

T.case("a click on a row asks about that item", function()
	T.reset()
	local a = gear({ name = "A", raw = str(30) })
	show(false)
	setup({ { a, 500 } })
	T.eq(Check.One(Stats.ItemID(a)), true, "one item"); T.eq(#w.searches, 1, "one search")
	T.eq(Check.One(Stats.ItemID(a)), true, "asked again while it runs"); T.eq(#w.searches, 1, "no second search for the same item")
	local b = gear({ name = "B", raw = str(31) })
	Check.One(Stats.ItemID(b))
	local _, _, total = Check.State()
	T.eq(total, 2, "another item joins the run")
	results(a, {}, true)
	w.answer({})
	w.advance(1)
	T.eq(fixed(a), 0, "the answer of our search for a plain item with nothing left: gone")
	T.eq(#w.searches, 1, "and the second item's search went out")
	Check.Stop()
end)

T.case("a row of the scan that was read late joins the window without a new job", function()
	T.reset()
	local a = gear({ name = "A", raw = str(30) })
	local late = gear({ name = "Late", raw = str(40) })
	local cloth = gear({ name = "Wand", raw = str(90), equipLoc = "INVTYPE_RANGEDRIGHT", classID = 2, subclassID = 19 })
	show(false)
	setup({ { a, 20000 } })
	show(true)
	T.check(scored(), "scored")
	local job, reads = Window.S.job, Window.S.job.reads
	NS.Fire("MarketAdded", key(cloth), 5, "new", { 2, 19, "INVTYPE_RANGEDRIGHT", 0 })
	T.check(scored(), "settled")
	T.eq(job.reads, reads, "an item the class cannot use is dropped unread, from its facts")
	NS.Fire("MarketAdded", key(late), 15000, "new", { 4, 4, "INVTYPE_CHEST", 0 })
	T.check(scored(), "scored")
	Window.Rearrange()
	T.check(Window.S.job == job, "the same job"); T.eq(job.reads, reads + 1, "one item read")
	T.eq(shownNames():match("^[^,]+"), "Late=15000", "and it leads its slot")
	T.eq(job.byKey[key(late)].checkedAt, nil, "it is scan data: not marked as checked")
	-- scan data never replaces what a search said since
	w.advance(2)
	Market.Fix(key(a), 0, GetServerTime())
	NS.Fire("PriceChanged", key(a), 0, GetServerTime())
	NS.Fire("MarketAdded", key(a), 1, "cheaper", { 4, 4, "INVTYPE_CHEST", 0 })
	w.frames(3)
	T.eq(job.byKey[key(a)].gone, true, "an item a search found sold stays gone when an old row of it is read late")
end)

return T.done()
