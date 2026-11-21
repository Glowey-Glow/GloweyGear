-- Glowey's Gear: the Upgrades for Sale window.
--
--   Window.Open() / Close() / Toggle()     ns.OpenWindow = Window.Toggle (/gear)
--   Window.Refresh(force)                  scores the saved list again (a new Rank.Job) when what
--                                          is owned or the list changed; else only reads again
--                                          what the game had not loaded
--   Window.Rearrange()                     Rank.Arrange only: the price limit, the smallest gain
--                                          or the ranking mode changed
--   Window.frame                           the window (made at login, hidden)
--
-- The logic the tests cover is pure and at the top of the file:
--   Window.Model(view, selected)       -> the rows to draw, in order
--   Window.EmptyState(facts)           -> key, sentence | nil when there are rows to show
--   Window.Mode(host, dock, folded, free) -> "docked" | "tab" | "free" | "hidden"
--   Window.DockSide(host, screenW, w)  -> "right" | "left" | nil
--   Window.StepPrice(gold, dir)        -> the next max price up or down
--   Window.SearchText(row)             -> what is searched for in the Auction House
--   Window.AgeText(seconds), Window.GainText(row), Window.Over(view)
--
-- WHAT IT IS. A compact list (340 wide, as tall as its rows up to a limit, then it scrolls):
-- one row per slot with the best pick for sale, the alternatives under the row that was
-- clicked, and a footer with the two controls that matter while shopping (Max Price, Best
-- Pick: the same settings as the options page). While Daylight UI's Auction House window is
-- up and Dock to the Auction House is on, it sits flush against that window's right edge (the
-- left one when the right has no room), tops level, and follows it; a small tab at that corner
-- folds it away. Anywhere else /gear opens it as a window of its own that is dragged by
-- its body and remembers its place.
--
-- A CLICK on a row (A on a controller) searches that item in Daylight UI's Buy page. Nothing
-- is ever bought, bid on or posted from here.
--
-- DAYLIGHT UI'S INTERNALS touched, each behind one function that answers nil or false when
-- anything is not as read (the fall-back in brackets):
--   Host()          _G.DaylightUIAuctionHouse, the Auction House window's global name
--                   (DaylightUI_AuctionHouse\Window.lua:33, made at :487 by Win.New, a plain
--                   Frame with no secure template: DaylightUI\Windows\Frame.lua:288; no secure
--                   frame anywhere in that module). [a window of its own]
--   SearchInDui()   the module's BuyPage.Submit(text, anywhere) (BuyPage.lua:560-567 in 2.1.2:
--                   what Enter in its search box runs; anywhere = true searches every category,
--                   as Daylight UI's own search for a linked item does, Window.lua:371; a 2.1.1
--                   Submit(text) ignores it) after Window.ShowTab("buy") (Window.lua:225; the shown tab
--                   is .tab on its frame, :31, :228). [a chat line saying what to type]
--   Money()         DaylightUI.MoneyString (DaylightUI\Core.lua:97). [the game's GetMoneyString]
--   SetSetting()    DaylightUI:Set(scope, path, value) (DaylightUI\Core.lua:889), as the owner's
--                   other plugins write their own settings. [the control does nothing]
--   ns.Pad          Guide.lua's wrapper round Daylight UI's controller kit. [mouse only]
-- Everything else is DaylightUI.API (Skin, Text, Button, Close, Colors, Accent, Media).
--
-- luacheck: read globals CreateFrame UIParent C_Timer C_Item GameTooltip ITEM_QUALITY_COLORS
-- luacheck: read globals GetMoneyString geterrorhandler GetServerTime
-- luacheck: globals UISpecialFrames

local ADDON, ns = ...
if ns.off or not ns.ok then return end

local L, API = ns.L, ns.API
local Game, Rank, Compare = ns.Game, ns.Rank, ns.Compare

local Window = {}
ns.Window = Window

local WIDTH, EDGE = 340, 12
local INNER = WIDTH - 2 * EDGE
local MAX_LIST = 364          -- the list's height before it scrolls
local SLICE_MS = 3            -- our own time in one frame: feeding, asking, scoring (a tick's overhead and the
                              -- one item that runs past the mark stay inside 4 ms)
local REPAINT_MS = 1000       -- the list fills in at this pace while it is scored, when it changed
local PROGRESS_MS = 500       -- the "reading ... rows" line moves at this pace
local LOADS_A_FRAME = 20      -- item loads asked of the game in one frame, at most
local LOADS_OUT = 400         -- and never more than this many unanswered at once
local WAIT_MS = 6000          -- an item asked for and not answered for this long is asked once more, then given up
local IDLE_S = 0.25           -- how often a job with nothing queued looks at its parked items

-- =============================================================================================
-- Logic (pure: tested offline)
-- =============================================================================================

-- The rows to draw from Rank.Arrange's view: one "slot" row per group that has a pick, in
-- Compare.GROUPS order, and under the selected group its alternatives.
-- The game's own word for a hand (Marks.SlotName), for a pair's two rows.
local function HandName(group)
	local M = ns.Marks
	return type(M) == "table" and type(M.SlotName) == "function" and M.SlotName(group) or group
end

-- `set` (Rank.Set's answer, or nil): a main hand and an off hand that are the better buy
-- together. It gets one row of its own under the two hands, group "WEAPONS", which opens to
-- its two items; the hands' own rows stay as they are, so no item is listed twice by default.
function Window.Model(view, selected, set)
	local out = {}
	if type(view) ~= "table" or type(view.groups) ~= "table" then return out end
	for _, group in ipairs(Compare.GROUPS) do
		local list = view.groups[group]
		if list and list[1] then
			local open = selected == group and #list > 1
			out[#out + 1] = { kind = "slot", group = group, row = list[1], more = #list - 1, open = open }
			if open then
				for i = 2, #list do out[#out + 1] = { kind = "alt", group = group, row = list[i] } end
			end
		end
		if group == "OFFHAND" and type(set) == "table" then
			local open = selected == "WEAPONS"
			local m, o = set.main, set.off
			out[#out + 1] = { kind = "slot", group = "WEAPONS", more = 2, open = open, row = {
				isSet = true, name = L["Both Together"], link = m.link, price = set.price, gain = set.gain,
				pct = set.pct, far = set.far, empty = set.empty, main = m, off = o } }
			if open then
				out[#out + 1] = { kind = "alt", group = "WEAPONS", row = { key = m.key, link = m.link, name = m.name,
					quality = m.quality, price = m.price, checkedAt = m.checkedAt, label = HandName("MAINHAND") } }
				out[#out + 1] = { kind = "alt", group = "WEAPONS", row = { key = o.key, link = o.link, name = o.name,
					quality = o.quality, price = o.price, checkedAt = o.checkedAt, label = HandName("OFFHAND") } }
			end
		end
	end
	return out
end

-- The lowest price among the upgrades only the max price hides (view.over), or nil.
function Window.Over(view)
	local best
	for _, row in pairs(type(view) == "table" and view.over or {}) do
		if not best or row.price < best then best = row.price end
	end
	return best
end

function Window.AgeText(seconds)
	seconds = tonumber(seconds)
	if not seconds then return nil end
	if seconds < 60 then return L["List read just now."] end
	if seconds < 3600 then return L["List read %d min ago."]:format(math.floor(seconds / 60)) end
	if seconds < 48 * 3600 then return L["List read %d h ago."]:format(math.floor(seconds / 3600)) end
	return L["List read more than two days ago."]
end

-- A gain in percent as it is written: whole from 10 up, one decimal below (Marks.lua's, when it
-- is loaded, so the window and the tooltip row never disagree).
local function Percent(pct)
	local M = ns.Marks
	if type(M) == "table" and type(M.Percent) == "function" then return M.Percent(pct) end
	pct = tonumber(pct) or 0
	if pct >= 9.95 then return ("%d"):format(math.floor(pct + 0.5)) end
	return (("%.1f"):format(math.max(pct, 0.1)):gsub("%.0$", ""))
end

