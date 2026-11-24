-- Glowey's Gear: the player's own stat weights, and the options page that edits them.
--
--   ns.MyWeights.Get(class, spec)          -> the sparse table of the player's own, or nil
--   ns.MyWeights.Set(class, spec, stat, v) -> v = nil puts the stat back to Glowey's recommendation
--   ns.MyWeights.RevertSpec(class, spec)   -> every stat of one spec back to the recommendation
--   ns.MyWeights.RevertAll()               -> every spec of every class back
--   ns.MyWeights.Count(class, spec)        -> how many stats of the spec are the player's own
--   ns.MyWeights.Signature(class, spec)    -> them as one string (Alert.lua), "" when none
--   ns.MyWeights.Page()                    -> the "Stat Weights" options page (Core.lua adds it)
--   ns.MyWeights.Parse(text)               -> a typed weight as a number, nil when it is not one
--   ns.MyWeights.Format(n)                 -> a weight as a box shows it ("0.55", "1", "12.5")
--   ns.MyWeights.Display(stat)             -> the edited spec's weight for stat as shown, and true
--                                             when it is the player's own
--   ns.MyWeights.Commit(stat, text)        -> saves a typed weight; false when it is not a number
--
-- Saved in GloweyGearDB.weights (account-wide, as the weights are per class and spec, not per
-- character):
--   weights = { [<CLASS>] = { [<SPEC KEY>] = { [<stat key>] = number } } }
-- Only what the player set is kept (sparse): a stat they never touched has no entry and keeps
-- following the shipped data (Data/Weights.lua), so a weight correction in a later version still
-- reaches it. Spec.Effective lays these over the recommendation (Spec.lua, "The player's own
-- weights"). A weight set by hand is used at every level; the shipped ones slide by level.
--
-- The weights are a grid of number boxes, two or three across as the page's width allows (one
-- row of the page, of type "custom": build(row), update(row), height(row), as Daylight UI 2.2.5's
-- registry takes one, DaylightUI\Options\Registry.lua:18, :75-76, drawn by Options\Widgets.lua:
-- 3590-3601, and as Host.lua draws it without Daylight UI, I.CustomRow). Each box shows the
-- weight; one the player set is in the accent with a small revert arrow beside it, the others
-- plain. Typing a number and pressing Enter (or leaving the box) saves it, Escape puts the box
-- back as it was, Tab goes on to the next box (Shift+Tab back); anything but a number of 0 or more
-- with up to four decimals is refused and the box shows the weight again. The boxes are Daylight
-- UI's own (API.Input, its Widgets.Input) or Host.lua's (API.Input: drawn in each look, Blizzard
-- Style's the client's input box art).
-- The custom row is not in Daylight UI's API.md, so the page takes it only when Host.CustomRows()
-- says Daylight UI 2.2.5 or later is there (or Host.lua draws the window); otherwise, and if the
-- grid fails to build, it keeps one slider per stat as before (with Daylight UI's own reset arrow:
-- Options\Widgets.lua:3783-3819).
-- A controller (Daylight UI's, DaylightUI\Pad.lua): the game's D-pad stops on every edit box and
-- button by itself (Blizzard_GamepadSmartNavigation\Utility.lua:263-276); A on a box picks it up,
-- and left and right then step the weight as Daylight UI's own slider rows do (Pad.HoldSides,
-- Pad.lua:316-351; Options\Widgets.lua:1085-1121), A or B puts it down. Without Daylight UI the
-- game's controller does not reach the settings window (it lists only windows it opened itself).
-- Loaded before Core.lua; everything of Core's is looked up when it is needed.
--
-- luacheck: read globals C_Timer C_Texture GameTooltip IsShiftKeyDown InCombatLockdown CreateFrame geterrorhandler

local _, ns = ...
local L = ns.L
local Spec = ns.Spec

local MyWeights = {}
ns.MyWeights = MyWeights

