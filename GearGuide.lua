-- Glowey's Gear's welcome, what's new and tour (the engine: Guide.lua, the file shared by
-- Glowey's Daylight UI plugins). Loaded before Core.lua, so the options page can show the Help
-- card (Retake Tour, What's New); everything of Core.lua's and Window.lua's is looked up when
-- it is needed.
--
-- The tour is five cards of words: what the plugin does, where the list opens, the tooltip row,
-- the bag mark, and where the numbers come from (and that they can be wrong). The second card
-- opens the Upgrades for Sale window and lights it when Window.lua is there; the others have
-- nothing on screen to point at (a tooltip and a bag slot only exist while the player makes
-- them), so their cards sit in the middle. On a controller the cards, the welcome and What's
-- New take the D-pad through Guide.lua's own ns.Pad.

local _, ns = ...
local Guide = ns.Guide
if not Guide then return end
local L = ns.L
local Pop = Guide.Pop

-- What the welcome lists; the first version's "what's new" is the same three lines.
local WINDOW = L["Upgrades for Sale: the best upgrade on the Auction House for each slot, by improvement per gold. /gear opens it."]
local TOOLTIP = L["A Gear Advice row on item tooltips: how much better an item is than yours, or the level you can wear it at."]
local BAGS = L["A green plus on bag and bank slots that hold an upgrade."]

-- What changed, newest first: shown once after an update ("What's New" in the options shows
-- them again). The first version's notes only ever show from that button: a new player gets
-- the welcome, which marks them as read.
local NEWS = {
	{ version = "1.1.0", lines = {
		L["Your own stat weights: the Stat Weights page in Gear's options has a box for each stat. Change any; the rest keep Glowey's recommendation, and Revert puts yours back."],
		L["Works without Daylight UI: its settings are in Glowey's settings (/glowey). In Blizzard Style the Upgrades for Sale window docks flush beside the Auction House."],
	} },
	{ version = "1.0.0", lines = {
		WINDOW,
		TOOLTIP,
		BAGS,
		L["Stat weights for every class and talent tree, with their own values while you level."],
		L["Quest rewards: a chat line names the best reward for you."],
	} },
}

Guide.Setup({
	name = "Glowey's Gear",
	db = function() return _G.GloweyGearDB end,
	-- (The guide ships with the first version: nobody had the plugin before it.)
	existing = function() return false end,
	intro = L["Glowey's Gear scores gear for your spec and tells you what is an upgrade over what you wear and carry."],
	heading = L["What It Adds:"],
	takes = function()
		return {
			WINDOW,
			TOOLTIP,
			BAGS,
			ns.standalone and L["Stat weights are a starting point and can be wrong for your build. Pick your spec in Glowey's settings: /glowey, Gear."]
				or L["Stat weights are a starting point and can be wrong for your build. Pick your spec in Daylight UI's options: Plugins > Gear."],
		}
	end,
	tour = "gear",
	news = NEWS,
	decline = { label = L["Okay"], fn = function() end },
})

-- The Upgrades for Sale window, when Window.lua is loaded and says where its frame is
-- (ARCHITECTURE.md 7.2: ns.Window.Open / Close; the frame under whichever name it is kept).
local opened = false
local function Window() return type(ns.Window) == "table" and ns.Window or nil end
local function WindowFrame()
	local W = Window()
	local f = W and (W.frame or W.window) or nil
	if type(f) == "table" and type(f.IsShown) == "function" then return f end
	return nil
end
local function CloseWindow()
	if not opened then return end
	opened = false
	local W = Window()
	if W and type(W.Close) == "function" then pcall(W.Close) end
end

Guide.AddTour("gear", {
	finished = CloseWindow,
	steps = {
	{ title = L["Gear Advice"],
	  text = L["Every piece of gear gets a score from its stats and your spec's stat weights. An item is an upgrade when it beats the best you own for that slot, worn or in your bags."] },
	{ title = L["Upgrades for Sale"],
	  text = function()
		if ns.standalone then
			return string.format(L["%s opens this list: the best upgrade on the Auction House for each slot. It fills after %s at the Auction House, and keeps the list for later."],
				Pop("/gear"), Pop(L["Scan the Auction House"]))
		end
		return string.format(L["%s opens this list: the best upgrade on the Auction House for each slot. It fills after a Full scan in Daylight UI's Auction House, and keeps the list for later."], Pop("/gear"))
	  end,
	  -- (Shown for the card only when it was closed: a window the player had open stays open.)
	  enter = function()
		local W, f = Window(), WindowFrame()
		if W and f and not f:IsShown() and type(W.Open) == "function" then
			opened = pcall(W.Open)
		end
	  end,
	  leave = CloseWindow,
	  part = function()
		local f = WindowFrame()
		if f and f:IsShown() then return f end
	  end },
	{ title = L["Item Tooltips"],
	  text = L["Point at any gear: the Gear Advice row says how much better it is than yours, or the level you can wear it at. Gear your class can't wear gets no row."] },
	{ title = L["Bag Slots"],
	  text = function()
		return string.format(L["A green plus in a corner of a bag or bank slot marks an upgrade you already have. %s in the options moves it to another corner."], Pop(L["Bag Corner"]))
	  end },
	{ title = L["Quest Rewards"],
	  text = L["When a quest lets you choose a reward, a chat line names the biggest upgrade for you, and that reward's tooltip says so too."] },
	{ title = L["Your Own Stat Weights"],
	  text = function()
		return string.format(L["%s in the options has a box for each stat your spec's weights use: type your own. Only the ones you change are yours; the rest keep following Glowey's recommendation, and %s puts a spec's back."],
			Pop(L["Stat Weights"]), Pop(L["Revert This Spec"]))
	  end },
	{ title = L["About the Numbers"],
	  text = function()
		if ns.standalone then
			return string.format(L["Stat weights are a starting point, not a final answer: they can be wrong for your build. Your spec and the other settings are in Glowey's settings: %s. %s there shows this tour again."],
				Pop("/glowey"), Pop(L["Retake Tour"]))
		end
		return string.format(L["Stat weights are a starting point, not a final answer: they can be wrong for your build. Your spec and the other settings are in Daylight UI's options: %s. %s there shows this tour again."],
			Pop(L["Plugins > Gear"]), Pop(L["Retake Tour"]))
	  end },
} })
