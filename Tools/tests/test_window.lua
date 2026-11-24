-- Window.lua's logic on the stand-in world (mocks.lua, T.world): the rows drawn from a ranked
-- view, which sentence stands in for an empty list, where the window goes beside its host, what
-- is searched for, and that moving a control arranges again without scoring again. No frame is
-- built here (the stand-in Daylight UI has no Skin or Text): everything below is logic.
-- The globals stay locked: Window.lua may read only what T.world() and the lines below gave it.
-- luacheck: read globals UISpecialFrames

local w = T.world()
w.load("Market.lua")
w.load("Sweep.lua")
rawset(_G, "UIParent", {})
rawset(_G, "GameTooltip", {})
rawset(_G, "C_Item", {})
rawset(_G, "ITEM_QUALITY_COLORS", {})
rawset(_G, "GetMoneyString", function(copper) return copper .. "c" end)
rawset(_G, "UISpecialFrames", {})
rawset(_G, "DaylightUIAuctionHouse", false)
w.load("Window.lua")
local Window, Market, Stats, Rank = NS.Window, NS.Market, NS.Stats, NS.Rank
local ah = w.ah

w.dui("Login")

local function gear(def)
	def.equipLoc = def.equipLoc or "INVTYPE_CHEST"
	def.subclassID = def.subclassID or 4
	return T.item(def)