-- ---------------------------------------------------------------------------------------------
-- The stats the editor lists, in the order it lists them
-- ---------------------------------------------------------------------------------------------
-- key, name, how the label says its unit, slider top and step, and scale: the slider shows
-- weight x scale ("Armor, per 100": a weight of 0.005 per armor point shows as 0.5), so the
-- small per-point weights of armor, health and mana are readable with two decimals. Tops are
-- above twice the largest shipped value of each stat (Data/Weights.lua); a typed number is kept
-- inside them. The *_SPEED keys are left out: nothing reads a weapon's speed yet, so their
-- weights multiply 0 (design/data-format.md, 3.6).
local PCT, HUNDRED = "pct", "hundred"
local LIST = {
	{ "STR", L["Strength"], nil, 3, 0.01 },
	{ "AGI", L["Agility"], nil, 3, 0.01 },
	{ "STA", L["Stamina"], nil, 3, 0.01 },
	{ "INT", L["Intellect"], nil, 3, 0.01 },
	{ "SPI", L["Spirit"], nil, 3, 0.01 },
	{ "AP", L["Attack Power"], nil, 2, 0.01 },
	{ "RAP", L["Ranged Attack Power"], nil, 2, 0.01 },
	{ "FERAL_AP", L["Attack Power in Forms"], nil, 2, 0.01 },
	{ "SPELL_DMG", L["Spell Damage"], nil, 3, 0.01 },
	{ "HEAL", L["Healing"], nil, 3, 0.01 },
	{ "SPELL_DMG_ARCANE", L["Arcane Damage"], nil, 3, 0.01 },
	{ "SPELL_DMG_FIRE", L["Fire Damage"], nil, 3, 0.01 },
	{ "SPELL_DMG_FROST", L["Frost Damage"], nil, 3, 0.01 },
	{ "SPELL_DMG_HOLY", L["Holy Damage"], nil, 3, 0.01 },
	{ "SPELL_DMG_NATURE", L["Nature Damage"], nil, 3, 0.01 },
	{ "SPELL_DMG_SHADOW", L["Shadow Damage"], nil, 3, 0.01 },
	{ "HIT", L["Hit"], PCT, 60, 0.1 },
	{ "CRIT", L["Critical Strike"], PCT, 60, 0.1 },
	{ "SPELL_HIT", L["Spell Hit"], PCT, 60, 0.1 },
	{ "SPELL_CRIT", L["Spell Critical Strike"], PCT, 60, 0.1 },
	{ "HASTE", L["Haste"], PCT, 60, 0.1 },
	{ "EXPERTISE", L["Expertise"], PCT, 60, 0.1 },
	{ "ARMOR_PEN", L["Armor Penetration"], PCT, 10, 0.05 },
	{ "MH_DPS", L["Main Hand Weapon DPS"], nil, 20, 0.05 },
	{ "OH_DPS", L["Off Hand Weapon DPS"], nil, 10, 0.05 },
	{ "RANGED_DPS", L["Ranged Weapon DPS"], nil, 10, 0.05 },
	{ "ARMOR", L["Armor"], HUNDRED, 40, 0.05 },
	{ "HEALTH", L["Health"], HUNDRED, 20, 0.05 },
	{ "MANA", L["Mana"], HUNDRED, 10, 0.05 },
	{ "DODGE", L["Dodge"], PCT, 10, 0.05 },
	{ "PARRY", L["Parry"], PCT, 10, 0.05 },
	{ "BLOCK", L["Block"], PCT, 10, 0.05 },
	{ "BLOCK_VALUE", L["Block Value"], nil, 3, 0.01 },
	{ "DEFENSE", L["Defense Skill"], nil, 3, 0.01 },
	{ "MP5", L["Mana per 5 Seconds"], nil, 5, 0.01 },
	{ "HP5", L["Health per 5 Seconds"], nil, 5, 0.01 },
	{ "SPELL_PEN", L["Spell Penetration"], nil, 3, 0.01 },
	{ "RES_FIRE", L["Fire Resistance"], nil, 3, 0.01 },
	{ "RES_NATURE", L["Nature Resistance"], nil, 3, 0.01 },
	{ "RES_FROST", L["Frost Resistance"], nil, 3, 0.01 },
	{ "RES_SHADOW", L["Shadow Resistance"], nil, 3, 0.01 },
	{ "RES_ARCANE", L["Arcane Resistance"], nil, 3, 0.01 },
}
MyWeights.LIST = LIST
local SCALE = { [HUNDRED] = 100 }
local NAME, BY = {}, {}
for _, s in ipairs(LIST) do NAME[s[1]] = s[2]; BY[s[1]] = s end
MyWeights.NAME = NAME

-- ---------------------------------------------------------------------------------------------
-- Storage
-- ---------------------------------------------------------------------------------------------
local function All()
	local db = ns.DB and ns.DB()
	if not db then return nil end
	if type(db.weights) ~= "table" then db.weights = {} end
	return db.weights
end

local function finite(n)
	return type(n) == "number" and n == n and n ~= math.huge and n ~= -math.huge
