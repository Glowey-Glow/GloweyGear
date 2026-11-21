-- Glowey's Gear: when another addon does the same thing.
--
-- Other addons also mark upgrades in the bags or add upgrade lines to item tooltips. The
-- owner's standing rule for such overlaps: ask once, our side by default, every choice can be
-- changed back. One question per SURFACE, not per addon:
--     Upgrade Marks on Bags      (setting yieldBags: false = Gear Advice has them)
--     Upgrade Advice on Tooltips (setting yieldTips: false = Gear Advice has it)
-- "Ours" shows ours and, where the other addon has a switch of its own that an outside addon
-- may flip, turns its copy off (its value from before is kept and put back when the choice is
-- reversed). "Theirs" hides ours on that surface and puts their switches back.
--
--   Overlap.Rivals(surface)   -> { { addon, name, can = bool (it has a switch we may flip) }, ... } loaded ones
--   Overlap.Yields(surface)   -> true when ours stands down there ("bags" | "tips")
--   Overlap.Apply()           makes the other addons' switches follow the two settings
--   Overlap.Show(all)         the question window (all: also what was answered before)
--   Overlap.Unasked()         -> the surfaces with a rival not asked about yet
--
-- WHO, AND WHAT CAN BE SWITCHED (each read in the addon's own files where its license lets
-- them be read; nothing of theirs is edited, hooked or copied):
--   * Polestar (GPL-3): its settings "gear.bagArrows" (the upgrade arrow on bag items) and
--     "gear.tooltip" (its gear line on tooltips) are registered defaults of its own (Polestar\
--     Gear\Gear.lua:104-110; read at Gear\Bags.lua:58), and its table is the global `Polestar`
--     with Get(path) and Set(path, value) (Core\Init.lua:11, :966, :1002). The owner's Addon
--     Skins hands settings of Polestar's over the same way (DaylightAddonSkins\Packs\
--     Polestar.lua:458-470). So: switched.
--   * Pawn: Daylight UI itself draws Pawn's arrow in its bags while Pawn is loaded (DaylightUI_
--     Bags\Plugins.lua:272-284, corner top left, priority 1). Pawn is not installed here and
--     no switch of its own could be verified, so nothing of Pawn's is touched: with "ours"
--     both show (ours in its own corner).
--   * Forever Leveling BiS: All Rights Reserved and not installed here; no switch verified.
--     Nothing of it is touched: with "ours" both show.
--   * CheapUpgrades: known by its folder name only. Its files were not opened for this plugin
--     and none of its settings is read or written: with "ours" both show. It is listed for
--     tooltips only: Daylight UI's bags are not among the bag windows other addons of its kind
--     hook, by the owner's study of the overlap (cheapupgrades-in-essentials.md, section 4.3).
-- An addon that marks bag upgrades through Daylight UI's corner-widget call without being on
-- this list cannot be told from any other corner widget (the call takes a free name:
-- DaylightUI_Bags\Plugins.lua:172), so it is not detected.
--
-- The window follows the owner's Addon Skins choice window (DaylightAddonSkins\Choices.lua, All
-- Rights Reserved, the owner's own): same widgets, same wording of the switch (on = the other
-- addon keeps its own), same waiting for Daylight UI's first-login windows and for the other
-- Daylight plugins' guides (_G.DaylightGuides).
--
-- luacheck: read globals CreateFrame UIParent C_Timer GetTime InCombatLockdown UISpecialFrames C_AddOns

local _, ns = ...
if ns.off or not ns.ok then return end

local Overlap = {}
ns.Overlap = Overlap

local API, L = ns.API, ns.L

local SURFACES = { "bags", "tips" }
local SETTING = { bags = "yieldBags", tips = "yieldTips" }
local RIVALS = {
	{ addon = "Polestar", name = "Polestar", bags = "gear.bagArrows", tips = "gear.tooltip" },
	{ addon = "Pawn", name = "Pawn", bags = true, tips = true },
	{ addon = "ForeverLevelingBiS", name = "Forever Leveling BiS", bags = true, tips = true },
	{ addon = "CheapUpgrades", name = "CheapUpgrades", tips = true },
}
Overlap.RIVALS = RIVALS

