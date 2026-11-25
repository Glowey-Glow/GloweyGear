-- Glowey's Gear: the verdict where the player meets an item. One "Gear Advice" row on item
-- tooltips, and a small mark in a corner of bag and bank slots that hold an upgrade.
--
--   Marks.Kind(verdict, minGain)   -> "up" | "far" | "better" | "empty" | "small" | "same" |
--                                     "none" | "later" | "skill" | "prof" | nil (pure)
--   Marks.Text(verdict, minGain)   -> "+12%" | "Far Better" | "Better" | "Empty Slot" | nil, color
--                                     the short form: only for an upgrade (pure). The window's
--                                     rows use it too, so the two never disagree.
--   Marks.NOTE                     -> the sentence for an item with an effect the score leaves out
--   Marks.Advice(verdict, minGain) -> sentence, color, kind | nil     the tooltip row (pure)
--   Marks.Percent(pct)             -> "12" | "2.5"                     (pure)
--   Marks.SlotName(group)          -> the game's word for a Compare group ("Chest")
--   Marks.Refresh()                   forgets every answer kept and asks the bags to repaint
--   Marks.Register()                  (run at Daylight UI's "Login") the tooltip row and the bag mark
--
-- WHAT THE ROW SAYS (verdict = Compare.Evaluate's table, through ns.Verdict):
--   up      wearable now, better by at least Smallest Gain to Show   "+12% over your Chest"
--   far     better by more than a percent can say (over 200%)        "Far better than your Chest"
--   small   better, but by less than Smallest Gain to Show           the same words, plain color
--   better  better, with nothing worn to measure a percent against   "Better than your Chest"
--   empty   nothing is replaced: the slot is empty                    "Fills your empty Chest slot"
-- (The percent, its floor and the "far" cap are worked out once, in Compare.lua: THE PERCENT.
-- A slot holding an item that scores nothing is not "empty".)
-- The slot named is the one the item would go in: a dual wielder's one-hand weapon that is
-- better in the off hand reads "... your Off Hand".
-- An item with a Use, proc or Equip effect the score does not know gets a second line saying so
-- (Stats.Uncounted).
--   same    wearable now, no better than the best owned               "No better than your Chest"
--   none    wearable, but it has no stat the spec's weights count     "No stats your spec uses"
--   later   only the level is missing                                 "Wearable at level 40"
--   skill   a weapon type the class can train and has not             "Needs a weapon skill ..."
--   prof    a profession the item asks for and you lack (or too low)  "Needs Engineering (150)"
--   nil     not gear, or gear the class cannot wear: no row at all.
-- The bag mark shows for up, better and empty.
--
-- WHAT IS ALREADY WORN gets no row and no mark: the row is advice about what could be put on,
-- and an item compared with itself would only read "No better than your Chest". That also
-- covers the compare tooltip (the worn item shown beside a hovered one): Daylight UI runs the
-- "item" lines there too and "compare" on top (DUI:DaylightUI_Tooltip\Tooltip.lua:1939-1940;
-- DUI:DaylightUI\API.md:740-741), so one "item" registration reaches every item tooltip and a
-- second one for "compare" would have nothing to add.
--
-- COST. The tooltip callback runs on every fill of an item tooltip, several times a second while
-- one is up (DUI:DaylightUI_Tooltip\Tooltip.lua:1225-1230, :1932-1941; line numbers are Daylight UI 2.1.2's), and the bag widget once
-- per slot per repaint (DUI:DaylightUI_Bags\Plugins.lua:76-117). Both are a table lookup here:
-- the answer for a link is worked out once (ns.Verdict) and kept until the character, what they
-- own or a setting changes. An item whose data has not arrived is not kept: the tooltip fills
-- again by itself and the bags ask again when told nil (Plugins.lua:98-100, :110-117).
--
-- IN A FIGHT nothing is worked out: what is already kept still shows, anything else waits for
-- the fight's end. Nothing the engine reads is secret (Game.lua's header; it never calls the
-- character-sheet stat functions), so this is the plan's second safety, not a need.
--
-- Daylight UI is reached two ways. The tooltip row goes through its public API,
-- me.AddTooltipLines (DUI:DaylightUI\API.lua:1610-1629; API.md:730-750). The bag mark goes
-- through the Baganator-style calls its bags answer while Baganator itself is off
-- (DUI:DaylightUI_Bags\Plugins.lua:1-20, :172-207; the same call Daylight UI makes itself for
-- Pawn's arrow, :279-284): that is not part of DaylightUI.API, so it sits behind one guarded
-- adapter, BagShim(), and without it there is simply no bag mark.
--
-- luacheck: read globals CreateFrame C_Timer NUM_BAG_SLOTS geterrorhandler

local _, ns = ...
if ns.off then return end
local L = ns.L

local Marks = {}
ns.Marks = Marks

-- ---------------------------------------------------------------------------------------------
-- The words (pure: no game call, no setting read)
-- ---------------------------------------------------------------------------------------------
-- Our own colors; Daylight UI's ink takes their place at login (Colors() below).
local COLOR = {
	good = { 0.37, 0.83, 0.55 },   -- an upgrade
	soft = { 0.72, 0.70, 0.66 },   -- no upgrade
	wait = { 1.00, 0.76, 0.30 },   -- not yet
}
Marks.COLOR = COLOR
-- kind -> the color's name in COLOR; a kind with none takes the tooltip's own value color.
local COLOR_OF = { up = "good", far = "good", better = "good", empty = "good", same = "soft", none = "soft",
	later = "wait", skill = "wait", prof = "wait" }
local MARKED = { up = true, far = true, better = true, empty = true }
Marks.NOTE = L["Gear Advice does not count this item's special effect."]

-- Compare's group -> the game's word for the slot (a global string every client has in its own
-- language; ours when it is missing). Single source for the global names: the game's
-- GlobalStrings, which the UI source checkout does not carry.
local SLOT = {
	HEAD = { "INVTYPE_HEAD", "Head" }, NECK = { "INVTYPE_NECK", "Neck" },
	SHOULDER = { "INVTYPE_SHOULDER", "Shoulder" }, BACK = { "INVTYPE_CLOAK", "Back" },
	CHEST = { "INVTYPE_CHEST", "Chest" }, WRIST = { "INVTYPE_WRIST", "Wrist" },
	HANDS = { "INVTYPE_HAND", "Hands" }, WAIST = { "INVTYPE_WAIST", "Waist" },
	LEGS = { "INVTYPE_LEGS", "Legs" }, FEET = { "INVTYPE_FEET", "Feet" },
	FINGER = { "INVTYPE_FINGER", "Finger" }, TRINKET = { "INVTYPE_TRINKET", "Trinket" },
	MAINHAND = { "INVTYPE_WEAPONMAINHAND", "Main Hand" },
	OFFHAND = { "INVTYPE_WEAPONOFFHAND", "Off Hand" }, RANGED = { "INVTYPE_RANGED", "Ranged" },
}

function Marks.SlotName(group)
	local s = SLOT[group]
	if not s then return "" end
	if ns.GameText then return ns.GameText(s[1], s[2]) end
	return s[2]
end

-- A gain in percent as it is written: whole from 10 up, one decimal below ("2.5").
function Marks.Percent(pct)
	pct = tonumber(pct) or 0
	if pct >= 9.95 then return ("%d"):format(math.floor(pct + 0.5)) end
	local tenths = math.floor(pct * 10 + 0.5)
	if tenths < 1 then tenths = pct > 0 and 1 or 0 end   -- (a real gain never reads "+0%")
	if tenths % 10 == 0 then return ("%d"):format(tenths / 10) end
	return ("%d.%d"):format(math.floor(tenths / 10), tenths % 10)
end

function Marks.Kind(v, minGain)
	if type(v) ~= "table" or not v.group then return nil end
	if not v.usable then
		if v.reason == "level" then return "later" end
		if v.reason == "skill" then return "skill" end
		if v.reason == "profession" then return "prof" end
		return nil   -- armor or a weapon the class never wears, a tool, lighter armor than asked for
	end
	local gain = tonumber(v.gain) or 0
	if gain > 0 then
		-- (Empty first: a slot with nothing in it is said in words even when a percent exists.)
		if v.empty or (v.empty == nil and not v.replaces) then return "empty" end
		if v.pct == nil then return "better" end
		if v.far then return "far" end
		if v.pct >= (tonumber(minGain) or 0) then return "up" end
		return "small"
	end
	if (tonumber(v.score) or 0) <= 0 then return "none" end
	return "same"
end

-- The short form, for a list or a corner: only an upgrade has one.
function Marks.Text(v, minGain)
	local kind = Marks.Kind(v, minGain)
	if kind == "up" then return L["+%s%%"]:format(Marks.Percent(v.pct)), COLOR.good end
	if kind == "far" then return L["Far Better"], COLOR.good end
	if kind == "better" then return L["Better"], COLOR.good end
	if kind == "empty" then return L["Empty Slot"], COLOR.good end
	return nil
end

-- The tooltip row's sentence, its color (nil: the tooltip's own value color) and the kind.
function Marks.Advice(v, minGain)
	local kind = Marks.Kind(v, minGain)
	if not kind then return nil end
	local text
	if kind == "up" or kind == "small" then
		text = L["+%s%% over your %s"]:format(Marks.Percent(v.pct), Marks.SlotName(v.group))
	elseif kind == "far" then
		text = L["Far better than your %s"]:format(Marks.SlotName(v.group))
	elseif kind == "better" then
		text = L["Better than your %s"]:format(Marks.SlotName(v.group))
	elseif kind == "empty" then
		text = L["Fills your empty %s slot"]:format(Marks.SlotName(v.group))
	elseif kind == "same" then
		text = L["No better than your %s"]:format(Marks.SlotName(v.group))
	elseif kind == "none" then
		text = L["No stats your spec uses"]
	elseif kind == "later" then
		text = L["Wearable at level %d"]:format(tonumber(v.atLevel) or 0)
	elseif kind == "prof" then
		-- (The game's own way of saying it, "Requires Engineering (150)", in our words.)
		if type(v.needName) == "string" and tonumber(v.needRank) then
			text = L["Needs %s (%d)"]:format(v.needName, v.needRank)
		else
			text = L["Needs a profession skill you do not have"]
		end
	else
		text = L["Needs a weapon skill you have not trained"]
	end
	return text, COLOR[COLOR_OF[kind]], kind
end

-- ---------------------------------------------------------------------------------------------
-- One answer per link, kept until something changes
-- ---------------------------------------------------------------------------------------------
-- Three views of a link: on a tooltip (worn gear says nothing; an item that is in the bags is
-- compared with the rest of what is owned), in a bag (the same, known from the bag's number
-- alone) and in the bank (not owned in the plan's sense: compared with everything worn and
-- carried). An entry is { kind, text, color, mark }, or false for "nothing to say".
local tipCache, bagCache, bankCache = {}, {}, {}
local pendingSeen = false     -- an answer was missing because item data had not arrived
local missed = false          -- something was asked for in a fight and not worked out
local stats = { computed = 0 }
Marks.stats = stats           -- (for /gear debug and the tests)

-- Which keys are worn and which are carried, read off the context's pools (Compare.lua:
-- ctx.pools[group] = { { rec, score, slot }, ... }, slot nil for a carried item). Built once
-- per context.
local indexOf, wornKeys, carriedKeys
local function Index(ctx)
	if indexOf == ctx then return end
	indexOf, wornKeys, carriedKeys = ctx, {}, {}
	if type(ctx) ~= "table" or type(ctx.pools) ~= "table" then return end
	for _, pool in pairs(ctx.pools) do
		for i = 1, #pool do
			local e = pool[i]
			if e.slot then wornKeys[e.rec.key] = true else carriedKeys[e.rec.key] = true end
		end
	end
end

local function Judge(link, carried)
	stats.computed = stats.computed + 1
	local v, why = ns.Verdict(link, carried)
	if not v then
		if why == "pending" then
			pendingSeen = true
			return nil
		end
		return false
	end
	local minGain = ns.Get("minGain")
	local text, color, kind = Marks.Advice(v, minGain)
	if not kind then return false end
	-- (ns.Verdict has just read the item, so this is the kept record. Only asked for what is
	-- shown: counting a tooltip's effect lines costs more than the stat call.)
	local rec = ns.Stats.Of(link)
	local note = rec ~= nil and ns.Stats.Uncounted(rec) > 0
	return { kind = kind, text = text, color = color, mark = MARKED[kind] or false, note = note or false }
end

-- view = "tip" | "bag" | "bank". Returns an entry, false, or nil for "cannot tell yet".
local function Lookup(view, link)
	local cache = (view == "tip" and tipCache) or (view == "bag" and bagCache) or bankCache
	local hit = cache[link]
	if hit ~= nil then return hit end
	if ns.Game.InCombat() then
		missed = true
		return false
	end
	local carried = view == "bag"
	if view == "tip" then
		local ctx = ns.Context()
		if ctx then
			Index(ctx)
			local key = ns.Stats.Key(link)
			if key and wornKeys[key] then
				cache[link] = false
				return false
			end
			carried = key ~= nil and carriedKeys[key] == true
		end
	end
	local entry = Judge(link, carried)
	if entry ~= nil then cache[link] = entry end
	return entry
end
Marks.Lookup = Lookup

-- ---------------------------------------------------------------------------------------------
-- The bags (Daylight UI's Baganator-style calls)
-- ---------------------------------------------------------------------------------------------
-- The one place that touches them. Only Daylight UI's own stand-in counts (it marks itself
-- with DaylightUI = true: DUI:DaylightUI_Bags\Plugins.lua:206-207); Baganator itself, were it
-- on, answers calls of the same names with rules we have not read. nil when anything is not as
-- read, and then there is no bag mark.
local function BagShim()
	local B = rawget(_G, "Baganator")
	if type(B) ~= "table" or B.DaylightUI ~= true then return nil end
	local api = B.API
	if type(api) ~= "table" then return nil end
	if type(api.RegisterCornerWidget) ~= "function" or type(api.RequestItemButtonsRefresh) ~= "function" then return nil end
	return api
end

-- Daylight UI's four corner names (Plugins.lua:25).
local CORNERS = { "top_left", "top_right", "bottom_left", "bottom_right" }
local IS_CORNER = { top_left = true, top_right = true, bottom_left = true, bottom_right = true }
-- One mark shows per corner, the lowest number first (Plugins.lua:90-100, :166-170). The marks
-- Daylight UI hooks up itself all sit at 1 (Pawn, Can I Mog It, Simple Item Levels: :257, :283,
-- :303); an upgrade is the rarer news, so ours goes before them in the corner the player picked.
local PRIORITY = 0
local SIZE = 11

local function Corner()
	local c = ns.Get("bagCorner")
	if IS_CORNER[c] then return c end
	return ns.DEFAULTS.bagCorner
end

-- The mark: a plus sign in our green on a dark one a pixel wider, drawn from plain color (no
-- art file). Texture:SetColorTexture, DOC SimpleTextureBaseAPIDocumentation.lua:403;
-- Frame:CreateTexture, DOC SimpleFrameAPIDocumentation.lua:131. Drawn the first time a slot
-- shows it, so the three corners not in use cost one empty frame each.
local function Draw(frame)
	frame.drawn = true
	local g = COLOR.good
	local function bar(layer, w, h, r, gr, b, a)
		local t = frame:CreateTexture(nil, "OVERLAY", nil, layer)
		t:SetColorTexture(r, gr, b, a)
		t:SetSize(w, h)
		t:SetPoint("CENTER", frame, "CENTER", 0, 0)
		return t
	end
	bar(1, 5, SIZE + 2, 0, 0, 0, 0.85)
	bar(1, SIZE + 2, 5, 0, 0, 0, 0.85)
	bar(2, 3, SIZE, g[1], g[2], g[3], 1)
	bar(2, SIZE, 3, g[1], g[2], g[3], 1)
end

-- onInit(button): our frame for that slot; Daylight UI parents and places it (Plugins.lua:50-73).
local function InitMark(button)
	local f = CreateFrame("Frame", nil, button)
	f:SetSize(SIZE, SIZE)
	return f
end

-- onUpdate(frame, details) for one corner: true shows the mark, false hides it, nil means "ask
-- again in a moment" (Plugins.lua:95-117). details: itemLink, bagID, slotID (:85-88).
-- One widget is registered per corner and only the corner picked in the options ever answers
-- true: the calls have no way to move or drop a widget, and this way Bag Corner works at once.
local function UpdaterFor(corner)
	return function(frame, details)
		if corner ~= Corner() then return false end
		if ns.Get("enabled") == false or ns.Get("bagMarks") == false then return false end
		-- (Another addon marks bag upgrades and the player chose it: Overlap.lua.)
		if ns.Overlap and ns.Overlap.Yields("bags") then return false end
		local link = type(details) == "table" and details.itemLink or nil
		if type(link) ~= "string" then return false end
		-- (The backpack and the four bags are "carried", as Game.BagLinks reads them: Game.lua.)
		local bag = details.bagID
		local carried = type(bag) == "number" and bag >= 0 and bag <= (NUM_BAG_SLOTS or 4)
		local entry = Lookup(carried and "bag" or "bank", link)
		if entry == nil then return nil end
		if not (entry and entry.mark) then return false end
		if not frame.drawn then Draw(frame) end
		return true
	end
end

-- ---------------------------------------------------------------------------------------------
-- Refreshing
-- ---------------------------------------------------------------------------------------------
local shim                -- BagShim()'s answer once the widgets are registered
local queued, afterFight = false, false

-- One repaint a moment after the last request of a burst, and never in a fight.
local function Repaint()
	if not shim or queued then return end
	queued = true
	-- C_Timer.After: DOC UITimerDocumentation.lua:11.
	C_Timer.After(0.1, function()
		queued = false
		if ns.Game.InCombat() then
			afterFight = true
			return
		end
		pcall(shim.RequestItemButtonsRefresh)
	end)
end

local watchers = {}       -- other addons' "your answers may have changed" (GloweyGearAPI.Watch)

function Marks.Refresh()
	if ns.Perf then ns.Perf.Count("bags") end
	tipCache, bagCache, bankCache = {}, {}, {}
	indexOf, wornKeys, carriedKeys = nil, nil, nil
	pendingSeen = false
	Repaint()
	for _, fn in ipairs(watchers) do pcall(fn) end
end

-- ---------------------------------------------------------------------------------------------
-- For other addons: GloweyGearAPI
-- ---------------------------------------------------------------------------------------------
-- The one thing another addon may ask of Glowey's Gear (Glowey's Recipes marks the recipes whose
-- item would be an upgrade). A global table, so nothing of ours has to be read or copied:
--
--   GloweyGearAPI.Upgrade(link) -> true, text, { r, g, b }   an upgrade for this character now
--                                                            (the bag mark's rule: up, far,
--                                                            better, empty), with the tooltip
--                                                            row's words ("+12% over your Chest")
--                               -> false                     not one (or Gear is switched off,
--                                                            or a fight is on: nothing is
--                                                            worked out in one)
--                               -> nil                       can't tell yet (the item's data has
--                                                            not arrived): ask again after Watch
--   GloweyGearAPI.Watch(fn)        fn() runs whenever the answers may have changed (gear put on,
--                                  a level, a setting, item data arriving). Keep it cheap.
--
--   GloweyGearAPI.Compare(tooltip, link) -> true when shown   (version 2) beside `tooltip`, which
--                                  already shows the item, Gear's comparison: the piece it would
--                                  replace (Equipped / In Your Bags) and the stat changes, as in
--                                  Upgrades for Sale (CompareTip.lua). Nothing for an item that
--                                  isn't gear, nor in a fight. It goes with that
--                                  tooltip; GloweyGearAPI.HideCompare() takes it away sooner.
--
-- link: an item link or "item:12345". The item is judged as one you don't own yet. The answer
-- for a link is kept, as the bags' is, so asking for every row of a list each repaint is fine.
local function PublicUpgrade(link)
	if type(link) ~= "string" or ns.Get("enabled") == false then return false end
	local entry = Lookup("bank", link)
	if entry == nil then return nil end
	if not entry or not entry.mark then return false end
	return true, entry.text, entry.color
end
-- (Worked out on hover only: one verdict, the same call the tooltip row makes.)
local function PublicCompare(tooltip, link)
	local Tip = ns.CompareTip
	if not Tip then return false end
	if type(tooltip) ~= "table" or type(link) ~= "string" or ns.Game.InCombat() then
		Tip.Hide()
		return false
	end
	local v = ns.Verdict(link, false)
	local rep = v and v.replaces or nil
	if type(rep) ~= "table" or type(rep.link) ~= "string" then
		Tip.Hide()
		return false
	end
	-- (The verdict's table is reused by the next one: what is needed is copied out.)
	Tip.Show(tooltip, { link = link, replaces = { link = rep.link } })
	return true
end
rawset(_G, "GloweyGearAPI", {
	version = 2,
	Upgrade = function(link)
		local ok, up, text, color = pcall(PublicUpgrade, link)
		if not ok then return false end
		return up, text, color
	end,
	Watch = function(fn)
		if type(fn) ~= "function" then return false end
		watchers[#watchers + 1] = fn
		return true
	end,
	Compare = function(tooltip, link)
		local ok, shown = pcall(PublicCompare, tooltip, link)
		return ok and shown == true
	end,
	HideCompare = function()
		if ns.CompareTip then pcall(ns.CompareTip.Hide) end
	end,
})

local function InUse()
	if ns.Get("enabled") == false then return false end
	-- (Another addon asks for answers too: GloweyGearAPI.Watch.)
	return ns.Get("tooltips") ~= false or (shim ~= nil and ns.Get("bagMarks") ~= false) or #watchers > 0
end

-- What is owned, as one string: the worn and carried keys per group, in the pools' own (sorted)
-- order. Item data arriving for anything fires "OwnedChanged" several times a second while the
-- Auction House is browsed; when what is owned reads the same and no answer was waiting for
-- data, everything kept is still right and the bags are left alone.
local parts = {}
local function Signature(ctx)
	if type(ctx) ~= "table" or type(ctx.pools) ~= "table" then return "none" end
	local n = 1
	parts[1] = tostring(ctx.pending or 0)
	for _, group in ipairs(ns.Compare.GROUPS) do
		local pool = ctx.pools[group]
		for i = 1, pool and #pool or 0 do
			n = n + 1
			parts[n] = (pool[i].slot or "b") .. "=" .. pool[i].rec.key
		end
		n = n + 1
		parts[n] = "/"
	end
	local two = ctx.pools.TWOHAND
	for i = 1, two and #two or 0 do
		n = n + 1
		parts[n] = (two[i].slot or "b") .. "=" .. two[i].rec.key
	end
	return table.concat(parts, ",", 1, n)
end

local lastSig
local function OwnedChanged()
	if not InUse() then
		-- (Switched off: nothing shows, so nothing is repainted; the switch itself did that.)
		lastSig = nil
		tipCache, bagCache, bankCache = {}, {}, {}
		indexOf, wornKeys, carriedKeys = nil, nil, nil
		pendingSeen = false
		return
	end
	local sig = Signature(ns.Context())
	if sig == lastSig and not pendingSeen then return end
	lastSig = sig
	Marks.Refresh()
end

local function WhoChanged()
	lastSig = nil
	Marks.Refresh()
end

local MINE = { enabled = true, minGain = true, bestArmor = true, tooltips = true, bagMarks = true, bagCorner = true,
	yieldBags = true, yieldTips = true }
local function Setting(path)
	if path ~= nil and not MINE[path] then return end
	lastSig = nil
	Marks.Refresh()
end

-- The fight is over: what was put off in it.
local function FightOver()
	if not (afterFight or missed) then return end
	afterFight, missed = false, false
	Marks.Refresh()
end

-- ---------------------------------------------------------------------------------------------
-- The tooltip row
-- ---------------------------------------------------------------------------------------------
-- fn(lines, data) for kind "item": data.link is the item's link, or nil when the game keeps it
-- secret (DUI:DaylightUI_Tooltip\Tooltip.lua:1346-1354); lines.Row(label, value, color) is a
-- label and its value in both looks, Rich and Simple, color = { r, g, b } (:1246-1255, :1267;
-- API.md:747), lines.Text(text, color) a wrapped sentence (API.md:748), and a line already on
-- the tooltip is not added twice (:1225-1230). Line numbers are Daylight UI 2.1.2's.
-- ROW OR LINE. Daylight UI's Rich card for an item is at most 290 wide, 258 inside its padding
-- (DUI:DaylightUI_Tooltip\Rich\Panel.lua:34, :25). A row keeps its VALUE whole at the right
-- edge and cuts the LABEL to what is left, 16 px of gap taken off (:766-777): beside "Needs a
-- weapon skill you have not trained" nothing of "Gear Advice" was left, as seen in play. A
-- sentence (lines.Text) wraps to the card instead (Panel.lua:508-512; API.md:748). So:
--   * label + verdict fit in the row's room: lines.Row(label, verdict), as before;
--   * they do not: the label on a row of its own (no value), the verdict as a sentence under
--     it, in the verdict's color. Nothing is cut in either case, in either look (Simple shows
--     the same two pieces as two plain lines).
-- Widths are measured with Daylight UI's own body text where it can be made (API.Text), else
-- estimated per character (5.8 px for Latin, 7 for other alphabets, 12 for Chinese and Korean).
Marks.ROW_ROOM = 236   -- 258 inside the card, less the 16 px gap, less a little for rounding

local measurer, measured = nil, {}
local function estimate(text)
	local w = 0
	for i = 1, #text do
		local b = text:byte(i)
		if b < 128 then
			w = w + 5.8
		elseif b >= 0xE3 and b < 0xF0 then
			w = w + 12        -- (the first byte of a Chinese, Japanese or Korean character)
		elseif b >= 0xC0 then
			w = w + 7         -- (the first byte of any other character; the bytes after it count nothing)
		end
	end
	return w
end

function Marks.Width(text)
	text = tostring(text or "")
	local known = measured[text]
	if known then return known end
	local w
	local API = ns.API
	if measurer == nil then
		measurer = false
		if API and type(API.Text) == "function" then
			local ok, fs = pcall(API.Text, CreateFrame("Frame"), "body", "LEFT")
			if ok and type(fs) == "table" and type(fs.GetStringWidth) == "function" then measurer = fs end
		end
	end
	if measurer then
		local ok, got = pcall(function()
			measurer:SetText(text)
			return measurer:GetStringWidth()
		end)
		if ok and type(got) == "number" and got > 0 then w = got end
	end
	w = w or estimate(text)
	measured[text] = w
	return w
end

-- Whether a label and its value fit side by side in the card's row. measure: a width
-- function, for the tests.
function Marks.Fits(label, value, measure)
	measure = measure or Marks.Width
	return measure(label) + measure(value) <= Marks.ROW_ROOM
end

local function OnItemTooltip(lines, data)
	if ns.Get("enabled") == false or ns.Get("tooltips") == false then return end
	if ns.Overlap and ns.Overlap.Yields("tips") then return end
	local link = type(data) == "table" and data.link or nil
	-- (A quest reward's tooltip can come without a link: found among the page's rewards.)
	if type(link) ~= "string" and type(data) == "table" and ns.Quest and ns.Quest.LinkFor then
		link = ns.Quest.LinkFor(data.itemID)
	end
	if type(link) ~= "string" or type(lines) ~= "table" then return end
	local entry = Lookup("tip", link)
	if not entry then return end
	local row = lines.Row or lines.Line   -- (Row is API 1.12; Line is the same piece since 1.7)
	if type(row) == "function" then
		local label = L["Gear Advice"]
		if type(lines.Text) ~= "function" or Marks.Fits(label, entry.text) then
			row(label, entry.text, entry.color)
		else
			-- (Too long for the row: the label alone, the verdict as a sentence under it.)
			row(label, "")
			lines.Text(entry.text, entry.color)
		end
	end
	-- (lines.Text: a wrapped sentence in both looks, API.md's tooltip pieces table.)
	if entry.note and type(lines.Text) == "function" then lines.Text(Marks.NOTE, COLOR.soft) end
	-- (The reward Quest.lua picked, while its quest page is open.)
	local Q = ns.Quest
	if Q and type(lines.Text) == "function" then
		local best = Q.Best()
		if best and best == ns.Stats.Key(link) then lines.Text(L["Best reward of this quest for you."], COLOR.good) end
	end
end
Marks.OnItemTooltip = OnItemTooltip

-- Daylight UI's ink for good, soft and "not yet", so the row matches its other rows
-- (API.Colors: DUI:DaylightUI\API.lua:1028-1036). Ours stay when it has none.
local function Colors()
	local API = ns.API
	if not (API and type(API.Colors) == "function") then return end
	local ok, ink = pcall(API.Colors)
	if not ok or type(ink) ~= "table" then return end
	local function take(name, role)
		local c = ink[role]
		if type(c) == "table" and type(c[1]) == "number" and type(c[2]) == "number" and type(c[3]) == "number" then
			local mine = COLOR[name]
			mine[1], mine[2], mine[3] = c[1], c[2], c[3]
		end
	end
	take("good", "GOOD")
	take("soft", "LABEL")
	take("wait", "WARN")
end

local registered = false
function Marks.Register()
	if registered then return end
	registered = true
	Colors()
	-- (And again after every look change, Host.OnStyle: the rows are written from COLOR each time.)
	local H = ns.Host
	if type(H) == "table" and type(H.OnStyle) == "function" then H.OnStyle(Colors) end
	local me = ns.me
	if me and type(me.AddTooltipLines) == "function" then
		local ok, err = pcall(me.AddTooltipLines, "item", OnItemTooltip)
		if not ok then geterrorhandler()(err) end
	end
	-- (With Daylight UI's tooltips off, or another addon drawing them: the same row, written
	-- into the game's own tooltip. TipFallback.lua)
	if ns.TipFallback then ns.TipFallback(OnItemTooltip) end
	-- The bags: Daylight UI's stand-in exists from the moment its bags load, which can be after
	-- this plugin, so it is looked for at "Login" (every addon is loaded by then).
	local api = BagShim()
	if api then
		local okAll = true
		for _, corner in ipairs(CORNERS) do
			local ok = pcall(api.RegisterCornerWidget, L["Gear Advice"], "daylightgear_" .. corner,
				UpdaterFor(corner), InitMark, { corner = corner, priority = PRIORITY })
			okAll = okAll and ok
		end
		if okAll then shim = api end
	end
	Marks.shim = shim ~= nil
end

ns.On("WhoChanged", WhoChanged)
ns.On("OwnedChanged", OwnedChanged)
-- Item data came in for something: only worth a look when an answer of ours was waiting for
-- data (a bag slot told "ask again" runs out of asks after a moment: DUI Plugins.lua:27-28).
ns.On("ItemsArrived", function()
	if pendingSeen and InUse() then Marks.Refresh() end
end)
ns.On("Setting", Setting)

if ns.me and type(ns.me.On) == "function" then ns.me.On("Login", Marks.Register) end

-- PLAYER_REGEN_ENABLED: DOC UnitDocumentation.lua:3893.
local watcher = CreateFrame("Frame")
pcall(watcher.RegisterEvent, watcher, "PLAYER_REGEN_ENABLED")
watcher:SetScript("OnEvent", FightOver)
