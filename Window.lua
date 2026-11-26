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
-- Pick: the same settings as the options page). While Daylight UI's Auction House window (or,
-- without it, the game's own) is up and Dock to the Auction House is on, it sits flush against that window's right edge (the
-- left one when the right has no room), tops level, and follows it; a small tab at that corner
-- folds it away. Anywhere else /gear opens it as a window of its own that is dragged by
-- its body and remembers its place (Host.Spot: with Daylight UI in the player's profile). On its
-- own it also takes part in Daylight UI's window room (Host.Window: other windows slide aside for
-- it) and takes Daylight UI's global scale (Host.Scaled); beside the Auction House it does neither,
-- and takes the Auction House window's scale instead.
--
-- A CLICK on a row (A on a controller) searches that item in Daylight UI's Buy page. Nothing
-- is ever bought, bid on or posted from here.
--
-- DAYLIGHT UI'S INTERNALS touched, each behind one function that answers nil or false when
-- anything is not as read (the fall-back in brackets):
--   Host()          _G.DaylightUIAuctionHouse, the Auction House window's global name
--                   (DaylightUI_AuctionHouse\Window.lua:33, made at :487 by Win.New, a plain
--                   Frame with no secure template: DaylightUI\Windows\Frame.lua:288; no secure
--                   frame anywhere in that module). [the game's own AuctionHouseFrame while it
--                   is the one on screen (Blizzard_AuctionHouseFrame.xml:4, a plain Frame),
--                   docked to the same way; else a window of its own]
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

local ADDON, ns = ...
if ns.off or not ns.ok then return end

local L, API = ns.L, ns.API
local Game, Rank, Compare = ns.Game, ns.Rank, ns.Compare

local Window = {}
ns.Window = Window

local WIDTH, EDGE = 340, 12
local BOX_W = 64              -- a footer gold box: six digits
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
				-- (A pair is weighed against the hands as they are, so each hand's row compares with
				-- what that hand holds now: CompareTip.lua.)
				local inMain, inOff = Game.WornLink(16), Game.WornLink(17)
				out[#out + 1] = { kind = "alt", group = "WEAPONS", row = { key = m.key, link = m.link, name = m.name,
					quality = m.quality, price = m.price, checkedAt = m.checkedAt, label = HandName("MAINHAND"),
					replaces = inMain and { link = inMain } or nil } }
				out[#out + 1] = { kind = "alt", group = "WEAPONS", row = { key = o.key, link = o.link, name = o.name,
					quality = o.quality, price = o.price, checkedAt = o.checkedAt, label = HandName("OFFHAND"),
					replaces = inOff and { link = inOff } or nil } }
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

-- A list read over a day ago is "Stale" (as Glowey's Recipes' prices, Calc.STALE): auctions run
-- 12, 24 or 48 hours and most are posted for 24, so by then most of what the list was read from
-- has sold or run out. Said in front of its age, so the player knows to scan again.
Window.STALE = 24 * 3600

function Window.AgeText(seconds)
	seconds = tonumber(seconds)
	if not seconds then return nil end
	if seconds < 60 then return L["List read just now."] end
	if seconds < 3600 then return L["List read %d min ago."]:format(math.floor(seconds / 60)) end
	local text = seconds < 48 * 3600 and L["List read %d h ago."]:format(math.floor(seconds / 3600))
		or L["List read more than two days ago."]
	if seconds >= Window.STALE then text = L["Stale: %s"]:format(text) end
	return text
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
--   is the one in use), other (the names of the addons whose full scan is the way, or nil), scoring (bool), left, listed, over (copper | nil), money(copper) -> text
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
		if f.sweep then return "sweeping", Window.SweepText(f.sweep) end
		if f.dui then
			return "nolist", L["No list of the Auction House yet. Run a Full scan there, and the upgrades show up here."]
		end
		if f.other then
			return "nolistother", L["No list of the Auction House yet. Run a full scan in %s, and the upgrades show up here."]:format(f.other)
		end
		return "nolistown", L["No list of the Auction House yet. Open the Auction House and press Scan the Auction House."]
	end
	if (f.listed or 0) > 0 then return nil end
	if f.fight then return "fight", L["Gear isn't checked during a fight. The list fills in when it ends."] end
	if f.scoring then return "scoring", L["Scoring the items for sale: %d left."]:format(f.left or 0) end
	-- (Max Spend for All Slots left every slot out: the cheapest pick it would take.)
	if f.spend and (f.spend.nCut or 0) > 0 then
		local cheapest
		for _, row in pairs(f.spend.cut) do
			if not cheapest or row.price < cheapest then cheapest = row.price end
		end
		local money = f.money or tostring
		return "spend", L["No upgrades for sale fit your max spend for all slots. Raise it to %s to see one."]:format(money(cheapest))
	end
	if f.over then
		local money = f.money or tostring
		return "over", L["No upgrades for sale under your max price. Raise it to %s to see one."]:format(money(f.over))
	end
	return "nothing", L["No upgrades for sale right now."]
end

