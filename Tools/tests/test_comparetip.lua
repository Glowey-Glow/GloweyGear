-- CompareTip.lua on stand-ins for the game's tooltips: hovering an upgrade shows the piece it
-- replaces beside the item's tooltip, headed "Equipped" when it is worn and "In Your Bags" when
-- it is carried, with the game's stat-change lines; nothing for an empty slot; it takes the side
-- with room, and the other side when the game's own comparison (Shift) is showing; it goes with
-- the item's tooltip. (The stand-ins follow Blizzard_GameTooltip/Mainline/GameTooltip.xml:109-146
-- for the template's CompareHeader and TooltipComparisonDocumentation.lua:24-40 for the delta.)
-- luacheck: ignore 111 112 113 121 122 212
setmetatable(_G, nil)

local function read(rel)
	local handle = assert(io.open(ADDON_ROOT .. "/" .. rel, "r"))
	local source = handle:read("*a")
	handle:close()
	return source
end

-- A frame or tooltip: points, shown state, lines; the template's CompareHeader when asked for.
local function frame(template)
	local f = { shown = false, points = {}, lines = {}, scripts = {}, left = 0, right = 0 }
	function f:Show() self.shown = true end
	function f:Hide() self.shown = false end
	function f:IsShown() return self.shown end
	function f:SetShown(on) self.shown = on and true or false end
	function f:SetFrameStrata() end
	function f:SetClampedToScreen() end
	function f:SetAlpha(a) self.alpha = a end
	function f:GetItem() return self.link and "Name" or nil, self.link end
	function f:SetScript(name, fn) self.scripts[name] = fn end
	function f:HookScript(name, fn) self.hooks = self.hooks or {}; self.hooks[name] = fn end
	function f:SetOwner(owner) self.owner = owner end
	function f:GetOwner() return self.owner end
	function f:ClearAllPoints() self.points = {} end
	function f:SetPoint(...) self.points[#self.points + 1] = { ... } end
	function f:GetLeft() return self.left end
	function f:GetRight() return self.right end
	function f:GetEffectiveScale() return 1 end
	function f:AddLine(text) self.lines[#self.lines + 1] = text end
	function f:SetHyperlink(link)
		self.lines = { "tip of " .. link }
		self.link = link
		if self.CompareHeader then self.CompareHeader:Hide() end   -- (OnTooltipCleared)
	end
	if template == "ShoppingTooltipTemplate" then
		local h = { shown = false }
		function h:Show() self.shown = true end
		function h:Hide() self.shown = false end
		function h:SetWidth(w) self.width = w end
		h.Label = { SetText = function(self, t) self.text = t end, GetWidth = function() return 70 end }
		f.CompareHeader = h
	end
	return f
end

local made = {}
CreateFrame = function(kind, name, parent, template)
	local f = frame(template)
	f.kind, f.name, f.template = kind, name, template
	made[#made + 1] = f
	return f
end
UIParent = frame()
function UIParent:GetEffectiveScale() return 1 end
GetScreenWidth = function() return 1920 end
EQUIPPED = "Equipped"
ITEM_DELTA_DESCRIPTION = "If you replace this item, the following stat changes will occur:"
local asked
C_TooltipComparison = { GetItemComparisonDelta = function(new, old)
	asked = { new.hyperlink, old.hyperlink }
	return { "+12 Stamina", "-3 Agility" }
end }
local main = frame()
main.shown, main.left, main.right = true, 600, 900
ShoppingTooltip1, ShoppingTooltip2 = frame(), frame()

-- The game's comparison manager (TooltipComparisonManager.lua): RefreshItems fills the shopping
-- tooltips again where they stand; compareInfo.item is the piece shown, by guid when worn.
TooltipComparisonManager = { RefreshItems = function() end }
function hooksecurefunc(t, key, fn)
	local orig = t[key]
	t[key] = function(...) local r = orig(...) fn(...) return r end
end
C_Item = { GetItemLinkByGUID = function(guid) return guid == "Item-worn-boots" and "item:100" or nil end }
local worn = { [5] = "item:100" }
local ns = { L = setmetatable({}, { __index = function(_, k) return k end }),
	Game = { WornLink = function(slot) return worn[slot] end },
	Stats = { Key = function(link) return link end } }
assert(loadstring(read("CompareTip.lua"), "@CompareTip.lua"))("GloweyGear", ns)
local Tip = ns.CompareTip
local tip

local function side() return tip.points[1] and tip.points[1][1] end

T.case("an upgrade for a worn piece: beside the item, Equipped, the game's stat changes", function()
	Tip.Show(main, { link = "item:200", replaces = { link = "item:100" } })
	tip = made[1]
	T.check(tip ~= nil and tip.template == "ShoppingTooltipTemplate", "our own tooltip, of the game's comparison template")
	T.eq(tip.name, "GloweyGearCompareTip", "named ours, never the game's ShoppingTooltip1")
	T.check(tip:IsShown(), "shown")
	T.eq(tip.link, "item:100", "the piece it replaces")
	T.eq(tip.CompareHeader.Label.text, "Equipped", "headed Equipped: it is worn")
	T.check(tip.CompareHeader.shown, "the header shows (set after the item, which clears it)")
	T.eq(tip.CompareHeader.width, 100, "as wide as the game makes it: label + 30")
	T.eq(asked[1] .. ">" .. asked[2], "item:200>item:100", "the delta asked from the new item to the old")
	T.eq(tip.lines[#tip.lines], "-3 Agility", "the stat changes listed")
	T.eq(tip.lines[3], ITEM_DELTA_DESCRIPTION, "under the game's own words")
	T.eq(side(), "TOPLEFT", "on the right of the item's tooltip: more room there (1020 > 600)")
end)

T.case("a piece in the bags is headed In Your Bags", function()
	Tip.Show(main, { link = "item:201", replaces = { link = "item:300" } })
	T.eq(tip.CompareHeader.Label.text, "In Your Bags", "carried")
end)

T.case("the side: room, and away from the game's own comparison", function()
	main.left, main.right = 1300, 1600
	Tip.Show(main, { link = "item:200", replaces = { link = "item:100" } })
	T.eq(side(), "TOPRIGHT", "on the left: no room on the right")
	main.left, main.right = 600, 900
	ShoppingTooltip1.shown, ShoppingTooltip1.owner, ShoppingTooltip1.left = true, main, 900
	Tip.Place(main)
	T.eq(side(), "TOPRIGHT", "the game's comparison took the right: ours goes left")
	ShoppingTooltip1.shown = false
	ShoppingTooltip1.hooks.OnHide(ShoppingTooltip1)
	T.eq(side(), "TOPLEFT", "back on the right once it's gone (its OnHide, no polling)")
	ShoppingTooltip1.shown = true
	ShoppingTooltip1.hooks.OnShow(ShoppingTooltip1)
	T.eq(side(), "TOPRIGHT", "and left again when it shows (its OnShow)")
	ShoppingTooltip1.shown = false
	tip.scripts.OnEvent(tip, "MODIFIER_STATE_CHANGED", "LSHIFT", 0)
	T.eq(side(), "TOPLEFT", "Shift let go: placed again")
	T.check(tip.scripts.OnUpdate == nil, "no OnUpdate on our tooltip")
end)

T.case("the game's comparison shows the same piece: ours steps aside until it goes", function()
	main.left, main.right = 600, 900
	ShoppingTooltip1.shown, ShoppingTooltip1.link = false, nil
	Tip.Show(main, { link = "item:200", replaces = { link = "item:100" } })
	T.eq(tip.alpha, 1, "alone: ours shows")
	ShoppingTooltip1.shown, ShoppingTooltip1.owner, ShoppingTooltip1.left, ShoppingTooltip1.link = true, main, 900, "item:100"
	ShoppingTooltip1.hooks.OnShow(ShoppingTooltip1)
	T.eq(tip.alpha, 0, "the game's shows the same boots: ours is out of sight")
	T.check(tip:IsShown(), "but kept, to come back")
	ShoppingTooltip1.shown = false
	ShoppingTooltip1.hooks.OnHide(ShoppingTooltip1)
	T.eq(tip.alpha, 1, "the game's gone (Shift let go): ours is back")
	ShoppingTooltip1.shown, ShoppingTooltip1.link = true, "item:999"
	ShoppingTooltip1.hooks.OnShow(ShoppingTooltip1)
	T.eq(tip.alpha, 1, "the game's shows a different piece: both stay, on either side")
	T.eq(side(), "TOPRIGHT", "ours on the other side")
	ShoppingTooltip1.shown, ShoppingTooltip1.link = false, nil
end)

T.case("Shift held, item to item: the game fills its comparison again without hiding it", function()
	local M = TooltipComparisonManager
	main.left, main.right = 600, 900
	ShoppingTooltip1.shown, ShoppingTooltip1.owner, ShoppingTooltip1.left, ShoppingTooltip1.link = true, main, 900, nil
	-- First row: the game's shows a different piece (by guid); both stay.
	M.tooltip, M.compareInfo = main, { item = { guid = "Item-other" } }
	Tip.Show(main, { link = "item:200", replaces = { link = "item:100" } })
	T.eq(tip.alpha, 1, "a different piece: ours shows")
	-- Next row, Shift still held: no OnShow, only RefreshItems with the worn boots.
	M.compareInfo = { item = { guid = "Item-worn-boots" } }
	M:RefreshItems()
	T.eq(tip.alpha, 0, "the game's now shows the same boots (by guid): ours steps aside")
	-- A ring's second piece counts too.
	M.compareInfo = { item = { hyperlink = "item:7" }, additionalItems = { { hyperlink = "item:100" } } }
	M:RefreshItems()
	T.eq(tip.alpha, 0, "the same piece as the game's second one")
	M.compareInfo = { item = { hyperlink = "item:7" } }
	M:RefreshItems()
	T.eq(tip.alpha, 1, "and back when it isn't")
	M.tooltip, M.compareInfo = nil, nil
	ShoppingTooltip1.shown = false
end)

T.case("nothing to compare: hidden; gone with the item's tooltip", function()
	Tip.Show(main, { link = "item:200", empty = true })
	T.check(not tip:IsShown(), "an empty slot: no comparison")
	Tip.Show(main, { link = "item:200", replaces = { link = "item:100" } })
	main.shown = false
	main.hooks.OnHide(main)
	T.check(not tip:IsShown(), "hidden when the item's tooltip is")
	main.shown = true
	Tip.Show(main, { link = "item:200", replaces = { link = "item:100" } })
	Tip.Hide()
	T.check(not tip:IsShown(), "Hide")
	C_TooltipComparison = nil
	Tip.Show(main, { link = "item:200", replaces = { link = "item:100" } })
	T.check(tip:IsShown(), "without the game's delta call: still the piece")
	T.eq(tip.lines[#tip.lines], "tip of item:100", "just the piece")
end)

return T.done()
