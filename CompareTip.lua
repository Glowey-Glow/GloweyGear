-- Glowey's Gear: the comparison beside an item of the Upgrades for Sale list. Hovering a row shows
-- the game's tooltip for the item for sale (Window.lua); this file stands a second tooltip beside
-- it with the piece Gear says it replaces (the row's `replaces`, Compare.Evaluate: the best you
-- own for that place, worn or in your bags; for rings and trinkets the weaker of the two), headed
-- "Equipped" or "In Your Bags" as the game heads its own, with the game's own list of the stat
-- changes the swap makes. A row that fills an empty slot has nothing to compare and shows none.
--
--   CompareTip.Show(main, row)   main = GameTooltip, already showing the row's item
--   CompareTip.Place(main)       stands it beside main again (the row's UpdateTooltip, 5 times a second)
--   CompareTip.Hide()
--
-- Our own tooltip, never the game's ShoppingTooltip1 / 2: holding Shift (or "Always Compare
-- Items") the game still shows ITS comparison with what is equipped in that slot, and ours goes on
-- the other side of the item's tooltip, so neither overwrites the other.
-- Source read (Gethe/wow-ui-source, branch forever):
--   Blizzard_GameTooltip/Mainline/GameTooltip.xml:109-146  ShoppingTooltipTemplate: CompareHeader
--     (its Label), hidden again by OnTooltipCleared; no supportsItemComparison (only GameTooltip,
--     :251), so a tooltip of this template never starts a comparison of its own
--     (Blizzard_SharedXMLGame/Tooltip/TooltipDataRules.lua:168-175)
--   Blizzard_SharedXMLGame/Tooltip/TooltipComparisonManager.lua:219-260  how the game fills its
--     own: header EQUIPPED (width = label + 30), the item, a blank line, ITEM_DELTA_DESCRIPTION,
--     then C_TooltipComparison.GetItemComparisonDelta(new, old) lines in the highlight color;
--     :48-145 its placement: beside the item's tooltip, tops level, on the side with room
--   Blizzard_APIDocumentationGenerated/TooltipComparisonDocumentation.lua:24-40
--     GetItemComparisonDelta(comparisonItem, equippedItem [, pairedItem, addPairedStats]) -> lines;
--     an item is { hyperlink = link } (TooltipComparisonManager.lua:11-21)
--   Blizzard_GameTooltip/Mainline/GameTooltip.lua:451-463  the tooltip calls its owner's
--     UpdateTooltip every TOOLTIP_UPDATE_TIME while it shows.

-- luacheck: read globals CreateFrame UIParent

local _, ns = ...
local L = ns.L

local Tip = {}
ns.CompareTip = Tip

local HEADER_PAD = 30      -- TooltipComparisonManager.lua: COMPARE_HEADER_PADDING
local tip, made = nil, false
local shownFor            -- the main tooltip ours stands beside

local function Make()
	if made then return tip end
	made = true
	local ok, f = pcall(CreateFrame, "GameTooltip", "GloweyGearCompareTip", UIParent, "ShoppingTooltipTemplate")
	if not ok or not f then
		ok, f = pcall(CreateFrame, "GameTooltip", "GloweyGearCompareTip", UIParent, "GameTooltipTemplate")
	end
	if not ok or not f then return nil end
	f:SetFrameStrata("TOOLTIP")
	f:SetClampedToScreen(true)
	-- (Gone with the item's tooltip, whatever hid it.)
	f:SetScript("OnUpdate", function(self)
		if not shownFor or not shownFor:IsShown() then return self:Hide() end
		-- (The game's own comparison can come or go with Shift while it shows: kept on the
		-- other side. Place does nothing while the side is unchanged.)
		Tip.Place(shownFor)
	end)
	tip = f
	return f
end

-- Whether that piece is worn now (else it is in the bags).
local function Worn(link)
	local G, Stats = ns.Game, ns.Stats
	if not (G and G.WornLink and Stats and Stats.Key) then return true end
	local key = Stats.Key(link)
	for slot = 1, 18 do
		local worn = G.WornLink(slot)
		if worn and Stats.Key(worn) == key then return true end
	end
	return false
end

local function Delta(newLink, oldLink)
	local C = rawget(_G, "C_TooltipComparison")
	if type(C) ~= "table" or type(C.GetItemComparisonDelta) ~= "function" then return nil end
	local ok, lines = pcall(C.GetItemComparisonDelta, { hyperlink = newLink }, { hyperlink = oldLink })
	if ok and type(lines) == "table" and #lines > 0 then return lines end
	return nil
end

-- The game's comparison, when it is showing beside `main`: the side it took ("left" / "right").
local function TheirSide(main)
	for _, s in ipairs({ rawget(_G, "ShoppingTooltip1") or false, rawget(_G, "ShoppingTooltip2") or false }) do
		if type(s) == "table" and s.IsShown and s:IsShown() and s.GetOwner and s:GetOwner() == main then
			local sl, ml = s:GetLeft(), main:GetLeft()
			if sl and ml then return sl < ml and "left" or "right" end
		end
	end
	return nil
end

function Tip.Place(main)
	local f = tip
	if not f or not f:IsShown() or not main then return end
	local side
	local theirs = TheirSide(main)
	if theirs then
		side = theirs == "left" and "right" or "left"
	else
		-- (The side with more room, as the game picks for its own.)
		local left, right = main:GetLeft(), main:GetRight()
		local screen = rawget(_G, "GetScreenWidth")
		local width = screen and screen() or 0
		if left and right then
			local scale = (main:GetEffectiveScale() or 1) / (UIParent:GetEffectiveScale() or 1)
			side = (width - right * scale) >= left * scale and "right" or "left"
		else
			side = "right"
		end
	end
	if f.side == side and f.anchoredTo == main then return end
	f.side, f.anchoredTo = side, main
	f:ClearAllPoints()
	if side == "left" then
		f:SetPoint("TOPRIGHT", main, "TOPLEFT", 0, 0)
	else
		f:SetPoint("TOPLEFT", main, "TOPRIGHT", 0, 0)
	end
end

function Tip.Show(main, row)
	local rep = type(row) == "table" and row.replaces or nil
	if type(rep) ~= "table" or type(rep.link) ~= "string" or type(row.link) ~= "string" then return Tip.Hide() end
	local f = Make()
	if not f then return end
	f:SetOwner(main, "ANCHOR_NONE")
	f.side, f.anchoredTo = nil, nil
	if not pcall(f.SetHyperlink, f, rep.link) then return Tip.Hide() end
	-- (After SetHyperlink: clearing the tooltip hides the header.)
	local header = Worn(rep.link) and (rawget(_G, "EQUIPPED") or "Equipped") or L["In Your Bags"]
	local h = f.CompareHeader
	if type(h) == "table" and h.Label then
		h.Label:SetText(header)
		h:SetWidth((h.Label:GetWidth() or 60) + HEADER_PAD)
		h:Show()
	end
	local lines = Delta(row.link, rep.link)
	if lines then
		f:AddLine(" ")
		f:AddLine(rawget(_G, "ITEM_DELTA_DESCRIPTION") or "If you replace this item, the following stat changes will occur:", 1, 0.82, 0, true)
		for _, line in ipairs(lines) do f:AddLine(line, 1, 1, 1, true) end
	end
	shownFor = main
	f:Show()
	Tip.Place(main)
end

function Tip.Hide()
	shownFor = nil
	if tip then tip:Hide() end
end
