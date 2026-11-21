-- Glowey's Gear: what a candidate item would replace, and how much better it is.
--
--   Compare.Context(who, worn, carried, opts) -> ctx
--        who     = { class, level, weights }            (Spec.Current() gives exactly this)
--        worn    = { [slot] = link }                     slots 1 to 18
--        carried = { link, link, ... }                   what is in the bags
--        opts    = { bestArmor = bool }
--        ctx.pending = how many owned links the game had not loaded yet (build it again later)
--        ctx.typical = what a worn piece is worth on average (see THE PERCENT below)
--        ctx.dual    = the character can hold a weapon in the off hand
--   Compare.FromGame(who, opts)               -> ctx    (worn and carried read through ns.Game)
--   Compare.Evaluate(rec, ctx, opts, out)     -> out
--        opts = { exclude = key }   leave one copy of this item out of what is owned: for a
--                                   verdict on an item that is itself in the bags
--               { wornOnly = true } compare with what is worn, ignoring the bags
--        out  = { usable, reason, atLevel, group, slot, score, base, gain, pct, far, empty,
--                 replaces (a record or nil), twoHand, offHand }
--   Compare.GROUPS                            -> the slot groups in display order
--   Compare.FAR                               -> the percent above which "far" is set
--
-- THE RULE. The item to beat is the best the character already has for that place, worn or in
-- the bags, so the plugin never suggests buying something worse than what is already owned.
-- Carried items count only when the character can wear them now.
--
--   One-slot places (head, chest, ...): gain = candidate - best owned.
--   Rings and trinkets (two slots): the candidate takes the place of the weaker of the best two
--     owned, so gain = candidate - second best owned (an empty second slot counts as 0).
--     A unique-equipped candidate the character already has among those two can only replace
--     its own copy: gain = candidate - that copy.
--   Weapons. The hands are judged as a set. The set the character can make today is worth
--         W = the larger of (best two-hander) and (best main hand + best off hand),
--     where the pair is two different items. The candidate is tried in the hand it can go in
--     and the new set compared with W:
--         a two-hander:            new set = candidate
--         in the main hand:        new set = candidate + best owned off hand
--         in the off hand:         new set = best owned main hand + candidate
--     A one-hand weapon (INVTYPE_WEAPON) goes in the main hand; for a character who can dual
--     wield it is tried in BOTH hands and the better answer stands (in the off hand its damage
--     counts with the off-hand weight, OH_DPS, in place of MH_DPS). Owned one-handers likewise
--     count as possible off hands for a dual wielder. Shields and held items only ever go in
--     the off hand. The verdict's group says which hand won ("MAINHAND" or "OFFHAND").
--     Still left out: pairs across the Auction House (a main hand and an off hand that are only
--     an upgrade when bought together), and the ranged slot is a one-slot place of its own.
--
-- THE PERCENT. gain is in score points and is what ranking uses. The percent is only for
-- reading, and a bare gain / base misleads when the replaced item is worth next to nothing to
-- the spec: a +15 Strength neck over a +5 health neck is "+19900%". So:
--   * pct = gain / max(base, floor) x 100, where floor = half of ctx.typical, and ctx.typical is
--     the average score of the worn pieces that score anything. A replaced item is never
--     counted as worth less than half a typical piece of the character's own gear, so the
--     percent answers "how much better than a piece like the ones I wear" when the baseline is
--     tiny. With a normal baseline the floor does nothing.
--   * Above Compare.FAR (200) the number stops meaning anything a player can use: `far` is set
--     and the surfaces say "far better" in words instead of a figure.
--   * pct is nil only when there is nothing to measure against at all (nothing worn scores, so
--     there is no typical piece). `empty` is true only when nothing is replaced: a slot that
--     holds an item that scores 0 is not empty.

local _, ns = ...

local Compare = {}
ns.Compare = Compare

Compare.FAR = 200

