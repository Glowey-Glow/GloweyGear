-- Glowey's Gear: from a list of things for sale to the best buy per slot.
--
--   Rank.Job(ctx, opts)            -> job           ctx from Compare.Context; opts for the live view
--   job:Add(link, price, classID, subclassID, equipLoc, minLevel, checkedAt)
--                                                   one thing for sale, price in copper (buyout).
--                                                   The four facts are optional: with them the
--                                                   item is weighed BEFORE any game call.
--                                                   checkedAt: when a search confirmed the price.
--   Rank.Set(job, opts, view)     -> set | nil      a main hand and an off hand, both for sale,
--                                                   that together beat what the hands hold now
--                                                   by more than the two slots' picks add up to
--                                                   (see WEAPON SETS below)
--   job:Reprice(key, copper, at)  -> "row" | "known" | nil
--                                                   a search says what the item costs now (0:
--                                                   none left). The score does not depend on
--                                                   the price, so nothing is scored again: the
--                                                   row is moved within its slot (Live:Regroup).
--   job:Step(count)                -> idle          scores up to `count` of what is queued
--   job:Run()                                       scores everything queued now (tests, small lists)
--   job:Pump(max, now)             -> asked         asks the game to load up to `max` parked items
--   job:Arrived(itemID, ok)        -> moved         an item's data came (or will not): its parked
--                                                   rows go back in the queue, or are given up
--   job:Expire(now, ms)            -> given up      parked rows asked for longer than `ms` ago
--   job:Done()                     -> nothing queued and nothing parked
--   job:Left()                     -> queued, not looked at yet
--   job.rows                                        every usable upgrade found so far
--   job.seen, job.nParked, job.gaveUp, job.filtered = { class, level, notgear }, job.later
--   job.live                                        Rank.Live: the best per slot, kept as rows come
--   Rank.Arrange(rows, opts)       -> view
--        opts = { mode = "perGold" | "biggest", maxPrice = copper (0 or nil: no limit),
--                 minPct = number, level = number, alternatives = 10 }
--        view = { groups = { [group] = { row, row, ... } }, listed = n,
--                 over = { [group] = row } }   the biggest upgrade that only the max price hides
--   Rank.Live(opts)                -> live          live:Offer(row), live:View(rows), live.changed
--   Rank.Value(gain, price, level) -> gain per gold
--   Rank.Pocket(level)             -> copper
--
-- A row: { key, link, name, quality, price, group, twoHand, offHand, score, base, gain, pct, far,
--          empty, replaces (record or nil), value, checkedAt (when a search confirmed the price),
--          gone (a search found none left: the row is in no view) }
--
-- WHAT IS RANKED is the gain in score points (and gain per gold), never the percent: the percent
-- is a reading aid with a floor and a cap (Compare.lua, THE PERCENT), and an item replacing a
-- piece that is worth little to the spec must not jump the list for that. The percent is used
-- for one thing here, the "smallest gain to show" filter, where its floor is what makes the
-- filter mean something for slots that hold a near-worthless item.
--
-- HOW A BIG HOUSE IS KEPT CHEAP. A real Auction House has held 232,540 rows and 16,159 distinct
-- pieces of gear (the owner's, 2026-11-20). For one character most of that is gear it cannot
-- wear or is too low in level for. So the work is cut in this order, cheapest first:
--   1. At Add, from facts saved with the list (item class, subclass, equip location, required
--      level): what the class can never wear, cannot wear yet, or (with the option) is lighter
--      than its best armor is dropped with NO game call at all. Counted in job.filtered.
--   2. In Step, an item whose data the game has not got is PARKED under its item ID, not asked
--      for by a call that makes the game load it on the spot. Pump asks for parked items a few
--      a frame; Arrived puts one item's rows back when that item's own event comes. So a flood
--      of item events costs one table lookup each, and nothing is ever retried wholesale.
--   3. A parked row that gets no answer is given up after a set time, and counted. A job
--      therefore always ends: Done() is "nothing queued and nothing parked".
--   4. A record is read for a candidate and dropped again unless the item is an upgrade: only
--      upgrades (a few hundred to a few thousand) are kept in memory.
--   5. The best per slot is kept as rows arrive (Rank.Live: one short sorted list per slot), so
--      showing progress does not sort everything found so far. Rank.Arrange, the full and exact
--      arrangement, runs once at the end and when a control changes.

local _, ns = ...

local Rank = {}
ns.Rank = Rank

-- ---------------------------------------------------------------------------------------------
-- Improvement per gold
-- ---------------------------------------------------------------------------------------------
-- value = gain / (price in gold), with the price never counted below "pocket change".
--
-- Without the floor, an item listed for one copper with a hair's gain would beat every real
-- upgrade (its gain per gold would be astronomical). Pocket change is the amount under which a
-- price makes no difference to a character of that level: the price is raised to it before
-- dividing, so among very cheap items the bigger gain wins, and above it gold counts in full.
--
-- pocket(level) = 5 copper x level x level, at least 1 silver:
--   level 10: 5 silver, level 30: 45 silver, level 60: 1 gold 80 silver.
-- Our own round figure for "not worth thinking about"; it grows with the square of the level
-- because income in this game does roughly that. One line to tune after play.
function Rank.Pocket(level)
	level = tonumber(level) or 1
	return math.max(100, 5 * level * level)
end

function Rank.Value(gain, price, level)
	local counted = math.max(price or 0, Rank.Pocket(level))
	return gain / (counted / 10000)
end

-- ---------------------------------------------------------------------------------------------
-- Orders
-- ---------------------------------------------------------------------------------------------
-- Total (no two rows ever compare equal), so a list never reshuffles between two looks at the
-- same data:
--   "perGold": most improvement per gold; then the bigger gain; then the lower price; then key.
--   "biggest": the bigger gain; then the lower price; then key.
local function perGold(a, b)
	if a.value ~= b.value then return a.value > b.value end
	if a.gain ~= b.gain then return a.gain > b.gain end
	if a.price ~= b.price then return a.price < b.price end
	return a.key < b.key
end

local function biggest(a, b)
	if a.gain ~= b.gain then return a.gain > b.gain end
	if a.price ~= b.price then return a.price < b.price end
	return a.key < b.key
end

-- Where a row stands under the options: "list", "over" (only the max price hides it) or nil.
-- The smallest gain to show is a percent of what is worn; an empty slot, and a gain with
-- nothing to measure it against, always pass (anything beats nothing).
local function place(row, maxPrice, minPct)
	if row.gone then return nil end
	if not (row.gain > 0 and (row.empty or row.pct == nil or row.pct >= minPct)) then return nil end
	if maxPrice > 0 and row.price > maxPrice then return "over" end
	return "list"
end

-- ---------------------------------------------------------------------------------------------
-- Arrange: filter, order, group (the full, exact arrangement)
-- ---------------------------------------------------------------------------------------------
function Rank.Arrange(rows, opts)
	opts = opts or {}
	local maxPrice = tonumber(opts.maxPrice) or 0
	local minPct = tonumber(opts.minPct) or 0
	local keep = tonumber(opts.alternatives) or 10
	local order = opts.mode == "biggest" and biggest or perGold
	local view = { groups = {}, over = {}, listed = 0 }

	for i = 1, #rows do
		local row = rows[i]
		local where = place(row, maxPrice, minPct)
		if where == "over" then
			local o = view.over[row.group]
			if not o or biggest(row, o) then view.over[row.group] = row end
		elseif where then
			row.value = Rank.Value(row.gain, row.price, opts.level)
			local list = view.groups[row.group]
			if not list then
				list = {}
				view.groups[row.group] = list
			end
			list[#list + 1] = row
		end
	end

	for _, list in pairs(view.groups) do
		table.sort(list, order)
		-- The best pick and up to `keep` alternatives.
		for i = #list, keep + 2, -1 do list[i] = nil end
		view.listed = view.listed + #list
	end
	return view
end

-- ---------------------------------------------------------------------------------------------
-- Live: the best per slot, kept as rows come
-- ---------------------------------------------------------------------------------------------
-- The same answer as Rank.Arrange over every row offered so far, without sorting them all: each
-- slot keeps its best `alternatives + 1` rows in order, and a new row is put in its place (or
-- found to be below the last one kept) in at most that many steps. `changed` is set when what
-- would be SHOWN changed, so the window repaints only then. A row whose price drops after it
-- was offered could change places; that is rare (the same item listed again, cheaper), so it
-- only marks the live view `stale` and the next View() arranges everything once.
local Live = {}
Live.__index = Live

function Rank.Live(opts)
	opts = opts or {}
	return setmetatable({
		maxPrice = tonumber(opts.maxPrice) or 0, minPct = tonumber(opts.minPct) or 0,
		keep = (tonumber(opts.alternatives) or 10) + 1, level = opts.level, mode = opts.mode,
		order = opts.mode == "biggest" and biggest or perGold,
		groups = {}, over = {}, changed = false, stale = false,
	}, Live)
end

function Live:Offer(row)
	local where = place(row, self.maxPrice, self.minPct)
	if not where then return end
	if where == "over" then
		local o = self.over[row.group]
		if not o or biggest(row, o) then
			self.over[row.group] = row
			self.changed = true
		end
		return
	end
	row.value = Rank.Value(row.gain, row.price, self.level)
	local list = self.groups[row.group]
	if not list then
		list = {}
		self.groups[row.group] = list
	end
	local n, order = #list, self.order
	if n >= self.keep and not order(row, list[n]) then return end   -- below everything kept
	local at = n + 1
	while at > 1 and order(row, list[at - 1]) do
		list[at] = list[at - 1]
		at = at - 1
	end
	list[at] = row
	if n + 1 > self.keep then list[n + 1] = nil end
	self.changed = true
end

-- One slot made again from every row of that slot: for a row whose price changed or that is
-- no longer for sale. It may have been anywhere in the slot's short list, or not in it, and
-- its going may let another row in, so the slot is offered all its rows afresh (a pass over
-- the upgrades, a few thousand at most, comparing only that slot's). Other slots are untouched.
function Live:Regroup(group, rows)
	self.groups[group], self.over[group] = nil, nil
	for i = 1, #rows do
		if rows[i].group == group then self:Offer(rows[i]) end
	end
	self.changed = true
end

-- The same, put off until the view is next asked for: a search result can correct twenty
-- rolls of one item at once, and twenty passes over every row in one frame cost 4 ms in
-- play. Touch only notes the slot; View makes every noted slot again in ONE pass.
function Live:Touch(group)
	self.dirty = self.dirty or {}
	self.dirty[group] = true
	self.changed = true
end

-- The view, in Rank.Arrange's shape. `rows` (every row so far) is only used when the live view
-- went stale.
function Live:View(rows)
	if self.stale and rows then
		self.stale, self.dirty = false, nil
		local view = Rank.Arrange(rows, { mode = self.mode, maxPrice = self.maxPrice, minPct = self.minPct,
			level = self.level, alternatives = self.keep - 1 })
		-- (Kept, so the next View is this arrangement and not the one from before.)
		self.groups, self.over = view.groups, view.over
		return view
	end
	local dirty = self.dirty
	if dirty and rows then
		self.dirty = nil
		for group in pairs(dirty) do self.groups[group], self.over[group] = nil, nil end
		for i = 1, #rows do
			if dirty[rows[i].group] then self:Offer(rows[i]) end
		end
	end
	local listed = 0
	for _, list in pairs(self.groups) do listed = listed + #list end
	return { groups = self.groups, over = self.over, listed = listed }
end

-- ---------------------------------------------------------------------------------------------
-- WEAPON SETS: a main hand and an off hand bought together
-- ---------------------------------------------------------------------------------------------
-- A row of the list is one item beside what is already owned. What that cannot say: two items
-- for sale that are an upgrade only (or mostly) TOGETHER, such as a one-hander and a shield
-- for someone holding a two-hander. So the job remembers, for each hand, a short list of the
-- weapons for sale the character can wield there (upgrade alone or not): the HAND_KEEP best
-- by score and the HAND_KEEP best by score per gold. Rank.Set tries every main hand with every
-- off hand of those lists (at most 4 x HAND_KEEP x HAND_KEEP pairs, never the thousands a
-- house holds) and returns the best pair under the options:
--     gain  = Compare.PairScore(main, off) - Compare.SetValue(ctx)      (hit cap counted over both)
--     price = the two prices added; each must be within the max price (it is a price per item)
--     order = by gain per gold of the pair (Most per Gold) or by gain (Biggest Gain)
-- Never a pair the character cannot hold: only items Score.Usable passed are remembered; a
-- one-hander is an off hand only for a dual wielder (with the off-hand weights); a two-hander
-- is in no pair; one unique-equipped item is never both hands; the same listing is never both
-- hands (one copy is known to be for sale).
-- It is returned only when it gains more than the list's Main Hand pick and Off Hand pick add
-- up to. Two purchases that simply add up are already told by those two rows; the pair gets
-- a row of its own when it says something they cannot (coming off a two-hander, mostly).
-- Limit: the short lists are filled as the items are scored, at the prices of that moment.
local HAND_KEEP = 8
Rank.HAND_KEEP = HAND_KEEP

local function handBetter(a, b)
	if a.score ~= b.score then return a.score > b.score end
	return a.key < b.key
end
local function handThrift(a, b)
	if a.thrift ~= b.thrift then return a.thrift > b.thrift end
	return a.key < b.key
end

-- Puts `e` in a list kept in `order`, HAND_KEEP long.
-- Returns whether it went in, and the entry it pushed out (or nil).
local function handInto(list, e, order)
	local n = #list
	if n >= HAND_KEEP and not order(e, list[n]) then return false end
	local at = n + 1
	while at > 1 and order(e, list[at - 1]) do
		list[at] = list[at - 1]
		at = at - 1
	end
	list[at] = e
	local out
	if n + 1 > HAND_KEEP then
		out = list[n + 1]
		list[n + 1] = nil
	end
	return true, out
end

-- The same, with hands.byKey kept to the entries that are in a list: an entry counts the
-- lists it is in (`n`) and leaves byKey when the last one drops it. (A house's every usable
-- weapon was kept there before: 600 entries for 300 one-handers.)
local function handKeep(hands, list, e, order)
	local went, out = handInto(list, e, order)
	if went then
		e.n = (rawget(e, "n") or 0) + 1
		hands.byKey[e.bk] = e
	end
	if out then
		out.n = out.n - 1
		if out.n <= 0 then hands.byKey[out.bk] = nil end
	end
end

function Rank.Set(job, opts, view)
	local Compare = ns.Compare
	local hands, ctx = job.hands, job.ctx
	if not hands or not ctx then return nil end
	opts = opts or {}
	local maxPrice = tonumber(opts.maxPrice) or 0
	local minPct = tonumber(opts.minPct) or 0
	local byGain = opts.mode == "biggest"
	local now = Compare.SetValue(ctx)
	local best, bestMeasure
	local tried = {}
	for a = 1, 2 do
		local mains = a == 1 and hands.main or hands.mainThrift
		for b = 1, 2 do
			local offs = b == 1 and hands.off or hands.offThrift
			for i = 1, #mains do
				local m = mains[i]
				if not m.gone and (maxPrice <= 0 or m.price <= maxPrice) then
					for j = 1, #offs do
						local o = offs[j]
						local id = m.key .. "+" .. o.key
						if not tried[id] and not o.gone and o.key ~= m.key and (maxPrice <= 0 or o.price <= maxPrice) then
							tried[id] = true
							local pair = Compare.PairScore(ctx, m.rec, m.main, o.rec, o.off)
							local gain = pair and (pair - now) or 0
							if gain > 0 then
								local price = m.price + o.price
								local measure = byGain and gain or Rank.Value(gain, price, opts.level)
								if not best or measure > bestMeasure
									or (measure == bestMeasure and (price < best.price or (price == best.price and id < best.id))) then
									best = { id = id, main = m, off = o, gain = gain, price = price, score = pair, base = now }
									bestMeasure = measure
								end
							end
						end
					end
				end
			end
		end
	end
	if not best then return nil end
	local over = math.max(now, (ctx.typical or 0) / 2)
	if over > 0 then
		best.pct = best.gain / over * 100
		best.far = best.pct > Compare.FAR
		if best.pct < minPct then return nil end
	end
	best.empty = now <= 0
	best.value = Rank.Value(best.gain, best.price, opts.level)
	-- Said only when it tells more than the list's own two rows do.
	local groups = view and view.groups or {}
	local apart, twoHandPick = 0, false
	for _, group in ipairs({ "MAINHAND", "OFFHAND" }) do
		local pick = groups[group] and groups[group][1]
		-- (A two-hander as the Main Hand pick leaves no hand for the Off Hand pick: the two
		-- cannot be held together, so the pair has to beat each of them, not their sum.)
		if pick and (pick.twoHand or twoHandPick) then
			apart = math.max(apart, pick.gain)
			twoHandPick = true
		elseif pick then
			apart = apart + pick.gain
		end
	end
	if best.gain <= apart + 1e-6 then return nil end
	return best
end

-- ---------------------------------------------------------------------------------------------
-- The job: score what is for sale
-- ---------------------------------------------------------------------------------------------
local Job = {}
Job.__index = Job

local TRIES = 3   -- times an item the game says it has is read before its row is given up

function Rank.Job(ctx, opts)
	return setmetatable({
		ctx = ctx,
		links = {}, prices = {}, n = 0, at = 0,       -- the queue, as two flat lists
		rows = {}, byKey = {}, cheapest = {},         -- upgrades; key -> row; key -> lowest price seen
		seen = 0,
		parked = {}, nParked = 0,                     -- itemID -> { link, price, link, price, ... }
		toAsk = {}, askAt = 1, askTail = 0, askedAt = {}, nAsked = 0,   -- item IDs to ask for; itemID -> when asked
		tries = {}, asks = {}, gaveUp = 0, later = 0, reads = 0, checked = {}, gone = 0,
		hands = { main = {}, mainThrift = {}, off = {}, offThrift = {}, byKey = {} },
		filtered = { class = 0, level = 0, notgear = 0 },
		live = Rank.Live(opts),
		scratch = {}, facts = {},
	}, Job)
end

-- Weighed from the saved facts alone: no game call. Returns true when the item is worth a look.
local function worth(self, classID, subclassID, equipLoc, minLevel)
	if not ns.Stats.GEAR[equipLoc] then
		self.filtered.notgear = self.filtered.notgear + 1
		return false
	end
	local f = self.facts
	f.classID, f.subclassID, f.equipLoc, f.minLevel = classID, subclassID, equipLoc, minLevel or 0
	local usable, reason = ns.Score.Usable(f, self.ctx, self.ctx)
	if usable then return true end
	if reason == "level" then
		self.filtered.level = self.filtered.level + 1
	else
		self.filtered.class = self.filtered.class + 1
	end
	return false
end

function Job:Add(link, price, classID, subclassID, equipLoc, minLevel, checkedAt)
	if type(link) ~= "string" or type(price) ~= "number" or price <= 0 then return end
	if equipLoc ~= nil and not worth(self, classID, subclassID, equipLoc, minLevel) then return end
	local n = self.n + 1
	self.links[n], self.prices[n], self.n = link, price, n
	if checkedAt then self.checked[link] = checkedAt end
end

function Job:Left() return self.n - self.at end
function Job:Done() return self.at >= self.n and self.nParked == 0 end
-- Whether Pump has something it could ask for now.
function Job:CanAsk(most) return self.askAt <= self.askTail and self.nAsked < (most or 200) end

local function park(self, itemID, link, price)
	local entry = self.parked[itemID]
	if not entry then
		entry = {}
		self.parked[itemID] = entry
		if not self.askedAt[itemID] then
			self.askTail = self.askTail + 1
			self.toAsk[self.askTail] = itemID
		end
	end
	entry[#entry + 1] = link
	entry[#entry + 1] = price
	self.nParked = self.nParked + 1
end

local function one(self, link, price)
	local Stats, Compare, G = ns.Stats, ns.Compare, ns.Game
	local key = Stats.Key(link)
	if not key then return end
	-- The same item listed many times: only the cheapest listing matters. A row already made
	-- just takes the lower price; an item already found to be no upgrade is not scored again.
	local known = self.cheapest[key]
	if known then
		local row = self.byKey[key]
		-- (A price a search confirmed is newer than any listing of the list: it stands.)
		if price < known and not (row and row.checkedAt) then
			self.cheapest[key] = price
			local off = self.hands.byKey[key .. "#off"]
			local hand = self.hands.byKey[key] or (off and getmetatable(off).__index) or nil
			if hand and not hand.checkedAt then hand.price = price end
			if row then
				row.price, row.link = price, link
				self.live.stale = true
			end
		end
		return
	end
	local itemID = Stats.ItemID(link)
	-- Not in the game's cache: parked, to be asked for at a measured pace (Pump). Never read
	-- with the calls that would make the game fetch it on the spot.
	if itemID and G.ItemCached(link) == false then
		-- (Asked for twice with no answer: this row is given up, so a job always ends.)
		if (self.asks[itemID] or 0) >= 2 and not self.parked[itemID] then
			self.gaveUp = self.gaveUp + 1
			return
		end
		return park(self, itemID, link, price)
	end
	self.reads = self.reads + 1
	local rec, why = Stats.Read(link, key)
	if not rec then
		if why == "pending" and itemID then
			-- (The game has the item but not this answer yet, or cannot say what it has: tried
			-- again when the item's event comes or the wait runs out, a few times at most.)
			local tried = (self.tries[key] or 0) + 1
			self.tries[key] = tried
			if tried < TRIES then return park(self, itemID, link, price) end
			self.gaveUp = self.gaveUp + 1
		end
		return
	end
	self.cheapest[key] = price
	local v = Compare.Evaluate(rec, self.ctx, nil, self.scratch)
	if not v.usable then
		if v.reason == "level" then self.later = self.later + 1 end
		return
	end
	-- A weapon the character can wield: remembered for its hand, upgrade alone or not (Rank.Set).
	local asMain, asOff = Compare.HandScores(rec, self.ctx)
	if asMain or asOff then
		local hands = self.hands
		local pocket = Rank.Pocket(self.ctx.level)
		-- (Of the record only what a pair needs is kept: the record itself is not held.)
		-- (classID: an off-hand WEAPON means dual wielding, which changes the hit cap.)
		local e = { key = key, bk = key, n = 0, link = link, name = rec.name, quality = rec.quality, price = price,
			main = asMain, off = asOff, checkedAt = self.checked[link],
			rec = { id = rec.id, unique = rec.unique, classID = rec.classID,
				stats = { HIT = rec.stats.HIT, SPELL_HIT = rec.stats.SPELL_HIT } } }
		local gold = math.max(price, pocket) / 10000
		if asMain and asMain > 0 then
			e.score, e.thrift = asMain, asMain / gold
			handKeep(hands, hands.main, e, handBetter)
			handKeep(hands, hands.mainThrift, e, handThrift)
		end
		if asOff and asOff > 0 then
			-- (A one-hander is in both hands' lists: its own entry for the off hand.)
			local o = asMain and setmetatable({ score = asOff, thrift = asOff / gold, bk = key .. "#off", n = 0 }, { __index = e }) or e
			if o == e then e.score, e.thrift = asOff, asOff / gold end
			handKeep(hands, hands.off, o, handBetter)
			handKeep(hands, hands.offThrift, o, handThrift)
		end
	end
	-- Never listed: what is no better than what is owned. (A gain that is not a number, from
	-- weights gone wrong, is no upgrade either.)
	if v.gain ~= v.gain or v.gain <= 0 then return end
	Stats.Keep(rec)   -- (only an upgrade's record stays in memory: the window shows it)
	local row = {
		key = key, link = link, name = rec.name, quality = rec.quality, price = price,
		group = v.group, twoHand = v.twoHand, offHand = v.offHand, score = v.score, base = v.base,
		gain = v.gain, pct = v.pct, far = v.far, empty = v.empty, replaces = v.replaces,
		checkedAt = self.checked[link],
	}
	self.byKey[key] = row
	self.rows[#self.rows + 1] = row
	self.live:Offer(row)
end

-- A search says what an item costs now: `copper` is the lowest buyout among other players'
-- auctions, 0 when none is left. "row": an upgrade's row was changed (and its slot arranged
-- again); "known": the item was looked at before and is no upgrade at any price, or is still
-- in the queue (its price there is replaced); nil: the job has never seen the key (the caller
-- may Add it).
function Job:Reprice(key, copper, at)
	-- (A weapon remembered for a pair: its price and whether it is still for sale.)
	local off = self.hands.byKey[key .. "#off"]
	-- (The off-hand entry of a one-hander reads price and `gone` through its main entry.)
	local hand = self.hands.byKey[key] or (off and getmetatable(off).__index) or nil
	if hand then
		if copper > 0 then hand.price, hand.gone = copper, nil else hand.gone = true end
		hand.checkedAt = at
		self.live.changed = true
	end
	local row = self.byKey[key]
	if row then
		if copper > 0 then
			if row.gone then self.gone = self.gone - 1 end
			row.price, row.gone = copper, nil
		elseif not row.gone then
			row.gone = true
			self.gone = self.gone + 1
		end
		row.checkedAt = at
		self.cheapest[key] = copper > 0 and copper or self.cheapest[key]
		self.live:Touch(row.group)
		return "row"
	end
	if self.cheapest[key] then
		if copper > 0 then self.cheapest[key] = copper end
		return "known"
	end
	return nil
end

function Job:Step(count)
	local last = math.min(self.n, self.at + (count or self.n))
	for i = self.at + 1, last do
		self.seen = self.seen + 1
		local link, price = self.links[i], self.prices[i]
		self.links[i], self.prices[i] = nil, nil   -- (looked at: the queue does not keep it)
		one(self, link, price)
	end
	self.at = last
	return self.at >= self.n
end

function Job:Run() return self:Step(self.n) end

-- Asks the game to load parked items, up to `max` now and never more than `most` out at once.
function Job:Pump(max, now, most)
	local asked = 0
	most = most or 200
	while asked < (max or 20) and self.askAt <= self.askTail and self.nAsked < most do
		local itemID = self.toAsk[self.askAt]
		self.toAsk[self.askAt] = nil
		self.askAt = self.askAt + 1
		if self.parked[itemID] and not self.askedAt[itemID] then
			self.askedAt[itemID] = now or 0
			self.asks[itemID] = (self.asks[itemID] or 0) + 1
			self.nAsked = self.nAsked + 1
			ns.Game.RequestItem(itemID)
			asked = asked + 1
		end
	end
	return asked
end

local function release(self, itemID, back)
	local entry = self.parked[itemID]
	if not entry then return 0 end
	self.parked[itemID] = nil
	if self.askedAt[itemID] then
		self.askedAt[itemID] = nil
		self.nAsked = self.nAsked - 1
	end
	local rows = #entry / 2
	self.nParked = self.nParked - rows
	if back then
		for i = 1, #entry, 2 do
			local n = self.n + 1
			self.links[n], self.prices[n], self.n = entry[i], entry[i + 1], n
		end
	else
		self.gaveUp = self.gaveUp + rows
	end
	return rows
end

-- An item's data came (ok ~= false) or the game said none is coming (ok == false). One table
-- lookup when the item is nothing of ours.
function Job:Arrived(itemID, ok)
	if not self.parked[itemID] then return 0 end
	return release(self, itemID, ok ~= false)
end

-- Parked items asked for more than `ms` ago get one more look when the game might simply not
-- have sent an event (their rows go back in the queue, which counts a try); rows out of tries
-- are given up there. Items never asked for yet are left alone.
function Job:Expire(now, ms)
	local n = 0
	for itemID, at in pairs(self.askedAt) do
		if now - at >= ms then n = n + release(self, itemID, true) end
	end
	return n
end

-- Gives up everything still parked (the wait is over for good).
function Job:GiveUp()
	local n = 0
	for itemID in pairs(self.parked) do n = n + release(self, itemID, false) end
	self.toAsk, self.askAt, self.askTail = {}, 1, 0
	return n
end
