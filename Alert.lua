-- Glowey's Gear: one quiet line when the Auction House has a better buy than before.
--
-- When the list of upgrades has been scored (a new scan, or prices corrected by a search), the
-- best pick of each slot is compared with the best pick remembered from the time before. A
-- slot whose pick is another item AND measures higher than the remembered one (by gain per
-- gold, or by gain when Best Pick is Biggest Gain), or a slot that had no pick and has one
-- now, is news. One line says the biggest of them:
--     "New best upgrade for sale: [Item] for your Chest (+12%, 3g 20s)."
--
--   Alert.News(seen, view, mode) -> row | nil, slots     (pure) the row to speak of, and what
--                                                         to remember ({ [group] = { key, measure } })
--   Alert.Check(view, level)                              compares, speaks, remembers
--
-- Rules that keep it quiet:
--   * nothing the first time a house is scored for a character, or after the spec, the Best
--     Pick or the house changed (there is nothing to compare with: it is only remembered);
--   * one line at a time, the biggest news; never two lines within QUIET seconds;
--   * never in a fight (nothing is remembered then either, so the news keeps);
--   * off with the Chat Alert switch, and with Show Gear Advice.
-- What is remembered is per character: DaylightGearDB.chars[guid].seen =
--   { house = , spec = , mode = , slots = { [group] = { key, measure } } }.
-- Limit: the list is scored while the Upgrades for Sale window is up (docked beside the Auction
-- House, it is), so that is when news is found.
--
-- luacheck: read globals ITEM_QUALITY_COLORS

local _, ns = ...
if ns.off or not ns.ok then return end

local Alert = {}
ns.Alert = Alert

local L = ns.L
local QUIET = 60
local last = nil   -- Game.Time() of the last line

local function measure(row, mode)
	return mode == "biggest" and (row.gain or 0) or (row.value or 0)
end

function Alert.News(seen, view, mode)
	local slots, news = {}, nil
	for group, list in pairs(type(view) == "table" and view.groups or {}) do
		local row = list[1]
		if row then
			local m = measure(row, mode)
			slots[group] = { row.key, m }
			if seen then
				local was = seen[group]
				local better = (not was) or (was[1] ~= row.key and m > (tonumber(was[2]) or 0) * (1 + 1e-9))
				if better and (not news or (row.gain or 0) > (news.gain or 0)) then news = row end
			end
		end
	end
	return news, slots
end

-- A link the chat can show, from a row (whose own link is a bare item string).
function Alert.Link(row)
	local link = type(row.link) == "string" and row.link or ""
	if link:find("|H", 1, true) then return link end
	local color = "ffffffff"
	local all = rawget(_G, "ITEM_QUALITY_COLORS")
	local c = type(all) == "table" and all[row.quality]
	if type(c) == "table" and type(c.hex) == "string" then color = c.hex:gsub("^|c", "") end
	return ("|c%s|H%s|h[%s]|h|r"):format(color, link, row.name or "?")
end

function Alert.Line(row)
	local M = ns.Marks
	local slot = M and M.SlotName(row.group) or row.group
	local gain = ns.Window and ns.Window.GainText(row) or ""
	local money = ns.Money and ns.Money(row.price) or tostring(row.price)
	return L["New best upgrade for sale: %s for your %s (%s, %s)."]:format(Alert.Link(row), slot, gain, money)
end

function Alert.Check(view)
	if ns.Get("enabled") == false or ns.Get("alert") == false then return end
	if ns.Game.InCombat() then return end
	local c, who = ns.Char(), ns.Who()
	local house = ns.Market.House()
	if not c or not who or not house or type(view) ~= "table" then return end
	local mode = ns.Get("mode") == "biggest" and "biggest" or "perGold"
	local seen = type(c.seen) == "table" and c.seen or nil
	if seen and (seen.house ~= house or seen.spec ~= who.spec or seen.mode ~= mode) then seen = nil end
	local news, slots = Alert.News(seen and seen.slots or nil, view, mode)
	c.seen = { house = house, spec = who.spec, mode = mode, slots = slots }
	if not news then return end
	local now = ns.Game.Time()
	if last and now - last < QUIET then return end
	last = now
	ns.Print(Alert.Line(news))
end

function Alert.Reset() last = nil end