-- equip location -> group. The game's slot numbers (INVSLOT_*, FX Blizzard_FrameXMLBase\
-- Constants.lua:136-153): 1 head, 2 neck, 3 shoulder, 5 chest, 6 waist, 7 legs, 8 feet, 9 wrist,
-- 10 hands, 11-12 fingers, 13-14 trinkets, 15 back, 16 main hand, 17 off hand, 18 ranged.
local GROUP_OF = {
	INVTYPE_HEAD = "HEAD", INVTYPE_NECK = "NECK", INVTYPE_SHOULDER = "SHOULDER",
	INVTYPE_CLOAK = "BACK", INVTYPE_CHEST = "CHEST", INVTYPE_ROBE = "CHEST",
	INVTYPE_WRIST = "WRIST", INVTYPE_HAND = "HANDS", INVTYPE_WAIST = "WAIST",
	INVTYPE_LEGS = "LEGS", INVTYPE_FEET = "FEET",
	INVTYPE_FINGER = "FINGER", INVTYPE_TRINKET = "TRINKET",
	INVTYPE_WEAPON = "MAINHAND", INVTYPE_WEAPONMAINHAND = "MAINHAND",
	INVTYPE_2HWEAPON = "TWOHAND",
	INVTYPE_WEAPONOFFHAND = "OFFHAND", INVTYPE_SHIELD = "OFFHAND", INVTYPE_HOLDABLE = "OFFHAND",
	INVTYPE_RANGED = "RANGED", INVTYPE_RANGEDRIGHT = "RANGED", INVTYPE_THROWN = "RANGED",
	INVTYPE_RELIC = "RANGED",
}
Compare.GROUP_OF = GROUP_OF

-- The groups a list shows, in order. A two-hander is listed with the main hand.
Compare.GROUPS = { "HEAD", "NECK", "SHOULDER", "BACK", "CHEST", "WRIST", "HANDS", "WAIST", "LEGS",
	"FEET", "FINGER", "TRINKET", "MAINHAND", "OFFHAND", "RANGED" }

-- group -> the slot (or first slot) it fills, for the window's slot name and icon.
Compare.SLOT_OF = { HEAD = 1, NECK = 2, SHOULDER = 3, BACK = 15, CHEST = 5, WRIST = 9, HANDS = 10,
	WAIST = 6, LEGS = 7, FEET = 8, FINGER = 11, TRINKET = 13, MAINHAND = 16, TWOHAND = 16,
	OFFHAND = 17, RANGED = 18 }

local PAIR = { FINGER = true, TRINKET = true }
local WEAPONS = { MAINHAND = true, TWOHAND = true, OFFHAND = true }
local ONE_HAND = "INVTYPE_WEAPON"

-- A one-hand weapon's score when it is held in the off hand: the same stats, with its damage
-- per second (and swing time) counted by the off-hand weights instead of the main-hand ones.
local function offScore(rec, weights, mainScore)
	local s = rec.stats
	local dps, speed = s.MH_DPS or 0, s.MH_SPEED or 0
	return mainScore
		- dps * (weights.MH_DPS or 0) + dps * (weights.OH_DPS or 0)
		- speed * (weights.MH_SPEED or 0) + speed * (weights.OH_SPEED or 0)
end

-- ---------------------------------------------------------------------------------------------
-- What is owned
-- ---------------------------------------------------------------------------------------------
local function byScore(a, b)
	if a.score ~= b.score then return a.score > b.score end
	-- (Worn before carried, then by key: the same answer every time.)
	if (a.slot ~= nil) ~= (b.slot ~= nil) then return a.slot ~= nil end
	return a.rec.key < b.rec.key
end

