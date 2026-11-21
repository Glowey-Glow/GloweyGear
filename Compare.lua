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
--     A unique-equipped candidate is never set beside an owned copy of itself: the partner
--     is then the best owned item for the other hand that is another item.
--     Pairs across the Auction House (a main hand and an off hand that are only an upgrade
--     when bought together) are Rank.Set's work; Compare.SetValue and Compare.PairScore give
--     it the numbers. The ranged slot is a one-slot place of its own.
--
-- THE HIT CAP (stage 2). Hit beyond what is needed never to miss is worth nothing, so it is
-- not scored. The figures are the client's own, from the text of its Hit Chance tooltip
-- (CR_DEFAULT_HIT_CAP_TOOLTIP and CR_ROGUE_HIT_CAP_TOOLTIP in the GlobalStrings database, file
-- 1394440, read with Tools\client_facts.py's reader): against raid bosses 8% melee and ranged,
-- 17% spells, 27% dual wielding; against targets of the character's own level 5%, 4% and 24%.
-- The second reference is the client's Lua: FX Blizzard_UIPanels_Game\Camelot\
-- PaperDollFrameStats.lua:460-461 has 5.0 and 4.0 at the same level and 17.0 for spells three
-- levels up (its 9.0 for melee three levels up is not what the tooltip shows, and is used
-- nowhere in that file: the tooltip's 8% stands).
--   * Which cap: at level 60 the raid boss figures (the level 60 weights are made for raids);
--     below 60 the same-level figures. The leveling brackets of the weights already make a
--     point of hit worth less; the cap is about HOW MUCH hit counts, so the two do not clash.
--   * Dual wielding (an off-hand WEAPON is worn): the dual wield figure, as the tooltip gives
--     it. In practice that is no cap.
--   * What the character has: the hit on every worn item (from their links) plus who.hitMod =
--     { melee, spell }, the part that does not come from ratings (talents, mostly), which
--     Core.lua reads out of a fight and keeps (see there). No call is made in a fight.
--   * An item's hit counts only as far as the cap has room once the item it would replace is
--     taken off: counted = min(its hit, cap - (hit had - hit of what leaves)), never under 0.
--     What is owned is valued the same way (each piece as if it were the last one put on), so a
--     gain is always (new piece in the set) - (old piece in the set).
--   * Limits: a buff that gives hit at the moment Core.lua reads the game counts as the
--     character's own until the next read; a carried item is valued against the worn item of
--     its slot.
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

-- Hit needed never to miss: { melee, spell, dual } against raid bosses and against targets of
-- the character's own level (see THE HIT CAP in the header for where the figures are from).
Compare.HIT_CAP = { boss = { HIT = 8, SPELL_HIT = 17, DUAL = 27 }, level = { HIT = 5, SPELL_HIT = 4, DUAL = 24 } }
Compare.TOP_LEVEL = 60
local HITS = { "HIT", "SPELL_HIT" }

-- The caps for a character: { HIT = , SPELL_HIT = }.
function Compare.HitCap(level, dualWielding)
	local row = (level or 1) >= Compare.TOP_LEVEL and Compare.HIT_CAP.boss or Compare.HIT_CAP.level
	return { HIT = dualWielding and row.DUAL or row.HIT, SPELL_HIT = row.SPELL_HIT }
end

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

-- A piece's score with the hit that would go over the cap taken out. `leaves` and `leaves2`
-- are the records of what comes off for it (either may be nil), `extra` hit of a partner
-- that goes on with it ({ HIT = , SPELL_HIT = }, or nil).
local function capped(ctx, rec, score, leaves, leaves2, extra)
	local hit = ctx.hit
	if not hit then return score end
	local stats, w = rec.stats, ctx.weights
	for i = 1, 2 do
		local k = HITS[i]
		local h, weight = stats[k] or 0, w[k] or 0
		if h > 0 and weight > 0 then
			local others = hit.have[k] - (leaves and leaves.stats[k] or 0) - (leaves2 and leaves2.stats[k] or 0)
				+ (extra and extra[k] or 0)
			local room = hit.cap[k] - others
			if room < 0 then room = 0 end
			if h > room then score = score - (h - room) * weight end
		end
	end
	return score
end

-- What comes off when something goes in a group's place and the piece it replaces is not a
-- worn one: the worn record(s) of that place.
local function wornOf(ctx, group)
	local w = ctx.wornRec
	if group == "TWOHAND" then return w[16], w[17] end
	if PAIR[group] then return ctx.wornLow[group] end
	return w[Compare.SLOT_OF[group]]
end
Compare.Capped, Compare.WornOf = capped, wornOf

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
		bestArmor = opts and opts.bestArmor or false, pools = {}, pending = 0, typical = 0,
		wornRec = {}, wornLow = {} }
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
		if slot then ctx.wornRec[slot] = rec end
		items = items + 1
		-- (`item` tells two entries of one physical item apart from two copies of it.)
		into(group, { rec = rec, score = score, slot = slot, item = items })
		if rec.equipLoc == ONE_HAND and ctx.dual then
			-- The same weapon as a possible off hand.
			into("OFFHAND", { rec = rec, score = offScore(rec, ctx.weights, score), slot = slot, item = items })
		end
	end
	for slot = 1, 18 do
		if worn and worn[slot] then own(worn[slot], slot) end
	end
	for i = 1, carried and #carried or 0 do own(carried[i], nil) end

	-- The hit cap: only for a spec whose weights value hit at all.
	local w = ctx.weights
	if (w.HIT or 0) > 0 or (w.SPELL_HIT or 0) > 0 then
		local mod = who.hitMod
		local have = { HIT = mod and tonumber(mod.melee) or 0, SPELL_HIT = mod and tonumber(mod.spell) or 0 }
		for slot = 1, 18 do
			local rec = ctx.wornRec[slot]
			if rec then
				have.HIT = have.HIT + (rec.stats.HIT or 0)
				have.SPELL_HIT = have.SPELL_HIT + (rec.stats.SPELL_HIT or 0)
			end
		end
		local off = ctx.wornRec[17]
		local dualWielding = off ~= nil and off.classID == 2
		ctx.hit = { have = have, cap = Compare.HitCap(ctx.level, dualWielding), dual = dualWielding,
			mod = { HIT = mod and tonumber(mod.melee) or 0, SPELL_HIT = mod and tonumber(mod.spell) or 0 } }
		-- (Of two rings or trinkets worn, the weaker is the one a new one replaces.)
		for group in pairs(PAIR) do
			local low
			for _, e in ipairs(pools[group] or {}) do
				if e.slot and (not low or e.score < low.score) then low = e end
			end
			ctx.wornLow[group] = low and low.rec or nil
		end
		-- Every owned piece valued as the last one put on.
		for group, pool in pairs(pools) do
			for _, e in ipairs(pool) do
				if e.slot then
					e.score = capped(ctx, e.rec, e.score, e.rec, group == "TWOHAND" and ctx.wornRec[17] or nil)
				else
					e.score = capped(ctx, e.rec, e.score, wornOf(ctx, group))
				end
			end
		end
	end
	for _, pool in pairs(pools) do
		table.sort(pool, byScore)
		for _, e in ipairs(pool) do
			-- (A one-hander is in two pools: counted once, as the main hand.)
			local twice = e.rec.equipLoc == ONE_HAND
				and ((pool == pools.OFFHAND and e.slot == 16) or (pool == pools.MAINHAND and e.slot == 17))
			if e.slot and e.score > 0 and not twice then
				wornSum, wornCount = wornSum + e.score, wornCount + 1
			end
		end
	end
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
local function nth(ctx, group, n, exclude, wornOnly, notItem, notID)
	local pool = ctx.pools[group]
	if not pool then return nil end
	local skippedItem
	for i = 1, #pool do
		local e = pool[i]
		local take = true
		if wornOnly and not e.slot then
			take = false
		elseif notID and e.rec.id == notID then
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

-- What the hands are worth today: the larger of the best two-hander and the best pair. Also
-- the pair's two entries and the two-hander's (any may be nil), and whether the two-hander is
-- the set in use.
function Compare.SetValue(ctx)
	local two = nth(ctx, "TWOHAND", 1)
	local main, off = bestPair(ctx)
	local pair = scoreOf(main) + scoreOf(off)
	local usingTwo = two ~= nil and scoreOf(two) >= pair
	return math.max(scoreOf(two), pair), main, off, two, usingTwo
end

-- What a main hand and an off hand that are BOTH new are worth together, with the hit cap
-- counted over the two of them. mainScore and offScore are their scores for those hands
-- (Compare.HandScores); nil when the two cannot be held together (one unique-equipped item
-- twice).
function Compare.PairScore(ctx, mainRec, mainScore, offRec, offScore)
	if mainRec.id == offRec.id and (mainRec.unique or offRec.unique) then return nil end
	if not ctx.hit then return mainScore + offScore end
	local w = ctx.wornRec
	-- (The main hand goes on first; the off hand's hit counts in what room is left.)
	local a = capped(ctx, mainRec, mainScore, w[16], w[17])
	local b = capped(ctx, offRec, offScore, w[16], w[17], mainRec.stats)
	return a + b
end

-- A usable weapon's raw scores for the hands it can go in: main, off, two (each nil when it
-- cannot go there). A one-hander can be an off hand only for a dual wielder.
function Compare.HandScores(rec, ctx)
	local group = GROUP_OF[rec.equipLoc]
	if not WEAPONS[group] then return nil end
	local score = ns.Score.Value(rec.stats, ctx.weights)
	if group == "TWOHAND" then return nil, nil, score end
	if group == "OFFHAND" then return nil, score, nil end
	if rec.equipLoc == ONE_HAND and ctx.dual then return score, offScore(rec, ctx.weights, score), nil end
	return score, nil, nil
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
		score = capped(ctx, rec, score, replaces and replaces.slot and replaces.rec or wornOf(ctx, group))
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
		-- (A unique-equipped candidate is never set beside an owned copy of itself.)
		local notID = rec.unique and rec.id or nil
		local worn = ctx.wornRec
		if group == "TWOHAND" then
			base = set
			replaces = usingTwo and two or pairMain
			score = capped(ctx, rec, score, worn[16], worn[17])
		else
			local asMain, asOff
			local raw = score
			if group == "MAINHAND" then
				asMain = set - scoreOf(nth(ctx, "OFFHAND", 1, nil, wornOnly, gone, notID))
				score = capped(ctx, rec, raw, worn[16])
			end
			local off = raw
			if group == "OFFHAND" or (rec.equipLoc == ONE_HAND and ctx.dual) then
				if group == "MAINHAND" then off = offScore(rec, ctx.weights, raw) end
				asOff = set - scoreOf(nth(ctx, "MAINHAND", 1, nil, wornOnly, gone, notID))
				off = capped(ctx, rec, off, worn[17])
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
		score = capped(ctx, rec, score, replaces and replaces.slot and replaces.rec or wornOf(ctx, group))
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