end

function MyWeights.Get(class, spec)
	local all = All()
	local c = all and type(class) == "string" and all[class]
	local t = type(c) == "table" and c[spec]
	return type(t) == "table" and t or nil
end
Spec.GetCustom = MyWeights.Get

function MyWeights.Count(class, spec)
	local t, n = MyWeights.Get(class, spec), 0
	if t then
		for k, v in pairs(t) do
			if ns.Stats.KEYS[k] and finite(v) and v >= 0 then n = n + 1 end
		end
	end
	return n
end

-- The player's own weights of a spec as one string ("" when none), for Alert.lua: a change of
-- them changes the picks with nothing new for sale.
function MyWeights.Signature(class, spec)
	local t = MyWeights.Get(class, spec)
	if not t then return "" end
	local parts = {}
	for k, v in pairs(t) do parts[#parts + 1] = k .. "=" .. tostring(v) end
	table.sort(parts)
	return table.concat(parts, ",")
end

local function AnyAtAll()
	local all = All()
	for _, c in pairs(all or {}) do
		if type(c) == "table" then
			for _, t in pairs(c) do
				if type(t) == "table" and next(t) ~= nil then return true end
			end
		end
	end
	return false
end

-- The options window, when it is Daylight UI's: its rows are drawn again (a setter of our own
-- writes past DUI:Set, so no SettingChanged redraws the page; Daylight UI's own toggles do the
-- same, DUI Options\Widgets.lua:2562-2567). DUI.OptionsPanel is not in API.md, so it is guarded.
-- Without Daylight UI, Host.lua repaints its window after every set by itself. One redraw a
-- moment after a burst (a slider being dragged sets at every step).
local panelSoon = false
local function RefreshPanel()
	if ns.standalone or panelSoon then return end
	panelSoon = true
	C_Timer.After(0.1, function()
		panelSoon = false
		local D = ns.DUI
		local P = type(D) == "table" and rawget(D, "OptionsPanel")
		if type(P) == "table" and type(P.IsShown) == "function" and type(P.Refresh) == "function" then
			pcall(function()
				if P.IsShown() then P.Refresh() end
			end)
		end
	end)
end

local function Changed()
	Spec.Touched()
	if ns.WeightsChanged then ns.WeightsChanged() end
	RefreshPanel()
end

function MyWeights.Set(class, spec, stat, value)
	if not ns.Stats.KEYS[stat] or not Spec.Info(class, spec) then return false end
	local all = All()
	if not all then return false end
	if value ~= nil then
		if not finite(value) or value < 0 then return false end
		-- (Six places: a box takes four, and a weight shown per 100 points is stored per point.)
		value = tonumber(("%.6f"):format(value))
		all[class] = type(all[class]) == "table" and all[class] or {}
		all[class][spec] = type(all[class][spec]) == "table" and all[class][spec] or {}
		all[class][spec][stat] = value
	else
		local c = all[class]
		local t = type(c) == "table" and c[spec]
		if type(t) ~= "table" or t[stat] == nil then return true end
		t[stat] = nil
		if next(t) == nil then c[spec] = nil end
		if next(c) == nil then all[class] = nil end
	end
	Changed()
	return true
end

function MyWeights.RevertSpec(class, spec)
	local all = All()
	local c = all and all[class]
	if type(c) ~= "table" or c[spec] == nil then return end
	c[spec] = nil
	if next(c) == nil then all[class] = nil end
	Changed()
end

function MyWeights.RevertAll()
	local db = ns.DB and ns.DB()
	if not db then return end
	db.weights = {}
	Changed()
end

-- ---------------------------------------------------------------------------------------------
-- The spec being edited
-- ---------------------------------------------------------------------------------------------
-- The one gear is scored for, until the player picks another in "Spec to Edit" (kept for the
-- session only: the editor opens on the spec in use next time).
local editing

local function Class() return ns.Game and ns.Game.Class() end
local function Level()
	local level = ns.Game and ns.Game.Level()
	return tonumber(level) or Spec.MAX_LEVEL
end