-- "Price checked 3 min ago.": for a row whose price a search confirmed since the list was read.
-- `at` and `now` are the server's time in seconds (now: for the tests).
function Window.CheckedText(at, now)
	at = tonumber(at)
	if not at then return nil end
	if not now then
		local ok, t = pcall(GetServerTime)
		now = ok and tonumber(t) or at
	end
	local ago = math.max(0, now - at)
	if ago < 60 then return L["Price checked just now."] end
	if ago < 3600 then return L["Price checked %d min ago."]:format(math.floor(ago / 60)) end
	return L["Price checked %d h ago."]:format(math.floor(ago / 3600))
end

-- A row's gain in a word or a figure: "+12%", "Far Better" (beyond what a percent can say),
-- "Better" (nothing worn to measure against) or "Empty Slot" (nothing is replaced, and only
-- then: a slot holding an item that scores nothing is not empty). The same rule as the tooltip
-- row and the bag mark; the percent itself is Compare.lua's (THE PERCENT).
function Window.GainText(row)
	if row.empty then return L["Empty Slot"] end
	if not row.pct then return L["Better"] end
	if row.far then return L["Far Better"] end
	return L["+%s%%"]:format(Percent(row.pct))
end

-- Whether a row's item has an effect the score leaves out (Stats.Uncounted): the row's gain
-- then carries a "*" and its tooltip says so in words.
-- Asking costs a tooltip's worth of work the first time for an item (then it is kept), so a
-- paint asks for a few new ones only (`budget`, a table { left = n }) and comes back for the
-- rest a moment later (budget.more is set).
function Window.Uncounted(row, budget)
	local rec = ns.Stats.Of(row.link)
	if not rec then return false end
	if rec.uncounted == nil and budget then
		if budget.left <= 0 then
			budget.more = true
			return false
		end
		budget.left = budget.left - 1
	end
	return ns.Stats.Uncounted(rec) > 0
end

-- What to say instead of rows, or nil when there are rows. facts:
--   enabled, who (bool), whoWhy, fight (nothing scored yet and a fight is on),
--   market ("none" | "reading" | "ready"), hasList, done, total, dui (Daylight UI's Auction House
--   is the one in use), scoring (bool), left, listed, over (copper | nil), money(copper) -> text
function Window.EmptyState(f)
	if f.enabled == false then return "off", L["Gear advice is switched off in the options."] end
	if not f.who then
		if f.whoWhy == "noweights" then
			return "noweights", L["No stat weights for your class yet, so there is no gear advice."]
		end
		return "notready", L["Your character isn't ready yet. Try again in a moment."]
	end
	if not f.hasList then
		if f.market == "reading" then
			if (f.total or 0) > 0 then
				return "reading", L["Reading the Auction House: %d of %d rows."]:format(f.done or 0, f.total)
			end
			return "asking", L["Waiting for the Auction House's list."]
		end
		if f.dui then
			return "nolist", L["No list of the Auction House yet. Run a Full scan there, and the upgrades show up here."]
		end
		return "nolistown", L["No list of the Auction House yet. Open the Auction House and press Read the Auction House."]
	end
	if (f.listed or 0) > 0 then return nil end
	if f.fight then return "fight", L["Gear isn't checked during a fight. The list fills in when it ends."] end
	if f.scoring then return "scoring", L["Scoring the items for sale: %d left."]:format(f.left or 0) end
	if f.over then
		local money = f.money or tostring
		return "over", L["No upgrades for sale under your max price. Raise it to %s to see one."]:format(money(f.over))
	end
	return "nothing", L["No upgrades for sale right now."]
end

-- Where the window is: beside the Auction House (shown or folded to its tab), on its own, or away.
function Window.Mode(host, dock, folded, free)
	if host and dock then return folded and "tab" or "docked" end
	return free and "free" or "hidden"
end

-- Which side of the host has room for a panel `width` wide: host = { left =, right = }, all in
-- the same units as screenW. Right first; left when the right has none; nil when neither.
function Window.DockSide(host, screenW, width)
	if type(host) ~= "table" or type(host.left) ~= "number" or type(host.right) ~= "number" then return nil end
	if host.right + width <= screenW + 0.5 then return "right" end
	if host.left - width >= -0.5 then return "left" end
	return nil
end

-- Max Price moves along a ladder (gold), every step one the options page's slider can also
-- show (multiples of 5); past the top is "no limit" (0).
local LADDER = { 5, 10, 15, 20, 25, 30, 40, 50, 75, 100, 150, 200, 300, 500, 750, 1000 }
function Window.StepPrice(gold, dir)
	gold = tonumber(gold) or 0
	if dir > 0 then
		if gold <= 0 then return 0 end
		for i = 1, #LADDER do
			if LADDER[i] > gold then return LADDER[i] end
		end
		return 0
	end
	if gold <= 0 then return LADDER[#LADDER] end
	for i = #LADDER, 1, -1 do
		if LADDER[i] < gold then return LADDER[i] end
	end
	return LADDER[1]
end

-- The words searched for: the item's whole name, its suffix included ("Jade Ring of the Bear"),
-- so the Buy page shows that roll and not every roll of the item. From the row's name (the
-- game's, for the row's own item string); from a full link's text when the name is missing.
function Window.SearchText(row)
	if type(row) ~= "table" then return nil end
	local name = row.name
	if type(name) ~= "string" or name == "" then
		name = type(row.link) == "string" and row.link:match("|h%[(.-)%]|h") or nil
	end
	if type(name) ~= "string" then return nil end
	name = name:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("^%s+", ""):gsub("%s+$", "")
	if name == "" then return nil end
	return name
end

-- =============================================================================================
-- Scoring: a Rank.Job stepped in slices, then Rank.Arrange
-- =============================================================================================
local S = {
	job = nil, sig = nil, list = nil,   -- the job, what it was built for (owned gear, saved list)
	view = nil, model = {}, selected = nil,
	running = false, stale = true, force = false,
	free = false, mode = "hidden",
}
Window.S = S

local Paint, Place   -- (below)