-- What our own scan is doing (Sweep.Progress), in words, and how far it is (0 to 1).
function Window.SweepText(p)
	if not p then return "", 0 end
	local part = (p.total or 0) > 0 and math.min(1, (p.done or 0) / p.total) or 0
	if p.paused then
		if p.closed then
			return L["Scan paused: the Auction House closed. Open it and press Resume Scan."], part
		end
		return L["Scan paused. Press Resume Scan to go on."], part
	end
	if p.step == "browse" then
		return L["Scanning weapons and armor: %d of %d categories, %d items found."]:format(p.done or 0, p.total or 0,
			p.found or 0), part
	elseif p.step == "search" then
		return L["Checking rolled items: %d of %d."]:format(p.done or 0, p.total or 0), part
	end
	return L["Saving the scan."], part
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
-- show (multiples of 5); past the top is "no limit" (0). A typed amount off the ladder steps to
-- the next one up or down.
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

-- Max Spend for All Slots: the same, on a ladder of its own (multiples of the slider's 50).
local SPEND = { 50, 100, 250, 500, 1000, 2500, 5000, 10000, 25000, 50000 }
function Window.StepSpend(gold, dir)
	gold = tonumber(gold) or 0
	if dir > 0 then
		if gold <= 0 then return 0 end
		for i = 1, #SPEND do
			if SPEND[i] > gold then return SPEND[i] end
		end
		return 0
	end
	if gold <= 0 then return SPEND[#SPEND] end
	for i = #SPEND, 1, -1 do
		if SPEND[i] < gold then return SPEND[i] end
	end
	return SPEND[1]
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
-- (Not how many owned items wait for their data: one that arrives joins a pool, and changes
-- the signature there; one that waits changes no answer. Counted here, every arrival scored
-- the whole list again.)
local function Signature(ctx)
	local parts = { tostring(ctx.class), tostring(ctx.level), tostring(ctx.bestArmor) }
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
	local opts = job and ns.RankOptions(job.ctx.level)
	S.set = (job and S.view) and Rank.Set(job, opts, S.view) or nil
	-- Max Spend for All Slots: every slot's pick within it (Rank.Budget); the weapon pair only
	-- when it fits it on its own.
	local spend = opts and opts.maxSpend or 0
	S.shown = spend > 0 and Rank.Budget(S.view, spend) or S.view
	if S.set and spend > 0 and S.set.price > spend then S.set = nil end
	S.model = Window.Model(S.shown, S.selected, S.set)
end

-- The exact arrangement of everything found, and a paint. Cheap enough for a control change
-- (it sorts only the upgrades, a few hundred to a few thousand rows), too dear for every tick.
function Window.Rearrange()
	S.rearrange = nil
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

-- The list of a job that has ended, shown: the best per slot was kept as the rows came, so the
-- end needs no sort of everything found (thousands of rows for a well-geared house): the live
-- view IS the arrangement, unless a price dropped on a row already placed (then it is
-- arranged once, in full).
local function ShowEnded(job, t0)
	job.shown = true
	ns.Perf.Count("show")
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
	if ns.Alert and ns.Market.Saved() then ns.Alert.Check(S.view, S.sig) end
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
		-- A job that had ended once and was given a few more items (rows the tail read late, a
		-- new listing a search found) ends again within a frame or two, and again for the next
		-- batch: its list is shown once a second at most, like every other change to the list.
		-- (One paint per batch was 204 paints a minute while the tail fed 24,000 rows in play.)
		if job.shown and t0 - (S.painted or 0) < REPAINT_MS then
			if not S.showSoon then
				S.showSoon = true
				C_Timer.After((REPAINT_MS - (t0 - (S.painted or 0))) / 1000 + 0.01, function()
					S.showSoon = false
					-- (Running again: its own ticks paint, or its end comes back here.)
					if S.job ~= job or S.running or not Shown() then return end
					ShowEnded(job, Game.Clock())
				end)
			end
			return
		end
		return ShowEnded(job, t0)
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
	-- (A new job is arranged under the controls as they are now: nothing is left to rearrange.)
	S.rearrange = nil
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
		if ns.Alert then ns.Alert.Check(S.view, S.sig) end
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
-- Our own scan: started, paused or ended lays the window out again; its progress only moves the
-- bar and the words, twice a second at most.
ns.On("SweepChanged", function() if Shown() then Paint() end end)
ns.On("SweepProgress", function()
	if not Shown() then return end
	local now = Game.Clock()
	if now - (S.sweepTold or 0) < PROGRESS_MS then return end
	S.sweepTold = now
	Window.PaintProgress()
end)
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
-- A control changed (Max Price, Smallest Gain, Best Pick): the list is arranged again, once a
-- frame however many steps a slider took, and not at all while the window is away (the
-- arrangement is made when it shows: S.rearrange).
local rearrangeSoon = false
local function RearrangeSoon()
	S.rearrange = true
	if not Shown() or rearrangeSoon then return end
	rearrangeSoon = true
	C_Timer.After(0, function()
		rearrangeSoon = false
		if S.rearrange and Shown() then
			S.rearrange = nil
			Window.Rearrange()
		end
	end)
end
Window.RearrangeSoon = RearrangeSoon

ns.On("Setting", function(path)
	if path == "maxPrice" or path == "maxSpend" or path == "minGain" or path == "mode" then
		RearrangeSoon()
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
local function DuiHost()
	local f = _G.DaylightUIAuctionHouse
	local ok, visible = pcall(Visible, f)
	if ok and visible then return f end
	return nil
end

-- The game's own Auction House window while it is the one on screen, else nil: the fall-back
-- to dock to for a player who keeps it (Daylight UI's Auction House switched off, or another
-- addon that builds on the game's window). Daylight UI parks this frame at no opacity while its
-- own window stands in, which Visible() reads as not there. Only ever read and anchored to.
local function GameHost()
	local f = rawget(_G, "AuctionHouseFrame")
	local ok, visible = pcall(Visible, f)
	if ok and visible then return f end
	return nil
end

-- The Auction House window to sit beside: Daylight UI's first, else the game's own.
local function Host()
	return DuiHost() or GameHost()
end

local function SearchInDui(name)
	local m = ns.Market.DuiAH()
	if not m or not DuiHost() then return false end
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

-- The game's own Auction House window: the name in its search bar and the search started, as
-- its own search button does (Blizzard_AuctionHouseUI, branch forever:
-- Shared\Blizzard_AuctionHouseSearchBar.lua:203-207 StartSearch, :195 SetSearchText). From Sell or
-- Auctions it goes to the Buy tab first (Shared\Blizzard_AuctionHouseFrame.lua:541
-- SetDisplayMode, which also picks the tab), and a category picked there is let go
-- (Shared\Blizzard_AuctionHouseCategoriesList.lua:148), so the item is found in any category.
local BUY_MODES = { "Buy", "ItemBuy", "CommoditiesBuy" }
local function SearchInGame(name)
	local f = GameHost()
	if not f then return false end
	local bar = f.SearchBar
	if type(bar) ~= "table" or type(bar.SetSearchText) ~= "function" or type(bar.StartSearch) ~= "function" then
		return false
	end
	local modes = rawget(_G, "AuctionHouseFrameDisplayMode")
	if type(modes) == "table" and type(f.SetDisplayMode) == "function" then
		local buying = false
		for _, mode in ipairs(BUY_MODES) do
			if modes[mode] ~= nil and f.displayMode == modes[mode] then buying = true end
		end
		if not buying and modes.Buy ~= nil and not pcall(f.SetDisplayMode, f, modes.Buy) then return false end
	end
	if type(f.GetCategoriesList) == "function" then
		local ok, list = pcall(f.GetCategoriesList, f)
		if ok and type(list) == "table" and type(list.SetSelectedCategory) == "function" then
			pcall(list.SetSelectedCategory, list, nil)
		end
	end
	if not pcall(bar.SetSearchText, bar, name) then return false end
	return (pcall(bar.StartSearch, bar))
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

-- The search for a row's item. True when Daylight UI's Auction House or the game's own took it.
-- With an Auction House open that we could not hand it to (DaylightMogul's, or a window that
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
	if SearchInGame(text) then return true end
	if ns.Market.IsOpen() then
		ns.Print(L["Type %s in the Auction House's search box."]:format(text))
	end
	return false
end

-- =============================================================================================
-- Saved state: GloweyGearDB.window = { folded = bool } (per account); the spot on its own in the
-- plugin's settings (Spot below)
-- =============================================================================================
local function Saved()
	local db = ns.DB()
	if type(db.window) ~= "table" then db.window = {} end
	return db.window
end

-- Host.lua's calls (ns.Host, both modes): true and what it answered, or false when it is not there
-- (the offline tests load no Host.lua).
local function HostCall(name, ...)
	local H = ns.Host
	local fn = type(H) == "table" and H[name]
	if type(fn) ~= "function" then return false end
	return true, fn(...)
end

-- The window shown and hidden through Host.Open / Close (its fade and sounds, and the window
-- room), else straight; Up: shown and not closing (Host.Shown), for the toggle.
local function ShowWin(f) if not HostCall("Open", f) then f:Show() end end
local function HideWin(f) if not HostCall("Close", f) then f:Hide() end end
local function Up(f)
	local ok, v = HostCall("Shown", f)
	if ok then return v and true or false end
	return f:IsShown() == true
end

-- A role's color from the look (Host.Color), else the color given.
local function Rgb(role, r, g, b)
	local ok, called, r2, g2, b2 = pcall(HostCall, "Color", role)
	if ok and called and type(r2) == "number" then return r2, g2, b2 end
	return r, g, b
end

-- The window's spot on its own: its top left in UIParent units, { x =, y = }. Host.Spot keeps it
-- in the plugin's settings, so with Daylight UI in the player's profile, as Daylight UI's own
-- windows' spots are; the spot saved before (GloweyGearDB.window.x / y) is moved in once.
local Spot = {}
function Spot.Host()
	if Spot.s == nil then
		local ok, s = HostCall("Spot", "window", {
			get = function()
				local w = Saved()
				if type(w.x) == "number" and type(w.y) == "number" then return { x = w.x, y = w.y } end
				return nil
			end,
			clear = function()
				local w = Saved()
				w.x, w.y = nil, nil
			end,
		})
		Spot.s = ok and type(s) == "table" and s or false
	end
	return Spot.s or nil
end
function Spot.Get()
	local s = Spot.Host()
	local t = s and s.Get() or nil
	if type(t) ~= "table" then t = Saved() end
	if type(t.x) == "number" and type(t.y) == "number" then return t.x, t.y end
	return nil
end
function Spot.Save(x, y)
	local s = Spot.Host()
	if s and s.Save({ x = x, y = y }) ~= false then return end
	local w = Saved()
	w.x, w.y = x, y
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
		-- (The look's roles, Host.Color: the title in TITLE, the words and hands in LABEL; the
		-- items' names keep their quality's color.)
		local tr, tg, tb = Rgb("TITLE", 1, 1, 1)
		local lr, lg, lb = Rgb("LABEL", 0.72, 0.70, 0.66)
		GameTooltip:SetText(L["Both Together"], tr, tg, tb)
		GameTooltip:AddLine(L["Buying these two together is a bigger upgrade than either one alone."], lr, lg, lb, true)
		GameTooltip:AddDoubleLine(HandName("MAINHAND"), e.row.main.name or "", lr, lg, lb, QualityColor(e.row.main.quality))
		GameTooltip:AddDoubleLine(HandName("OFFHAND"), e.row.off.name or "", lr, lg, lb, QualityColor(e.row.off.quality))
		GameTooltip:Show()
		ns.CompareTip.Hide()
		return
	end
	if not pcall(GameTooltip.SetHyperlink, GameTooltip, e.row.link) then
		ns.CompareTip.Hide()
		return GameTooltip:Hide()
	end
	-- (A price a search confirmed since the scan says so, and how long ago.)
	local checked = Window.CheckedText(e.row.checkedAt)
	local lr, lg, lb = Rgb("LABEL", 0.72, 0.70, 0.66)
	if checked then GameTooltip:AddLine(checked, lr, lg, lb, true) end
	-- (With the tooltip row switched off, the "*" still gets its words.)
	if ns.Get("tooltips") == false and Window.Uncounted(e.row) then
		GameTooltip:AddLine(L["Gear Advice does not count this item's special effect."], lr, lg, lb, true)
	end
	-- (Only Daylight UI's window takes the search: beside the game's own, a click says what to type.)
	if DuiHost() then
		local r, g, b = API.Accent()
		GameTooltip:AddLine(L["Click: search for it in the Auction House"], r, g, b, true)
	end
	GameTooltip:Show()
	-- (Beside it, the piece it replaces: CompareTip.lua.)
	ns.CompareTip.Show(GameTooltip, e.row)
end

local function RowLeave(self)
	self.hover:Hide()
	ns.CompareTip.Hide()
	GameTooltip:Hide()
end

-- (The game calls this 5 times a second while the row owns the tooltip: the comparison moves to
-- the other side when the game's own, held Shift, takes this one.)
local function RowUpdateTooltip()
	if GameTooltip:IsShown() then ns.CompareTip.Place(GameTooltip) end
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
	r.UpdateTooltip = RowUpdateTooltip
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
	r.gain:SetText((row.label or Window.GainText(row)) .. ((not row.isSet and Window.Uncounted(row, S.tips)) and " *" or ""))
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
	local other
	if why == "other" then
		local names = ns.Market.Others()
		other = #names > 0 and table.concat(names, ", ") or "Daylight Mogul"
	end
	return {
		other = other, sweep = ns.Sweep and ns.Sweep.Progress() or nil,
		enabled = ns.Get("enabled") ~= false, who = who ~= nil, whoWhy = whoWhy,
		market = state, done = done, total = total, hasList = ns.Market.Saved() ~= nil, dui = why == "dui",
		fight = S.job == nil and Game.InCombat(),
		scoring = S.running, left = S.job and (S.job:Left() + S.job.nParked) or 0,
		unread = (S.job and not S.running and S.job.gaveUp or 0) + (ns.Market.Saved() and ns.Market.Saved().lost or 0),
		gone = S.job and S.job.gone or 0,
		-- (Listings never read, of items that do have another listing in the list; not while
		-- the tail is still reading them.)
		unreadRows = (ns.Market.Saved() and not ns.Market.Tail()) and ns.Market.Saved().lostRows or 0,
		listed = (S.shown or S.view) and (S.shown or S.view).listed or 0, over = Window.Over(S.view), money = Money,
		spend = S.shown and S.shown.spend or nil,
	}
end
Window.Facts = Facts

-- The line under the title: who is scored for, and how old the list is (or how far its
-- reading is).
local function SubText(facts)
	local parts = {}
	local who = ns.Who()
	if who then
		-- (Saying so when the player's own stat weights are in use: MyWeights.lua.)
		parts[1] = ((who.custom or 0) > 0 and L["Scoring gear for %s, level %d, with your own stat weights."]
			or L["Scoring gear for %s, level %d."]):format(ns.SpecValues[who.spec] or who.spec, who.level)
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
	-- (Max Spend for All Slots: what the picks cost together, and the slots it left out.)
	local spend = facts.spend
	if spend then
		parts[#parts + 1] = L["The picks cost %s of your %s max spend."]:format(Money(spend.spent), Money(spend.budget))
		if (spend.nCut or 0) > 0 then
			parts[#parts + 1] = ns.Plural(spend.nCut, L["%d more slot has an upgrade over it."],
				L["%d more slots have an upgrade over it."], L["%d more slots have an upgrade over it.#few"])
		end
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
	local function add(link)
		local id = ns.Stats.ItemID(link)
		if id and not seen[id] then
			seen[id] = true
			ids[#ids + 1] = id
		end
	end
	for _, e in ipairs(S.model) do
		-- (A pair's own row stands for two items, shown or not.)
		if e.row.isSet then
			add(e.row.main.link)
			add(e.row.off.link)
		else
			add(e.row.link)
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
	-- Our own scan of the Auction House: only where neither Daylight UI's Full Scan nor another
	-- installed addon's full scan is the way (Market.CanScan). While one runs or waits to go on,
	-- its bar and words stand above the button.
	local ok, why = ns.Market.CanScan()
	local p = ns.Sweep and ns.Sweep.Progress()
	if ok or why == "busy" or p then
		local label = L["Scan the Auction House"]
		if p and p.paused then
			label = L["Resume Scan"]
		elseif p then
			label = L["Stop Scan"]
		end
		f.scan.text:SetText(label)
		f.scan:ClearAllPoints()
		f.scan:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -EDGE, y)
		f.scan.FitWidth(120)
		f.scan:Show()
		y = y + 28
	else
		f.scan:Hide()
	end
	if p then
		f.bar:ClearAllPoints()
		f.bar:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", EDGE, y + 2)
		f.bar:SetSize(INNER, 6)
		f.bar:Show()
		f.barText:ClearAllPoints()
		f.barText:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", EDGE, y + 12)
		f.barText:SetWidth(INNER)
		ink(f.barText, C.LABEL)
		Window.PaintBar(f, p)
		y = y + 16 + math.ceil(f.barText:GetStringHeight() or 12)
	else
		f.bar:Hide()
		f.barText:Hide()
	end
	local mode = ns.Get("mode") == "biggest" and "biggest" or "perGold"
	f.mode.text:SetText(MODES[mode])
	f.mode.FitWidth(110)
	ink(f.modeLabel, C.LABEL)
	y = y + FootLine(f, f.modeLabel, f.mode, f.mode:GetWidth(), y)

	-- Max Spend for All Slots, then Max Price per Item: each a box that takes the gold typed
	-- (Enter sets it; empty or 0 is no limit) between - and + (a press steps along a ladder).
	local function Amount(box, label, minus, plus, key)
		local gold = tonumber(ns.Get(key)) or 0
		if not box:HasFocus() then box:SetText(gold > 0 and tostring(math.floor(gold)) or "") end
		box:SetWidth(BOX_W)
		plus:ClearAllPoints()
		box:ClearAllPoints()
		box:SetPoint("RIGHT", plus, "LEFT", -2, 0)
		minus:ClearAllPoints()
		minus:SetPoint("RIGHT", box, "LEFT", -2, 0)
		ink(label, C.LABEL)
		return FootLine(f, label, plus, 26 + BOX_W + 26 + 4, y)
	end
	y = y + Amount(f.spend, f.spendLabel, f.spendMinus, f.spendPlus, "maxSpend")
	y = y + Amount(f.value, f.priceLabel, f.minus, f.plus, "maxPrice")
	return y + 6
end

-- The thin bar on the list's right edge that says where a long list is scrolled to.
function Window.Thumb()
	local f = Window.frame
	if not f then return end
	local range, listH = f.range or 0, f.listH or 0
	local H = ns.Host
	if range <= 0 or listH <= 0 then
		f.thumb:Hide()
		if H and H.ScrollArt then H.ScrollArt(f.thumb, f.scroll, 4) end
		return
	end
	local h = math.max(16, listH * listH / (listH + range))
	local at = math.max(0, math.min(range, f.scroll:GetVerticalScroll() or 0)) / range * (listH - h)
	f.thumb:SetColorTexture(1, 1, 1, 0.18)
	f.thumb:SetHeight(h)
	f.thumb:ClearAllPoints()
	f.thumb:SetPoint("TOPRIGHT", f.scroll, "TOPRIGHT", -3, -at)
	f.thumb:Show()
	-- (Blizzard Style without Daylight UI: the minimal scroll bar round it, its own color hidden.)
	if H and H.ScrollArt and H.ScrollArt(f.thumb, f.scroll, 4) then f.thumb:SetAlpha(0) else f.thumb:SetAlpha(1) end
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
-- The scan's bar and words, set in place (no layout).
function Window.PaintBar(f, p)
	if not p then return end
	local text, part = Window.SweepText(p)
	f.bar:SetMinMaxValues(0, 1)
	f.bar:SetValue(part)
	f.barText:SetText(text)
	f.barText:Show()
end

function Window.PaintProgress()
	local f = Window.frame
	if not f or not f:IsShown() then return end
	local facts = Facts()
	if facts.sweep and f.bar:IsShown() then Window.PaintBar(f, facts.sweep) end
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
local function StepSpend(dir)
	SetSetting("maxSpend", Window.StepSpend(ns.Get("maxSpend"), dir))
end

-- A footer box that takes an amount of gold for a setting: Enter sets what was typed (empty: 0,
-- no limit), Escape or leaving it puts the setting's value back.
local function GoldBox(f, key, hint)
	local box = API.Input(f, { numeric = true, hint = hint })
	box:SetHeight(22)
	if box.SetMaxLetters then box:SetMaxLetters(6) end
	if box.SetJustifyH then box:SetJustifyH("CENTER") end
	box:SetScript("OnEnterPressed", function(self)
		local gold = tonumber(self:GetText()) or 0
		self:ClearFocus()
		if gold ~= (tonumber(ns.Get(key)) or 0) then SetSetting(key, math.max(0, math.floor(gold))) end
		Paint()
	end)
	box:SetScript("OnEscapePressed", function(self)
		self:ClearFocus()
		Paint()
	end)
	box:HookScript("OnEditFocusLost", function() Paint() end)
	return box
end

local function SetMode(mode)
	if ns.Get("mode") ~= mode then SetSetting("mode", mode) end
end

local function ScanClick()
	if ns.Sweep and ns.Sweep.Running() then
		ns.Sweep.Pause()
		return Paint()
	end
	local ok, why = ns.Market.Scan()
	if not ok then
		if why == "closed" then
			ns.Print(L["Open the Auction House to scan it."])
		elseif why == "noapi" then
			ns.Print(L["This game client doesn't let addons search the Auction House."])
		end
	end
	Paint()
end

-- The fold tab: a small bordered tab with a grip, at the top corner of the side the window
-- hangs from (on the window's outer edge while it is open, on the host's while folded).
local function PaintGrip(t, hover)
	-- (Host.Tint: the grip follows a look change as well, in LABEL, or the accent on hover.)
	local tinted = true
	for i = 1, 3 do tinted = HostCall("Tint", t.bars[i], hover and "pop" or "LABEL", 1) and tinted end
	if tinted then return end
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
	local t = CreateFrame("Button", "GloweyGearWindowTab", UIParent)
	t:SetSize(14, 34)
	t:SetFrameStrata("MEDIUM")
	t:Hide()
	-- (Host.Skin: dressed again after a look change.)
	if not HostCall("Skin", t, { noBevel = true }) then pcall(API.Skin, t, { noBevel = true }) end
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
		local title = Saved().folded and L["Show Upgrades for Sale"] or L["Hide Upgrades for Sale"]
		if not HostCall("Tip", self, title, nil, nil, tipSide()) then
			GameTooltip:SetOwner(self, tipSide())
			GameTooltip:SetText(title)
			GameTooltip:Show()
		end
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
	local f = CreateFrame("Frame", "GloweyGearWindow", UIParent)
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
	-- Blizzard Style without Daylight UI: a titled window, the X up in its title bar (Host.Chrome).
	if ns.Host and ns.Host.Chrome then ns.Host.Chrome(f, { title = "Glowey's Gear", close = f.close }) end
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
	f.priceLabel:SetText(L["Max Price per Item"])
	f.minus = API.Button(f, "-", 22)
	f.minus:SetWidth(26)
	f.minus:SetScript("OnClick", function() StepPrice(-1) end)
	f.plus = API.Button(f, "+", 22)
	f.plus:SetWidth(26)
	f.plus:SetScript("OnClick", function() StepPrice(1) end)
	f.value = GoldBox(f, "maxPrice", L["No Limit"])
	f.spendLabel = API.Text(f, "small", "LEFT")
	f.spendLabel:SetText(L["Max Spend for All Slots"])
	f.spendMinus = API.Button(f, "-", 22)
	f.spendMinus:SetWidth(26)
	f.spendMinus:SetScript("OnClick", function() StepSpend(-1) end)
	f.spendPlus = API.Button(f, "+", 22)
	f.spendPlus:SetWidth(26)
	f.spendPlus:SetScript("OnClick", function() StepSpend(1) end)
	f.spend = GoldBox(f, "maxSpend", L["No Limit"])
	f.modeLabel = API.Text(f, "small", "LEFT")
	f.modeLabel:SetText(L["Best Pick"])
	f.mode = API.Button(f, "", 22)
	f.mode:SetScript("OnClick", function() SetMode(ns.Get("mode") == "biggest" and "perGold" or "biggest") end)
	f.check = API.Button(f, L["Check Prices"], 22)
	f.check:SetScript("OnClick", CheckClick)
	f.check:SetScript("OnEnter", function(self)
		local text = L["Searches the Auction House for each item shown, to see what it costs now and whether it is still for sale."]
		if HostCall("Tip", self, nil, text, nil, "ANCHOR_TOP") then return end
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:SetText(text, 1, 1, 1, 1, true)
		GameTooltip:Show()
	end)
	f.check:SetScript("OnLeave", function() GameTooltip:Hide() end)
	f.check:Hide()
	f.scan = API.Button(f, L["Scan the Auction House"], 22)
	f.scan:SetScript("OnClick", ScanClick)
	f.scan:SetScript("OnEnter", function(self)
		local text = L["Goes through every weapon and armor category of the Auction House, page by page, at the pace the game allows. Keep the Auction House open until it finishes: closing it pauses the scan."]
		if HostCall("Tip", self, nil, text, nil, "ANCHOR_TOP") then return end
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:SetText(text, 1, 1, 1, 1, true)
		GameTooltip:Show()
	end)
	f.scan:SetScript("OnLeave", function() GameTooltip:Hide() end)
	f.scan:Hide()
	f.bar = API.Bar and API.Bar(f) or CreateFrame("StatusBar", nil, f)
	f.bar:Hide()
	f.barText = API.Text(f, "small", "LEFT")
	f.barText:SetWordWrap(true)
	f.barText:Hide()

	-- Dragged by its body while it stands alone; its place is kept (UIParent units). Anchored
	-- again by one point (the window room slides only a window with one, DaylightUI\Windows\n	-- Feel.lua:116-127), and the room is told its new home (Host.Moved).
	f:SetScript("OnDragStart", function(self)
		if S.mode == "free" then self:StartMoving() end
	end)
	f:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		if S.mode ~= "free" then return end
		local left, top = self:GetLeft(), self:GetTop()
		if left and top then
			local k = self:GetScale() or 1
			Spot.Save(left * k, top * k)
			self:ClearAllPoints()
			self:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
		end
		HostCall("Moved", self)
	end)
	f:SetScript("OnShow", function()
		if S.stale then
			Window.Refresh(S.force)
			-- (A new job arranges itself; a job that stood is arranged for the controls moved.)
			if S.rearrange then Window.Rearrange() end
		elseif S.rearrange then
			Window.Rearrange()
			if S.running then Tick(0) end
		else
			Paint()
			-- (A job that stood still while the window was away goes on.)
			if S.running then Tick(0) end
		end
	end)
	-- Hidden by something else than Place (Escape): standing alone it is closed; beside the
	-- Auction House it is folded, so the next frame does not bring it straight back.
	-- Hidden by the game while it stands alone: it is closed.
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
		if type(stop) == "table" and stop.entry and (DuiHost() or GameHost()) then return L["Search"] end
		return nil
	end
	-- (Followed here, before Host.Window, so B still folds it beside the Auction House: Host.Window
	-- then leaves the controller to this, frame.__gloweyFollowed. Escape there is the Auction
	-- House window's, below.)
	local P = Pad()
	if P then
		P.Follow(f, function() Window.Close() end)
		P.Stick(f, f.scroll)
	end
	-- Host.Window: Escape, the open and close sounds and fade, and on its own Daylight UI's window
	-- room (other windows slide aside for it). Escape closes it only while it stands alone: beside
	-- the Auction House the key belongs to that window (Daylight UI's takes it itself, DaylightUI\n	-- Windows\Keys.lua:30-41; in a fight the game's Escape closes both together, Blizzard_
	-- UIParentPanelManager CloseAllWindows), and a fold there would be kept for the next visit.
	-- Docked, it takes no part in the room (room() false) and never Daylight UI's scale (Scaled:
	-- docked() true): it takes the Auction House window's own (Place).
	HostCall("Window", f, {
		close = function() if S.mode == "free" and not S.loose then Window.Close() end end,
		room = function() return S.dockK == nil end,
	})
	HostCall("Scaled", f, {
		own = function() return S.dockK or 1 end,
		docked = function() return S.dockK ~= nil end,
	})

	Window.frame = f
	Window.tab = BuildTab()
	-- (A look change grows or drops Blizzard Style's frame round the window: docked, it is placed
	-- again so that frame stays flush with the Auction House window.)
	if ns.Host and ns.Host.Looked then
		ns.Host.Looked(Window, function() if S.mode == "docked" or S.mode == "tab" then Place() end end)
	end
	return f
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
	local before = S.mode
	S.mode, S.side = mode, side
	S.placing = true
	if mode == "docked" or mode == "tab" then
		local k = host:GetEffectiveScale() / UIParent:GetEffectiveScale()
		-- (The Auction House window's scale, never Daylight UI's on top: Host.Scaled's docked().)
		S.dockK = k
		if not HostCall("Rescale", f) then f:SetScale(k) end
		tab:SetScale(k)
		-- (Beside the Auction House it never takes the controller's cursor as it shows.)
		f.padSecond = true
		-- (Blizzard Style draws its metal frame and title bar past the window's own edges
		-- (Host.Outset): the frame's outer edge, not the window's, goes flush against the
		-- Auction House window, tops level.)
		local ol, or_, ot = 0, 0, 0
		if ns.Host and ns.Host.Outset then ol, or_, ot = ns.Host.Outset(f) end
		f:ClearAllPoints()
		if side == "right" then
			f:SetPoint("TOPLEFT", host, "TOPRIGHT", ol, -ot)
		else
			f:SetPoint("TOPRIGHT", host, "TOPLEFT", -or_, -ot)
		end
		if mode == "docked" then ShowWin(f) else HideWin(f) end
		local anchor = mode == "docked" and f or host
		local reach = mode == "docked" and (side == "right" and or_ or ol) or 0
		tab:ClearAllPoints()
		if side == "right" then
			tab:SetPoint("TOPLEFT", anchor, "TOPRIGHT", reach - 1, -12)
		else
			tab:SetPoint("TOPRIGHT", anchor, "TOPLEFT", 1 - reach, -12)
		end
		tab:Show()
	elseif mode == "free" then
		tab:Hide()
		f.padSecond = nil
		S.dockK = nil
		if not HostCall("Rescale", f) then f:SetScale(1) end
		-- (Placed again only as it comes out on its own: one already out keeps a slide the window
		-- room gave it.)
		if before ~= "free" or not Up(f) then
			f:ClearAllPoints()
			local x, y = Spot.Get()
			if x then
				-- (The spot is in UIParent units; the offsets are in the window's own.)
				local k = f:GetScale() or 1
				f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x / k, y / k)
			else
				f:SetPoint("CENTER", UIParent, "CENTER", 320, 60)
			end
		end
		ShowWin(f)
	else
		tab:Hide()
		HideWin(f)
	end
	S.placing = false
	-- (Docked or undocked while it is out: it leaves or joins Daylight UI's window room now.)
	local docked = S.dockK ~= nil
	if docked ~= S.wasDocked and f:IsShown() then HostCall("Moved", f) end
	S.wasDocked = docked
	if f:IsShown() then Paint() end
end

-- The host comes, goes, moves and scales. No polling: while an Auction House is open or the
-- window hangs on one, the host windows' own calls say so (Daylight UI steps its windows by hand
-- with SetAlpha and SetPoint, DaylightUI\Windows\Feel.lua, drags them with StartMoving /
-- StopMovingOrSizing, Windows\Frame.lua Win.Drag, and scales them with SetScale; the game's
-- window is placed by the panel manager's SetPoint, and Daylight UI parks it with SetAlpha), as do
-- their OnShow / OnHide and the screen's scale events. Each one looks again (four reads; the window
-- is only placed again when one changed). While a host is dragged our window follows on its own:
-- it is anchored to it.
local watch = CreateFrame("Frame")
local seen = {}
local watching = false
local hostHooked = setmetatable({}, { __mode = "k" })

local function Watch()
	if not watching then return end
	local host = Host()
	local l, t, r, s
	if host then l, t, r, s = host:GetLeft(), host:GetTop(), host:GetRight(), host:GetEffectiveScale() end
	if host ~= seen.host or l ~= seen.l or t ~= seen.t or r ~= seen.r or s ~= seen.s then
		seen.host, seen.l, seen.t, seen.r, seen.s = host, l, t, r, s
		Place()
	end
	if not host and not ns.Market.IsOpen() then watching = false end
end

-- (Run from hooks on Daylight UI's, the game's and UIParent's own calls: an error here would go
-- back to whoever called SetPoint or SetAlpha and cut its work short, so it is caught.)
local function SafeWatch() pcall(Watch) end

local function HookHost(f)
	if type(f) ~= "table" or hostHooked[f] then return end
	hostHooked[f] = true
	local hook = rawget(_G, "hooksecurefunc")
	if hook then
		for _, method in ipairs({ "SetPoint", "SetAlpha", "SetScale", "StopMovingOrSizing" }) do
			if type(f[method]) == "function" then pcall(hook, f, method, SafeWatch) end
		end
	end
	if type(f.HookScript) == "function" then
		pcall(f.HookScript, f, "OnShow", SafeWatch)
		pcall(f.HookScript, f, "OnHide", SafeWatch)
	end
end

-- The windows to listen to, once each as they come to be (the game's is load-on-demand; Daylight
-- UI's is built when its module starts). UIParent too: its alpha counts in Visible().
local function HookHosts()
	HookHost(rawget(_G, "DaylightUIAuctionHouse"))
	HookHost(rawget(_G, "AuctionHouseFrame"))
	HookHost(UIParent)
end

-- A look now and a couple more just after (the windows build and start fading in after the
-- event); one-shot timers, nothing that keeps running.
local function StartWatch()
	if not Window.frame then return end
	watching = true
	HookHosts()
	Watch()
	C_Timer.After(0, function() HookHosts() Watch() end)
	C_Timer.After(0.3, function() HookHosts() Watch() end)
end

watch:SetScript("OnEvent", function(_, event)
	if event == "AUCTION_HOUSE_SHOW" then
		StartWatch()
	elseif event == "AUCTION_HOUSE_CLOSED" or event == "UI_SCALE_CHANGED" or event == "DISPLAY_SIZE_CHANGED" then
		-- (After the windows' own handlers have run: Market's flag, the close.)
		C_Timer.After(0, Watch)
	elseif event == "PLAYER_REGEN_ENABLED" then
		if S.stale and Shown() then Window.Refresh(S.force) end
	end
end)
pcall(watch.RegisterEvent, watch, "AUCTION_HOUSE_SHOW")
pcall(watch.RegisterEvent, watch, "AUCTION_HOUSE_CLOSED")
pcall(watch.RegisterEvent, watch, "UI_SCALE_CHANGED")
pcall(watch.RegisterEvent, watch, "DISPLAY_SIZE_CHANGED")
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
	-- (Closing, it still says it's shown: Up asks whether it is going.)
	if Window.frame and Up(Window.frame) then Window.Close() else Window.Open() end
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