local function Edited()
	local class = Class()
	if not class or not Spec.HasClass(class) then return nil end
	if editing and Spec.Info(class, editing) then return class, editing end
	local who = ns.Who and ns.Who()
	if who and who.class == class then return class, who.spec end
	-- (No one scored yet, the first moments after login: the spec Auto or the player's pick gives.)
	return class, Spec.Resolve(class, Spec.GetChoice(), nil, Spec.GetLast())
end
MyWeights.Edited = Edited

local function Recommended(stat)
	local class, spec = Edited()
	if not class then return 0 end
	local w = Spec.Weights(class, spec, Level())
	return w and w[stat] or 0
end

local function Own(stat)
	local class, spec = Edited()
	local t = class and MyWeights.Get(class, spec)
	local v = t and t[stat]
	if finite(v) and v >= 0 then return v end
	return nil
end

-- "Spec to Edit": the class's specs, by the names the Spec picker uses (Core.lua's ns.SpecValues;
-- real tables, filled again before they are read, as both option windows walk them with pairs).
local editValues, editOrder = {}, {}
local function FillSpecs()
	local class = Class()
	for k in pairs(editValues) do editValues[k] = nil end
	for i = #editOrder, 1, -1 do editOrder[i] = nil end
	if not class then return end
	local names = ns.SpecValues or {}
	for _, key in ipairs(Spec.List(class)) do
		editOrder[#editOrder + 1] = key
		editValues[key] = names[key] or key
	end
end

-- The stats the editor shows for the edited spec: those its recommendation names at any level,
-- those the player set, and every stat with Show Every Stat on.
local showAll = false
local named, namedFor = {}, nil
local function Shown(stat)
	local class, spec = Edited()
	if not class then return false end
	if showAll then return true end
	local id = class .. ":" .. tostring(spec)
	if namedFor ~= id then
		named, namedFor = Spec.Named(class, spec), id
	end
	return named[stat] == true or Own(stat) ~= nil
end

-- The line that says which weights are the player's own.
local function Status()
	local class, spec = Edited()
	if not class then return L["No stat weights for your class yet, so there is no gear advice."] end
	local name = editValues[spec] or (ns.SpecValues and ns.SpecValues[spec]) or spec
	local t = MyWeights.Get(class, spec)
	local mine = {}
	for _, s in ipairs(LIST) do
		if t and t[s[1]] ~= nil then mine[#mine + 1] = s[2] end
	end
	if #mine == 0 then return L["Every weight for %s is Glowey's recommendation."]:format(name) end
	return L["Your own weights for %s: %s. Every other weight is Glowey's recommendation."]:format(name,
		table.concat(mine, ", "))
end
MyWeights.Status = Status


-- ---------------------------------------------------------------------------------------------
-- Typed weights
-- ---------------------------------------------------------------------------------------------
local DECIMALS = 4

local function Label(s)
	if s[3] == PCT then return L["%s, per 1%%"]:format(s[2]) end
	if s[3] == HUNDRED then return L["%s, per 100"]:format(s[2]) end
	return s[2]
end

-- A number of 0 or more with up to four decimals ("12", "0.55", ".5", "1,25" with a comma as the
-- decimal mark); nil for anything else (a sign, a letter, a second point, a fifth decimal).
function MyWeights.Parse(text)
	if type(text) ~= "string" then return nil end
	text = text:gsub("^%s+", ""):gsub("%s+$", ""):gsub(",", ".")
	local whole, frac = text:match("^(%d*)%.?(%d*)$")
	if not whole or (whole == "" and frac == "") or #frac > DECIMALS then return nil end
	local n = tonumber(text)
	if not finite(n) or n < 0 then return nil end
	return n
end

-- Up to four decimals, no trailing zeros: 0.55, 1, 12.5.
function MyWeights.Format(n)
	if not finite(n) then return "" end
	local text = ("%." .. DECIMALS .. "f"):format(n)
	if text:find(".", 1, true) then text = text:gsub("0+$", ""):gsub("%.$", "") end
	if text == "-0" then text = "0" end
	return text
end
local Format = MyWeights.Format

-- The edited spec's weight for stat as its box shows it (per 100 points for armor, health and
-- mana), and true when it is the player's own.
function MyWeights.Display(stat)
	local s = BY[stat]
	if not s then return "", false end
	local scale = SCALE[s[3]] or 1
	local own = Own(stat)
	if own ~= nil then return Format(own * scale), true end
	return Format(Recommended(stat) * scale), false
end

-- Glowey's recommendation for stat, as the box would show it.
local function RecommendedText(stat)
	local s = BY[stat]
	return Format(Recommended(stat) * (s and SCALE[s[3]] or 1))
end

-- Saves a typed weight for the edited spec. Typing the recommendation's own number puts the stat
-- back on the recommendation (so it follows the data again); the same number as now changes
-- nothing. False when text is not a weight (the box then shows the weight again).
function MyWeights.Commit(stat, text)
	local s = BY[stat]
	local v = s and MyWeights.Parse(text)
	if v == nil then return false end
	local class, spec = Edited()
	if not class then return false end
	local scale = SCALE[s[3]] or 1
	local typed, own = Format(v), Own(stat)
	if typed == RecommendedText(stat) then
		if own == nil then return true end
		return MyWeights.Set(class, spec, stat, nil)
	end
	if own ~= nil and Format(own * scale) == typed then return true end
	return MyWeights.Set(class, spec, stat, tonumber(typed) / scale)
end

-- ---------------------------------------------------------------------------------------------
-- The grid of boxes (a custom row: see the top of the file)
-- ---------------------------------------------------------------------------------------------
-- Sizes, in pixels: a box, the revert arrow and the gaps round them, the least room a label gets,
-- the gap between columns, a line of the grid (Daylight UI's own row height, Widgets.lua:15) and
-- the inset from the card's edge (its W.PAD, Widgets.lua:17; none in Host.lua's window).
local GRID = { BOX = 64, BOX_H = 22, ARROW = 16, ARROW_GAP = 4, LABEL_GAP = 8, LABEL_MIN = 80,
	COL_GAP = 24, MAX_COLS = 3, LINE = 28, EDGE = 4, PAD = 14, MAX_LINES = 2 }
MyWeights.GRID = GRID
local CONTROLS = GRID.LABEL_GAP + GRID.ARROW + GRID.ARROW_GAP + GRID.BOX
-- Daylight UI's undo arrow is its own art; this is the game's (common-icon-undo, as its Cooldown
-- Viewer settings and catalog shop use it: Blizzard_CooldownViewer\CooldownViewerSettings.lua:1218,
-- Blizzard_CatalogShop\Blizzard_CatalogShop_Elements.xml:521), or the older refresh arrow
-- (Blizzard_GroupFinder\Mainline\LFGList.xml:1137).
local UNDO_ATLAS, UNDO_FILE = "common-icon-undo", "Interface\\Buttons\\UI-RefreshButton"

local gridOn = false   -- the page has the grid, and it built

-- The open options page drawn again: Host.lua's window at once (its rows only repaint after a
-- change made through them), Daylight UI's a moment later (Changed's RefreshPanel).
local function Redraw()
	if ns.standalone and ns.Host and ns.Host.RefreshOptions then ns.Host.RefreshOptions() end