local SIG_GROUPS = { "TWOHAND" }
for _, group in ipairs(Compare.GROUPS) do SIG_GROUPS[#SIG_GROUPS + 1] = group end

-- What a job's answers depend on besides the list: who is scored for and every owned item that
-- counts. The same signature means the same answers, so only what was not loaded is read again.
local function Signature(ctx)
	local parts = { tostring(ctx.class), tostring(ctx.level), tostring(ctx.bestArmor), tostring(ctx.pending) }
	for _, group in ipairs(SIG_GROUPS) do
		local pool = ctx.pools[group]
		if pool then
			parts[#parts + 1] = group
			for i = 1, #pool do parts[#parts + 1] = pool[i].rec.key .. (pool[i].slot and "w" or "c") end
		end
	end
	return table.concat(parts, "|")
end

-- HOW THE LIST IS SCORED WITHOUT COSTING FRAMES (the first build did not manage that: with a
-- house of 16,159 gear items it scored every one, in batches whose length nobody measured,
-- re-sorted and repainted everything four times a second, and started over whenever item data
-- arrived for anything). The rules now:
--   * NOTHING RUNS WHILE THE WINDOW IS NOT SHOWN: closed, folded to its tab, or the interface
--     hidden. What changed meanwhile is remembered (S.stale) and done when it shows.
--   * NOTHING IS SCORED WHILE THE AUCTION HOUSE'S LIST IS BEING READ (Market.State() ==
--     "reading"): the list is not whole, and the reader has the frame's time. One job starts
--     when the read is saved.
--   * ONE TICK A FRAME, AND THE CLOCK IS LOOKED AT AFTER EVERY ITEM. A tick feeds saved
--     listings into the job (dropped at once when the character cannot use them: no game call),
--     asks the game for a few items it has not got, and scores queued items one at a time until
--     SLICE_MS is used. There is no batch size to get wrong: an item that turns out dear ends
--     the tick after that one item.
--   * ITEM DATA: the job parks what the game has not got and hears about it by item ID (the
--     two events below, registered only while something is parked). An event for anything else
--     is one table lookup. Nothing is retried wholesale.
--   * A JOB ENDS. An item asked for twice with no answer is given up and counted; the window
--     says how many could not be read.
--   * PAINTING: while a job runs, at most once a second and only when what is shown changed
--     (the job keeps the best per slot as it goes: Rank.Live). The full arrangement runs once
--     at the end and when a control changes. Dressing the window (API.Skin) only when its
--     height changed.
local items = CreateFrame("Frame")   -- item-data events, only while a job has items parked
local listening = false
local function Listen(on)
	if on == listening then return end
	listening = on
	for _, event in ipairs({ "GET_ITEM_INFO_RECEIVED", "ITEM_DATA_LOAD_RESULT" }) do
		if on then pcall(items.RegisterEvent, items, event) else pcall(items.UnregisterEvent, items, event) end
	end
end

-- Whether the window is on screen: the one test everything that costs time asks first.
function Window.IsShown()
	local f = Window.frame
	return f ~= nil and f:IsShown() == true
end
local function Shown() return Window.IsShown() end

-- The rows to draw, from the view in place: the list's own, and the weapon pair when there is one.
local function Remodel()
	local job = S.job
	S.set = (job and S.view) and Rank.Set(job, ns.RankOptions(job.ctx.level), S.view) or nil
	S.model = Window.Model(S.view, S.selected, S.set)
end

-- The exact arrangement of everything found, and a paint. Cheap enough for a control change
-- (it sorts only the upgrades, a few hundred to a few thousand rows), too dear for every tick.
function Window.Rearrange()
	local job = S.job
	if job then
		ns.Perf.Count("arrange")
		local opts = ns.RankOptions(job.ctx.level)
		S.view = Rank.Arrange(job.rows, opts)
		-- (A job still running goes on with a live view under the new options.)
		if S.running then
			local live = Rank.Live(opts)
			for i = 1, #job.rows do live:Offer(job.rows[i]) end
			live.changed = false
			job.live = live
		end
	else
		S.view = nil
	end
	Remodel()
	S.painted = Game.Clock()
	Paint()
end

local Step

local function Tick(delay)
	if S.ticking then return end
	S.ticking = true
	C_Timer.After(delay or 0, Step)
end

Step = function()
	S.ticking = false
	local job = S.job
	if not job or not S.running then return end
	-- Not shown: nothing runs. OnShow goes on with it.
	if not Shown() then return end
	-- The Auction House's list is being read: wait for it (MarketChanged starts a new job).
	if ns.Market.State() == "reading" then return end
	local t0 = Game.Clock()
	-- The job ended on the last tick: its list is shown now, on a frame of its own.
	if S.ending then
		S.ending, S.running = nil, false
		-- The best per slot was kept as the rows came, so the end needs no sort of everything
		-- found (thousands of rows for a well-geared house): the live view IS the arrangement,
		-- unless a price dropped on a row already placed (then it is arranged once, in full).
		if job.live.stale then
			Window.Rearrange()
		else
			job.live.changed = false
			S.view = job.live:View(job.rows)
			Remodel()
			S.painted = t0
			Paint()
		end
		-- (The list is whole: is there a better buy than the last time? Alert.lua.)
		if ns.Alert and ns.Market.Saved() then ns.Alert.Check(S.view) end
		return
	end
	-- The list fills in: only when what would be shown changed, not more than once a second,
	-- and on a tick of its own (a paint and a slice of scoring in one frame would be two
	-- budgets spent).
	if job.live.changed and t0 - (S.painted or 0) >= REPAINT_MS then
		job.live.changed = false
		S.view = job.live:View(job.rows)
		Remodel()
		S.painted = t0
		Paint()
		return Tick(0)
	end
	local function over() return Game.Clock() - t0 >= SLICE_MS end

	-- 1. Feed: saved listings into the job, a slice at a time.
	if S.feedAt then S.feedAt = ns.Market.Feed(job, S.feedAt, over) end
	-- 2. Ask the game for a few parked items, and hear about them.
	if job.nParked > 0 then
		Listen(true)
		job:Pump(LOADS_A_FRAME, t0, LOADS_OUT)
		if t0 - (S.expired or 0) >= 1000 then
			S.expired = t0
			job:Expire(t0, WAIT_MS)
		end
	end
	-- 3. Score, one item at a time, the clock looked at after each.
	local idle = job:Left() == 0
	while not idle and not over() do idle = job:Step(1) end
	ns.Perf.Time("scoring", Game.Clock() - t0)

	if not S.feedAt and job:Done() then
		Listen(false)
		S.ending = true
		return Tick(0)
	end
	-- Work queued: next frame. Only parked items left: a slow look is enough (their events
	-- wake the job at once).
	Tick((S.feedAt or job:Left() > 0 or job:CanAsk(LOADS_OUT)) and 0 or IDLE_S)
end

local function Run()
	S.running = true
	Tick(0)
end

items:SetScript("OnEvent", function(_, _, itemID, ok)
	local job = S.job
	if not job or job.nParked == 0 then return Listen(false) end
	if job:Arrived(itemID, ok) > 0 and S.running then Tick(0) end
end)

function Window.Refresh(force)
	if not Shown() then
		S.stale, S.force = true, S.force or force == true
		return
	end
	ns.Perf.Count("refresh")
	S.stale, S.force = false, false
	local who = ns.Who()
	if ns.Get("enabled") == false or not who then
		S.job, S.sig, S.list, S.running, S.feedAt = nil, nil, nil, false, nil
		Listen(false)
		return Window.Rearrange()
	end
	-- The list is being read: one job when it is saved, none now.
	if ns.Market.State() == "reading" then
		S.stale = true
		return Paint()
	end
	local ctx = ns.Context()
	if not ctx then
		-- (A fight: nothing is built now. What is there stays; done again when the fight ends.)
		S.stale = true
		return Paint()
	end
	local saved = ns.Market.Saved()
	local sig, list = Signature(ctx), saved and saved.items or nil
	-- The same character, the same owned gear, the same list: every answer stands.
	if not force and S.job and S.sig == sig and S.list == list then
		-- (A job that stood still while the window was away goes on.)
		if S.running then Tick(0) end
		return
	end
	ns.Perf.Count("job")
	S.job, S.sig, S.list = Rank.Job(ctx, ns.RankOptions(ctx.level)), sig, list
	S.view, S.model, S.ending = nil, {}, nil
	S.feedAt = list and 1 or nil
	if not list then
		S.running = false
		Listen(false)
		return Window.Rearrange()
	end
	-- (Reading what is owned was this frame's work. The first tick paints "Scoring ...", on a
	-- frame of its own; the ticks after it score.)
	S.painted = nil
	S.job.live.changed = true
	Run()
end

-- Something the answers depend on changed: done on the next frame when the window is up (not
-- inside whoever said so: a list being saved, a burst of bag events), else when it shows.
local dirtySoon = false
local function Dirty(force)
	S.stale, S.force = true, S.force or force == true
	if not Shown() or dirtySoon then return end
	dirtySoon = true
	C_Timer.After(0, function()
		dirtySoon = false
		if S.stale and Shown() then Window.Refresh(S.force) end
	end)
end
Window.Dirty = Dirty

-- What the job is doing, for /gear debug.
function Window.Debug()
	local out = {}
	local job = S.job
	if not job then
		out[1] = "window: no job" .. (S.stale and " (something changed while it was not shown: done when it shows)" or "")
		return out
	end
	local saved = ns.Market.Saved()
	out[1] = ("window: %s; job: %d of %d saved items fed, %d dropped unread (%d the class cannot wear, %d too high in level), %d looked at in %d passes of the queue, %d read from the game, %d upgrades (%d of them no longer for sale)"):format(
		Shown() and "shown" or "not shown", S.feedAt and (S.feedAt - 1) or (saved and #saved.items or 0), saved and #saved.items or 0,
		job.filtered.class + job.filtered.level + job.filtered.notgear, job.filtered.class, job.filtered.level, job.n, job.seen, job.reads,
		#job.rows, job.gone)
	out[2] = ("window: job %s; %d queued, %d waiting for item data (%d asked of the game now), %d given up; item records kept %d"):format(
		S.running and "running" or "done", job:Left(), job.nParked, job.nAsked, job.gaveUp, ns.Stats.Cached())
	return out
end

-- A price changed for one item (a search said so, or a row of the scan was read late). The
-- score does not depend on the price, so nothing is scored again: the job moves the row within
-- its slot, and the window paints once, on the next frame, however many prices came.
-- Corrections can come in a stream (Check Prices, the tail): the list is painted for them
-- once a second at most, like scoring progress (27 paints in a minute were seen in play, one
-- of 4.5 ms). The first of a quiet spell paints on the next frame.
local pricedSoon = false
local function Repriced()
	if pricedSoon or not Shown() then return end
	pricedSoon = true
	local since = (Game.Clock() - (S.pricedAt or -REPAINT_MS)) / 1000
	C_Timer.After(since >= REPAINT_MS / 1000 and 0 or (REPAINT_MS / 1000 - since), function()
		pricedSoon = false
		local job = S.job
		if not job or not Shown() then return end
		-- (While a job runs its own ticks paint; the live view is already right.)
		if S.running then
			job.live.changed = true
			return
		end
		job.live.changed = false
		S.view = job.live:View(job.rows)
		Remodel()
		S.painted = Game.Clock()
		S.pricedAt = S.painted
		ns.Perf.Count("reprice")
		Paint()
		if ns.Alert then ns.Alert.Check(S.view) end
	end)
end

-- facts (optional): { classID, subclassID, equipLoc, minLevel }, so an item the character
-- cannot use is dropped unread like any other of the list.
function Window.Priced(key, copper, at, facts)
	local job = S.job
	if not job then return end
	local what = job:Reprice(key, copper, at)
	if what == "row" then return Repriced() end
	if what == nil and copper > 0 then
		-- An item the job never saw (a new listing, or one read late): looked at like any other.
		local before = job.n
		if facts then
			job:Add("item:" .. key, copper, facts[1], facts[2], facts[3], facts[4], at)
		else
			job:Add("item:" .. key, copper, nil, nil, nil, nil, at)
		end
		if job.n == before then return end
		if Shown() then
			S.running = true
			Tick(0)
		else
			S.stale = true
		end
	end
end

ns.On("PriceChanged", function(key, copper, at) Window.Priced(key, copper, at) end)
ns.On("MarketAdded", function(key, copper, _, facts)
	local job = S.job
	if not job then return end
	-- (Scan data, as old as the list: it never replaces what a search said since.)
	if ns.Market.Fixed(key) ~= nil then return end
	local row = job.byKey[key]
	if row and (row.checkedAt or copper >= row.price) then return end
	Window.Priced(key, copper, nil, facts)
end)
ns.On("CheckProgress", function()
	if not Shown() then return end
	local running = ns.Check.State()
	-- (The line under the title while it runs; the button's word when it starts and ends.)
	if running and S.checking then return Window.PaintProgress() end
	S.checking = running
	Paint()
end)

ns.On("WhoChanged", function() Dirty(true) end)
ns.On("OwnedChanged", function() Dirty(false) end)
ns.On("MarketChanged", function() Dirty(false) end)
ns.On("MarketProgress", function(done)
	if not Shown() then return end
	-- Told every frame while a list is read, from inside the reader's own slice of the frame.
	-- So only the words move, twice a second: the line that says how far the reading is, set in
	-- place, with no layout and no rows. (A read that stopped without a list paints in full.)
	if done == nil then
		-- (No new list: what waited for the read is done now.)
		if S.stale then return Window.Dirty(S.force) end
		return Paint()
	end
	local now = Game.Clock()
	if now - (S.told or 0) < PROGRESS_MS then return end
	S.told = now
	Window.PaintProgress()
end)
ns.On("Setting", function(path)
	if path == "maxPrice" or path == "minGain" or path == "mode" then
		Window.Rearrange()
	elseif path == "dock" then
		Place()
	elseif path == "bestArmor" or path == "enabled" then
		Dirty(true)
	end
end)

-- =============================================================================================
-- Daylight UI (guarded adapters)
-- =============================================================================================
local function Visible(f)
	if type(f) ~= "table" or type(f.IsVisible) ~= "function" or not f:IsVisible() then return false end
	if type(f.GetEffectiveAlpha) == "function" and f:GetEffectiveAlpha() < 0.05 then return false end
	return f:GetLeft() ~= nil
end

-- Daylight UI's Auction House window while it is on screen, else nil.
local function Host()
	local f = _G.DaylightUIAuctionHouse
	local ok, visible = pcall(Visible, f)
	if ok and visible then return f end
	return nil
end

local function SearchInDui(name)
	local m = ns.Market.DuiAH()
	if not m or not Host() then return false end
	local page, win = m.BuyPage, m.Window
	if type(page) ~= "table" or type(page.Submit) ~= "function" then return false end
	-- (Submit writes into the Buy page's own search box: the window must have been built.)
	if type(win) ~= "table" or type(win.frame) ~= "table" then return false end
	-- (On Sell or My Auctions the search would run unseen: the Buy tab first.)
	if win.frame.tab ~= "buy" then
		if type(win.ShowTab) ~= "function" or not pcall(win.ShowTab, "buy") then return false end
	end
	-- (Submit answers false when it could not start, and has then said why on its own page.
	-- true: in every category, not only the one picked on the Buy page.)
	return (pcall(page.Submit, name, true))
end

local Money
ns.Money = function(copper) return Money(copper) end
Money = function(copper)
	local D = ns.DUI
	if type(D) == "table" and type(D.MoneyString) == "function" then
		local ok, text = pcall(D.MoneyString, copper)
		if ok and type(text) == "string" and text ~= "" then return text end
	end
	if type(GetMoneyString) == "function" then
		local ok, text = pcall(GetMoneyString, copper, true)
		if ok and type(text) == "string" then return text end
	end
	return ("%dg %ds %dc"):format(math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100)
end

local function SetSetting(path, value)
	local D = ns.DUI
	if type(D) ~= "table" or type(D.Set) ~= "function" then return false end
	return (pcall(D.Set, D, ADDON, path, value))
end

local function Pad() return type(ns.Pad) == "table" and ns.Pad or nil end

-- The search for a row's item. True when Daylight UI took it. With an Auction House open that
-- we could not hand it to (the game's own window, DaylightMogul's, or a Daylight UI that
-- changed), the player is told what to type; away from an Auction House a click only selects.
function Window.Search(row)
	local text = Window.SearchText(row)
	if not text then return false end
	if SearchInDui(text) then
		-- The Buy page lists by name; what the item costs now, roll by roll, comes from a search
		-- of the item itself, which is asked for too (Check.lua). Its answer corrects this row.
		local id = ns.Stats.ItemID(row.link)
		if ns.Check and id then ns.Check.One(id) end
		return true
	end
	if ns.Market.IsOpen() then
		ns.Print(L["Type %s in the Auction House's search box."]:format(text))
	end
	return false
end

-- =============================================================================================
-- Saved state: DaylightGearDB.window = { folded = bool, x =, y = } (per account)
-- =============================================================================================
local function Saved()
	local db = ns.DB()
	if type(db.window) ~= "table" then db.window = {} end
	return db.window
end

-- =============================================================================================
-- The frames
-- =============================================================================================
local function Colors()
	local ok, c = pcall(API.Colors)
	return ok and type(c) == "table" and c or {}
end

local function ink(fs, color)
	if color then fs:SetTextColor(color[1], color[2], color[3]) end
end

local function Icon(itemID)
	local get = C_Item and C_Item.GetItemIconByID   -- DOC ItemDocumentation.lua:611
	if not get or not itemID then return nil end
	local ok, file = pcall(get, itemID)
	return ok and file or nil
end

local function QualityColor(quality)
	local all = ITEM_QUALITY_COLORS   -- FX Blizzard_Colors\Mainline\ColorConstants.lua:15
	local c = type(all) == "table" and all[quality]
	if type(c) == "table" and type(c.r) == "number" then return c.r, c.g, c.b end
	return 1, 1, 1
end

local function tipSide()
	return S.side == "left" and "ANCHOR_LEFT" or "ANCHOR_RIGHT"
end

local function RowEnter(self)
	self.hover:Show()
	local e = self.entry
	if not e then return end
	GameTooltip:SetOwner(self, tipSide())
	-- (The game's own tooltip for the item's link: Daylight UI's card and the Gear Advice row
	-- come with it.)
	if e.row.isSet then
		-- The pair's own row: what it is, in words.
		GameTooltip:SetText(L["Both Together"], 1, 1, 1)
		GameTooltip:AddLine(L["Buying these two together is a bigger upgrade than either one alone."], 0.72, 0.70, 0.66, true)
		GameTooltip:AddDoubleLine(HandName("MAINHAND"), e.row.main.name or "", 0.72, 0.70, 0.66, QualityColor(e.row.main.quality))
		GameTooltip:AddDoubleLine(HandName("OFFHAND"), e.row.off.name or "", 0.72, 0.70, 0.66, QualityColor(e.row.off.quality))
		GameTooltip:Show()
		return
	end
	if not pcall(GameTooltip.SetHyperlink, GameTooltip, e.row.link) then return GameTooltip:Hide() end
	-- (A price a search confirmed since the scan says so, and how long ago.)
	local checked = Window.CheckedText(e.row.checkedAt)
	if checked then GameTooltip:AddLine(checked, 0.72, 0.70, 0.66, true) end
	-- (With the tooltip row switched off, the "*" still gets its words.)
	if ns.Get("tooltips") == false and Window.Uncounted(e.row) then
		GameTooltip:AddLine(L["Gear Advice does not count this item's special effect."], 0.72, 0.70, 0.66, true)
	end
	if Host() then
		local r, g, b = API.Accent()
		GameTooltip:AddLine(L["Click: search for it in the Auction House"], r, g, b, true)
	end
	GameTooltip:Show()
end

local function RowLeave(self)
	self.hover:Hide()
	GameTooltip:Hide()
end

local function RowClick(self)
	local e = self.entry
	if not e then return end
	if e.kind == "slot" then
		-- (The clicked slot opens its alternatives; a second click on it closes them.)
		S.selected = (S.selected ~= e.group or not e.open) and e.group or nil
		S.aim = e.group
		Remodel()
	end
	-- (The pair's own row only opens: its two items are the ones to search for.)
	if not e.row.isSet then Window.Search(e.row) end
	if e.kind == "slot" then Paint() end
end

local rows = {}
local function Row(i)
	local f = Window.frame
	local r = rows[i]
	if r then return r end
	r = CreateFrame("Button", nil, f.child)
	r.hover = r:CreateTexture(nil, "BACKGROUND")
	r.hover:SetAllPoints(r)
	r.hover:SetColorTexture(1, 1, 1, 0.06)
	r.hover:Hide()
	r.mark = r:CreateTexture(nil, "ARTWORK")
	r.mark:SetWidth(2)
	r.mark:SetPoint("TOPLEFT", r, "TOPLEFT", 0, -2)
	r.mark:SetPoint("BOTTOMLEFT", r, "BOTTOMLEFT", 0, 2)
	r.icon = r:CreateTexture(nil, "ARTWORK")
	r.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	r.name = API.Text(r, "body", "LEFT")
	r.name:SetWordWrap(true)
	r.name:SetNonSpaceWrap(true)
	r.slot = API.Text(r, "small", "LEFT")
	r.gain = API.Text(r, "body", "RIGHT")
	r.price = API.Text(r, "small", "RIGHT")
	r.chev = r:CreateTexture(nil, "ARTWORK")
	r.chev:SetSize(10, 10)
	local okM, file = pcall(API.Media, "ui-chevron.png")
	if okM and file then r.chev:SetTexture(file) end
	r:SetScript("OnEnter", RowEnter)
	r:SetScript("OnLeave", RowLeave)
	r:SetScript("OnClick", RowClick)
	rows[i] = r
	return r
end

-- One row drawn at `y` under the list's top; returns its height. Nothing is cut: the right
-- column takes the width its two texts need, the name wraps in what is left.
local function FillRow(r, e, y, C)
	local row, slot = e.row, e.kind == "slot"
	local indent = slot and 0 or 18
	local size = slot and 30 or 20
	r.entry = e
	r.icon:SetSize(size, size)
	r.icon:SetTexture(Icon(ns.Stats.ItemID(row.link)) or 134400)   -- (134400: the game's question mark)
	-- (A pair's two items say which hand they are for; the pair's own row has the gain.)
	r.gain:SetText(row.label or (Window.GainText(row) .. ((not row.isSet and Window.Uncounted(row, S.tips)) and " *" or "")))
	ink(r.gain, C.GOOD)
	r.price:SetText(Money(row.price))
	ink(r.price, C.VALUE)
	local right = math.ceil(math.max(r.gain:GetStringWidth() or 0, r.price:GetStringWidth() or 0))
	local chev = slot and e.more > 0
	local nameW = math.max(60, WIDTH - EDGE - indent - size - 8 - 8 - right - (chev and 14 or 0) - EDGE)
	r.name:SetWidth(nameW)
	r.name:SetText(row.name or "")
	r.name:SetTextColor(QualityColor(row.quality))
	local textH = r.name:GetStringHeight() or 13
	if slot then
		local M = ns.Marks
		r.slot:SetWidth(nameW)
		r.slot:SetText(e.group == "WEAPONS" and L["Weapons"]
			or (type(M) == "table" and type(M.SlotName) == "function" and M.SlotName(e.group)) or "")
		ink(r.slot, C.LABEL)
		r.slot:Show()
		textH = textH + 2 + (r.slot:GetStringHeight() or 12)
	else
		r.slot:Hide()
	end
	local rightH = (r.gain:GetStringHeight() or 13) + 2 + (r.price:GetStringHeight() or 12)
	local h = math.ceil(math.max(size, textH, rightH)) + 8

	r:ClearAllPoints()
	r:SetPoint("TOPLEFT", r:GetParent(), "TOPLEFT", 0, -y)
	r:SetSize(WIDTH, h)
	r.icon:ClearAllPoints()
	r.icon:SetPoint("TOPLEFT", r, "TOPLEFT", EDGE + indent, -4)
	r.name:ClearAllPoints()
	r.name:SetPoint("TOPLEFT", r.icon, "TOPRIGHT", 8, 0)
	r.slot:ClearAllPoints()
	r.slot:SetPoint("TOPLEFT", r.name, "BOTTOMLEFT", 0, -2)
	r.gain:ClearAllPoints()
	r.gain:SetPoint("TOPRIGHT", r, "TOPRIGHT", -EDGE - (chev and 14 or 0), -4)
	r.price:ClearAllPoints()
	r.price:SetPoint("TOPRIGHT", r.gain, "BOTTOMRIGHT", 0, -2)
	if chev then
		-- (Daylight UI's chevron points down as drawn: DaylightUI\Book\Arrows.lua:25. A quarter turn
		-- counter-clockwise makes it point right, at a closed row.)
		r.chev:ClearAllPoints()
		r.chev:SetPoint("RIGHT", r, "RIGHT", -EDGE, 0)
		r.chev:SetRotation(e.open and 0 or math.pi / 2)
		local lr, lg, lb = (C.LABEL or {})[1] or 0.76, (C.LABEL or {})[2] or 0.71, (C.LABEL or {})[3] or 0.62
		r.chev:SetVertexColor(lr, lg, lb)
		r.chev:Show()
	else
		r.chev:Hide()
	end
	if slot and e.open then
		r.mark:SetColorTexture(API.Accent())
		r.mark:Show()
	else
		r.mark:Hide()
	end
	r:Show()
	return h
end

local function Facts()
	local who, whoWhy = ns.Who()
	local state, done, total = ns.Market.State()
	local _, why = ns.Market.CanScan()
	return {
		enabled = ns.Get("enabled") ~= false, who = who ~= nil, whoWhy = whoWhy,
		market = state, done = done, total = total, hasList = ns.Market.Saved() ~= nil, dui = why == "dui",
		fight = S.job == nil and Game.InCombat(),
		scoring = S.running, left = S.job and (S.job:Left() + S.job.nParked) or 0,
		unread = (S.job and not S.running and S.job.gaveUp or 0) + (ns.Market.Saved() and ns.Market.Saved().lost or 0),
		gone = S.job and S.job.gone or 0,
		-- (Listings never read, of items that do have another listing in the list; not while
		-- the tail is still reading them.)
		unreadRows = (ns.Market.Saved() and not ns.Market.Tail()) and ns.Market.Saved().lostRows or 0,
		listed = S.view and S.view.listed or 0, over = Window.Over(S.view), money = Money,
	}
end
Window.Facts = Facts

-- The line under the title: who is scored for, and how old the list is (or how far its
-- reading is).
local function SubText(facts)
	local parts = {}
	local who = ns.Who()
	if who then
		parts[1] = L["Scoring gear for %s, level %d."]:format(ns.SpecValues[who.spec] or who.spec, who.level)
	end
	if facts.market == "reading" and facts.hasList then
		if (facts.total or 0) > 0 then
			parts[#parts + 1] = L["Reading the Auction House: %d of %d rows."]:format(facts.done or 0, facts.total)
		else
			parts[#parts + 1] = L["Waiting for the Auction House's list."]
		end
	else
		parts[#parts + 1] = Window.AgeText(ns.Market.Age())
	end
	-- (Upgrades the list had that a search since found sold.)
	if (facts.gone or 0) > 0 then
		parts[#parts + 1] = ns.Plural(facts.gone, L["%d is no longer for sale."], L["%d are no longer for sale."],
			L["%d are no longer for sale.#few"])
	end
	local checking, done, total = false, 0, 0
	if ns.Check then checking, done, total = ns.Check.State() end
	if checking then parts[#parts + 1] = L["Checking prices: %d of %d."]:format(math.min(done + 1, total), total) end
	-- (Said plainly: gear that was for sale and could not be read is not in the list.)
	if (facts.unread or 0) == 0 and (facts.unreadRows or 0) > 0 then
		parts[#parts + 1] = ns.Plural(facts.unreadRows, L["%d listing could not be read."], L["%d listings could not be read."],
			L["%d listings could not be read.#few"])
	end
	if (facts.unread or 0) > 0 then
		parts[#parts + 1] = ns.Plural(facts.unread, L["%d item for sale could not be read."], L["%d items for sale could not be read."],
			L["%d items for sale could not be read.#few"])
	end
	return table.concat(parts, " ")
end
Window.SubText = SubText

-- A footer line: its label on the left and its control on the right when both fit, else the
-- control under the label. Returns the height used.
local function FootLine(f, label, control, width, y)
	label:ClearAllPoints()
	label:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", EDGE, y + 5)
	local need = (label:GetStringWidth() or 0) + 10 + width
	if need <= INNER then
		control:ClearAllPoints()
		control:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -EDGE, y)
		return 26
	end
	control:ClearAllPoints()
	control:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -EDGE, y)
	label:ClearAllPoints()
	label:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", EDGE, y + 28)
	return 46
end

local MODES = { perGold = L["Most per Gold"], biggest = L["Biggest Gain"] }

-- The item IDs of the rows on screen (the best pick per slot and the opened slot's
-- alternatives): what Check Prices asks about.
function Window.ShownItems()
	local ids, seen = {}, {}
	for _, e in ipairs(S.model) do
		local id = ns.Stats.ItemID(e.row.link)
		if id and not seen[id] then
			seen[id] = true
			ids[#ids + 1] = id
		end
	end
	return ids
end

local function CheckClick()
	if not ns.Check then return end
	if ns.Check.State() then
		ns.Check.Stop()
	else
		ns.Check.Start(Window.ShownItems())
	end
end

local function LayoutFoot(f, C)
	local y = 10
	-- Check Prices: where Daylight UI's own search can be asked, and there are rows to ask about.
	local checking = ns.Check and ns.Check.State()
	local can = ns.Check and (checking or (ns.Check.CanRun() and #S.model > 0))
	if can then
		f.check.text:SetText(checking and L["Stop"] or L["Check Prices"])
		f.check:ClearAllPoints()
		f.check:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -EDGE, y)
		f.check.FitWidth(110)
		f.check:Show()
		y = y + 28
	else
		f.check:Hide()
	end
	-- Our own read of the Auction House: only where Daylight UI's Full Scan is not the way.
	local ok, why = ns.Market.CanScan()
	if ok or why == "cooldown" or why == "busy" then
		f.scan:ClearAllPoints()
		f.scan:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -EDGE, y)
		f.scan.FitWidth(120)
		f.scan:Show()
		y = y + 28
	else
		f.scan:Hide()
	end
	local mode = ns.Get("mode") == "biggest" and "biggest" or "perGold"
	f.mode.text:SetText(MODES[mode])
	f.mode.FitWidth(110)
	ink(f.modeLabel, C.LABEL)
	y = y + FootLine(f, f.modeLabel, f.mode, f.mode:GetWidth(), y)

	local gold = tonumber(ns.Get("maxPrice")) or 0
	f.value:SetText(gold > 0 and Money(gold * 10000) or L["No Limit"])
	ink(f.value, C.VALUE)
	local valueW = math.max(64, math.ceil(f.value:GetStringWidth() or 0) + 12)
	f.value:SetWidth(valueW)
	f.plus:ClearAllPoints()
	f.value:ClearAllPoints()
	f.value:SetPoint("RIGHT", f.plus, "LEFT", 0, 0)
	f.minus:ClearAllPoints()
	f.minus:SetPoint("RIGHT", f.value, "LEFT", 0, 0)
	ink(f.priceLabel, C.LABEL)
	y = y + FootLine(f, f.priceLabel, f.plus, 26 + valueW + 26, y)
	return y + 6
end

-- The thin bar on the list's right edge that says where a long list is scrolled to.
function Window.Thumb()
	local f = Window.frame
	if not f then return end
	local range, listH = f.range or 0, f.listH or 0
	if range <= 0 or listH <= 0 then return f.thumb:Hide() end
	local h = math.max(16, listH * listH / (listH + range))
	local at = math.max(0, math.min(range, f.scroll:GetVerticalScroll() or 0)) / range * (listH - h)
	f.thumb:SetColorTexture(1, 1, 1, 0.18)
	f.thumb:SetHeight(h)
	f.thumb:ClearAllPoints()
	f.thumb:SetPoint("TOPRIGHT", f.scroll, "TOPRIGHT", -3, -at)
	f.thumb:Show()
end

local painting = false
local function PaintNow()
	local f = Window.frame
	if not f or not f:IsShown() then return end
	local C = Colors()
	local facts = Facts()

	ink(f.title, C.TITLE)
	f.sub:SetWidth(INNER)
	f.sub:SetText(SubText(facts))
	ink(f.sub, C.LABEL)
	local head = 12 + (f.title:GetStringHeight() or 15) + 4 + (f.sub:GetStringHeight() or 12) + 8

	local key, text = Window.EmptyState(facts)
	local y = 0
	local first, aimed
	if key then
		for i = 1, #rows do rows[i]:Hide() end
		f.empty:SetWidth(INNER)
		f.empty:SetText(text)
		ink(f.empty, C.TEXT)
		f.empty:Show()
		y = math.ceil(f.empty:GetStringHeight() or 13) + 20
	else
		f.empty:Hide()
		S.tips = S.tips or {}
		S.tips.left, S.tips.more = 3, false
		for i, e in ipairs(S.model) do
			local r = Row(i)
			y = y + FillRow(r, e, y, C)
			first = first or r
			if e.kind == "slot" and e.group == S.aim then aimed = r end
		end
		for i = #S.model + 1, #rows do
			rows[i].entry = nil
			rows[i]:Hide()
		end
	end
	f.first = first
	f.child:SetSize(WIDTH, math.max(1, y))
	local listH = math.min(y, MAX_LIST)
	local foot = LayoutFoot(f, C)

	f.scroll:ClearAllPoints()
	f.scroll:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -head)
	f.scroll:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, -head)
	f.scroll:SetHeight(math.max(1, listH))
	f.line:ClearAllPoints()
	f.line:SetPoint("TOPLEFT", f.scroll, "BOTTOMLEFT", 0, -2)
	f.line:SetPoint("TOPRIGHT", f.scroll, "BOTTOMRIGHT", 0, -2)
	local height = head + listH + 4 + foot
	f:SetHeight(height)
	local range = math.max(0, y - listH)
	if (f.scroll:GetVerticalScroll() or 0) > range then f.scroll:SetVerticalScroll(range) end
	f.range, f.listH = range, listH
	Window.Thumb()
	-- (The shell is laid out again after a resize: API.md, "Call it again after resizing". Only
	-- then: dressing a window is the dearest thing a paint does.)
	if height ~= f.dressed then
		f.dressed = height
		pcall(API.Skin, f, { window = true })
	end

	-- (Rows whose "effect not counted" mark was not asked for yet: the rest on the next paints.)
	if S.tips and S.tips.more and not S.tipSoon then
		S.tipSoon = true
		C_Timer.After(0.1, function()
			S.tipSoon = false
			Paint()
		end)
	end

	-- A controller: the game finds the rows again when they changed, the cursor on the slot
	-- just opened or closed.
	local shape = (key or "") .. #S.model .. tostring(S.selected)
	if shape ~= f.shape then
		f.shape = shape
		local P = Pad()
		if P and P.On() then P.Settle(aimed) end
	end
	S.aim = nil
end

-- Only the sentence about the reading, where it stands now (the line under the title, or the
-- text that stands in for an empty list).
function Window.PaintProgress()
	local f = Window.frame
	if not f or not f:IsShown() then return end
	local facts = Facts()
	f.sub:SetText(SubText(facts))
	local key, text = Window.EmptyState(facts)
	if key and f.empty:IsShown() then f.empty:SetText(text) end
end

Paint = function()
	if painting then return end
	local f = Window.frame
	if not f or not f:IsShown() then return end
	painting = true
	local t0 = Game.Clock()
	local ok, err = pcall(PaintNow)
	painting = false
	ns.Perf.Time("paint", Game.Clock() - t0)
	ns.Perf.Count("paint")
	if not ok then geterrorhandler()(err) end
end

local function StepPrice(dir)
	SetSetting("maxPrice", Window.StepPrice(ns.Get("maxPrice"), dir))
end

local function SetMode(mode)
	if ns.Get("mode") ~= mode then SetSetting("mode", mode) end
end

local function ScanClick()
	local ok, why, left = ns.Market.Scan()
	if ok or why == "busy" then return Paint() end
	if why == "cooldown" then
		ns.Print(L["You can read the Auction House again in %d min."]:format(math.max(1, math.ceil((left or 0) / 60))))
	elseif why == "throttled" then
		ns.Print(L["The Auction House isn't taking requests right now. Try again in a moment."])
	end
	Paint()
end

-- The fold tab: a small bordered tab with a grip, at the top corner of the side the window
-- hangs from (on the window's outer edge while it is open, on the host's while folded).
local function PaintGrip(t, hover)
	local r, g, b
	if hover then
		r, g, b = API.Accent()
	else
		local c = Colors().LABEL or { 0.76, 0.71, 0.62 }
		r, g, b = c[1], c[2], c[3]
	end
	for i = 1, 3 do t.bars[i]:SetColorTexture(r, g, b, 1) end
end

local function BuildTab()
	local t = CreateFrame("Button", "DaylightGearWindowTab", UIParent)
	t:SetSize(14, 34)
	t:SetFrameStrata("MEDIUM")
	t:Hide()
	pcall(API.Skin, t, { noBevel = true })
	t.bars = {}
	for i = 1, 3 do
		local bar = t:CreateTexture(nil, "OVERLAY")
		bar:SetSize(6, 2)
		bar:SetPoint("CENTER", t, "CENTER", 0, (2 - i) * 4)
		t.bars[i] = bar
	end
	PaintGrip(t, false)
	t:SetScript("OnClick", function()
		GameTooltip:Hide()
		local saved = Saved()
		saved.folded = not saved.folded or nil
		Place()
	end)
	t:SetScript("OnEnter", function(self)
		PaintGrip(self, true)
		GameTooltip:SetOwner(self, tipSide())
		GameTooltip:SetText(Saved().folded and L["Show Upgrades for Sale"] or L["Hide Upgrades for Sale"])
		GameTooltip:Show()
	end)
	t:SetScript("OnLeave", function(self)
		PaintGrip(self, false)
		GameTooltip:Hide()
	end)
	-- A controller: one more stop the triggers reach beside the Auction House window, never
	-- taking the cursor as it shows; A folds or opens the list.
	t.padSecond = true
	local P = Pad()
	if P then P.Follow(t) end
	return t
end

local function Build()
	if Window.frame then return Window.frame end
	if Window.failed then return nil end
	for _, name in ipairs({ "Skin", "Text", "Button", "Close", "Colors", "Accent", "Media" }) do
		if type(API[name]) ~= "function" then
			Window.failed = true
			return nil
		end
	end
	local f = CreateFrame("Frame", "DaylightGearWindow", UIParent)
	f:SetSize(WIDTH, 200)
	f:SetFrameStrata("MEDIUM")
	f:SetToplevel(true)
	f:SetClampedToScreen(true)
	f:EnableMouse(true)
	f:SetMovable(true)
	f:RegisterForDrag("LeftButton")
	f:Hide()
	API.Skin(f, { window = true })

	f.title = API.Text(f, "head", "LEFT")
	f.title:SetPoint("TOPLEFT", f, "TOPLEFT", EDGE, -12)
	f.title:SetWidth(INNER - 22)
	f.title:SetWordWrap(true)
	f.title:SetText(L["Upgrades for Sale"])
	f.close = API.Close(f, function() Window.Close() end)
	f.close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -8, -8)
	f.sub = API.Text(f, "small", "LEFT")
	f.sub:SetPoint("TOPLEFT", f.title, "BOTTOMLEFT", 0, -4)
	f.sub:SetWordWrap(true)

	f.scroll = CreateFrame("ScrollFrame", nil, f)
	f.child = CreateFrame("Frame", nil, f.scroll)
	f.child:SetSize(WIDTH, 1)
	f.scroll:SetScrollChild(f.child)
	f.scroll:EnableMouseWheel(true)
	f.scroll:SetScript("OnMouseWheel", function(self, delta)
		local to = math.max(0, math.min(f.range or 0, (self:GetVerticalScroll() or 0) - delta * 44))
		self:SetVerticalScroll(to)
		Window.Thumb()
	end)
	f.scroll:SetScript("OnVerticalScroll", function() Window.Thumb() end)
	f.thumb = f:CreateTexture(nil, "OVERLAY")
	f.thumb:SetWidth(2)
	f.thumb:Hide()
	f.empty = API.Text(f.child, "body", "LEFT")
	f.empty:SetPoint("TOPLEFT", f.child, "TOPLEFT", EDGE, -8)
	f.empty:SetWordWrap(true)
	f.line = f:CreateTexture(nil, "ARTWORK")
	f.line:SetHeight(1)
	f.line:SetColorTexture(1, 1, 1, 0.06)

	f.priceLabel = API.Text(f, "small", "LEFT")
	f.priceLabel:SetText(L["Max Price"])
	f.minus = API.Button(f, "-", 22)
	f.minus:SetWidth(26)
	f.minus:SetScript("OnClick", function() StepPrice(-1) end)
	f.plus = API.Button(f, "+", 22)
	f.plus:SetWidth(26)
	f.plus:SetScript("OnClick", function() StepPrice(1) end)
	f.value = API.Text(f, "body", "CENTER")
	f.modeLabel = API.Text(f, "small", "LEFT")
	f.modeLabel:SetText(L["Best Pick"])
	f.mode = API.Button(f, "", 22)
	f.mode:SetScript("OnClick", function() SetMode(ns.Get("mode") == "biggest" and "perGold" or "biggest") end)
	f.check = API.Button(f, L["Check Prices"], 22)
	f.check:SetScript("OnClick", CheckClick)
	f.check:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:SetText(L["Searches the Auction House for each item shown, to see what it costs now and whether it is still for sale."], 1, 1, 1, 1, true)
		GameTooltip:Show()
	end)
	f.check:SetScript("OnLeave", function() GameTooltip:Hide() end)
	f.check:Hide()
	f.scan = API.Button(f, L["Read the Auction House"], 22)
	f.scan:SetScript("OnClick", ScanClick)
	f.scan:Hide()

	-- Dragged by its body while it stands alone; its place is kept (UIParent units).
	f:SetScript("OnDragStart", function(self)
		if S.mode == "free" then self:StartMoving() end
	end)
	f:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		if S.mode ~= "free" then return end
		local left, top = self:GetLeft(), self:GetTop()
		if left and top then
			local saved = Saved()
			saved.x, saved.y = left * self:GetScale(), top * self:GetScale()
		end
	end)
	f:SetScript("OnShow", function()
		if S.stale then
			Window.Refresh(S.force)
		else
			Paint()
			-- (A job that stood still while the window was away goes on.)
			if S.running then Tick(0) end
		end
	end)
	-- Hidden by something else than Place (Escape): standing alone it is closed; beside the
	-- Auction House it is folded, so the next frame does not bring it straight back.
	-- Hidden by the game (Escape, while it stands alone: Special below): it is closed.
	f:SetScript("OnHide", function(self)
		-- (Hidden along with the whole interface it is still "shown": nothing to remember.)
		if S.placing or self:IsShown() then return end
		if S.mode == "free" and not S.loose then
			S.free, S.mode = false, "hidden"
		end
	end)

	-- A controller (Guide.lua's ns.Pad; mouse only without it). The D-pad walks the rows, the
	-- two Max Price buttons, the Best Pick button, Check Prices and the close X; A presses (on a row: search,
	-- and a slot row opens its alternatives); LB / RB switch Best Pick; the right stick scrolls
	-- the list; B closes (folds, beside the Auction House).
	local tabs = {
		{ Click = function() SetMode("perGold") end },
		{ Click = function() SetMode("biggest") end },
	}
	f.padTabs = function() return tabs, ns.Get("mode") == "biggest" and 2 or 1 end
	f.padTabsLabel = L["Best Pick"]
	f.padFirst = function() return f.first or f.minus end
	f.padSelect = function(stop)
		if type(stop) == "table" and stop.entry and Host() then return L["Search"] end
		return nil
	end
	local P = Pad()
	if P then
		P.Follow(f, function() Window.Close() end)
		P.Stick(f, f.scroll)
	end

	Window.frame = f
	Window.tab = BuildTab()
	return f
end

-- Escape closes the window while it stands alone: its name is on the game's list of such
-- windows (UISpecialFrames) only then. Beside the Auction House it is not: there Escape belongs
-- to that window (Daylight UI's takes the key itself: DaylightUI\Windows\Keys.lua:30-41; in a
-- fight the key goes to the game, and a panel that swallowed it would keep the Auction House
-- from closing).
local function Special(on)
	local list = UISpecialFrames
	if type(list) ~= "table" then return end
	for i = #list, 1, -1 do
		if list[i] == "DaylightGearWindow" then
			if on then return end
			table.remove(list, i)
		end
	end
	if on then list[#list + 1] = "DaylightGearWindow" end
end

-- Puts the window and its tab where the mode says. Our frames are never protected, so this is
-- allowed in a fight; the host is a plain frame too (the top of this file).
Place = function()
	local f = Window.frame
	if not f then return end
	local tab = Window.tab
	local host = Host()
	local saved = Saved()
	local mode = Window.Mode(host ~= nil, ns.Get("dock") ~= false, saved.folded == true, S.free)
	local side
	if host then
		local k = host:GetEffectiveScale() / UIParent:GetEffectiveScale()
		side = Window.DockSide({ left = host:GetLeft() * k, right = host:GetRight() * k }, UIParent:GetWidth(), WIDTH * k)
		if (mode == "docked" or mode == "tab") and not side then
			-- No room on either side of the Auction House: the window stays where the player
			-- last left it, with no tab (X or /gear put it away and bring it back; S.loose).
			mode = mode == "docked" and "free" or "hidden"
			S.loose = true
		else
			S.loose = nil
		end
	else
		S.loose = nil
	end
	S.mode, S.side = mode, side
	S.placing = true
	Special(mode == "free" and not S.loose)
	if mode == "docked" or mode == "tab" then
		local k = host:GetEffectiveScale() / UIParent:GetEffectiveScale()
		f:SetScale(k)
		tab:SetScale(k)
		-- (Beside the Auction House it never takes the controller's cursor as it shows.)
		f.padSecond = true
		f:ClearAllPoints()
		if side == "right" then
			f:SetPoint("TOPLEFT", host, "TOPRIGHT", 0, 0)
		else
			f:SetPoint("TOPRIGHT", host, "TOPLEFT", 0, 0)
		end
		f:SetShown(mode == "docked")
		local anchor = mode == "docked" and f or host
		tab:ClearAllPoints()
		if side == "right" then
			tab:SetPoint("TOPLEFT", anchor, "TOPRIGHT", -1, -12)
		else
			tab:SetPoint("TOPRIGHT", anchor, "TOPLEFT", 1, -12)
		end
		tab:Show()
	elseif mode == "free" then
		tab:Hide()
		f.padSecond = nil
		f:SetScale(1)
		f:ClearAllPoints()
		if type(saved.x) == "number" and type(saved.y) == "number" then
			f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", saved.x, saved.y)
		else
			f:SetPoint("CENTER", UIParent, "CENTER", 320, 60)
		end
		f:Show()
	else
		tab:Hide()
		f:Hide()
	end
	S.placing = false
	if f:IsShown() then Paint() end
end

-- The host comes, goes, moves and scales: looked at every frame while an Auction House is open
-- or the window hangs on one (four reads; the window is only placed again when one changed).
local watch = CreateFrame("Frame")
local seen = {}
local function Watch()
	local host = Host()
	local l, t, r, s
	if host then l, t, r, s = host:GetLeft(), host:GetTop(), host:GetRight(), host:GetEffectiveScale() end
	if host ~= seen.host or l ~= seen.l or t ~= seen.t or r ~= seen.r or s ~= seen.s then
		seen.host, seen.l, seen.t, seen.r, seen.s = host, l, t, r, s
		Place()
	end
	if not host and not ns.Market.IsOpen() then watch:SetScript("OnUpdate", nil) end
end

local function StartWatch()
	if Window.frame then watch:SetScript("OnUpdate", Watch) end
end

watch:SetScript("OnEvent", function(_, event)
	if event == "AUCTION_HOUSE_SHOW" then
		StartWatch()
	elseif event == "PLAYER_REGEN_ENABLED" then
		if S.stale and Shown() then Window.Refresh(S.force) end
	end
end)
pcall(watch.RegisterEvent, watch, "AUCTION_HOUSE_SHOW")
pcall(watch.RegisterEvent, watch, "PLAYER_REGEN_ENABLED")

-- =============================================================================================
-- Open, close
-- =============================================================================================
function Window.Open()
	if not Build() then return false end
	if Host() and ns.Get("dock") ~= false then
		Saved().folded = nil
		StartWatch()
	else
		S.free = true
	end
	Place()
	return true
end

function Window.Close()
	if not Window.frame then return end
	if S.mode == "docked" or S.loose then
		Saved().folded = true
	else
		S.free = false
	end
	Place()
end

function Window.Toggle()
	if not Build() then
		-- (A Daylight UI without the pieces the window is built from: say who is scored for.)
		local who = ns.Who()
		if who then ns.Print(L["Scoring gear for %s, level %d."]:format(ns.SpecValues[who.spec] or who.spec, who.level)) end
		return
	end
	if Shown() then Window.Close() else Window.Open() end
end
ns.OpenWindow = Window.Toggle

ns.me.On("Login", function()
	local ok, err = pcall(Build)
	if not ok then
		Window.failed = true
		geterrorhandler()(err)
	end
end)
pcall(ns.me.On, "StyleChanged", function()
	if Window.frame then
		Window.frame.dressed = nil
		Paint()
	end
end)