function Compare.Context(who, worn, carried, opts)
	local Stats, Score = ns.Stats, ns.Score
	Score.Fresh()
	local ctx = { class = who.class, level = who.level, weights = who.weights,
		bestArmor = opts and opts.bestArmor or false, pools = {}, pending = 0, typical = 0 }
	ctx.dual = Score.CanDualWield(ctx)
	local pools = ctx.pools
	local wornSum, wornCount, items = 0, 0, 0
	local function into(group, entry)
		local pool = pools[group]
		if not pool then
			pool = {}
			pools[group] = pool
		end
		pool[#pool + 1] = entry
	end
	local function own(link, slot)
		local rec, why = Stats.Of(link)
		if not rec then
			if why == "pending" then ctx.pending = ctx.pending + 1 end
			return
		end
		local group = GROUP_OF[rec.equipLoc]
		if not group then return end
		-- (What is worn is wearable by definition; what is carried must pass the same test a
		-- candidate does, except the "best armor only" preference, which is about buying.)
		if not slot and not Score.Usable(rec, ctx) then return end
		local score = Score.Value(rec.stats, ctx.weights)
		items = items + 1
		-- (`item` tells two entries of one physical item apart from two copies of it.)
		into(group, { rec = rec, score = score, slot = slot, item = items })
		if rec.equipLoc == ONE_HAND and ctx.dual then
			-- The same weapon as a possible off hand.
			into("OFFHAND", { rec = rec, score = offScore(rec, ctx.weights, score), slot = slot, item = items })
		end
		if slot and score > 0 then
			wornSum, wornCount = wornSum + score, wornCount + 1
		end
	end
	for slot = 1, 18 do
		if worn and worn[slot] then own(worn[slot], slot) end
	end
	for i = 1, carried and #carried or 0 do own(carried[i], nil) end
	for _, pool in pairs(pools) do table.sort(pool, byScore) end
	if wornCount > 0 then ctx.typical = wornSum / wornCount end
	return ctx
end

local wornBuf, bagBuf = {}, {}
function Compare.FromGame(who, opts)
	local G = ns.Game
	for slot = 1, 18 do wornBuf[slot] = G.WornLink(slot) end
	for i = #bagBuf, 1, -1 do bagBuf[i] = nil end
	G.BagLinks(bagBuf)
	return Compare.Context(who, wornBuf, bagBuf, opts)
end

-- The nth best owned entry of a group (pools are sorted best first), passing over one copy of
-- `exclude` (a carried one: a worn item is never the one being judged), everything that is not
-- worn when wornOnly is set, and the physical item `notItem`.
local function nth(ctx, group, n, exclude, wornOnly, notItem)
	local pool = ctx.pools[group]
	if not pool then return nil end
	local skippedItem
	for i = 1, #pool do
		local e = pool[i]
		local take = true
		if wornOnly and not e.slot then
			take = false
		elseif notItem and e.item == notItem then
			take = false
		elseif exclude and not e.slot and e.rec.key == exclude and (skippedItem == nil or skippedItem == e.item) then
			skippedItem, take = e.item, false
		end
		if take then
			n = n - 1
			if n == 0 then return e end
		end
	end
	return nil
end

-- Which carried physical item `exclude` stands for, so the same one is passed over in every
-- pool it sits in (a one-hander is in two).
local function excludedItem(ctx, exclude)
	if not exclude then return nil end
	for _, group in ipairs({ "MAINHAND", "OFFHAND", "TWOHAND" }) do
		local pool = ctx.pools[group]
		for i = 1, pool and #pool or 0 do
			local e = pool[i]
			if not e.slot and e.rec.key == exclude then return e.item end
		end
	end
	return nil
end

local function scoreOf(e) return e and e.score or 0 end

-- The best main hand and off hand that are two different items: main, off (either may be nil).
local function bestPair(ctx, wornOnly, gone)
	local best, bestMain, bestOff = nil, nil, nil
	for i = 1, 2 do
		local m = nth(ctx, "MAINHAND", i, nil, wornOnly, gone)
		for j = 1, 2 do
			local o = nth(ctx, "OFFHAND", j, nil, wornOnly, gone)
			if not (m and o and m.item == o.item) and (m or o) then
				local sum = scoreOf(m) + scoreOf(o)
				if best == nil or sum > best then best, bestMain, bestOff = sum, m, o end
			end
		end
	end
	return bestMain, bestOff
end

-- ---------------------------------------------------------------------------------------------
-- The verdict
-- ---------------------------------------------------------------------------------------------
function Compare.Evaluate(rec, ctx, opts, out)
	out = out or {}
	local Score = ns.Score
	local exclude, wornOnly = opts and opts.exclude, opts and opts.wornOnly

	local group = GROUP_OF[rec.equipLoc]
	out.group = (group == "TWOHAND") and "MAINHAND" or group
	out.twoHand = group == "TWOHAND"
	out.offHand = group == "OFFHAND"
	out.slot = group and Compare.SLOT_OF[group] or nil
	out.score, out.base, out.gain, out.pct, out.far, out.empty, out.replaces = 0, 0, 0, nil, false, false, nil

	local usable, reason, atLevel = false, "armor", rec.minLevel or 0
	if group then usable, reason, atLevel = Score.Usable(rec, ctx, ctx) end
	out.usable, out.reason, out.atLevel = usable, reason, atLevel
	if not group then return out end

	local score = Score.Value(rec.stats, ctx.weights)
	local base, replaces

	if PAIR[group] then
		local first = nth(ctx, group, 1, exclude, wornOnly)
		local second = nth(ctx, group, 2, exclude, wornOnly)
		replaces = second
		if rec.unique then
			-- Only one may be worn: a copy among the best two is the one it would replace.
			if first and first.rec.id == rec.id then
				replaces = first
			elseif second and second.rec.id == rec.id then
				replaces = second
			end
		end
		base = scoreOf(replaces)
	elseif WEAPONS[group] then
		local gone = excludedItem(ctx, exclude)
		local two = nth(ctx, "TWOHAND", 1, nil, wornOnly, gone)
		local pairMain, pairOff = bestPair(ctx, wornOnly, gone)
		local pair = scoreOf(pairMain) + scoreOf(pairOff)
		local set = math.max(scoreOf(two), pair)
		local usingTwo = two ~= nil and scoreOf(two) >= pair
		-- base is what the candidate must beat ON ITS OWN, so that gain = (new set) - (old set):
		--   two-hander:  new set = candidate               -> base = W
		--   main hand:   new set = candidate + best off    -> base = W - best off
		--   off hand:    new set = best main + candidate   -> base = W - best main
		-- (The partner is the best owned item for the other hand: the candidate is a new item,
		-- so any owned one may stand beside it.)
		if group == "TWOHAND" then
			base = set
			replaces = usingTwo and two or pairMain
		else
			local asMain, asOff
			if group == "MAINHAND" then
				asMain = set - scoreOf(nth(ctx, "OFFHAND", 1, nil, wornOnly, gone))
			end
			local off = score
			if group == "OFFHAND" or (rec.equipLoc == ONE_HAND and ctx.dual) then
				if group == "MAINHAND" then off = offScore(rec, ctx.weights, score) end
				asOff = set - scoreOf(nth(ctx, "MAINHAND", 1, nil, wornOnly, gone))
			end
			-- A dual wielder's one-hander: the hand it gains more in (the main hand on a tie).
			if asMain and asOff and (off - asOff) > (score - asMain) then asMain = nil end
			if asMain then
				base = asMain
				replaces = usingTwo and two or pairMain
			else
				score, base = off, asOff
				replaces = usingTwo and two or pairOff
				out.group, out.slot, out.offHand = "OFFHAND", Compare.SLOT_OF.OFFHAND, true
			end
		end
	else
		replaces = nth(ctx, group, 1, exclude, wornOnly)
		base = scoreOf(replaces)
	end

	out.score, out.base, out.replaces = score, base, replaces and replaces.rec or nil
	out.gain = score - base
	out.empty = replaces == nil
	local floor = (ctx.typical or 0) / 2
	local over = math.max(base, floor)
	if over > 0 then
		out.pct = out.gain / over * 100
		out.far = out.pct > Compare.FAR
	end
	return out
end
