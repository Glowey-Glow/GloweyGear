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
--                 replaces (a record or nil), twoHand, offHand,
--                 needLine, needRank, needName (reason "profession": the skill line it asks
--                 for, the rank, the profession's name or nil) }
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
-- levels up (its 9.0 for melee three levels up is in a table that function never reads: the
-- tooltip's 8% stands).
--   * Which cap: at level 60 the raid boss figures (the level 60 weights are made for raids);
--     below 60 the same-level figures. The leveling brackets of the weights already make a
--     point of hit worth less; the cap is about HOW MUCH hit counts, so the two do not clash.
--   * THREE KINDS OF ATTACK, each with its own cap and its own total. The weights have two
--     hit stats: HIT (melee and ranged) and SPELL_HIT. For a hunter HIT is ranged hit (the
--     ranged share of who.hitMod, 8% / 5%, and never a dual wield figure: ranged attacks do
--     not dual wield); for every other class it is melee hit. Which of them matter is the
--     weights' business: a stat with no weight is not looked at.
--   * DUAL WIELDING (an off-hand WEAPON is held, melee only). The tooltip's 27% (24%) is for
--     NORMAL swings; special attacks never miss from 8% (5%) on. The client names the two
--     kinds itself (STAT_HIT_NORMAL_ATTACKS "Normal Attacks", STAT_HIT_SPECIAL_ATTACKS
--     "Special Attacks", same database), and its rogue tooltip lists "8.00% Melee/Ranged"
--     beside "27.00% Dual Wielding": those are the two references for the rule. So up to 8%
--     hit counts in full, and from there to 27% it counts for Compare.DUAL_SHARE of its
--     weight: the share of a dual wielder's damage that normal swings do. That share is OUR
--     OWN ESTIMATE, one half, for every class: the weights' upstream presets hold a single
--     hit weight and no value for hit past the cap (Tools\data\upstream.json: only
--     StatHitRating), and no table of damage shares ships. Past 27% hit counts for nothing.
--   * What the character has: the hit on every worn item (from their links) plus who.hitMod =
--     { melee, spell }, the part that does not come from ratings (talents, mostly), which
--     Core.lua reads out of a fight and keeps (see there). No call is made in a fight.
--   * THE OUTFIT IS VALUED AS A WHOLE. A verdict compares two outfits: the one the character
--     can make today (the best owned piece or pieces in the place in question) and the one
--     with the candidate in. Each is worth the plain scores of the pieces with their hit
--     taken out, plus what the outfit's TOTAL hit is worth under the caps that outfit has
--     (a two-hander in place of two weapons ends dual wielding, and the other way round). So
--     one item, a pair and a two-hander are all measured the same way, and an item identical
--     to the one it replaces gains exactly nothing.
--     out.score and out.base are the candidate's and the replaced piece's worth in that
--     outfit (each measured from the outfit with the place left empty), so gain = score - base.
--   * Limits: a buff that gives hit at the moment Core.lua reads the game counts as the
--     character's own until the next read; hit from an enchant on a worn item (a scope) and
--     from set bonuses is not on a link and is not counted; talents that lower one spell
--     school's resist chance are likely not in the spell figure the game gives.
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

-- Hit needed never to miss, against raid bosses and against targets of the character's own
-- level: HIT for melee special attacks and for ranged attacks, DUAL for a dual wielder's
-- normal swings, SPELL_HIT for spells (see THE HIT CAP in the header for where they are from).
Compare.HIT_CAP = { boss = { HIT = 8, SPELL_HIT = 17, DUAL = 27 }, level = { HIT = 5, SPELL_HIT = 4, DUAL = 24 } }
Compare.TOP_LEVEL = 60
-- What a percent of hit between HIT and DUAL is worth to a dual wielder, as a share of the
-- weight: our own estimate of the part of the damage that normal swings do (see the header).
Compare.DUAL_SHARE = 0.5

-- The caps for a character's level: { HIT = , SPELL_HIT = , DUAL = }.
function Compare.HitCap(level)
	local row = (level or 1) >= Compare.TOP_LEVEL and Compare.HIT_CAP.boss or Compare.HIT_CAP.level
	return { HIT = row.HIT, SPELL_HIT = row.SPELL_HIT, DUAL = row.DUAL }
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

-- What an outfit's total hit is worth: `hit` percent of melee or ranged hit and `spell`
-- percent of spell hit, `dual` when it dual wields (melee only).
local function hitValue(ctx, hit, spell, dual)
	local cap, w = ctx.hit.cap, ctx.weights
	local v = 0
	local wh, ws = w.HIT or 0, w.SPELL_HIT or 0
	if wh > 0 and hit > 0 then
		v = (hit < cap.HIT and hit or cap.HIT) * wh
		if dual and hit > cap.HIT then
			v = v + ((hit < cap.DUAL and hit or cap.DUAL) - cap.HIT) * wh * Compare.DUAL_SHARE
		end
	end
	if ws > 0 and spell > 0 then v = v + (spell < cap.SPELL_HIT and spell or cap.SPELL_HIT) * ws end
	return v
end
Compare.HitValue = hitValue

-- Whether holding `rec` in the off hand makes the character dual wield, for melee hit.
local function isDual(ctx, rec)
	local h = ctx.hit
	return h ~= nil and rec ~= nil and rec.classID == 2 and not h.ranged
end

-- What the pieces r1 and r2 (plain scores s1 and s2; any may be nil) are worth in the outfit
-- once the worn pieces l1 and l2 (either may be nil) are off and they are on: their scores
-- without their hit, plus what the whole outfit's hit is then worth. `dual`: the outfit dual
-- wields. With no pieces it is what the rest of the outfit's hit is worth with the place empty.
local function outfit(ctx, l1, l2, dual, r1, s1, r2, s2)
	local sum = (r1 and s1 or 0) + (r2 and s2 or 0)
	local h = ctx.hit
	if not h then return sum end
	local w = ctx.weights
	local wh, ws = w.HIT or 0, w.SPELL_HIT or 0
	local hit, spell = h.have.HIT, h.have.SPELL_HIT
	if l1 then hit, spell = hit - (l1.stats.HIT or 0), spell - (l1.stats.SPELL_HIT or 0) end
	if l2 and l2 ~= l1 then hit, spell = hit - (l2.stats.HIT or 0), spell - (l2.stats.SPELL_HIT or 0) end
	if r1 then
		local a, b = r1.stats.HIT or 0, r1.stats.SPELL_HIT or 0
		hit, spell, sum = hit + a, spell + b, sum - a * wh - b * ws
	end
	if r2 then
		local a, b = r2.stats.HIT or 0, r2.stats.SPELL_HIT or 0
		hit, spell, sum = hit + a, spell + b, sum - a * wh - b * ws
	end
	return sum + hitValue(ctx, hit, spell, dual)
end

-- The worn record(s) of a group's place.
local function wornOf(ctx, group)
	local w = ctx.wornRec
	if WEAPONS[group] then return w[16], w[17] end
	if group == "FINGER" then return w[11], w[12] end
	if group == "TRINKET" then return w[13], w[14] end
	return w[Compare.SLOT_OF[group]]
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
		bestArmor = opts and opts.bestArmor or false, pools = {}, pending = 0, typical = 0,
		wornRec = {} }
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
		into(group, { rec = rec, score = score, raw = score, slot = slot, item = items })
		if rec.equipLoc == ONE_HAND and ctx.dual then
			-- The same weapon as a possible off hand.
			local asOff = offScore(rec, ctx.weights, score)
			into("OFFHAND", { rec = rec, score = asOff, raw = asOff, slot = slot, item = items })
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
		-- (A hunter's HIT is ranged hit: Core.lua gives the ranged share, and no dual wield figure applies.)
		ctx.hit = { have = have, cap = Compare.HitCap(ctx.level), ranged = ctx.class == "HUNTER",
			mod = { HIT = mod and tonumber(mod.melee) or 0, SPELL_HIT = mod and tonumber(mod.spell) or 0 } }
		local dualNow = isDual(ctx, ctx.wornRec[17])
		ctx.hit.dual = dualNow
		-- Every owned piece gets the worth it has in the outfit worn now (a worn piece: what the
		-- outfit loses without it; a carried one: what it adds in the place of the worn piece),
		-- which is what the pools are ordered by. Verdicts value whole outfits (Evaluate).
		for group, pool in pairs(pools) do
			for _, e in ipairs(pool) do
				if e.slot then
					local without = dualNow and e.slot ~= 17
					e.score = outfit(ctx, e.rec, nil, dualNow, e.rec, e.raw) - outfit(ctx, e.rec, nil, without)
				else
					local l1, l2 = wornOf(ctx, group)
					if PAIR[group] then l2 = nil end
					if group == "MAINHAND" then l2 = nil elseif group == "OFFHAND" then l1 = l2 l2 = nil end
					local dual = dualNow
					if group == "OFFHAND" then dual = isDual(ctx, e.rec) elseif group == "TWOHAND" then dual = false end
					e.score = outfit(ctx, l1, l2, dual, e.rec, e.raw) - outfit(ctx, l1, l2, dual and group ~= "OFFHAND")
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


-- What a main hand and an off hand (entries; either may be nil) are worth held together.
local function pairWorth(ctx, m, o)
	local w = ctx.wornRec
	return outfit(ctx, w[16], w[17], isDual(ctx, o and o.rec), m and m.rec, m and m.raw, o and o.rec, o and o.raw)
end

-- The best main hand and off hand that are two different items: main, off (either may be nil),
-- and what they are worth together.
local function bestPair(ctx, wornOnly, gone)
	local best, bestMain, bestOff = nil, nil, nil
	for i = 1, 2 do
		local m = nth(ctx, "MAINHAND", i, nil, wornOnly, gone)
		for j = 1, 2 do
			local o = nth(ctx, "OFFHAND", j, nil, wornOnly, gone)
			if not (m and o and m.item == o.item) and (m or o) then
				local sum = pairWorth(ctx, m, o)
				if best == nil or sum > best then best, bestMain, bestOff = sum, m, o end
			end
		end
	end
	return bestMain, bestOff, best
end

-- The hands: what the character can make of them today. Returns the set's worth in the outfit
-- (the larger of the best two-hander and the best pair), the pair's entries, the two-hander's
-- entry, whether the two-hander is the set in use, and the worth of the outfit with both hands
-- empty (what is left of the hit's worth), which every weapon verdict measures from.
local function handsNow(ctx, wornOnly, gone)
	local w = ctx.wornRec
	local empty = outfit(ctx, w[16], w[17], false)
	local two = nth(ctx, "TWOHAND", 1, nil, wornOnly, gone)
	local main, off, pair = bestPair(ctx, wornOnly, gone)
	local twoWorth = two and outfit(ctx, w[16], w[17], false, two.rec, two.raw) or nil
	local usingTwo = twoWorth ~= nil and (pair == nil or twoWorth >= pair)
	local set = usingTwo and twoWorth or pair or empty
	return set, main, off, two, usingTwo, empty
end

-- What the hands are worth today (measured from both hands empty), and the entries: the
-- pair's main and off, the two-hander's, and whether the two-hander is the set in use.
function Compare.SetValue(ctx)
	local set, main, off, two, usingTwo, empty = handsNow(ctx)
	return set - empty, main, off, two, usingTwo
end

-- What a main hand and an off hand that are BOTH new are worth together, measured the same
-- way (from both hands empty, the hit of the whole outfit counted under the caps the pair
-- makes: an off-hand weapon means dual wielding). mainValue and offValue are their plain
-- scores for those hands (Compare.HandScores); nil when the two cannot be held together (one
-- unique-equipped item twice).
function Compare.PairScore(ctx, mainRec, mainValue, offRec, offValue)
	if mainRec.id == offRec.id and (mainRec.unique or offRec.unique) then return nil end
	local w = ctx.wornRec
	return outfit(ctx, w[16], w[17], isDual(ctx, offRec), mainRec, mainValue, offRec, offValue)
		- outfit(ctx, w[16], w[17], false)
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
	-- (A profession the item asks for: which, how much, and its name when the game gives one.)
	out.needLine, out.needRank, out.needName = nil, nil, nil
	if reason == "profession" then
		local line, rank = Score.NeedsProfession(rec.id)
		out.needLine, out.needRank = line, rank
		out.needName = line and ns.Game.SkillName and ns.Game.SkillName(line) or nil
	end
	if not group then return out end

	local raw = Score.Value(rec.stats, ctx.weights)
	local score, base, replaces
	-- (Every branch values two outfits, with and without the candidate, both measured from
	-- the outfit with the place left empty: see THE HIT CAP in the header.)
	local dualNow = ctx.hit ~= nil and ctx.hit.dual or false

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
		local kept = (replaces ~= nil and replaces == first) and second or first
		local l1, l2 = wornOf(ctx, group)
		local empty = outfit(ctx, l1, l2, dualNow, kept and kept.rec, kept and kept.raw)
		score = outfit(ctx, l1, l2, dualNow, kept and kept.rec, kept and kept.raw, rec, raw) - empty
		base = replaces and (outfit(ctx, l1, l2, dualNow, kept and kept.rec, kept and kept.raw, replaces.rec, replaces.raw) - empty) or 0
	elseif WEAPONS[group] then
		local gone = excludedItem(ctx, exclude)
		local set, pairMain, pairOff, two, usingTwo = handsNow(ctx, wornOnly, gone)
		local w16, w17 = ctx.wornRec[16], ctx.wornRec[17]
		-- (A unique-equipped candidate is never set beside an owned copy of itself.)
		local notID = rec.unique and rec.id or nil
		if group == "TWOHAND" then
			local empty = outfit(ctx, w16, w17, false)
			score, base = outfit(ctx, w16, w17, false, rec, raw) - empty, set - empty
			replaces = usingTwo and two or pairMain
		else
			-- The candidate beside the best owned item for the other hand (a new item: any owned
			-- one may stand beside it), in the hand it can go in; a dual wielder's one-hander in
			-- both, and the hand it gains more in stands (the main hand on a tie).
			local mainScore, mainBase, offValue, offBase
			if group == "MAINHAND" then
				local p = nth(ctx, "OFFHAND", 1, nil, wornOnly, gone, notID)
				local dual = isDual(ctx, p and p.rec)
				local empty = outfit(ctx, w16, w17, dual, nil, nil, p and p.rec, p and p.raw)
				mainScore = outfit(ctx, w16, w17, dual, rec, raw, p and p.rec, p and p.raw) - empty
				mainBase = set - empty
			end
			if group == "OFFHAND" or (rec.equipLoc == ONE_HAND and ctx.dual) then
				local asOff = group == "MAINHAND" and offScore(rec, ctx.weights, raw) or raw
				local p = nth(ctx, "MAINHAND", 1, nil, wornOnly, gone, notID)
				local empty = outfit(ctx, w16, w17, false, p and p.rec, p and p.raw)
				offValue = outfit(ctx, w16, w17, isDual(ctx, rec), p and p.rec, p and p.raw, rec, asOff) - empty
				offBase = set - empty
			end
			if mainScore and offValue and (offValue - offBase) > (mainScore - mainBase) then mainScore = nil end
			if mainScore then
				score, base = mainScore, mainBase
				replaces = usingTwo and two or pairMain
			else
				score, base = offValue, offBase
				replaces = usingTwo and two or pairOff
				out.group, out.slot, out.offHand = "OFFHAND", Compare.SLOT_OF.OFFHAND, true
			end
		end
	else
		replaces = nth(ctx, group, 1, exclude, wornOnly)
		local l1 = wornOf(ctx, group)
		local empty = outfit(ctx, l1, nil, dualNow)
		score = outfit(ctx, l1, nil, dualNow, rec, raw) - empty
		base = replaces and (outfit(ctx, l1, nil, dualNow, replaces.rec, replaces.raw) - empty) or 0
	end

	out.score, out.base, out.replaces = score, base, replaces and replaces.rec or nil
	out.gain = score - base
	-- (Two outfits that are the same must differ by exactly nothing: the sums above can leave
	-- a remainder in the fifteenth digit, and "+0%" must not be listed as an upgrade.)
	if out.gain > -1e-9 and out.gain < 1e-9 then out.gain = 0 end
	out.empty = replaces == nil
	local floor = (ctx.typical or 0) / 2
	local over = math.max(base, floor)
	if over > 0 then
		out.pct = out.gain / over * 100
		out.far = out.pct > Compare.FAR
	end
	return out
end
