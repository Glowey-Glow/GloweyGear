-- Rank.lua: improvement per gold, the price limit, the smallest gain, order and ties.
local Rank, Compare, Stats = NS.Rank, NS.Compare, NS.Stats

local W = { STR = 1, STA = 0.5, MH_DPS = 2 }
local GOLD = 10000

local function piece(loc, str, more)
	local def = { equipLoc = loc, classID = 4, subclassID = 0, raw = { ITEM_MOD_STRENGTH_SHORT = str } }
	for k, v in pairs(more or {}) do def[k] = v end
	return T.item(def)
end
-- A level 60 warrior wearing a 10-Strength helm, 10-Strength legs and rings of 10 and 4.
local function world(level)
	T.reset()
	local worn = { [1] = piece("INVTYPE_HEAD", 10), [7] = piece("INVTYPE_LEGS", 10),
		[11] = piece("INVTYPE_FINGER", 10), [12] = piece("INVTYPE_FINGER", 4) }
	return Compare.Context({ class = "WARRIOR", level = level or 60, weights = W }, worn, {})
end
local function names(list)
	local t = {}
	for i, row in ipairs(list or {}) do t[i] = row.name end
	return table.concat(t, ",")
end

T.case("pocket change and value", function()
	T.eq(Rank.Pocket(60), 18000, "level 60: 1 gold 80 silver"); T.eq(Rank.Pocket(30), 4500, "level 30: 45 silver")
	T.eq(Rank.Pocket(10), 500, "level 10: 5 silver"); T.eq(Rank.Pocket(1), 100, "never under a silver")
	T.eq(Rank.Pocket(nil), 100, "no level")
	T.near(Rank.Value(10, 5 * GOLD, 60), 2, "10 gain for 5 gold is 2 per gold")
	T.near(Rank.Value(10, 1, 60), 10 / 1.8, "a one-copper price counts as pocket change")
	T.near(Rank.Value(10, 18000, 60), Rank.Value(10, 1, 60), "anything under pocket change is worth the same per gold")
	T.check(Rank.Value(10, 18001, 60) < Rank.Value(10, 18000, 60), "above it, gold counts")
end)

T.case("most improvement per gold is the default order", function()
	local job = Rank.Job(world())
	job:Add(piece("INVTYPE_HEAD", 30, { name = "Big" }), 100 * GOLD)      -- +20 for 100g: 0.2 per gold
	job:Add(piece("INVTYPE_HEAD", 16, { name = "Thrifty" }), 5 * GOLD)    -- +6 for 5g: 1.2 per gold
	job:Add(piece("INVTYPE_HEAD", 20, { name = "Middle" }), 20 * GOLD)    -- +10 for 20g: 0.5 per gold
	job:Run()
	local view = Rank.Arrange(job.rows, { level = 60 })
	T.eq(names(view.groups.HEAD), "Thrifty,Middle,Big", "per gold")
	T.near(view.groups.HEAD[1].value, 1.2, "value"); T.eq(view.listed, 3, "listed")
	view = Rank.Arrange(job.rows, { level = 60, mode = "perGold" })
	T.eq(names(view.groups.HEAD), "Thrifty,Middle,Big", "named explicitly")
	view = Rank.Arrange(job.rows, { level = 60, mode = "biggest" })
	T.eq(names(view.groups.HEAD), "Big,Middle,Thrifty", "the switch: biggest improvement")
	local row = view.groups.HEAD[1]
	T.near(row.gain, 20, "gain"); T.near(row.pct, 200, "percent"); T.eq(row.price, 100 * GOLD, "price")
	T.eq(row.group, "HEAD", "group"); T.check(row.replaces ~= nil, "what it replaces"); T.eq(row.empty, false, "not empty")
end)

T.case("a one-copper trifle does not beat a real upgrade", function()
	local job = Rank.Job(world())
	job:Add(piece("INVTYPE_HEAD", 10.5, { name = "Trifle" }), 1)          -- +0.5 for 1 copper
	job:Add(piece("INVTYPE_HEAD", 25, { name = "Real" }), 1 * GOLD)       -- +15 for 1 gold
	job:Run()
	T.eq(names(Rank.Arrange(job.rows, { level = 60 }).groups.HEAD), "Real,Trifle", "both under pocket change: the gain decides")
end)

