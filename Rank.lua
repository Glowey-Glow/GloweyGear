-- Glowey's Gear: from a list of things for sale to the best buy per slot.
--
--   Rank.Job(ctx, opts)            -> job           ctx from Compare.Context; opts for the live view
--   job:Add(link, price, classID, subclassID, equipLoc, minLevel, checkedAt)
--                                                   one thing for sale, price in copper (buyout).
--                                                   The four facts are optional: with them the
--                                                   item is weighed BEFORE any game call.
--                                                   checkedAt: when a search confirmed the price.
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

-- The view, in Rank.Arrange's shape. `rows` (every row so far) is only used when the live view
-- went stale.
function Live:View(rows)
	if self.stale and rows then
		self.stale = false
		return Rank.Arrange(rows, { mode = self.mode, maxPrice = self.maxPrice, minPct = self.minPct,
			level = self.level, alternatives = self.keep - 1 })
	end
	local listed = 0
	for _, list in pairs(self.groups) do listed = listed + #list end
	return { groups = self.groups, over = self.over, listed = listed }
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
		self.live:Regroup(row.group, self.rows)
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
