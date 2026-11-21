-- Glowey's Gear: which reward of a quest to take.
--
-- When a quest lets the player choose one reward of several, one line in the chat says which
-- is the biggest upgrade for the spec ("Best quest reward for you: [Item] (+12% over your
-- Chest)."). With the Vendor Value Hint switched on and no upgrade among them, it says
-- which sells for the most instead. On the reward's own tooltip the Gear Advice row is there
-- as on any item, and the picked reward's tooltip gets one more line.
--
--   Quest.Choose(list, minGain, sell) -> pick | nil      (pure: no game call)
--        list = { { link = , count = , v = Compare.Evaluate's answer or nil, sell = copper each }, ... }
--        pick = { kind = "upgrade" | "sell", index = , link = , v = , total = copper }
--   Quest.Look()          looks at the quest page that is open, and speaks once for it
--   Quest.Best()          -> the picked reward's Stats.Key while its quest page is open, or nil
--
-- WHAT IT READS, all of it public. The game says a reward page is up with QUEST_COMPLETE (DOC
-- QuestLogDocumentation.lua:1332), that a reward's item data came with QUEST_ITEM_UPDATE (DOC
-- QuestOfferDocumentation.lua:91) and that the page closed with QUEST_FINISHED (:79). The
-- choices are GetNumQuestChoices(), GetQuestItemLink("choice", i) and GetQuestItemInfo(
-- "choice", i) (name, texture, count, quality, usable, itemID), the calls the game's own quest
-- frame makes (FX Blizzard_UIPanels_Game\Mainline\QuestInfo.lua:526, :647; QuestFrame.lua:743)
-- and Daylight UI's quest window too (DUI DaylightUI\Npc\Data.lua:141-147, Window.lua:277).
-- A sell price is the item's own (Game.ItemInfo).
--
-- THE TOOLTIP ROW NEEDS NOTHING NEW. Both windows show a reward with GameTooltip:SetQuestItem
-- (the game's: QuestInfo.lua:1297; Daylight UI's: Npc\Window.lua:260-261), which is an item
-- tooltip, so Marks.lua's row comes with it.
--
-- NO MARK IS DRAWN ON THE REWARD TILES. Daylight UI's quest window has no frame kind for them
-- in its public API (API.md's list of kinds, :200-215: unit frames, action buttons, shop
-- tiles, craft rows, cast bars, quest tracker rows, bag slots) and builds them inside itself
-- (Npc\Window.lua:281-297, Npc.tiles); the game's own reward buttons are parked with the quest
-- frame while Daylight UI's window is up (Npc\Window.lua:36-45). A mark would mean reaching
-- into Daylight UI's own table several times a second, which this plugin does not do.
--
-- Never in a fight, never twice for one page or for the same rewards within ten minutes,
-- nothing for a quest with a single reward.
--
-- luacheck: read globals CreateFrame C_Timer

local _, ns = ...
if ns.off or not ns.ok then return end

local Quest = {}
ns.Quest = Quest

local L = ns.L
local Game, Stats = ns.Game, ns.Stats

-- ---------------------------------------------------------------------------------------------
-- The choice (pure)
-- ---------------------------------------------------------------------------------------------
function Quest.Choose(list, minGain, sell)
	if type(list) ~= "table" or #list < 2 then return nil end
	minGain = tonumber(minGain) or 0
	local best
	for i = 1, #list do
		local it = list[i]
		local v = it.v
		-- An upgrade as the tooltip row counts one: usable now, a real gain, not under the
		-- smallest gain to show (an empty slot, or nothing to measure against, always counts).
		if v and v.usable and v.gain and v.gain > 0 and (v.empty or v.pct == nil or v.pct >= minGain) then
			if not best or v.gain > best.v.gain then best = { kind = "upgrade", index = i, link = it.link, v = v } end
		end
	end
	if best then return best end
	if not sell then return nil end
	for i = 1, #list do
		local it = list[i]
		local total = (tonumber(it.sell) or 0) * math.max(1, tonumber(it.count) or 1)
		if total > 0 and (not best or total > best.total) then best = { kind = "sell", index = i, link = it.link, total = total } end
	end
	return best
end

-- ---------------------------------------------------------------------------------------------
-- The page that is open
-- ---------------------------------------------------------------------------------------------
local page = nil        -- { said = signature spoken for, best = key, tries = n } while a reward page is up
local buf = {}

local function Money(copper)
	if type(ns.Money) == "function" then return ns.Money(copper) end
	return ("%dg %ds %dc"):format(math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100)
end

function Quest.Best() return page and page.best or nil end

-- The link of the quest reward with this item ID, among the choices and the fixed rewards of
-- the page that is up, or nil. For a reward's tooltip that came without a link: Daylight UI
-- finds a tooltip's link from its data's guid or hyperlink, else from GameTooltip:GetItem
-- (DUI DaylightUI_Tooltip\Tooltip.lua:705-722), and a quest reward the game is still loading
-- can have none of the three.
local linkBuf = {}
function Quest.LinkFor(itemID)
	if type(itemID) ~= "number" then return nil end
	for _, kind in ipairs({ "choice", "reward" }) do
		for i = #linkBuf, 1, -1 do linkBuf[i] = nil end
		local n = Game.QuestChoices(linkBuf, kind) or 0
		for i = 1, n do
			local link = linkBuf[i] and linkBuf[i].link
			if type(link) == "string" and Stats.ItemID(link) == itemID then return link end
		end
	end
	return nil
end

-- The sentence for a pick (also for the tests).
function Quest.Line(pick)
	if pick.kind == "upgrade" then
		local advice = ns.Marks and ns.Marks.Advice(pick.v, 0) or nil
		if advice then return L["Best quest reward for you: %s (%s)."]:format(pick.link, advice) end
		return L["Best quest reward for you: %s."]:format(pick.link)
	end
	return L["No quest reward is an upgrade. %s sells for the most (%s)."]:format(pick.link, Money(pick.total))
end

-- THE CHOICES CAN COME LATE. Daylight UI's own notes on this client: "On a first visit the
-- page arrives before its choices. GetNumQuestChoices reports 0 until they load" (DUI
-- DaylightUI\Npc\Window.lua:210-216) and "A reward whose item isn't cached has no name yet,
-- and QUEST_ITEM_UPDATE doesn't always follow" (:750-752). So a page is looked at again on
-- QUEST_ITEM_UPDATE, when any item's data arrives (Core.lua's "ItemsArrived"), and on a
-- timer of its own: every EVERY seconds, TRIES times at most, while fewer than two choices
-- are there, a choice has no link yet, or a reward's stats are still loading. After that it
-- speaks about what it has (a choice that never gets a link, a currency, is passed over) or,
-- with fewer than two choices, gives the page up.
local TRIES, EVERY = 12, 0.5
-- The same rewards within this long are not spoken of twice (a page closed and opened again).
local AGAIN = 600
local spoken = nil   -- { sig = , at = Game.Time() }