end

-- Daylight UI's controller kit (its Pad: inside, not in API.md), only when its options are the
-- window and its HoldSides / FreeSides are as read (Pad.lua:316-351).
local function PadKit()
	if ns.standalone then return nil end
	local D = ns.DUI
	local P = type(D) == "table" and rawget(D, "Pad")
	if type(P) == "table" and type(P.HoldSides) == "function" and type(P.FreeSides) == "function"
		and type(P.On) == "function" then return P end
	return nil
end

local function Ease(e) if type(e.Ease) == "function" then pcall(e.Ease) end end

local function Paint(cell)
	local e = cell.box
	local text, mine = MyWeights.Display(cell.stat)
	if not e:HasFocus() then e:SetText(text) end
	if ns.Host and ns.Host.Ink then ns.Host.Ink(e, mine and "pop" or "TEXT") end
	cell.revert:SetShown(mine)
end

local function Tip(cell, owner)
	if not (ns.Host and ns.Host.Tip) then return end
	local text, mine = MyWeights.Display(cell.stat)
	local lines = { L["Glowey's recommendation: %s"]:format(RecommendedText(cell.stat)) }
	if mine then lines[2] = L["Your weight: %s"]:format(text) end
	ns.Host.Tip(owner or cell.box, cell.name, lines,
		L["Type a number of 0 or more, up to 4 decimals, then press Enter. Escape cancels; Tab goes to the next box."])
end
local function Untip() if GameTooltip then GameTooltip:Hide() end end

-- Saves what a box holds (or shows the weight again when it is not one).
local function Save(cell)
	local ok = MyWeights.Commit(cell.stat, cell.box:GetText() or "")
	Paint(cell)
	if ok then Redraw() end
	return ok
end

-- One controller step: left or right by the old slider's step, never under 0.
local function Step(cell, dir)
	local step = BY[cell.stat][5]
	local now = MyWeights.Parse((MyWeights.Display(cell.stat))) or 0
	local to = math.max(0, math.floor((now + dir * step) / step + 0.5) * step)
	if MyWeights.Commit(cell.stat, Format(to)) then
		Paint(cell)
		Redraw()
	end