T.case("zero and negative gains are never listed", function()
	local job = Rank.Job(world())
	job:Add(piece("INVTYPE_HEAD", 10, { name = "Same" }), 1)
	job:Add(piece("INVTYPE_HEAD", 9, { name = "Worse" }), 1)
	job:Add(piece("INVTYPE_HEAD", 0, { name = "Nothing" }), 1)
	job:Add(piece("INVTYPE_HEAD", 10.01, { name = "Hair" }), 1)
	job:Run()
	T.eq(#job.rows, 1, "only the real upgrade is kept"); T.eq(job.rows[1].name, "Hair", "the hair's gain")
	T.eq(job.seen, 4, "all four were looked at")
end)

T.case("unusable items are never recommended", function()
	T.reset()
	local worn = { [5] = piece("INVTYPE_CHEST", 5, { subclassID = 1 }) }
	local ctx = Compare.Context({ class = "MAGE", level = 30, weights = W }, worn, {})
	local job = Rank.Job(ctx)
	job:Add(piece("INVTYPE_CHEST", 99, { name = "Plate", subclassID = 4 }), GOLD)
	job:Add(piece("INVTYPE_CHEST", 99, { name = "TooHigh", subclassID = 1, minLevel = 31 }), GOLD)
	job:Add(T.item({ name = "Axe", equipLoc = "INVTYPE_2HWEAPON", classID = 2, subclassID = 1, raw = { ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 90 } }), GOLD)
	job:Add(T.item({ name = "OffDagger", equipLoc = "INVTYPE_WEAPONOFFHAND", classID = 2, subclassID = 15, raw = { ITEM_MOD_STRENGTH_SHORT = 50 } }), GOLD)
	job:Add(T.item({ name = "Pole", equipLoc = "INVTYPE_2HWEAPON", classID = 2, subclassID = 20, raw = { ITEM_MOD_STRENGTH_SHORT = 50 } }), GOLD)
	job:Add(piece("INVTYPE_SHIELD", 50, { name = "Shield", subclassID = 6 }), GOLD)
	job:Add(piece("INVTYPE_RELIC", 50, { name = "Idol", subclassID = 8 }), GOLD)
	job:Add(T.item({ name = "Shirt", equipLoc = "INVTYPE_BODY", raw = { ITEM_MOD_STRENGTH_SHORT = 50 } }), GOLD)
	job:Add(T.item({ name = "Ore", equipLoc = "" }), GOLD)
	job:Add(piece("INVTYPE_CHEST", 9, { name = "Robe", subclassID = 1, minLevel = 30 }), GOLD)
	job:Run()
	T.eq(#job.rows, 1, "one usable upgrade"); T.eq(job.rows[1].name, "Robe", "the cloth robe at the character's level")
	T.eq(job.nParked, 0, "nothing parked"); T.eq(job:Done(), true, "done")
end)

T.case("max price is a hard ceiling", function()
	local job = Rank.Job(world())
	job:Add(piece("INVTYPE_HEAD", 30, { name = "Dear" }), 50 * GOLD + 1)
	job:Add(piece("INVTYPE_HEAD", 40, { name = "Dearest" }), 500 * GOLD)
	job:Add(piece("INVTYPE_HEAD", 20, { name = "AtLimit" }), 50 * GOLD)
	job:Add(piece("INVTYPE_HEAD", 12, { name = "Cheap" }), 1 * GOLD)
	job:Run()
	local view = Rank.Arrange(job.rows, { level = 60, maxPrice = 50 * GOLD })
	T.eq(names(view.groups.HEAD), "Cheap,AtLimit", "a price equal to the limit is allowed, a copper more is not")
	T.eq(view.over.HEAD.name, "Dearest", "the biggest upgrade the limit hides is remembered")
	view = Rank.Arrange(job.rows, { level = 60, maxPrice = 50 * GOLD, mode = "biggest" })
	T.eq(names(view.groups.HEAD), "AtLimit,Cheap", "biggest improvement within my max price")
	view = Rank.Arrange(job.rows, { level = 60, maxPrice = 0 })
	T.eq(#view.groups.HEAD, 4, "0 means no limit"); T.eq(view.over.HEAD, nil, "nothing hidden")
	view = Rank.Arrange(job.rows, { level = 60 })
	T.eq(#view.groups.HEAD, 4, "no limit given")
	view = Rank.Arrange(job.rows, { level = 60, maxPrice = 10 })
	T.eq(view.groups.HEAD, nil, "a limit under everything leaves the slot out"); T.eq(view.listed, 0, "nothing listed")
	T.eq(view.over.HEAD.name, "Dearest", "with the hint kept")
end)

T.case("the smallest gain to show", function()
	local job = Rank.Job(world())
	job:Add(piece("INVTYPE_HEAD", 10.2, { name = "TwoPct" }), GOLD)
	job:Add(piece("INVTYPE_HEAD", 10.5, { name = "FivePct" }), GOLD)
	job:Add(piece("INVTYPE_CHEST", 0.1, { name = "EmptySlot" }), GOLD)
	job:Run()
	local view = Rank.Arrange(job.rows, { level = 60, minPct = 5 })
	T.eq(names(view.groups.HEAD), "FivePct", "5% passes a 5% floor, 2% does not")
	T.eq(names(view.groups.CHEST), "EmptySlot", "an empty slot has no percent and always passes")
	T.eq(view.over.HEAD, nil, "a gain too small is not a price hint")
	view = Rank.Arrange(job.rows, { level = 60, minPct = 0 })
	T.eq(#view.groups.HEAD, 2, "no floor shows both")
end)

T.case("ties are broken the same way every time", function()
	local job = Rank.Job(world())
	local a = piece("INVTYPE_HEAD", 20, { name = "A", id = 5001 })
	local b = piece("INVTYPE_HEAD", 20, { name = "B", id = 5002 })
	local c = piece("INVTYPE_HEAD", 20, { name = "C", id = 5003 })
	local d = piece("INVTYPE_HEAD", 30, { name = "D", id = 5004 })
	job:Add(c, 10 * GOLD); job:Add(b, 10 * GOLD); job:Add(a, 10 * GOLD)   -- same gain, same price: by key
	job:Add(d, 20 * GOLD)                                                 -- same per gold as the others, bigger gain
	job:Run()
	T.eq(names(Rank.Arrange(job.rows, { level = 60 }).groups.HEAD), "D,A,B,C", "per gold tie: bigger gain first, then key")
	T.eq(names(Rank.Arrange(job.rows, { level = 60, mode = "biggest" }).groups.HEAD), "D,A,B,C", "biggest: gain, then key")
	local again = Rank.Job(world())
	local a2 = piece("INVTYPE_HEAD", 20, { name = "A", id = 5001 })
	local b2 = piece("INVTYPE_HEAD", 20, { name = "B", id = 5002 })
	local c2 = piece("INVTYPE_HEAD", 20, { name = "C", id = 5003 })
	local d2 = piece("INVTYPE_HEAD", 30, { name = "D", id = 5004 })
	again:Add(a2, 10 * GOLD); again:Add(d2, 20 * GOLD); again:Add(c2, 10 * GOLD); again:Add(b2, 10 * GOLD)
	again:Run()
	T.eq(names(Rank.Arrange(again.rows, { level = 60 }).groups.HEAD), "D,A,B,C", "whatever order they were added in")
	-- same gain, different price, in "biggest" mode: the cheaper first
	local job2 = Rank.Job(world())
	job2:Add(piece("INVTYPE_HEAD", 20, { name = "Dear" }), 30 * GOLD)
	job2:Add(piece("INVTYPE_HEAD", 20, { name = "Fair" }), 10 * GOLD)
	job2:Run()
	T.eq(names(Rank.Arrange(job2.rows, { level = 60, mode = "biggest" }).groups.HEAD), "Fair,Dear", "equal gain: lower price first")
end)

T.case("the same item listed many times: the cheapest listing counts", function()
	local job = Rank.Job(world())
	local helm = piece("INVTYPE_HEAD", 20, { name = "Helm", id = 6001 })
	job:Add(helm, 30 * GOLD)
	job:Add(helm, 10 * GOLD)
	job:Add(T.link(6001, "", "Helm", 17, 2504), 20 * GOLD)     -- another seller's link, enchanted
	job:Add(helm, 10 * GOLD)
	local dud = piece("INVTYPE_HEAD", 5, { name = "Dud", id = 6002 })
	job:Add(dud, GOLD); job:Add(dud, 1)
	job:Run()
	T.eq(#job.rows, 1, "one row"); T.eq(job.rows[1].price, 10 * GOLD, "at the lowest price")
	T.eq(WORLD.calls.ItemStats, 6, "four worn items, the helm and the dud: each read once")
end)

T.case("two rolls of one item are two rows", function()
	local job = Rank.Job(world())
	local bear = T.item({ id = 6100, suffix = 1, name = "Legs of the Bear", equipLoc = "INVTYPE_LEGS", raw = { ITEM_MOD_STRENGTH_SHORT = 14, ITEM_MOD_STAMINA_SHORT = 14 } })
	local owl = T.item({ id = 6100, suffix = 2, name = "Legs of the Owl", equipLoc = "INVTYPE_LEGS", raw = { ITEM_MOD_INTELLECT_SHORT = 14, ITEM_MOD_SPIRIT_SHORT = 14 } })
	local tiger = T.item({ id = 6100, suffix = 3, name = "Legs of the Tiger", equipLoc = "INVTYPE_LEGS", raw = { ITEM_MOD_STRENGTH_SHORT = 12 } })
	job:Add(bear, 4 * GOLD); job:Add(owl, 1 * GOLD); job:Add(tiger, 2 * GOLD)
	job:Run()
	local list = Rank.Arrange(job.rows, { level = 60 }).groups.LEGS
	T.eq(names(list), "Legs of the Bear,Legs of the Tiger", "the Bear (+11 for 4g) beats the Tiger (+2 for 2g); the Owl is no upgrade")
	T.near(list[1].gain, 11, "the roll's own stats were scored")
end)

T.case("best per slot plus alternatives", function()
	local job = Rank.Job(world())
	for i = 1, 15 do job:Add(piece("INVTYPE_HEAD", 10 + i, { name = "H" .. i }), GOLD) end
	job:Add(piece("INVTYPE_LEGS", 12, { name = "L" }), GOLD)
	job:Add(piece("INVTYPE_FINGER", 6, { name = "R" }), GOLD)
	job:Add(piece("INVTYPE_WAIST", 1, { name = "B" }), GOLD)
	job:Run()
	local view = Rank.Arrange(job.rows, { level = 60 })
	T.eq(#view.groups.HEAD, 11, "the best and ten alternatives"); T.eq(view.groups.HEAD[1].name, "H15", "best first")
	T.eq(view.groups.HEAD[11].name, "H5", "the eleventh"); T.eq(view.listed, 14, "11 + 1 + 1 + 1")
	T.eq(view.groups.LEGS[1].name, "L", "legs"); T.eq(view.groups.FINGER[1].name, "R", "a ring that beats the weaker ring")
	T.eq(view.groups.WAIST[1].empty, true, "an empty slot"); T.eq(view.groups.NECK, nil, "a slot with nothing has no list")
	view = Rank.Arrange(job.rows, { level = 60, alternatives = 2 })
	T.eq(#view.groups.HEAD, 3, "the number of alternatives is a setting")
	T.eq(#job.rows, 18, "Arrange never trims the job's own rows")
end)

T.case("a two-hander is listed with the main hand", function()
	T.reset()
	local sword = T.item({ equipLoc = "INVTYPE_WEAPON", classID = 2, subclassID = 7, raw = { ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 20 } })
	local ctx = Compare.Context({ class = "WARRIOR", level = 60, weights = W }, { [16] = sword }, {})
	local job = Rank.Job(ctx)
	job:Add(T.item({ name = "Claymore", equipLoc = "INVTYPE_2HWEAPON", classID = 2, subclassID = 8, raw = { ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 30 } }), GOLD)
	job:Add(T.item({ name = "Saber", equipLoc = "INVTYPE_WEAPON", classID = 2, subclassID = 7, raw = { ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 24 } }), GOLD)
	job:Run()
	local list = Rank.Arrange(job.rows, { level = 60, mode = "biggest" }).groups.MAINHAND
	T.eq(names(list), "Claymore,Saber", "one list for the hands"); T.eq(list[1].twoHand, true, "marked two-hand"); T.eq(list[2].twoHand, false, "the saber is not")
end)

T.case("work in slices", function()
	local job = Rank.Job(world())
	for i = 1, 25 do job:Add(piece("INVTYPE_HEAD", 10 + i, { name = "H" .. i }), GOLD) end
	T.eq(job:Left(), 25, "queued")
	T.eq(job:Step(10), false, "not done after ten"); T.eq(job.seen, 10, "ten seen"); T.eq(#job.rows, 10, "ten rows so far")
	T.eq(job:Left(), 15, "fifteen left")
	T.eq(job:Step(10), false, "nor after twenty"); T.eq(job:Step(10), true, "done"); T.eq(job.seen, 25, "all seen")
	T.eq(job:Step(10), true, "a step with nothing left is done at once"); T.eq(#job.rows, 25, "no row twice")
	job:Add(piece("INVTYPE_HEAD", 50, { name = "Late" }), GOLD)
	T.eq(job:Step(5), true, "more can be added later"); T.eq(#job.rows, 26, "and is scored")
	-- a view can be made part way
	local part = Rank.Job(world())
	for i = 1, 6 do part:Add(piece("INVTYPE_HEAD", 10 + i, { name = "P" .. i }), GOLD) end
	part:Step(3)
	T.eq(#Rank.Arrange(part.rows, { level = 60 }).groups.HEAD, 3, "a list from what is scored so far")
end)

T.case("items the game has not loaded are parked, asked for at a pace, and scored when they come", function()
	local job = Rank.Job(world())
	local late = piece("INVTYPE_HEAD", 20, { name = "Late", loaded = false })
	local late2 = piece("INVTYPE_HEAD", 30, { name = "Later", loaded = false })
	job:Add(late, 3 * GOLD); job:Add(late, 2 * GOLD); job:Add(late2, GOLD)
	job:Add(piece("INVTYPE_HEAD", 15, { name = "Ready" }), GOLD)
	local infos = WORLD.calls.ItemInfo or 0
	T.eq(job:Run(), true, "the queue is through")
	T.eq(#job.rows, 1, "only the loaded one"); T.eq(job.nParked, 3, "three listings parked"); T.eq(job:Done(), false, "not done")
	T.eq((WORLD.calls.ItemInfo or 0) - infos, 1, "an item the game has not got is never read (reading it would make the game fetch it)")
	T.eq(#WORLD.requested, 0, "and nothing is asked for until Pump")
	T.eq(job:Pump(1, 1000), 1, "one a call when told so"); T.eq(job:Pump(20, 1000), 1, "then the other"); T.eq(job:Pump(20, 1000), 0, "each item once")
	T.eq(#WORLD.requested, 2, "two items asked of the game")
	-- an event for something else is nothing
	T.eq(job:Arrived(424242, true), 0, "an item that is not ours")
	T.load(late)
	T.eq(job:Arrived(Stats.ItemID(late), true), 2, "its two listings go back in the queue"); T.eq(job.nParked, 1, "one still parked")
	job:Run()
	T.eq(#job.rows, 2, "scored once loaded"); T.eq(job.byKey[Stats.Key(late)].price, 2 * GOLD, "at its cheapest listing")
	-- the game says no data is coming
	T.eq(job:Arrived(Stats.ItemID(late2), false), 1, "refused"); T.eq(job.gaveUp, 1, "given up and counted")
	T.eq(job:Done(), true, "done"); T.eq(job.nAsked, 0, "nothing out")
end)

T.case("a job with rows that never resolve ends", function()
	local job = Rank.Job(world())
	local never = {}
	for i = 1, 40 do never[i] = piece("INVTYPE_HEAD", 20 + i, { loaded = false }) end
	for i = 1, 40 do job:Add(never[i], GOLD) end
	job:Add(piece("INVTYPE_HEAD", 15, { name = "Ready" }), GOLD)
	local now, rounds = 0, 0
	-- the window's loop: score, ask, and once a second look for answers that never came
	while not job:Done() and rounds < 1000 do
		rounds = rounds + 1
		now = now + 1000
		job:Step(50)
		job:Pump(20, now)
		job:Expire(now, 20000)
	end
	T.eq(job:Done(), true, "it ends (" .. rounds .. " seconds)"); T.check(rounds < 60, "within about two waits")
	T.eq(job.gaveUp, 40, "every unanswered row given up, and counted"); T.eq(job.nParked, 0, "nothing parked")
	T.eq(#job.rows, 1, "what could be read was")
	T.eq(#WORLD.requested, 80, "each item asked for twice, no more")
	-- an item the game has, whose stats never come: a few tries, then given up
	T.reset()
	job = Rank.Job(world())
	local odd = piece("INVTYPE_HEAD", 20)
	WORLD.items[T_ident(odd)].raw = nil
	local base = NS.Game.ItemStats
	NS.Game.ItemStats = function() return nil end
	job:Add(odd, GOLD)
	rounds = 0
	while not job:Done() and rounds < 100 do
		rounds = rounds + 1
		job:Step(5); job:Pump(20, rounds * 1000); job:Expire(rounds * 1000, 2000)
	end
	NS.Game.ItemStats = base
	T.eq(job:Done(), true, "that ends too"); T.eq(job.gaveUp, 1, "given up after a few tries")
	-- GiveUp ends a job at once
	job = Rank.Job(world())
	job:Add(piece("INVTYPE_HEAD", 20, { loaded = false }), GOLD)
	job:Run()
	T.eq(job:GiveUp(), 1, "what is parked is dropped"); T.eq(job:Done(), true, "done")
end)

T.case("a game that cannot say what it has cached", function()
	local job = Rank.Job(world())
	WORLD.noCacheCall = true
	local late = piece("INVTYPE_HEAD", 20, { name = "Late", loaded = false })
	job:Add(late, GOLD); job:Add(piece("INVTYPE_HEAD", 15, { name = "Ready" }), GOLD)
	job:Run()
	T.eq(#job.rows, 1, "the loaded one"); T.eq(job.nParked, 1, "the other waits, read the old way")
	T.load(late)
	job:Arrived(Stats.ItemID(late), true); job:Run()
	T.eq(#job.rows, 2, "and is scored when its event comes"); T.eq(job:Done(), true, "done")
end)

T.case("what the character cannot use is dropped before any game call", function()
	T.reset()
	local ctx = Compare.Context({ class = "SHAMAN", level = 33, weights = W }, { [1] = piece("INVTYPE_HEAD", 10) }, {})
	local job = Rank.Job(ctx)
	local calls = {}
	for name, n in pairs(WORLD.calls) do calls[name] = n end
	-- item class 4 armor (1 cloth, 2 leather, 3 mail, 4 plate, 6 shield), 2 weapons (2 bow, 4 mace, 7 sword, 8 two-hand sword)
	job:Add("item:1", GOLD, 4, 4, "INVTYPE_CHEST", 20)           -- plate: never
	job:Add("item:2", GOLD, 4, 3, "INVTYPE_CHEST", 20)           -- mail: not before 40
	job:Add("item:3", GOLD, 4, 2, "INVTYPE_CHEST", 34)           -- leather, level 34: not yet
	job:Add("item:4", GOLD, 2, 2, "INVTYPE_RANGED", 10)          -- a bow: never
	job:Add("item:5", GOLD, 2, 7, "INVTYPE_WEAPON", 10)          -- a sword: never
	job:Add("item:6", GOLD, 2, 4, "INVTYPE_WEAPONOFFHAND", 10)   -- an off-hand mace: no dual wield
	job:Add("item:7", GOLD, 4, 0, "INVTYPE_BAG", 0)              -- not gear at all
	job:Add("item:8", GOLD, 4, 2, "INVTYPE_CHEST", 33)           -- leather at the character's level: a candidate
	job:Add("item:9", GOLD, 4, 6, "INVTYPE_SHIELD", 30)          -- a shield: a candidate
	job:Add("item:10", GOLD, 2, 4, "INVTYPE_WEAPON", 30)         -- a mace: a candidate
	job:Add("item:11", GOLD, 4, 1, "INVTYPE_CLOAK", 1)           -- a cloak: a candidate
	job:Add("item:12", GOLD)                                     -- no facts (an old save): looked at the slow way
	T.eq(job:Left(), 5, "five of twelve are worth a look")
	T.eq(job.filtered.class, 4, "four the class cannot wear or wield"); T.eq(job.filtered.level, 2, "two it cannot wear yet")
	T.eq(job.filtered.notgear, 1, "one that is not gear")
	for name, n in pairs(WORLD.calls) do T.eq(n, calls[name], "no game call was made to decide (" .. name .. ")") end
	T.eq(WORLD.calls.ItemCached, calls.ItemCached, "not even 'is it cached'")
	-- "only my best armor type" works from the facts too
	ctx = Compare.Context({ class = "WARRIOR", level = 60, weights = W }, {}, {}, { bestArmor = true })
	job = Rank.Job(ctx)
	job:Add("item:20", GOLD, 4, 3, "INVTYPE_CHEST", 20); job:Add("item:21", GOLD, 4, 4, "INVTYPE_CHEST", 20)
	T.eq(job:Left(), 1, "mail is dropped for a level 60 warrior who asked for plate only")
end)

T.case("only upgrades are kept in memory", function()
	T.reset()
	local worn = piece("INVTYPE_HEAD", 10)
	local ctx = Compare.Context({ class = "WARRIOR", level = 60, weights = W }, { [1] = worn }, {})
	local kept = Stats.Cached()
	local job = Rank.Job(ctx)
	for i = 1, 300 do job:Add(piece("INVTYPE_HEAD", i % 10), GOLD) end   -- none better than the worn 10
	for i = 1, 7 do job:Add(piece("INVTYPE_HEAD", 20 + i), GOLD) end
	job:Run()
	T.eq(#job.rows, 7, "seven upgrades"); T.eq(Stats.Cached() - kept, 7, "seven records kept, not 307")
	T.eq(job.n, 307, "all were looked at"); T.eq(next(job.links), nil, "and the queue lets go of what it has looked at")
end)

T.case("the live view is the full arrangement, kept as rows come", function()
	local function names3(view)
		local out = {}
		for _, group in ipairs(Compare.GROUPS) do
			local list = view.groups[group]
			for i = 1, list and #list or 0 do out[#out + 1] = group .. ":" .. list[i].name end
			if view.over[group] then out[#out + 1] = group .. ">" .. view.over[group].name end
		end
		return table.concat(out, " ")
	end
	local locs = { "INVTYPE_HEAD", "INVTYPE_LEGS", "INVTYPE_FINGER", "INVTYPE_CHEST", "INVTYPE_WAIST" }
	for _, mode in ipairs({ "perGold", "biggest" }) do
		local opts = { mode = mode, maxPrice = 6 * GOLD, minPct = 3, level = 60, alternatives = 10 }
		local job = Rank.Job(world(), opts)
		for i = 1, 1500 do
			job:Add(piece(locs[i % 5 + 1], (i * 7) % 40, { id = 40000 + i, name = "N" .. i }), (i * 131) % 90000 + 1)
		end
		local changes = 0
		for _ = 1, 30 do
			job:Step(50)
			if job.live.changed then
				changes = changes + 1
				job.live.changed = false
			end
			-- at every point the live view equals arranging everything found so far
			T.eq(names3(job.live:View(job.rows)), names3(Rank.Arrange(job.rows, opts)), mode .. ": live equals the full arrangement after " .. job.seen)
		end
		T.eq(job.live:View(job.rows).listed, Rank.Arrange(job.rows, opts).listed, mode .. ": the same count")
		T.check(changes >= 1 and changes < 30, mode .. ": and it stops changing once the best are found (" .. changes .. " of 30 steps changed what is shown)")
	end
	-- a cheaper listing of a row already placed: the live view says it is stale, and View arranges once
	local job = Rank.Job(world(), { level = 60 })
	local a = piece("INVTYPE_HEAD", 20, { name = "A", id = 41001 })
	job:Add(a, 30 * GOLD); job:Add(piece("INVTYPE_HEAD", 18, { name = "B", id = 41002 }), 10 * GOLD)
	job:Run()
	T.eq(job.live:View(job.rows).groups.HEAD[1].name, "B", "B is the better buy per gold")
	job:Add(a, 1 * GOLD); job:Run()
	T.eq(job.live.stale, true, "a price dropped on a placed row")
	T.eq(job.live:View(job.rows).groups.HEAD[1].name, "A", "the view is arranged again, once"); T.eq(job.live.stale, false, "and is current")
end)

T.case("bad input is ignored", function()
	local job = Rank.Job(world())
	job:Add(nil, GOLD); job:Add("junk", GOLD); job:Add(piece("INVTYPE_HEAD", 20), 0); job:Add(piece("INVTYPE_HEAD", 20), -5)
	job:Add(piece("INVTYPE_HEAD", 20), "12"); job:Add(12345, GOLD)
	job:Run()
	T.eq(#job.rows, 0, "nothing listed"); T.eq(job.seen, 1, "only the junk string got as far as being looked at")
	local view = Rank.Arrange({}, nil)
	T.eq(view.listed, 0, "an empty list arranges to nothing"); T.eq(next(view.groups), nil, "no groups")
end)

T.case("no weights for any stat on offer: nothing is listed, nothing breaks", function()
	T.reset()
	local ctx = Compare.Context({ class = "WARRIOR", level = 60, weights = {} }, { [1] = piece("INVTYPE_HEAD", 10) }, {})
	local job = Rank.Job(ctx)
	job:Add(piece("INVTYPE_HEAD", 99), GOLD)
	job:Run()
	T.eq(#job.rows, 0, "every score is zero, so nothing is an upgrade")
	ctx = Compare.Context({ class = "WARRIOR", level = 60, weights = { INT = 1 } }, { [1] = piece("INVTYPE_HEAD", 10) }, {})
	job = Rank.Job(ctx)
	job:Add(piece("INVTYPE_HEAD", 99), GOLD)
	job:Add(T.item({ name = "Wise", equipLoc = "INVTYPE_HEAD", raw = { ITEM_MOD_INTELLECT_SHORT = 3, ITEM_MOD_STRENGTH_SHORT = 1 } }), GOLD)
	job:Run()
	T.eq(#job.rows, 1, "only the stat with a weight counts"); T.near(job.rows[1].gain, 3, "the unweighted Strength adds nothing")
end)

T.case("many items for sale", function()
	local job = Rank.Job(world())
	local locs = { "INVTYPE_HEAD", "INVTYPE_LEGS", "INVTYPE_FINGER", "INVTYPE_CHEST", "INVTYPE_WAIST" }
	for i = 1, 3000 do
		job:Add(piece(locs[i % 5 + 1], (i * 7) % 40, { id = 20000 + i }), (i * 131) % 90000 + 1)
	end
	job:Run()
	T.eq(job.seen, 3000, "all seen")
	local view = Rank.Arrange(job.rows, { level = 60, maxPrice = 5 * GOLD, minPct = 3 })
	local again = Rank.Arrange(job.rows, { level = 60, maxPrice = 5 * GOLD, minPct = 3 })
	for _, group in ipairs(Compare.GROUPS) do
		local a, b = view.groups[group], again.groups[group]
		T.eq(a and #a or 0, b and #b or 0, group .. " same length twice")
		for i = 1, a and #a or 0 do
			T.check(a[i] == b[i], group .. " same order twice")
			T.check(a[i].gain > 0, "only gains"); T.check(a[i].price <= 5 * GOLD, "under the limit")
			if i > 1 then T.check(a[i - 1].value >= a[i].value, "best value first") end
		end
	end
	T.check(view.listed > 20 and view.listed <= 55, "at most eleven a slot (" .. view.listed .. ")")
end)

T.case("ranking goes by the gain, never by the percent (the audit's M2)", function()
	T.reset()
	-- A neck worth 0.5 and a chest worth 20 are worn. A neck that adds 6 is "+60%" against the
	-- floor (half a typical piece); a chest that adds 8 is "+40%". The chest gains more and must
	-- rank first, in both orders, at the same price.
	local worn = { [2] = piece("INVTYPE_NECK", 0.5), [5] = piece("INVTYPE_CHEST", 20) }
	local ctx = Compare.Context({ class = "WARRIOR", level = 60, weights = W }, worn, {})
	local job = Rank.Job(ctx)
	job:Add(piece("INVTYPE_NECK", 6.5, { name = "Neck" }), 2 * GOLD)
	job:Add(piece("INVTYPE_CHEST", 28, { name = "Chest" }), 2 * GOLD)
	job:Add(piece("INVTYPE_NECK", 40, { name = "Huge" }), 2 * GOLD)
	job:Run()
	local neck, chest, huge = job.rows[1], job.rows[2], job.rows[3]
	T.near(neck.gain, 6, "the neck's gain"); T.near(chest.gain, 8, "the chest's gain")
	T.check(neck.pct > chest.pct, "the neck's percent is the bigger one"); T.check(neck.pct < 200, "and floored: not 1200%")
	T.eq(huge.far, true, "a row can be 'far better'"); T.eq(neck.far, false, "and most are not")
	local rows = { neck, chest }
	T.check(Rank.Value(chest.gain, chest.price, 60) > Rank.Value(neck.gain, neck.price, 60), "per gold: the chest is worth more")
	local flat = {}
	for _, mode in ipairs({ "perGold", "biggest" }) do
		local view = Rank.Arrange(rows, { level = 60, mode = mode })
		flat[mode] = view.groups.CHEST[1].value > view.groups.NECK[1].value
	end
	T.check(flat.perGold and flat.biggest, "the value used for ordering follows the gain")
end)

T.case("the smallest gain to show, with nothing to measure against", function()
	T.reset()
	-- Nothing worn scores, so there is no percent at all: such a row always passes.
	local ctx = Compare.Context({ class = "WARRIOR", level = 60, weights = W },
		{ [2] = T.item({ equipLoc = "INVTYPE_NECK", raw = { ITEM_MOD_SPIRIT_SHORT = 9 } }) }, {})
	local job = Rank.Job(ctx)
	job:Add(piece("INVTYPE_NECK", 1, { name = "Any" }), GOLD)
	job:Run()
	T.eq(job.rows[1].pct, nil, "no percent"); T.eq(job.rows[1].empty, false, "and the slot is not empty")
	T.eq(#Rank.Arrange(job.rows, { level = 60, minPct = 20 }).groups.NECK, 1, "it is listed whatever the smallest gain is")
end)

T.case("the same roll listed under three link shapes is one row at its cheapest (the audit's M6)", function()
	local job = Rank.Job(world())
	T.item({ id = 7445, roll = 12751, name = "Sentinel Cap of the Bandit", equipLoc = "INVTYPE_HEAD", raw = { ITEM_MOD_STRENGTH_SHORT = 20 } })
	job:Add(T.link(7445, 12751, "Sentinel Cap of the Bandit", 33), 30 * GOLD)
	job:Add(T.link(7445, 12751, "Sentinel Cap of the Bandit", 33, nil, { context = 1 }), 10 * GOLD)
	job:Add(T.link(7445, 12751, "Sentinel Cap of the Bandit", 60, nil, { context = 1, modifiers = "28:4522" }), 20 * GOLD)
	job:Run()
	T.eq(#job.rows, 1, "one item, one row"); T.eq(job.rows[1].price, 10 * GOLD, "at the cheapest of the three listings")
	T.eq(#Rank.Arrange(job.rows, { level = 60 }).groups.HEAD, 1, "and one place in the list, not three")
end)


T.case("a corrected price moves the row within its slot and scores nothing again", function()
	local job = Rank.Job(world(), { level = 60 })
	local a, b, c = piece("INVTYPE_HEAD", 30, { name = "A" }), piece("INVTYPE_HEAD", 20, { name = "B" }), piece("INVTYPE_LEGS", 20, { name = "C" })
	job:Add(a, 100 * GOLD); job:Add(b, 20 * GOLD); job:Add(c, 20 * GOLD)
	job:Run()
	T.eq(job.reads, 3, "three items read from the game, once each"); T.eq(job.seen, 3, "in three looks")
	T.eq(names(job.live:View(job.rows).groups.HEAD), "B,A", "B is the better buy per gold")
	local stats, seen, reads = WORLD.calls.ItemStats, job.seen, job.reads
	local legs = job.live:View(job.rows).groups.LEGS
	T.eq(job:Reprice(Stats.Key(a), 10 * GOLD, 500), "row", "A's price is corrected")
	local view = job.live:View(job.rows)
	T.eq(names(view.groups.HEAD), "A,B", "and A leads its slot now"); T.eq(view.groups.HEAD[1].price, 10 * GOLD, "at the new price")
	T.eq(view.groups.HEAD[1].checkedAt, 500, "the row says when it was checked")
	T.eq(view.groups.LEGS, legs, "the other slot's list is the very same table: untouched")
	T.eq(WORLD.calls.ItemStats, stats, "no item read"); T.eq(job.seen, seen, "nothing looked at again"); T.eq(job.reads, reads, "nothing read again")
	T.eq(job.live.stale, false, "and no full arrangement was needed")
	T.eq(names(view.groups.HEAD), names(Rank.Arrange(job.rows, { level = 60 }).groups.HEAD), "the same as arranging everything")
	-- none left
	T.eq(job:Reprice(Stats.Key(a), 0, 600), "row", "A is sold")
	view = job.live:View(job.rows)
	T.eq(names(view.groups.HEAD), "B", "A is in no view"); T.eq(job.gone, 1, "one gone"); T.eq(view.listed, 2, "two listed")
	T.eq(names(Rank.Arrange(job.rows, { level = 60 }).groups.HEAD), "B", "nor in a full arrangement")
	job:Reprice(Stats.Key(a), 0, 700)
	T.eq(job.gone, 1, "said twice, counted once")
	-- listed again
	job:Reprice(Stats.Key(a), 50 * GOLD, 800)
	T.eq(job.gone, 0, "back for sale"); T.eq(names(job.live:View(job.rows).groups.HEAD), "B,A", "and placed by its new price")
	-- a listing of the old list never undoes a checked price
	job:Add(a, 1)
	job:Run()
	T.eq(job.byKey[Stats.Key(a)].price, 50 * GOLD, "the checked price stands against an older, cheaper listing")
end)

T.case("a correction for an item that is no upgrade, and for one never seen", function()
	local job = Rank.Job(world(), { level = 60 })
	local worse = piece("INVTYPE_HEAD", 5, { name = "Worse" })
	job:Add(worse, 10)
	job:Run()
	T.eq(job:Reprice(Stats.Key(worse), 5, 1), "known", "known and no upgrade: nothing to move")
	T.eq(job:Reprice(Stats.Key(worse), 0, 1), "known", "nor when it is sold"); T.eq(job.gone, 0, "not counted as an upgrade gone")
	local new = piece("INVTYPE_HEAD", 40, { name = "New" })
	T.eq(job:Reprice(Stats.Key(new), 7, 1), nil, "never seen: the caller adds it")
	job:Add("item:" .. Stats.Key(new), 7, nil, nil, nil, nil, 900)
	job:Run()
	T.eq(job.byKey[Stats.Key(new)].checkedAt, 900, "an added item keeps when it was checked")
end)

T.case("two rolls of one item are two rows, corrected apart", function()
	local job = Rank.Job(world(), { level = 60 })
	local id = Stats.ItemID(piece("INVTYPE_HEAD", 0, { name = "Helm" }))
	local bear = T.item({ id = id, equipLoc = "INVTYPE_HEAD", classID = 4, subclassID = 0, roll = 1201, name = "Helm of the Bear", raw = { ITEM_MOD_STRENGTH_SHORT = 30 } })
	local tiger = T.item({ id = id, equipLoc = "INVTYPE_HEAD", classID = 4, subclassID = 0, roll = 1202, name = "Helm of the Tiger", raw = { ITEM_MOD_STRENGTH_SHORT = 25 } })
	T.check(Stats.Key(bear) ~= Stats.Key(tiger) and Stats.ItemID(tiger) == id, "one item, two keys")
	job:Add(bear, 10 * GOLD); job:Add(tiger, 10 * GOLD)
	job:Run()
	job:Reprice(Stats.Key(bear), 3 * GOLD, 5)
	T.eq(job.byKey[Stats.Key(bear)].price, 3 * GOLD, "the Bear re-priced"); T.eq(job.byKey[Stats.Key(tiger)].price, 10 * GOLD, "the Tiger as it was")
	T.eq(job.byKey[Stats.Key(tiger)].checkedAt, nil, "and not marked as checked")
end)

T.case("each item is read from the game once, however often it passes the queue", function()
	-- A real job once reported "16,159 fed, 34,414 read": every item not in the game's cache was
	-- read, parked and read again. An item not cached is not read at all until it arrives.
	local job = Rank.Job(world(), { level = 60 })
	local cached, late = piece("INVTYPE_HEAD", 30, { name = "Cached" }), piece("INVTYPE_LEGS", 30, { name = "Late" })
	WORLD.items[T_ident(late)].loaded = false
	Stats.Forget()
	local stats = WORLD.calls.ItemStats or 0
	job:Add(cached, 10); job:Add(late, 10)
	job:Run()
	T.eq(job.reads, 1, "the cached item is read, the other is parked unread"); T.eq((WORLD.calls.ItemStats or 0) - stats, 1, "one stat call")
	job:Pump(20, 1000)
	T.load(late)
	job:Arrived(Stats.ItemID(late), true)
	job:Run()
	T.eq(job.reads, 2, "read once when it arrived"); T.eq((WORLD.calls.ItemStats or 0) - stats, 2, "two stat calls for two items")
	T.eq(job.seen, 3, "three passes of the queue for two items: passes are not reads"); T.eq(#job.rows, 2, "both are upgrades")
end)

-- ---------------------------------------------------------------------------------------------
-- Weapon sets
-- ---------------------------------------------------------------------------------------------
local WS = { STR = 1, MH_DPS = 2, OH_DPS = 1 }
local function arm(loc, dps, more)
	local def = { equipLoc = loc, classID = 2, subclassID = (loc == "INVTYPE_2HWEAPON") and 8 or 7,
		raw = { ITEM_MOD_DAMAGE_PER_SECOND_SHORT = dps } }
	for k, v in pairs(more or {}) do def[k] = v end
	return T.item(def)
end
local function shield(str, more)
	local def = { equipLoc = "INVTYPE_SHIELD", classID = 4, subclassID = 6, raw = { ITEM_MOD_STRENGTH_SHORT = str } }
	for k, v in pairs(more or {}) do def[k] = v end
	return T.item(def)
end
local function hands(class, worn, carried)
	return Compare.Context({ class = class, level = 60, weights = WS }, worn, carried or {})
end
local OPTS = { level = 60 }

T.case("a main hand and an off hand that are an upgrade only together", function()
	T.reset()
	-- holding a two-hander worth 60; for sale: a sword worth 40 and a shield worth 25
	local job = Rank.Job(hands("WARRIOR", { [16] = arm("INVTYPE_2HWEAPON", 30) }), OPTS)
	local sword, board = arm("INVTYPE_WEAPON", 20, { name = "Sword" }), shield(25, { name = "Board" })
	job:Add(sword, 3 * GOLD); job:Add(board, 2 * GOLD)
	job:Run()
	T.eq(#job.rows, 0, "neither is an upgrade alone: no row")
	local view = job.live:View(job.rows)
	local set = Rank.Set(job, OPTS, view)
	T.check(set ~= nil, "together they are")
	T.eq(set.main.name, "Sword", "the main hand"); T.eq(set.off.name, "Board", "the off hand")
	T.near(set.gain, 5, "40 + 25 against the two-hander's 60"); T.eq(set.price, 5 * GOLD, "priced as a set")
	T.near(set.pct, 5 / 60 * 100, "the percent is of what the hands hold now")
	-- the price limit is per item
	T.eq(Rank.Set(job, { level = 60, maxPrice = 2.5 * GOLD }, view), nil, "the sword is over the max price per item: no pair")
	T.check(Rank.Set(job, { level = 60, maxPrice = 3 * GOLD }, view) ~= nil, "at the limit it stands")
	T.eq(Rank.Set(job, { level = 60, minPct = 20 }, view), nil, "under the smallest gain to show: no pair")
	-- sold
	job:Reprice(Stats.Key(board), 0, 5)
	T.eq(Rank.Set(job, OPTS, view), nil, "the shield sold: no pair")
	job:Reprice(Stats.Key(board), 1 * GOLD, 6)
	T.eq(Rank.Set(job, OPTS, view).price, 4 * GOLD, "listed again, cheaper: the pair's price follows")
end)

T.case("two purchases that simply add up get no row of their own", function()
	T.reset()
	-- holding a sword worth 20 and no off hand; a better sword (+40) and a shield (+5) add up to +45
	local job = Rank.Job(hands("WARRIOR", { [16] = arm("INVTYPE_WEAPON", 10) }), OPTS)
	job:Add(arm("INVTYPE_WEAPON", 30, { name = "Sword" }), 3 * GOLD); job:Add(shield(5, { name = "Board" }), 2 * GOLD)
	job:Run()
	local view = job.live:View(job.rows)
	T.eq(#job.rows, 2, "each is an upgrade alone: two rows")
	T.eq(Rank.Set(job, OPTS, view), nil, "the pair says nothing the two rows do not")
end)

T.case("the pair against a two-hander for sale, and by which measure", function()
	T.reset()
	local job = Rank.Job(hands("WARRIOR", { [16] = arm("INVTYPE_2HWEAPON", 30) }), OPTS)
	job:Add(arm("INVTYPE_WEAPON", 20, { name = "Sword" }), 3 * GOLD); job:Add(shield(25, { name = "Board" }), 2 * GOLD)
	job:Add(arm("INVTYPE_2HWEAPON", 34, { name = "Big" }), 4 * GOLD)      -- 68: +8 alone
	job:Run()
	local view = job.live:View(job.rows)
	T.eq(view.groups.MAINHAND[1].name, "Big", "the two-hander is the Main Hand pick")
	T.eq(Rank.Set(job, OPTS, view), nil, "the pair gains 5, the two-hander 8: the pair is not said")
	-- a better shield: the pair gains more than the two-hander
	job:Add(shield(40, { name = "Wall" }), 2 * GOLD)
	job:Run()
	local set = Rank.Set(job, OPTS, job.live:View(job.rows))
	T.eq(set.off.name, "Wall", "the better shield"); T.near(set.gain, 20, "40 + 40 against 60")
	-- per gold or biggest: a dear, slightly better sword
	job:Add(arm("INVTYPE_WEAPON", 21, { name = "Dear Sword" }), 60 * GOLD)
	job:Run()
	T.eq(Rank.Set(job, { level = 60, mode = "perGold" }, job.live:View(job.rows)).main.name, "Sword", "most per gold: the cheap sword")
	T.eq(Rank.Set(job, { level = 60, mode = "biggest" }, job.live:View(job.rows)).main.name, "Dear Sword", "biggest gain: the dear one")
end)

T.case("never a pair the character cannot hold", function()
	T.reset()
	-- a mage holds no shield and no second weapon
	local ctx = Compare.Context({ class = "MAGE", level = 60, weights = WS }, { [16] = T.item({ equipLoc = "INVTYPE_2HWEAPON", classID = 2, subclassID = 10,
		raw = { ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 30 } }) }, {})
	local job = Rank.Job(ctx, OPTS)
	job:Add(T.item({ equipLoc = "INVTYPE_WEAPON", classID = 2, subclassID = 15, name = "Dagger", raw = { ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 20 } }), GOLD)
	job:Add(shield(90, { name = "Board" }), GOLD)
	job:Add(T.item({ equipLoc = "INVTYPE_WEAPON", classID = 2, subclassID = 15, name = "Dagger 2", raw = { ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 25 } }), GOLD)
	job:Run()
	T.eq(#job.hands.off, 0, "a shield is no off hand for a mage, nor a second dagger")
	T.eq(Rank.Set(job, OPTS, job.live:View(job.rows)), nil, "no pair")
	-- a rogue dual wields: the off hand's damage counts with the off-hand weight
	T.reset()
	job = Rank.Job(hands("ROGUE", { [16] = arm("INVTYPE_2HWEAPON", 30, { subclassID = 7 }) }), OPTS)
	local a, b = arm("INVTYPE_WEAPON", 25, { name = "A" }), arm("INVTYPE_WEAPON", 20, { name = "B" })
	job:Add(a, GOLD); job:Add(b, GOLD)
	job:Run()
	local set = Rank.Set(job, OPTS, job.live:View(job.rows))
	T.check(set ~= nil, "two one-handers for a dual wielder")
	T.eq(set.main.name, "A", "the stronger in the main hand"); T.eq(set.off.name, "B", "the other in the off hand")
	T.near(set.gain, 25 * 2 + 20 * 1 - 60, "main hand damage x2, off hand damage x1, against the two-hander")
	-- one listing is never both hands; one unique-equipped item is never both hands
	T.reset()
	job = Rank.Job(hands("ROGUE", { [16] = arm("INVTYPE_2HWEAPON", 30, { subclassID = 7 }) }), OPTS)
	local only = arm("INVTYPE_WEAPON", 40, { name = "Only" })
	job:Add(only, GOLD)
	job:Run()
	T.eq(Rank.Set(job, OPTS, job.live:View(job.rows)), nil, "one sword for sale is not a pair with itself")
	local base = Stats.ItemID(arm("INVTYPE_WEAPON", 0, { name = "One" }))
	job:Add(arm("INVTYPE_WEAPON", 40, { id = base, roll = 1, unique = true, name = "One of A" }), GOLD)
	job:Add(arm("INVTYPE_WEAPON", 40, { id = base, roll = 2, unique = true, name = "One of B" }), GOLD)
	job:Run()
	set = Rank.Set(job, OPTS, job.live:View(job.rows))
	T.check(set ~= nil, "a pair is found")
	T.check(not (set.main.name:find("One of") and set.off.name:find("One of")), "but never two of one unique-equipped item (" ..
		set.main.name .. " + " .. set.off.name .. ")")
end)

T.case("the lists per hand stay short, and the best pair is still found", function()
	T.reset()
	local job = Rank.Job(hands("WARRIOR", { [16] = arm("INVTYPE_2HWEAPON", 30) }), OPTS)
	for i = 1, 150 do
		job:Add(arm("INVTYPE_WEAPON", i / 10, { name = "S" .. i }), (1 + i) * GOLD)
		job:Add(shield(i / 10, { name = "B" .. i }), (1 + i) * GOLD)
	end
	job:Add(arm("INVTYPE_WEAPON", 40, { name = "Best Sword" }), 5 * GOLD); job:Add(shield(50, { name = "Best Board" }), 5 * GOLD)
	job:Run()
	local h = job.hands
	T.check(#h.main <= Rank.HAND_KEEP and #h.off <= Rank.HAND_KEEP and #h.mainThrift <= Rank.HAND_KEEP and #h.offThrift <= Rank.HAND_KEEP,
		"at most " .. Rank.HAND_KEEP .. " kept per list, of 151 for sale per hand")
	local set = Rank.Set(job, OPTS, job.live:View(job.rows))
	T.eq(set.main.name, "Best Sword", "the best main hand"); T.eq(set.off.name, "Best Board", "and off hand")
end)

T.case("the hit cap counts over the pair", function()
	T.reset()
	local w = { STR = 1, MH_DPS = 2, HIT = 10 }
	local ctx = Compare.Context({ class = "WARRIOR", level = 60, weights = w }, { [16] = arm("INVTYPE_2HWEAPON", 30),
		[5] = T.item({ equipLoc = "INVTYPE_CHEST", classID = 4, subclassID = 0, raw = { ITEM_MOD_HIT_MELEE_RATING_SHORT = 60 } }) }, {})
	local job = Rank.Job(ctx, OPTS)
	-- 6% worn; the sword has 2% and the shield 2%: only 2% of the pair's 4% counts
	job:Add(arm("INVTYPE_WEAPON", 25, { name = "Sword", raw = { ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 25, ITEM_MOD_HIT_MELEE_RATING_SHORT = 20 } }), GOLD)
	job:Add(shield(15, { name = "Board", raw = { ITEM_MOD_STRENGTH_SHORT = 15, ITEM_MOD_HIT_MELEE_RATING_SHORT = 20 } }), GOLD)
	job:Run()
	local set = Rank.Set(job, OPTS, job.live:View(job.rows))
	T.near(set.gain, 50 + 15 + 20 - 60, "damage, Strength and 2% of hit; the other 2% is over the cap")
end)

return T.done()