function Quest.Forget() spoken = nil end

local function again()
	if not page or page.timer then return end
	local mine = page
	page.timer = true
	C_Timer.After(EVERY, function()
		mine.timer = false
		if page == mine then Quest.Look() end
	end)
end

function Quest.Look()
	if not page then return end
	if ns.Get("enabled") == false or ns.Get("questPick") == false then return end
	if Game.InCombat() then return end
	for i = #buf, 1, -1 do buf[i] = nil end
	local n = Game.QuestChoices(buf) or 0
	local signature, waiting = "", n < 2
	for i = 1, n do
		local it = buf[i]
		if type(it.link) ~= "string" then
			waiting = true
		else
			signature = signature .. it.link .. ";"
			local v, why = ns.Verdict(it.link)
			if v then
				-- (ns.Verdict's table is a shared one: what is needed of it is copied.)
				it.v = { usable = v.usable, gain = v.gain, pct = v.pct, far = v.far, empty = v.empty, group = v.group,
					score = v.score, atLevel = v.atLevel, reason = v.reason, offHand = v.offHand, twoHand = v.twoHand }
			elseif why == "pending" then
				waiting = true
			end
			local _, _, _, sellPrice = Game.ItemInfo(it.link)
			it.sell = sellPrice
		end
	end
	if waiting and (page.tries or 0) < TRIES then
		page.tries = (page.tries or 0) + 1
		return again()
	end
	if n < 2 or page.said == signature then return end
	page.said = signature
	local pick = Quest.Choose(buf, ns.Get("minGain"), ns.Get("questSell") == true)
	page.best = pick and pick.kind == "upgrade" and Stats.Key(pick.link) or nil
	if not pick then return end
	-- (The same rewards as a moment ago: the page was closed and opened again.)
	local now = Game.Time() or 0
	if spoken and spoken.sig == signature and now - spoken.at < AGAIN then return end
	spoken = { sig = signature, at = now }
	ns.Print(Quest.Line(pick))
end

local frame = CreateFrame("Frame")
for _, event in ipairs({ "QUEST_COMPLETE", "QUEST_ITEM_UPDATE", "QUEST_FINISHED" }) do pcall(frame.RegisterEvent, frame, event) end
frame:SetScript("OnEvent", function(_, event)
	if event == "QUEST_FINISHED" then
		page = nil
	elseif event == "QUEST_COMPLETE" then
		page = { tries = 0 }
		-- (A moment later: the choices can arrive just after the page.)
		C_Timer.After(0.3, Quest.Look)
	elseif page then
		Quest.Look()
	end
end)
ns.On("ItemsArrived", function()
	if page then Quest.Look() end
end)