end

local function PutDown(cell)
	local e = cell.box
	if not e.padEditing then return end
	e.padEditing = nil
	local P = PadKit()
	if P then pcall(P.FreeSides, cell.padStep) end
	Ease(e)
end

-- Tab and Shift+Tab: the next (or the previous) box shown, round to the first.
local function TabOn(row, cell, e)
	local order, at = row.order or {}, nil
	for i, c in ipairs(order) do if c == cell then at = i end end
	e:ClearFocus()
	if not at then return end
	local back = IsShiftKeyDown and IsShiftKeyDown()
	local nextCell = order[(at - 1 + (back and -1 or 1)) % #order + 1]
	if nextCell and nextCell.box:IsVisible() then nextCell.box:SetFocus() end
end

local function Wire(row, cell, e)
	e:HookScript("OnEditFocusGained", function(self)
		self.cancel = nil
		self.before = self:GetText() or ""
		self:HighlightText()
	end)
	e:HookScript("OnEditFocusLost", function(self)
		self:HighlightText(0, 0)
		if self.cancel then
			self.cancel = nil
			Paint(cell)
			return
		end
		Save(cell)
	end)
	e:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
	e:SetScript("OnEscapePressed", function(self)
		self.cancel = true
		self:SetText(self.before or "")
		self:ClearFocus()
	end)
	e:SetScript("OnTabPressed", function(self) TabOn(row, cell, self) end)
	e:HookScript("OnEnter", function() Tip(cell) end)
	e:HookScript("OnLeave", Untip)
	-- A controller (Daylight UI's): selecting shows the hover, A picks the weight up for left and
	-- right (the game calls these through its own wrapper: SmartNavigation.lua:1645-1652).
	cell.padStep = function(dir) Step(cell, dir) end
	e.OnSmartNavSelect = function()
		e.padOn = true
		Ease(e)
		Tip(cell)
	end
	e.OnSmartNavDeselect = function()
		e.padOn = nil
		PutDown(cell)
		Ease(e)
		Untip()
	end
	e.OnSmartNavClick = function()
		local P = PadKit()
		if not P or (InCombatLockdown and InCombatLockdown()) then
			e:SetFocus()
			return true
		end
		if e.padEditing then
			PutDown(cell)
			return true
		end
		e.padEditing = true
		Ease(e)
		pcall(P.HoldSides, cell.padStep, function() PutDown(cell) end)
		return true
	end
end

local function Arrow(cell, e)
	local r = CreateFrame("Button", nil, cell)
	r:SetSize(GRID.ARROW, GRID.ARROW)
	r:SetPoint("RIGHT", e, "LEFT", -GRID.ARROW_GAP, 0)
	r.icon = r:CreateTexture(nil, "ARTWORK")
	r.icon:SetAllPoints()
	local atlas = false
	if C_Texture and type(C_Texture.GetAtlasInfo) == "function" and C_Texture.GetAtlasInfo(UNDO_ATLAS) then
		atlas = pcall(r.icon.SetAtlas, r.icon, UNDO_ATLAS, false)
	end
	if not atlas then r.icon:SetTexture(UNDO_FILE) end
	r.icon:SetAlpha(0.7)
	r:SetScript("OnEnter", function(self)
		self.icon:SetAlpha(1)
		if ns.Host and ns.Host.Tip then
			ns.Host.Tip(self, L["Revert to Glowey's Recommendation"],
				L["Glowey's recommendation: %s"]:format(RecommendedText(cell.stat)))
		end
	end)
	r:SetScript("OnLeave", function(self)
		self.icon:SetAlpha(0.7)
		Untip()
	end)
	r:SetScript("OnClick", function()
		local class, spec = Edited()
		if class and MyWeights.Set(class, spec, cell.stat, nil) then
			Paint(cell)
			Redraw()
		end
	end)
	return r
end

local function MakeCell(row, s)
	local api = ns.API
	local cell = CreateFrame("Frame", nil, row)
	cell.stat, cell.name = s[1], Label(s)
	cell:SetHeight(GRID.LINE)
	cell.label = api.Text(cell, "body", "LEFT")
	cell.label:SetJustifyV("MIDDLE")
	cell.label:SetWordWrap(true)
	cell.label:SetText(cell.name)
	cell.label:SetPoint("LEFT", cell, "LEFT", 0, 0)
	if ns.Host and ns.Host.Ink then ns.Host.Ink(cell.label, "TEXT") end
	local e = api.Input(cell, { justify = "CENTER", maxLetters = 9, height = GRID.BOX_H })
	e:SetSize(GRID.BOX, GRID.BOX_H)
	e:SetJustifyH("CENTER")
	e:SetPoint("RIGHT", cell, "RIGHT", 0, 0)
	cell.box = e
	Wire(row, cell, e)
	cell.revert = Arrow(cell, e)
	return cell
end

-- How wide the row is: the card's width with Daylight UI (an anchored width is only worked out on
-- the next frame: its card description note, Widgets.lua), the row's own in Host.lua's window.
local function RowWidth(row)
	local parent = row:GetParent()
	local w = ns.standalone and row:GetWidth() or (parent and parent:GetWidth())
	if type(w) ~= "number" or w <= 0 then w = row:GetWidth() end
	if type(w) ~= "number" or w <= 0 then w = 600 end
	return w
end

-- The lines a label takes at its width (it wraps; never cut short).
local function Lines(row, fs)
	local one = row.lineH
	if not one then
		row.probe:SetText("Hg")
		one = row.probe:GetStringHeight()
		if type(one) ~= "number" or one <= 0 then one = 14 end
		row.lineH = one
	end
	local h = fs:GetStringHeight()
	if type(h) ~= "number" or h <= 0 then return 1 end
	return math.max(1, math.floor(h / one + 0.5))
end

-- Columns for inner px: of up to three, the count that keeps every label on two lines or fewer
-- and makes the grid shortest (fewer columns on a tie); one when none does. linesAt(i, labelW):
-- how many lines the i-th shown label takes labelW wide; lineH: a line of text's height.
function MyWeights.Columns(inner, count, linesAt, lineH)
	lineH = lineH or 14
	local best, bestH
	for n = 1, GRID.MAX_COLS do
		local colW = math.floor((inner - (n - 1) * GRID.COL_GAP) / n)
		local labelW = colW - CONTROLS
		if labelW >= GRID.LABEL_MIN then
			local h, fits = 0, true
			for first = 1, count, n do
				local most = 1
				for i = first, math.min(first + n - 1, count) do
					local lines = linesAt(i, labelW)
					if lines > GRID.MAX_LINES then fits = false end
					if lines > most then most = lines end
				end
				h = h + math.max(GRID.LINE, math.ceil(most * lineH) + 10)
			end
			if fits and (not bestH or h < bestH) then best, bestH = n, h end
		end
	end
	return best or 1
end

-- Lays the shown boxes out across the row; returns the row's height.
local function Layout(row)
	local pad = ns.standalone and 0 or GRID.PAD
	local inner = math.max(GRID.LABEL_MIN + CONTROLS, RowWidth(row) - 2 * pad)
	local shown = {}
	for _, cell in ipairs(row.cells) do
		if Shown(cell.stat) then shown[#shown + 1] = cell else cell:Hide() end
	end
	row.order = shown
	if not row.lineH then Lines(row, row.probe) end   -- (a line's height, measured once)
	local n = MyWeights.Columns(inner, #shown, function(i, labelW)
		shown[i].label:SetWidth(labelW)
		return Lines(row, shown[i].label)
	end, row.lineH)
	local colW = math.floor((inner - (n - 1) * GRID.COL_GAP) / n)
	local labelW = math.max(1, colW - CONTROLS)
	local y = GRID.EDGE
	for first = 1, #shown, n do
		local last, most = math.min(first + n - 1, #shown), 1
		for i = first, last do
			shown[i].label:SetWidth(labelW)
			most = math.max(most, Lines(row, shown[i].label))
		end
		local h = math.max(GRID.LINE, math.ceil(most * (row.lineH or 14)) + 10)
		for i = first, last do
			local cell = shown[i]
			cell:ClearAllPoints()
			cell:SetPoint("TOPLEFT", row, "TOPLEFT", pad + (i - first) * (colW + GRID.COL_GAP), -y)
			cell:SetSize(colW, h)
			cell:Show()
		end
		y = y + h
	end
	row.columns = n
	return y + GRID.EDGE
end

local function GridItem()
	return {
		type = "custom", label = "",
		hidden = function() return not gridOn or Edited() == nil end,
		build = function(row)
			local ok, err = pcall(function()
				row.probe = ns.API.Text(row, "body", "LEFT")
				row.probe:Hide()
				row.cells = {}
				for _, s in ipairs(LIST) do row.cells[#row.cells + 1] = MakeCell(row, s) end
			end)
			if not ok then
				-- (The sliders come back in its place at the next redraw.)
				gridOn = false
				row.cells = nil
				if geterrorhandler then geterrorhandler()(err) end
				C_Timer.After(0, function()
					if ns.standalone then Redraw() else RefreshPanel() end
				end)
			end
		end,
		update = function(row)
			if not row.cells then return end
			for _, cell in ipairs(row.cells) do Paint(cell) end
		end,
		height = function(row)
			if not row.cells then return 1 end
			return Layout(row)
		end,
	}
end

-- ---------------------------------------------------------------------------------------------
-- The page
-- ---------------------------------------------------------------------------------------------
-- (Without the grid: one slider per stat, as before.)
local function SliderRow(s)
	local stat, scale = s[1], SCALE[s[3]] or 1
	return {
		type = "slider", label = Label(s), min = 0, max = s[4], step = s[5], free = true,
		hidden = function() return gridOn or not Shown(stat) end,
		get = function()
			local v = Own(stat)
			if v == nil then v = Recommended(stat) end
			return v * scale
		end,
		set = function(v)
			v = tonumber(v)
			if not v then return false end
			local class, spec = Edited()
			if not class then return false end
			v = v / scale
			-- (Back on the recommendation: no longer the player's own, so it follows the data again.)
			if math.abs(v - Recommended(stat)) < 1e-6 then return MyWeights.Set(class, spec, stat, nil) end
			return MyWeights.Set(class, spec, stat, v)
		end,
		default = function() return Recommended(stat) * scale end,
	}
end

local function NoData() return Edited() == nil end

-- Whether this window takes the grid (Host.lua: always without Daylight UI, with it from 2.2.5).
local function CanGrid()
	local H = ns.Host
	if type(H) ~= "table" or type(ns.API) ~= "table" or type(ns.API.Input) ~= "function" then return false end
	local ok, yes = pcall(function() return H.CustomRows and H.CustomRows() end)
	return ok and yes == true
end
MyWeights.CanGrid = CanGrid

function MyWeights.Page()
	gridOn = CanGrid()
	local items = {
		{ type = "dropdown", label = L["Spec to Edit"], values = editValues, order = editOrder,
		  desc = L["Whose weights this page shows. It starts on the spec gear is scored for."],
		  hidden = function()
			FillSpecs()
			return NoData()
		  end,
		  get = function()
			FillSpecs()
			local _, spec = Edited()
			return spec
		  end,
		  set = function(value)
			local class = Class()
			if not class or not Spec.Info(class, value) then return false end
			editing = value
			RefreshPanel()
			return true
		  end },
		{ type = "text", label = Status },
		{ type = "toggle", label = L["Show Every Stat"],
		  desc = L["Also lists the stats this spec's recommendation leaves at nothing, so you can give them a weight."],
		  hidden = NoData,
		  get = function() return showAll end,
		  set = function(value)
			showAll = value == true
			RefreshPanel()
			return true
		  end },
	}
	if gridOn then items[#items + 1] = GridItem() end
	for _, s in ipairs(LIST) do items[#items + 1] = SliderRow(s) end

	return { id = "weights", label = L["Stat Weights"],
	  desc = L["Set your own stat weights, or keep Glowey's recommendation."],
	  groups = {
		{ label = L["Your Stat Weights"],
		  desc = L["What each stat is worth to the spec, with its main stat near 1. A weight you set is used at every level; the others follow Glowey's recommendation for your level."],
		  items = items },
		{ label = L["Glowey's Recommendation"], items = {
			{ type = "button", label = L["Revert This Spec"], text = L["Revert"], confirm = true,
			  desc = L["Puts every weight of the spec you are editing back to Glowey's recommendation."],
			  disabled = function()
				local class, spec = Edited()
				return not class or MyWeights.Get(class, spec) == nil
			  end,
			  func = function()
				local class, spec = Edited()
				if class then MyWeights.RevertSpec(class, spec) end
			  end },
			{ type = "button", label = L["Revert Every Spec"], text = L["Revert All"], confirm = true,
			  desc = L["Puts the weights of every spec of every class back to Glowey's recommendation."],
			  disabled = function() return not AnyAtAll() end,
			  func = function() MyWeights.RevertAll() end },
		} },
	  } }
end