end
local function str(n) return { ITEM_MOD_STRENGTH_SHORT = n } end
-- A character, and a saved list read through Market from a stand-in Auction House.
local function setup(rowsFor)
	WORLD.class, WORLD.level = "WARRIOR", 60
	WORLD.trees = { { name = "Arms", spent = 31 }, { name = "Fury", spent = 20 }, { name = "Protection", spent = 0 } }
	WORLD.worn, WORLD.bags = {}, {}
	w.settings.GloweyGear = {}
	w.dui("SettingChanged", "GloweyGear", "maxPrice")
	w.dui("Login")
	ah.rows = {}
	for _, r in ipairs(rowsFor) do
		ah.rows[#ah.rows + 1] = { itemID = Stats.ItemID(r[1]), link = r[1], buyout = r[2], count = 1 }
	end
	ah.open = true
	w.fire("AUCTION_HOUSE_SHOW")
	w.fire("REPLICATE_ITEM_LIST_UPDATE")
	for _ = 1, 60 do
		if not Market.Looking() then break end
		w.frames(1)
	end
	for _ = 1, 400 do
		w.frames(1)
		local list = Market.List()
		if Market.State() == "ready" and list and list.rows == #rowsFor then break end
	end
end
-- Runs frames until the job has ended and nothing is waiting to be refreshed.
local function scored(limit)
	for _ = 1, limit or 400 do
		if not Window.S.running and not (Window.S.stale and Window.IsShown()) then return true end
		w.frames(1)
	end
	return not Window.S.running
end
-- The cases below this line run without a frame (the stand-in Daylight UI has none to build it
-- from): whether the window is on screen is what the test says. The real test, on a real
-- frame, is put back for the last case.
local realShown = Window.IsShown
local onScreen = false
local function show(on)
	onScreen = on
	Window.IsShown = function() return onScreen end
	if on and Window.S.stale then Window.Refresh(Window.S.force) end
end

T.case("the window registers itself", function()
	T.eq(NS.OpenWindow, Window.Toggle, "/gear toggles it")
	T.eq(Window.frame, nil, "no frame on a Daylight UI without the pieces it is built from")
	WORLD.trees = { { name = "Arms", spent = 31 }, { name = "Fury", spent = 20 }, { name = "Protection", spent = 0 } }
	w.dui("Login")
	local lines = #w.chat
	Window.Toggle()
	T.eq(#w.chat, lines + 1, "the bare word then still answers in chat")
	T.eq(Window.Open(), false, "and Open says it could not")
end)

T.case("the row model: one row per slot in order, alternatives under the selected one", function()
	local function r(name) return { name = name } end
	local view = { groups = {
		CHEST = { r("c1"), r("c2"), r("c3") }, HEAD = { r("h1") }, RANGED = { r("r1"), r("r2") },
		FINGER = {},
	}, over = {}, listed = 6 }
	local m = Window.Model(view, nil)
	T.eq(#m, 3, "three slots with a pick (an empty group has no row)")
	T.eq(m[1].group, "HEAD", "head first"); T.eq(m[2].group, "CHEST", "then chest"); T.eq(m[3].group, "RANGED", "ranged last")
	T.eq(m[1].kind, "slot", "slot rows"); T.eq(m[2].row.name, "c1", "showing the best pick")
	T.eq(m[2].more, 2, "and how many alternatives"); T.eq(m[1].more, 0, "none for a single pick"); T.eq(m[2].open, false, "closed")
	m = Window.Model(view, "CHEST")
	T.eq(#m, 5, "the selected slot's alternatives are listed")
	T.eq(m[2].open, true, "open"); T.eq(m[3].kind, "alt", "an alternative"); T.eq(m[3].row.name, "c2", "second best")
	T.eq(m[4].row.name, "c3", "third"); T.eq(m[5].group, "RANGED", "then the next slot")
	m = Window.Model(view, "HEAD")
	T.eq(#m, 3, "a slot with no alternatives opens nothing"); T.eq(m[1].open, false, "and is not marked open")
	T.eq(#Window.Model(view, "WAIST"), 3, "a selected slot that has no pick adds nothing")
	T.eq(#Window.Model(nil), 0, "no view, no rows")
end)

T.case("which sentence stands in for an empty list", function()
	local function state(f)
		local base = { enabled = true, who = true, market = "ready", hasList = true, listed = 0, dui = true,
			money = function(c) return (c / 10000) .. "g" end }
		for k, v in pairs(f) do base[k] = v end
		return Window.EmptyState(base)
	end
	local text
	local key = state({ enabled = false })
	T.eq(key, "off", "switched off wins")
	key = state({ who = false, whoWhy = "noweights" }); T.eq(key, "noweights", "no weights for the class")
	key = state({ who = false, whoWhy = "nolevel" }); T.eq(key, "notready", "the character is not ready")
	key = state({ market = "none", hasList = false }); T.eq(key, "nolist", "no list: run a Full Scan")
	key = state({ market = "none", hasList = false, dui = false }); T.eq(key, "nolistown", "no list: our own read")
	key, text = state({ market = "none", hasList = false, dui = false, other = "Auctionator" })
	T.eq(key, "nolistother", "no list: another addon's full scan"); T.check(text:find("Auctionator", 1, true), "names it: " .. text)
	key, text = state({ market = "reading", hasList = false, done = 1200, total = 30000 })
	T.eq(key, "reading", "the first list is being read"); T.check(text:find("1200 of 30000", 1, true), "with its progress: " .. text)
	key = state({ market = "reading", hasList = false, done = 0, total = 0 }); T.eq(key, "asking", "asked, no rows yet")
	key = state({ market = "reading", listed = 3 }); T.eq(key, nil, "a list being read again still shows the old rows")
	key = state({ listed = 2, scoring = true }); T.eq(key, nil, "rows found so far show while the rest is scored")
	key, text = state({ scoring = true, left = 420 }); T.eq(key, "scoring", "nothing found yet, still scoring")
	T.check(text:find("420", 1, true), "says how many are left")
	key = state({ fight = true }); T.eq(key, "fight", "a fight")
	key, text = state({ over = 850000 }); T.eq(key, "over", "only the max price hides upgrades")
	T.check(text:find("85g", 1, true), "and says what it would take: " .. text)
	key = state({}); T.eq(key, "nothing", "nothing to buy")
	for _, f in ipairs({ { enabled = false }, { who = false }, { market = "none", hasList = false }, { fight = true }, {} }) do
		local _, sentence = state(f)
		T.check(type(sentence) == "string" and sentence:match("%.$"), "a plain sentence: " .. tostring(sentence))
	end
end)

T.case("where the window goes", function()
	T.eq(Window.Mode(true, true, false, false), "docked", "beside the open Auction House")
	T.eq(Window.Mode(true, true, true, false), "tab", "folded: only its tab")
	T.eq(Window.Mode(true, true, true, true), "tab", "folded wins over an earlier free opening")
	T.eq(Window.Mode(true, false, false, false), "hidden", "docking off: not by itself")
	T.eq(Window.Mode(true, false, true, true), "free", "docking off: on its own when opened")
	T.eq(Window.Mode(false, true, false, true), "free", "no Auction House: on its own")
	T.eq(Window.Mode(false, true, false, false), "hidden", "no Auction House, not opened")
	-- the host's left and right edges and the screen, all in the same units
	T.eq(Window.DockSide({ left = 16, right = 976 }, 1920, 340), "right", "room on the right")
	T.eq(Window.DockSide({ left = 900, right = 1860 }, 1920, 340), "left", "no room on the right: the left")
	T.eq(Window.DockSide({ left = 200, right = 1700 }, 1920, 340), nil, "room on neither side")
	T.eq(Window.DockSide({ left = 0, right = 1580 }, 1920, 340), "right", "exactly enough is enough")
	T.eq(Window.DockSide({ left = 340, right = 1900 }, 1920, 340), "left", "on the left too")
	T.eq(Window.DockSide({ left = 16, right = 976 }, 1280, 340 * 1.3), nil, "a scaled-up window needs more room")
	T.eq(Window.DockSide({ left = 16 }, 1920, 340), nil, "a host that cannot be measured docks nowhere")
	T.eq(Window.DockSide(nil, 1920, 340), nil, "nor one that is not there")
end)

T.case("the max price ladder", function()
	T.eq(Window.StepPrice(50, 1), 75, "up"); T.eq(Window.StepPrice(50, -1), 40, "down")
	T.eq(Window.StepPrice(5, -1), 5, "never under the first step")
	T.eq(Window.StepPrice(1000, 1), 0, "past the top is no limit"); T.eq(Window.StepPrice(0, 1), 0, "which stays")
	T.eq(Window.StepPrice(0, -1), 1000, "down from no limit")
	T.eq(Window.StepPrice(55, 1), 75, "from a value the options slider set: the next step up")
	T.eq(Window.StepPrice(55, -1), 50, "or down")
	for gold = 0, 1000, 5 do
		local up, down = Window.StepPrice(gold, 1), Window.StepPrice(gold, -1)
		T.check(up % 5 == 0 and down % 5 == 0 and down > 0, "every step is one the options slider can show (" .. gold .. ")")
	end
end)

T.case("the search text", function()
	T.eq(Window.SearchText({ name = "Jade Ring of the Bear" }), "Jade Ring of the Bear", "the whole name, suffix and all")
	T.eq(Window.SearchText({ name = "  Cutthroat's Pants of the Bandit " }), "Cutthroat's Pants of the Bandit", "trimmed")
	T.eq(Window.SearchText({ link = "|cff1eff00|Hitem:15139::::::::33:1489:::1:12751::::::|h[Cutthroat's Pants of the Bandit]|h|r" }),
		"Cutthroat's Pants of the Bandit", "from a full link when the name is missing")
	T.eq(Window.SearchText({ name = "|cff1eff00Jade Ring|r" }), "Jade Ring", "color codes are not searched")
	T.eq(Window.SearchText({ link = "item:15139" }), nil, "nothing to search for without a name")
	T.eq(Window.SearchText({ name = "" }), nil, "or with an empty one"); T.eq(Window.SearchText(nil), nil, "or no row")
	-- a row as the job makes it carries the rolled item's own name
	T.reset()
	gear({ id = 7001, name = "Jade Ring", equipLoc = "INVTYPE_FINGER" })
	local rolled = gear({ id = 7001, suffix = 1204, name = "Jade Ring of the Bear", equipLoc = "INVTYPE_FINGER", raw = str(9) })
	local job = Rank.Job(NS.Compare.Context({ class = "WARRIOR", level = 60, weights = { STR = 1 } }, {}, {}))
	job:Add("item:" .. Stats.Key(rolled), 100)
	job:Run()
	T.eq(#job.rows, 1, "the saved key scores as the roll")
	T.eq(Window.SearchText(job.rows[1]), "Jade Ring of the Bear", "and is searched by the roll's name")
end)

T.case("the search hand-off", function()
	local asked = {}
	w.ahmod.ns.BuyPage = { Submit = function(text, anywhere)
		asked[#asked + 1] = text
		asked.anywhere = anywhere
		return true
	end }
	w.ahmod.ns.Window = { frame = { tab = "sell" } }
	w.ahmod.ns.Window.ShowTab = function(id)
		asked[#asked + 1] = "tab:" .. id
		w.ahmod.ns.Window.frame.tab = id
	end
	local host = { shown = true }
	function host:IsVisible() return self.shown end
	function host.GetEffectiveAlpha() return 1 end
	function host.GetLeft() return 16 end
	rawset(_G, "DaylightUIAuctionHouse", host)
	ah.open = true
	w.fire("AUCTION_HOUSE_SHOW")
	T.eq(Window.Search({ name = "Jade Ring of the Bear" }), true, "handed to Daylight UI")
	T.eq(asked[1], "tab:buy", "the Buy tab first"); T.eq(asked[2], "Jade Ring of the Bear", "then the search")
	T.eq(asked.anywhere, true, "in every category, not only the one picked there")
	T.eq(Window.Search({ name = "Onyx Ring" }), true, "again"); T.eq(asked[3], "Onyx Ring", "already on Buy: only the search")
	-- a Daylight UI that changed: the chat line
	w.ahmod.ns.BuyPage = nil
	local lines = #w.chat
	T.eq(Window.Search({ name = "Onyx Ring" }), false, "not handed over")
	T.eq(#w.chat, lines + 1, "one chat line"); T.check(w.chat[#w.chat]:find("Type Onyx Ring in", 1, true), "saying what to type: " .. w.chat[#w.chat])
	w.ahmod.ns.BuyPage = { Submit = function() error("changed") end }
	T.eq(Window.Search({ name = "Onyx Ring" }), false, "a Submit that raises is caught"); T.eq(#w.chat, lines + 2, "and the player is told")
	-- the window not on screen, the Auction House closed: a click only selects
	host.shown = false
	ah.open = false
	w.fire("AUCTION_HOUSE_CLOSED")
	T.eq(Window.Search({ name = "Onyx Ring" }), false, "nothing to hand to"); T.eq(#w.chat, lines + 2, "and no chat line away from an Auction House")
	rawset(_G, "DaylightUIAuctionHouse", false)
	w.advance(3)
end)

T.case("scoring in slices, then arranging again without scoring again", function()
	T.reset()
	local worn = gear({ raw = str(10) })
	local cheap = gear({ name = "Cheap", raw = str(12) })       -- +20% for 2g: 10 per gold
	local big = gear({ name = "Big", raw = str(20) })           -- +100% for 40g: 2.5 per gold
	local dear = gear({ name = "Dear", raw = str(30) })         -- +200% for 400g: over the default 50g
	local tiny = gear({ name = "Tiny", raw = str(10.2) })       -- +2%: under the smallest gain
	local helm = gear({ name = "Helm", equipLoc = "INVTYPE_HEAD", raw = str(5) })   -- an empty slot
	local list = { { cheap, 20000 }, { big, 400000 }, { dear, 4000000 }, { tiny, 100 }, { helm, 5000 } }
	for i = 1, 600 do list[#list + 1] = { gear({ raw = str(1) }), 100 + i } end      -- 600 that are no upgrade
	setup(list)
	WORLD.worn[5] = worn
	show(false)
	w.fire("PLAYER_EQUIPMENT_CHANGED"); w.advance(0.4)
	T.eq(Window.S.stale, true, "a window that is not up does not score")
	T.eq(Window.S.job, nil, "no job yet")
	Window.Refresh()
	T.eq(Window.S.job, nil, "asked to refresh while it is not up: still nothing")

	w.clockStep = 0.4     -- (a look at the clock costs 0.4 ms: a slice of 3 ms is a handful of items)
	show(true)
	local job = Window.S.job
	T.check(job ~= nil and Window.S.running, "a job runs once it is up")
	w.frames(1)
	T.eq(job.seen, 0, "the first tick paints, it does not score")
	w.frames(8)
	T.check(job.seen > 0 and job.seen < 60, "then it feeds and scores in slices (" .. job.seen .. " scored after eight more frames)")
	T.check(scored(), "to its end")
	w.clockStep = 0.05
	T.eq(job.seen, 605, "every saved item was looked at"); T.eq(job:Done(), true, "and the job is done")
	local view = Window.S.view
	T.eq(#job.rows, 5, "five upgrades found")
	T.eq(view.listed, 3, "three shown: the dear one is over the max price, the tiny one under the smallest gain")
	T.eq(view.groups.CHEST[1].name, "Cheap", "most per gold first"); T.eq(view.groups.CHEST[2].name, "Big", "then the next")
	T.eq(view.groups.HEAD[1].name, "Helm", "the empty slot's pick")
	T.eq(Window.GainText(view.groups.HEAD[1]), "Empty Slot", "an empty slot in words")
	T.eq(Window.GainText(view.groups.CHEST[1]), "+20%", "a gain as a percent")
	T.eq(Window.Over(view), 4000000, "what the max price hides")
	local model = Window.S.model
	T.eq(#model, 2, "two slot rows"); T.eq(model[1].group, "HEAD", "in slot order"); T.eq(model[2].more, 1, "chest has one alternative")

	-- the controls: arranged again, never scored again (once a frame, on the next one)
	local stats, seen = WORLD.calls.ItemStats, job.seen
	local set = w.set
	local function wset(path, value) set(path, value); w.frames(1) end
	wset("mode", "biggest")
	T.check(Window.S.job == job, "the same job after the mode switch")
	T.eq(Window.S.view.groups.CHEST[1].name, "Big", "biggest gain first now")
	wset("maxPrice", 500)
	T.eq(Window.S.view.groups.CHEST[1].name, "Dear", "a higher max price lets the dear one in"); T.eq(Window.S.view.listed, 4, "four shown")
	wset("maxPrice", 0)
	T.eq(Window.S.view.listed, 4, "no limit: the same four")
	wset("minGain", 0)
	T.eq(Window.S.view.listed, 5, "no smallest gain: the tiny one too")
	wset("maxPrice", 1)
	T.eq(Window.S.view.listed, 2, "one gold: only the two cheapest")
	T.eq(Window.EmptyState(Window.Facts()), nil, "rows to show")
	wset("minGain", 3); wset("maxPrice", 0); wset("mode", "perGold")
	local arranged = NS.Perf.Sum("arrange")
	set("maxPrice", 5); set("maxPrice", 6); set("maxPrice", 0); w.frames(1)
	T.eq(NS.Perf.Sum("arrange") - arranged, 1, "a slider's burst of steps is one arrangement")
	T.eq(job.seen, seen, "nothing was scored again"); T.eq(WORLD.calls.ItemStats, stats, "and no item was read again")
	T.check(Window.S.job == job and not Window.S.running, "still the one finished job")

	-- what is owned unchanged: the same job; changed: a new one
	Window.Refresh()
	T.check(Window.S.job == job and not Window.S.running, "a refresh with nothing changed keeps the job, and scores nothing")
	WORLD.worn[5] = big
	w.fire("PLAYER_EQUIPMENT_CHANGED"); w.advance(0.4)
	w.set("maxPrice", 50)
	w.frames(2)
	T.check(Window.S.job ~= job, "new gear on: scored again")
	T.check(scored(), "to its end")
	T.eq(Window.S.view.groups.CHEST, nil, "nothing under 50g beats the new chest")
	T.eq(Window.S.view.over.CHEST.name, "Dear", "the dear one would")
	local facts = Window.Facts()
	facts.listed = 0   -- (as if the helm were not for sale)
	local key, text = Window.EmptyState(facts)
	T.eq(key, "over", "with only that left, the hint"); T.check(text:find("4000000c", 1, true), "names its price: " .. text)
end)

T.case("items the game had not loaded: parked, asked for, scored when they come", function()
	T.reset()
	show(false)
	local late = gear({ name = "Late", raw = str(50), loaded = false })
	local lateID = Stats.ItemID(late)
	setup({ { late, 100 }, { gear({ raw = str(1) }), 100 } })
	-- (the scan saw the item; a later session's cache does not have it)
	WORLD.items[T_ident(late)].loaded = false
	Stats.Forget()
	show(true)
	w.frames(6)
	local job = Window.S.job
	T.eq(job.nParked, 1, "one is parked"); T.eq(#job.rows, 1, "the other is an upgrade for the empty slot")
	T.eq(Window.S.running, true, "the job is not done while an item is out")
	T.eq(WORLD.requested[#WORLD.requested], lateID, "the game was asked for it")
	local asked = #WORLD.requested
	w.advance(2)
	T.eq(#WORLD.requested, asked, "once, not on every tick")
	-- item data for other things: nothing happens
	local seen = job.seen
	for _ = 1, 500 do w.fire("GET_ITEM_INFO_RECEIVED", 987654, true) end
	w.frames(3)
	T.eq(job.seen, seen, "events for items that are not ours score nothing")
	T.load(late)
	w.fire("GET_ITEM_INFO_RECEIVED", lateID, true)
	T.check(scored(), "its own event finishes the job")
	T.eq(job.seen, seen + 1, "only the late item was scored"); T.eq(job.nParked, 0, "nothing left waiting")
	T.eq(Window.S.view.groups.CHEST[1].name, "Late", "and it is the best pick now")
	T.eq(Window.Facts().unread, 0, "nothing unread")
end)

T.case("a job whose items never arrive ends, and the window says how many could not be read", function()
	T.reset()
	show(false)
	local never, never2 = gear({ name = "Never", raw = str(50) }), gear({ name = "Never 2", raw = str(60) })
	setup({ { never, 100 }, { never2, 100 }, { gear({ name = "Fine", raw = str(5) }), 100 } })
	WORLD.items[T_ident(never)].loaded = false
	WORLD.items[T_ident(never2)].loaded = false
	Stats.Forget()
	show(true)
	w.advance(3)
	T.eq(Window.S.running, true, "still waiting after three seconds")
	local stats, infos = WORLD.calls.ItemStats, WORLD.calls.ItemInfo
	w.advance(20)
	T.eq(Window.S.running, false, "it ends by itself"); T.eq(Window.S.job:Done(), true, "done")
	T.eq(Window.S.job.gaveUp, 2, "two given up")
	T.eq(WORLD.calls.ItemStats, stats, "and it did not hammer the game meanwhile: no stat call"); T.eq(WORLD.calls.ItemInfo, infos, "no item info call")
	T.eq(#WORLD.requested, 4, "each asked for twice in all")
	T.eq(Window.Facts().unread, 2, "the window knows")
	local debug = table.concat(Window.Debug(), "\n")
	T.check(debug:find("job done", 1, true) and debug:find("2 given up", 1, true), "and /gear debug says so: " .. debug)
	local timers = #w.timers
	w.advance(5)
	T.check(#w.timers <= timers, "a finished job leaves no ticking behind")
end)

T.case("nothing is scored while the window is hidden or folded", function()
	T.reset()
	show(false)
	local list = {}
	for i = 1, 300 do list[i] = { gear({ raw = str(i % 30) }), 100 + i } end
	setup(list)
	local stats = WORLD.calls.ItemStats or 0
	local before = Window.S.job
	w.fire("PLAYER_EQUIPMENT_CHANGED"); w.advance(1)
	Window.Dirty(true); w.advance(1)
	for _ = 1, 500 do w.fire("GET_ITEM_INFO_RECEIVED", 5, true) end
	w.advance(2)
	T.check(Window.S.job == before, "no new job while it is away"); T.eq((WORLD.calls.ItemStats or 0), stats, "no item read")
	T.eq(Window.S.stale, true, "what changed is remembered")
	-- shown: it scores; hidden part way: it stops; shown again: it goes on with the same job
	w.clockStep = 0.4
	show(true)
	w.frames(8)
	local job = Window.S.job
	local seen = job.seen
	T.check(job ~= before and seen > 0 and seen < 300, "a new job, part way (" .. seen .. ")")
	show(false)
	w.frames(40)
	T.eq(job.seen, seen, "hidden: not one more item")
	show(true)
	Window.S.ticking = false   -- (the frame's OnShow starts the ticking again; without a frame the test does)
	Window.Refresh()
	w.frames(3)
	w.clockStep = 0.05
	T.check(scored(), "shown again: the same job goes on to its end"); T.check(Window.S.job == job, "the same job")
	T.eq(job.seen, 300, "everything looked at exactly once")
end)

T.case("scoring waits for the Auction House's list to be read", function()
	T.reset()
	show(true)
	local list = {}
	for i = 1, 40 do list[i] = { gear({ raw = str(i) }), 100 + i } end
	setup(list)
	T.check(scored(), "scored")
	local first = Window.S.job
	-- a new, longer list arrives: while it is read nothing is scored
	for i = 1, 5000 do ah.rows[#ah.rows + 1] = { itemID = Stats.ItemID(list[i % 40 + 1][1]), link = list[i % 40 + 1][1], buyout = 50, count = 1 } end
	ah.rows[#ah.rows + 1] = { itemID = 1, link = gear({ id = 880001, name = "New", raw = str(90) }), buyout = 7, count = 1 }
	ah.rows[#ah.rows].itemID = 880001
	w.fire("REPLICATE_ITEM_LIST_UPDATE")
	for _ = 1, 60 do if not Market.Looking() then break end w.frames(1) end
	w.frames(2)
	T.eq(Market.State(), "reading", "the list is being read")
	local stats = WORLD.calls.ItemStats
	w.fire("PLAYER_EQUIPMENT_CHANGED"); w.advance(0.5)
	Window.Refresh(true)
	T.eq(Market.State(), "reading", "still reading")
	T.check(Window.S.job == first and not Window.S.running, "no new job while the list is read")
	T.eq(WORLD.calls.ItemStats, stats, "and no item scored")
	for _ = 1, 600 do
		if Market.State() ~= "reading" then break end
		w.frames(1)
	end
	T.check(scored(), "one job when the list is saved")
	T.check(Window.S.job ~= first, "a new one"); T.eq(Window.S.view.groups.CHEST[1].name, "New", "with the new list's best")
	T.eq(NS.Perf.Sum("job") >= 2, true, "counted")
end)

T.case("a slice of scoring keeps to its time whatever an item costs", function()
	T.reset()
	show(false)
	local list = {}
	for i = 1, 400 do list[i] = { gear({ raw = str(i % 50) }), 100 + i } end
	setup(list)
	show(true)
	w.frames(2)
	-- cheap items: many a tick; dear items (each look at the clock costs 1 ms here): few
	local job = Window.S.job
	local function perTick(step)
		w.clockStep = step
		local before = job.seen
		w.frames(1)
		return job.seen - before
	end
	local cheap = perTick(0.01)
	local dear = perTick(1)
	local dearer = perTick(2.9)
	w.clockStep = 0.05
	T.check(cheap > 20, "cheap items: many in a tick (" .. cheap .. ")")
	T.check(dear >= 1 and dear <= 3, "dear items: the tick ends after two or three (" .. dear .. ")")
	T.check(dearer <= 1, "an item as dear as the whole slice: one, and the tick ends (" .. dearer .. ")")
	T.check(scored(), "to the end")
end)

T.case("a flood of item-data events rebuilds and repaints next to nothing", function()
	T.reset()
	show(false)
	local list = {}
	for i = 1, 60 do list[i] = { gear({ raw = str(i) }), 100 + i } end
	setup(list)
	show(true)
	T.check(scored(), "scored")
	local job = Window.S.job
	local walks, jobs, refreshes, paints = WORLD.calls.BagLinks, NS.Perf.Sum("job"), NS.Perf.Sum("refresh"), NS.Perf.Sum("paint")
	local seen, stats = job.seen, WORLD.calls.ItemStats
	for _ = 1, 100 do
		for k = 1, 50 do w.fire("GET_ITEM_INFO_RECEIVED", 400000 + k, true) end
		w.frames(1)
	end
	w.advance(2)
	T.check(Window.S.job == job, "5,000 events: the same job"); T.eq(job.seen, seen, "nothing scored again")
	T.eq(WORLD.calls.ItemStats, stats, "no item read"); T.eq(WORLD.calls.BagLinks, walks, "what is owned not read again")
	T.eq(NS.Perf.Sum("job"), jobs, "no new job"); T.eq(NS.Perf.Sum("refresh"), refreshes, "no refresh")
	T.eq(NS.Perf.Sum("paint"), paints, "no paint"); T.eq(Window.S.running, false, "nothing running")
	T.eq(NS.Perf.Sum("itemEvents") >= 5000, true, "and /gear debug counted the events")
end)

T.case("a new list is a new job; switched off is no job", function()
	local job = Window.S.job
	local id = Stats.ItemID(job.rows[1].link)
	show(false)
	ah.rows[#ah.rows + 1] = { itemID = id, link = T.link(id), buyout = 5, count = 1 }
	w.fire("REPLICATE_ITEM_LIST_UPDATE")
	w.advance(5)
	T.eq(Market.List().rows, 61, "the new list is in")
	T.eq(Window.S.stale, true, "MarketChanged marks the hidden window stale")
	show(true)
	T.check(Window.S.job ~= job, "scored from the new list")
	T.check(scored(), "to its end")
	w.set("enabled", false)
	w.frames(2)
	T.eq(Window.S.job, nil, "switched off: no job"); T.eq((Window.EmptyState(Window.Facts())), "off", "and the window says so")
	w.set("enabled", true)
	w.frames(2)
	T.check(scored(), "and on again")
end)

-- Not pixels, but every line of the frame code run once on stand-in widgets (a method that does
-- not exist, a nil compared, a state that cannot be left would raise here): built, painted with
-- rows and without, docked right and left, folded, loose, free, dragged, and its controls pressed.
T.case("the frames: built, placed and pressed on stand-in widgets", function()
	Window.IsShown = realShown
	local A = w.DUI.API
	local skinned = 0
	A.Skin = function() skinned = skinned + 1 end
	A.Text = function(parent)
		local t = w.widget(parent)
		t.GetStringWidth = function() return 60 end
		t.GetStringHeight = function() return 13 end
		return t
	end
	A.Button = function(parent, text)
		local b = w.widget(parent)
		b.text = w.widget(b)
		b.text:SetText(text)
		b.FitWidth = function(min) b:SetWidth(min or 90) end
		return b
	end
	A.Close = function(parent, onClick)
		local b = w.widget(parent)
		b:SetScript("OnClick", onClick)
		return b
	end
	A.Colors = function() return { TITLE = { 1, 1, 1 }, VALUE = { 1, 1, 1 }, TEXT = { 1, 1, 1 }, LABEL = { 1, 1, 1 }, GOOD = { 0, 1, 0 } } end
	A.Accent = function() return 0.3, 0.8, 0.5 end
	A.Media = function(file) return "media/" .. file end
	local screen = w.widget()
	screen.width = 1920
	rawset(_G, "UIParent", screen)
	local tip = w.widget()
	tip.shown = false
	rawset(_G, "GameTooltip", tip)
	-- A stand-in for Host.lua's calls (ns.Host): what the window hands it is kept; Daylight UI's
	-- global scale is 0.5 here, so a window given it shows.
	local hosted, spots = {}, {}
	NS.Host = {
		Window = function(frame, opts) hosted[frame] = opts return true end,
		Scaled = function(frame, opts) hosted.scaled = { frame = frame, opts = opts } end,
		Rescale = function(frame)
			local o = hosted.scaled.opts
			frame:SetScale(o.own() * (o.docked() and 1 or 0.5))
		end,
		Moved = function() hosted.moved = (hosted.moved or 0) + 1 end,
		Spot = function(key, legacy)
			local s = {}
			function s.Get()
				if spots[key] then return spots[key] end
				local old = legacy.get()
				if old then spots[key] = old; legacy.clear() end
				return old
			end
			function s.Save(t) spots[key] = t return true end
			return s
		end,
	}
	local followed = {}
	NS.Pad = { On = function() return true end, Follow = function(frame, close) followed[frame] = close or true end,
		Stick = function() end, Settle = function(aim) followed.aim = aim end }

	T.reset()
	local worn = gear({ raw = str(10) })
	local a, b = gear({ name = "A", raw = str(12) }), gear({ name = "B", raw = str(14) })
	local c = gear({ name = "C", equipLoc = "INVTYPE_HEAD", raw = str(3) })
	setup({ { a, 100 }, { b, 300 }, { c, 50 } })
	WORLD.worn[5] = worn
	w.fire("PLAYER_EQUIPMENT_CHANGED"); w.advance(0.4)

	Window.failed = nil
	T.eq(Window.Open(), true, "it opens")
	local f, tab = Window.frame, Window.tab
	T.check(f ~= nil and f:IsShown(), "shown"); T.eq(Window.S.mode, "free", "on its own (no Auction House window)")
	T.check(followed[f] ~= nil and followed[tab] ~= nil, "the window and its tab are given to the controller kit")
	T.check(hosted[f] ~= nil and type(hosted[f].close) == "function", "the window is given to Host.Window, with its Escape")
	T.eq(hosted.scaled.frame, f, "and to Host.Scaled")
	T.eq(hosted[f].room(), true, "on its own: in Daylight UI's window room"); T.eq(f:GetScale(), 0.5, "with Daylight UI's scale")
	T.check(scored(), "scored on showing")
	T.eq(#Window.S.model, 2, "two slot rows"); T.check(f.first ~= nil and f.first.entry.group == "HEAD", "the first row is the first slot")
	T.check(skinned > 0, "the shell is laid out"); T.check(not tab:IsShown(), "no tab on its own")
	T.eq(f.padFirst(), f.first, "the controller starts on the first row")

	-- a slot row opens its alternatives; an alternative row is drawn; a second click closes them
	local chest
	for _, child in ipairs(w.frames_) do
		if child.entry and child.entry.group == "CHEST" and child.entry.kind == "slot" then chest = child end
	end
	T.check(chest ~= nil and chest.entry.more == 1, "the chest row has one alternative")
	chest:Click()
	T.eq(Window.S.selected, "CHEST", "selected"); T.eq(#Window.S.model, 3, "its alternative is listed")
	T.eq(followed.aim, chest, "the controller's cursor stays on the row pressed")
	chest.scripts.OnEnter(chest)
	T.check(tip:IsShown(), "hovering a row shows the item's tooltip")
	chest.scripts.OnLeave(chest)
	T.check(not tip:IsShown(), "and leaving hides it")
	chest:Click()
	T.eq(Window.S.selected, nil, "a second click closes it"); T.eq(#Window.S.model, 2, "back to two rows")

	-- the controls write the same settings as the options page
	w.set("maxPrice", 50)
	f.plus:Click(); T.eq(NS.Get("maxPrice"), 75, "plus: the next step up")
	f.minus:Click(); f.minus:Click(); T.eq(NS.Get("maxPrice"), 40, "minus: down")
	f.mode:Click(); T.eq(NS.Get("mode"), "biggest", "the Best Pick button switches")
	local tabs, at = f.padTabs()
	T.eq(at, 2, "LB / RB know which is on"); tabs[1]:Click(); T.eq(NS.Get("mode"), "perGold", "and switch it")
	T.eq(f.padSelect(chest), nil, "A is plain Select away from the Auction House")

	-- the X closes a window on its own
	f.close:Click()
	T.check(not f:IsShown(), "closed"); T.eq(Window.S.free, false, "and stays closed")

	-- Daylight UI's Auction House window comes up: docked on its right, tops level
	local host = w.widget()
	host.rect = { 16, 976, 900 }
	function host:GetLeft() return self.rect[1] end
	function host:GetRight() return self.rect[2] end
	function host:GetTop() return self.rect[3] end
	function host.GetEffectiveAlpha() return 1 end
	rawset(_G, "DaylightUIAuctionHouse", host)
	w.ahmod.ns.BuyPage = { Submit = function(text) host.searched = text return true end }
	w.ahmod.ns.Window = { frame = { tab = "buy" } }
	ah.open = true
	w.fire("AUCTION_HOUSE_SHOW")
	w.update()
	T.eq(Window.S.mode, "docked", "docked"); T.eq(Window.S.side, "right", "on the right")
	T.check(f:IsShown() and tab:IsShown(), "window and tab shown")
	T.check(f.points[1][1] == "TOPLEFT" and f.points[1][2] == host and f.points[1][3] == "TOPRIGHT" and f.points[1][4] == 0
		and f.points[1][5] == 0, "flush against the host's right edge, tops level")
	T.check(tab.points[1][2] == f and tab.points[1][3] == "TOPRIGHT", "the tab at the window's outer top corner")
	T.eq(f.padSecond, true, "beside the Auction House it does not take the controller's cursor")
	T.eq(hosted[f].room(), false, "docked: not in the window room"); T.eq(f:GetScale(), 1, "nor Daylight UI's scale on top of the host's")
	T.check((hosted.moved or 0) > 0, "the room is told it docked")
	T.eq(f.padSelect(chest), "Search", "A says Search there")
	chest:Click()
	T.eq(host.searched, "B", "a click searches the best pick in the Buy page")

	-- folded: only the tab, at the host's corner; remembered
	f.close:Click()
	T.check(not f:IsShown() and tab:IsShown(), "the X folds it to its tab"); T.eq(GloweyGearDB.window.folded, true, "remembered")
	T.check(tab.points[1][2] == host and tab.points[1][1] == "TOPLEFT" and tab.points[1][3] == "TOPRIGHT",
		"the tab at the host's top right corner")
	tab.scripts.OnEnter(tab); tab.scripts.OnLeave(tab)
	tab:Click()
	T.check(f:IsShown(), "the tab opens it again"); T.eq(GloweyGearDB.window.folded, nil, "remembered too")

	-- the host moves: no room on the right, then on neither side
	host.rect = { 900, 1860, 900 }
	w.update()
	T.eq(Window.S.side, "left", "to the left when the right has no room")
	T.check(f.points[1][1] == "TOPRIGHT" and f.points[1][3] == "TOPLEFT", "flush against the left edge")
	T.check(tab.points[1][1] == "TOPRIGHT" and tab.points[1][2] == f, "the tab on the far side there")
	host.rect = { 200, 1700, 900 }
	w.update()
	T.eq(Window.S.mode, "free", "no room on either side: where the player left it"); T.check(not tab:IsShown(), "with no tab")
	T.check(f:IsShown() and f.points[1][2] == screen, "placed on the screen, not on the host")
	Window.Toggle()
	T.check(not f:IsShown(), "/gear puts it away there"); Window.Toggle(); T.check(f:IsShown(), "and brings it back")
	host.rect = { 16, 976, 900 }
	w.update()
	T.eq(Window.S.mode, "docked", "docked again once there is room")

	-- Escape belongs to the Auction House window while docked: Host.Window's close() leaves it be
	hosted[f].close()
	T.check(f:IsShown() and Window.S.mode == "docked", "docked: Escape is not ours")
	T.eq(GloweyGearDB.window.folded, nil, "and folds nothing")

	-- docking switched off: not shown by itself
	w.set("dock", false)
	T.eq(Window.S.mode, "hidden", "docking off: away"); T.check(not f:IsShown() and not tab:IsShown(), "window and tab")
	w.set("dock", true)
	T.eq(Window.S.mode, "docked", "docking on: back")

	-- the Auction House closes: gone with it; /gear then opens it on its own, where it is dragged to
	host.shown = false
	ah.open = false
	w.fire("AUCTION_HOUSE_CLOSED")
	w.update()
	T.eq(Window.S.mode, "hidden", "gone with the Auction House"); T.check(not f:IsShown() and not tab:IsShown(), "window and tab")
	Window.Toggle()
	T.eq(Window.S.mode, "free", "/gear: on its own"); T.eq(f.padSecond, nil, "taking the controller's cursor")
	hosted[f].close()
	T.check(not f:IsShown() and Window.S.free == false, "on its own: Escape closes it")
	Window.Toggle()
	f:Hide()
	T.eq(Window.S.free, false, "hidden by the game: closed, and it stays closed")
	Window.Toggle()
	T.check(f:IsShown(), "open again")
	T.eq(#UISpecialFrames, 0, "the window's own name is never on the game's Escape list (Host.Window's stand-in is)")
	function f.GetLeft() return 700 end
	function f.GetTop() return 650 end
	local moved = hosted.moved or 0
	f.scripts.OnDragStart(f); f.scripts.OnDragStop(f)
	T.eq(spots.window.x, 350, "its place is kept, in UIParent units (Host.Spot)"); T.eq(spots.window.y, 325, "both ways")
	T.eq(GloweyGearDB.window.x, nil, "not in the account's saved state any more")
	T.eq(#f.points, 1, "anchored by one point after a drag"); T.eq(hosted.moved, moved + 1, "and the room is told")
	Window.Close(); Window.Open()
	T.check(f.points[1][1] == "TOPLEFT" and f.points[1][4] == 700 and f.points[1][5] == 650, "and it opens there again")
	-- a spot saved the old way (GloweyGearDB.window.x / y) is moved into Host.Spot once
	spots.window = nil
	GloweyGearDB.window.x, GloweyGearDB.window.y = 100, 200
	Window.Close(); Window.Open()
	T.check(f.points[1][4] == 200 and f.points[1][5] == 400, "the old spot is used")
	T.check(spots.window and spots.window.x == 100 and GloweyGearDB.window.x == nil, "moved in, and cleared there")

	-- an empty state paints too, and our own read's button shows only when it is the way
	T.check(not f.scan:IsShown(), "no Read button while Daylight UI's Auction House is the one in use")
	w.settings.AuctionHouse.enabled = false
	ah.open = true
	w.fire("AUCTION_HOUSE_SHOW")
	w.set("enabled", false)
	w.frames(2)
	T.check(f.empty:IsShown() and f.empty:GetText():find("switched off", 1, true), "the sentence for an empty list is drawn")
	w.set("enabled", true)
	w.frames(2)
	T.check(scored(), "scored again")
	T.check(f.scan:IsShown(), "the Scan button where our own scan is the way")
	T.eq(f.scan.text:GetText(), NS.L["Scan the Auction House"], "named for what it does")
	T.check(not f.bar:IsShown(), "no bar before a scan")
	f.scan:Click()
	T.eq(NS.Sweep.Running(), true, "a click starts the scan")
	T.eq(f.scan.text:GetText(), NS.L["Stop Scan"], "the button stops it now"); T.check(f.bar:IsShown(), "and the bar shows")
	T.check(f.barText:GetText():find("categories", 1, true), "with how far it is: " .. tostring(f.barText:GetText()))
	f.scan:Click()
	T.eq(NS.Sweep.Running(), false, "a second click pauses it")
	T.eq(f.scan.text:GetText(), NS.L["Resume Scan"], "and the button goes on with it"); T.check(f.bar:IsShown(), "the bar stays")
	T.eq(ah.calls.ask, 0, "the whole-house list is never asked for")

	-- the game's own Auction House window, Daylight UI's not up: docked to it the same way
	local game = w.widget()
	game.rect = { 16, 976, 900 }
	function game:GetLeft() return self.rect[1] end
	function game:GetRight() return self.rect[2] end
	function game:GetTop() return self.rect[3] end
	game.alpha = 1
	function game:GetEffectiveAlpha() return self.alpha end
	rawset(_G, "AuctionHouseFrame", game)
	GloweyGearDB.window.folded = nil
	w.update()
	T.eq(Window.S.mode, "docked", "docked to the game's window"); T.eq(Window.S.side, "right", "on its right")
	T.check(f.points[1][1] == "TOPLEFT" and f.points[1][2] == game and f.points[1][3] == "TOPRIGHT" and f.points[1][4] == 0
		and f.points[1][5] == 0, "flush against its right edge, tops level")
	T.eq(f.padSelect(chest), NS.L["Search"], "the controller's Search there too")
	-- a click searches in the game's window: Buy tab, no category, the name, the search
	local did = {}
	rawset(_G, "AuctionHouseFrameDisplayMode", { Buy = "buy", ItemBuy = "itembuy", CommoditiesBuy = "cbuy", ItemSell = "sell" })
	game.displayMode = "sell"
	function game:SetDisplayMode(mode) self.displayMode = mode; did[#did + 1] = "mode:" .. mode end
	local cats = { SetSelectedCategory = function(_, picked) did[#did + 1] = "category:" .. tostring(picked) end }
	function game.GetCategoriesList() return cats end
	game.SearchBar = {
		SetSearchText = function(_, text) did[#did + 1] = "text:" .. text end,
		StartSearch = function() did[#did + 1] = "search" end,
	}
	local lines = #w.chat
	T.eq(Window.Search({ name = "Jade Ring of the Bear" }), true, "the game's window took it")
	T.eq(table.concat(did, ","), "mode:buy,category:nil,text:Jade Ring of the Bear,search", "Buy tab, any category, the name, searched")
	T.eq(#w.chat, lines, "no chat line")
	did = {}
	T.eq(Window.Search({ name = "Onyx Ring" }), true, "again")
	T.eq(table.concat(did, ","), "category:nil,text:Onyx Ring,search", "already buying: no tab change")
	game.SearchBar.StartSearch = function() error("changed") end
	T.eq(Window.Search({ name = "Onyx Ring" }), false, "a search bar that raises is caught")
	T.check(w.chat[#w.chat]:find("Type Onyx Ring in", 1, true), "and the player is told what to type")
	game.SearchBar = nil
	-- parked at no opacity (Daylight UI's window standing in for it): not a host
	game.alpha = 0
	w.update()
	T.check(Window.S.mode ~= "docked", "a parked game window is not docked to")
	-- both up: Daylight UI's comes first
	game.alpha = 1
	host.shown = true
	w.update()
	T.check(Window.S.mode == "docked" and f.points[1][2] == host, "Daylight UI's window wins over the game's")
	host.shown = false
	rawset(_G, "AuctionHouseFrame", nil)
	w.settings.AuctionHouse.enabled = true
	rawset(_G, "DaylightUIAuctionHouse", false)
end)

T.case("a row's gain in words: far better, better, empty; and the mark for an effect not counted", function()
	T.eq(Window.GainText({ pct = 12.4, empty = false, replaces = {} }), "+12%", "a percent")
	T.eq(Window.GainText({ pct = 340, far = true, empty = false, replaces = {} }), "Far Better", "beyond what a percent can say (the audit's M2)")
	T.eq(Window.GainText({ pct = nil, empty = false, replaces = {} }), "Better", "a worn item that scores nothing is not an empty slot (the audit's M3)")
	T.eq(Window.GainText({ pct = 40, empty = true }), "Empty Slot", "only a slot with nothing in it is empty")
	T.eq(Window.GainText({ pct = nil, empty = true }), "Empty Slot", "with or without a percent")
	local plain = T.item({ equipLoc = "INVTYPE_TRINKET", raw = { ITEM_MOD_STAMINA_SHORT = 5 }, effects = { equip = 0 } })
	local odd = T.item({ equipLoc = "INVTYPE_TRINKET", raw = { ITEM_MOD_STAMINA_SHORT = 5 }, effects = { use = 1 } })
	T.eq(Window.Uncounted({ link = plain }), false, "an item that is fully counted")
	T.eq(Window.Uncounted({ link = odd }), true, "an item with a Use effect the score leaves out (the audit's M1)")
	T.eq(Window.Uncounted({ link = "item:999999" }), false, "an item not loaded says nothing")
end)

return T.done()