local function Loaded(addon)
	local A = rawget(_G, "C_AddOns")
	if type(A) ~= "table" or type(A.IsAddOnLoaded) ~= "function" then return false end
	local ok, on = pcall(A.IsAddOnLoaded, addon)
	return ok and on == true
end
Overlap.Loaded = Loaded

-- Polestar's own Get and Set, or nil when they are not as read.
local function Polestar()
	local P = rawget(_G, "Polestar")
	if type(P) ~= "table" or type(P.Get) ~= "function" or type(P.Set) ~= "function" then return nil end
	return P
end

-- The other addon's switch for a surface: get(), set(value); nil when it has none we may use.
local function Switch(rival, surface)
	local path = rival[surface]
	if type(path) ~= "string" then return nil end
	if rival.addon == "Polestar" then
		local P = Polestar()
		if not P then return nil end
		return function()
			local ok, v = pcall(P.Get, path)
			if ok then return v end
		end, function(value) pcall(P.Set, path, value) end
	end
	return nil
end

function Overlap.Rivals(surface)
	local out = {}
	for _, rival in ipairs(RIVALS) do
		if rival[surface] and Loaded(rival.addon) then
			out[#out + 1] = { addon = rival.addon, name = rival.name, can = Switch(rival, surface) ~= nil }
		end
	end
	return out
end

function Overlap.Yields(surface)
	if ns.Get(SETTING[surface]) ~= true then return false end
	return #Overlap.Rivals(surface) > 0
end

local function State()
	local db = ns.DB()
	if type(db.overlap) ~= "table" then db.overlap = {} end
	local o = db.overlap
	if type(o.asked) ~= "table" then o.asked = {} end
	if type(o.took) ~= "table" then o.took = {} end
	return o
end

function Overlap.Apply()
	local o = State()
	for _, surface in ipairs(SURFACES) do
		local ours = ns.Get(SETTING[surface]) ~= true
		for _, rival in ipairs(RIVALS) do
			local get, set = nil, nil
			if rival[surface] and Loaded(rival.addon) then get, set = Switch(rival, surface) end
			if get then
				local id = rival.addon .. ":" .. surface
				-- (Only an answered question switches anything of another addon's.)
				if ours and o.asked[id] then
					local now = get()
					if now ~= false then
						if o.took[id] == nil then o.took[id] = now == nil and true or now end
						set(false)
					end
				elseif not ours and o.took[id] ~= nil then
					set(o.took[id])
					o.took[id] = nil
				end
			end
		end
	end
end

function Overlap.Unasked()
	local o = State()
	local out = {}
	for _, surface in ipairs(SURFACES) do
		for _, rival in ipairs(Overlap.Rivals(surface)) do
			if not o.asked[rival.addon .. ":" .. surface] then
				out[#out + 1] = surface
				break
			end
		end
	end
	return out
end

-- The player's answer for a surface: theirs = true when the other addons keep it.
function Overlap.Choose(surface, theirs)
	local o = State()
	for _, rival in ipairs(Overlap.Rivals(surface)) do o.asked[rival.addon .. ":" .. surface] = true end
	if type(ns.SetSetting) == "function" and (ns.Get(SETTING[surface]) == true) ~= (theirs and true or false) then
		ns.SetSetting(SETTING[surface], theirs and true or false)
	end
	Overlap.Apply()
end

-- The sentence under a row: who the others are, and what "ours" does about each.
function Overlap.What(surface)
	local can, cannot = {}, {}
	for _, rival in ipairs(Overlap.Rivals(surface)) do
		if rival.can then can[#can + 1] = rival.name else cannot[#cannot + 1] = rival.name end
	end
	local parts = {}
	if #can > 0 then parts[#parts + 1] = L["%s: its own is switched off."]:format(table.concat(can, ", ")) end
	if #cannot > 0 then parts[#parts + 1] = L["%s: has no switch we can use, so both show."]:format(table.concat(cannot, ", ")) end
	return table.concat(parts, " ")
end

-- ---------------------------------------------------------------------------------------------
-- The window
-- ---------------------------------------------------------------------------------------------
local W, PAD, ROW = 520, 18, 58
local LABEL = { bags = L["Upgrade Marks on Bags"], tips = L["Upgrade Advice on Tooltips"] }
local frame
local rows = {}
local GUIDE_KEY = "DaylightGearOverlap"
local DAYLIGHT_DIALOGS = { "DaylightUIInstaller", "DaylightUITour", "DaylightUITourAsk", "DaylightUIAsk",
	"DaylightUIQuestieChoice", "DaylightAddonSkinsChoices" }

local function SetBusy(on)
	local busy = rawget(_G, "DaylightGuides")
	if type(busy) ~= "table" then return end
	busy[GUIDE_KEY] = on and true or nil
end

local function DaylightBusy()
	for _, name in ipairs(DAYLIGHT_DIALOGS) do
		local f = rawget(_G, name)
		if type(f) == "table" and f.IsShown and f:IsShown() and (f:GetAlpha() or 0) > 0.05 then return true end
	end
	local busy = rawget(_G, "DaylightGuides")
	if type(busy) == "table" then
		for name, on in pairs(busy) do
			if on and name ~= GUIDE_KEY then return true end
		end
	end
	return false
end

local function Ink(fs, role)
	local ok, colors = pcall(API.Colors)
	local c = ok and type(colors) == "table" and colors[role]
	if type(c) == "table" then fs:SetTextColor(c[1], c[2], c[3]) end
end

local function Build()
	for _, name in ipairs({ "Skin", "Text", "Button", "Close", "Switch", "Colors" }) do
		if type(API[name]) ~= "function" then return nil end
	end
	local f = CreateFrame("Frame", "DaylightGearOverlap", UIParent)
	f:SetSize(W, 240)
	f:SetPoint("CENTER", 0, 60)
	f:SetFrameStrata("DIALOG")
	f:SetToplevel(true)
	f:SetClampedToScreen(true)
	f:EnableMouse(true)
	f:SetMovable(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop", f.StopMovingOrSizing)
	f:Hide()
	API.Skin(f, { window = true })
	f:HookScript("OnShow", function() SetBusy(true) end)
	f:HookScript("OnHide", function() SetBusy(false) end)
	if type(UISpecialFrames) == "table" then table.insert(UISpecialFrames, "DaylightGearOverlap") end

	f.title = API.Text(f, "title", "LEFT")
	f.title:SetPoint("TOPLEFT", PAD, -PAD)
	f.title:SetText("Glowey's Gear")
	Ink(f.title, "VALUE")

	f.sub = API.Text(f, "body", "LEFT")
	f.sub:SetPoint("TOPLEFT", f.title, "BOTTOMLEFT", 0, -8)
	f.sub:SetWidth(W - PAD * 2)
	f.sub:SetText(L["Another addon of yours also points out gear upgrades. Pick who does it in each place: on = the other addon keeps its own, off = Gear Advice does it. You can change this any time on the options page."])
	Ink(f.sub, "TEXT")

	local close = API.Close(f, function() f:Hide() end)
	close:SetPoint("TOPRIGHT", -10, -10)

	for i, surface in ipairs(SURFACES) do
		local r = CreateFrame("Frame", nil, f)
		r:SetHeight(ROW)
		r:EnableMouse(true)
		r.surface = surface
		r.name = API.Text(r, "body", "LEFT")
		r.name:SetPoint("TOPLEFT", 4, -6)
		r.name:SetText(LABEL[surface])
		r.what = API.Text(r, "small", "LEFT")
		r.what:SetPoint("TOPLEFT", r.name, "BOTTOMLEFT", 0, -3)
		r.what:SetWidth(W - PAD * 2 - 70)
		r.switch = API.Switch(r)
		r.switch:SetPoint("RIGHT", -4, 0)
		r.switch:SetScript("OnClick", function(self) self.SetOn(not self.on) end)
		r:SetScript("OnMouseUp", function(self, button) if button == "LeftButton" then self.switch:Click() end end)
		rows[i] = r
	end

	local apply = API.Button(f, L["Apply"], 26)
	apply:SetSize(150, 26)
	apply:SetPoint("BOTTOMLEFT", PAD, PAD)
	if type(API.MainButton) == "function" then pcall(API.MainButton, apply, true) end
	apply:SetScript("OnClick", function()
		for _, r in ipairs(rows) do
			if r:IsShown() then Overlap.Choose(r.surface, r.switch.on == true) end
		end
		f:Hide()
	end)
	f.apply = apply
	local later = API.Button(f, L["Ask Me Later"], 26)
	later:SetSize(150, 26)
	later:SetPoint("BOTTOMRIGHT", -PAD, PAD)
	later:SetScript("OnClick", function() f:Hide() end)

	-- A controller: the two switches and the two buttons are D-pad stops, B closes.
	local P = type(ns.Pad) == "table" and ns.Pad or nil
	if P and type(P.Popup) == "function" then P.Popup(f, function() f:Hide() end) end
	return f
end

-- all = true: every surface with a rival (as chosen now); otherwise only what was not asked yet.
function Overlap.Show(all)
	if InCombatLockdown() then return false end
	local want = {}
	for _, surface in ipairs(all and SURFACES or Overlap.Unasked()) do
		if #Overlap.Rivals(surface) > 0 then want[surface] = true end
	end
	if not next(want) then
		if all then ns.Print(L["None of your addons points out gear upgrades the way Gear Advice does."]) end
		return false
	end
	frame = frame or Build()
	if not frame then return false end
	local y = PAD + (frame.title:GetStringHeight() or 20) + 8 + (frame.sub:GetStringHeight() or 40) + 14
	for _, r in ipairs(rows) do
		if want[r.surface] then
			r:ClearAllPoints()
			r:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -y)
			r:SetPoint("RIGHT", frame, "RIGHT", -PAD, 0)
			Ink(r.name, "VALUE")
			r.what:SetText(Overlap.What(r.surface))
			Ink(r.what, "TEXT")
			r.switch.SetOn(ns.Get(SETTING[r.surface]) == true)
			r:SetHeight(math.max(ROW, 6 + (r.name:GetStringHeight() or 14) + 3 + (r.what:GetStringHeight() or 12) + 10))
			r:Show()
			y = y + r:GetHeight()
		else
			r:Hide()
		end
	end
	frame:SetHeight(y + 58 + 4)
	frame:Show()
	local P = type(ns.Pad) == "table" and ns.Pad or nil
	if P and type(P.On) == "function" and P.On() and type(P.Settle) == "function" then P.Settle(frame.apply) end
	return true
end

-- At login: the other addons' switches follow the settings; then the question, once the
-- screen is free (Daylight UI's own first-login windows and the other Daylight plugins'
-- guides go first, and the screen must have been free for a moment).
local FIRST, AGAIN, QUIET = 8, 3, 6
if ns.me and type(ns.me.On) == "function" then
	ns.me.On("Login", function()
		-- (Twice: some addons read their settings a little after login.)
		C_Timer.After(1, Overlap.Apply)
		C_Timer.After(6, Overlap.Apply)
		local waited, freeSince
		local function ask()
			if frame and frame:IsShown() then return end
			if #Overlap.Unasked() == 0 then return end
			if InCombatLockdown() or DaylightBusy() then
				waited, freeSince = true, nil
				C_Timer.After(AGAIN, ask)
				return
			end
			if waited then
				local now = GetTime()
				freeSince = freeSince or now
				if now - freeSince < QUIET then
					C_Timer.After(AGAIN, ask)
					return
				end
			end
			Overlap.Show(false)
		end
		C_Timer.After(FIRST, ask)
	end)
end

-- A change on the options page is an answer too.
ns.On("Setting", function(path)
	local surface = (path == "yieldBags" and "bags") or (path == "yieldTips" and "tips") or nil
	if not surface then return end
	local o = State()
	for _, rival in ipairs(Overlap.Rivals(surface)) do o.asked[rival.addon .. ":" .. surface] = true end
	Overlap.Apply()
end)
