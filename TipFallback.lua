-- Tooltip lines without Daylight UI's tooltips.
--
-- Our item tooltip lines are handed to Daylight UI (me.AddTooltipLines), which draws them in its
-- own look. It runs them only while its Tooltip module draws the tooltips: with that module
-- switched off, or another addon styling the tooltips in its place, nothing a plugin adds is
-- run (DaylightUI\API.md, Tooltips: "Nothing runs while another addon styles the tooltips
-- instead"; API.TooltipStyle() is nil then, API.lua:823-828). The lines were simply gone.
--
-- This is the way in for those cases: the same function, given the same pieces to call
-- (lines.Row, lines.Text...), written as plain lines into the game's own tooltip, where the
-- game's look or whichever addon styles it shows them. It stands down the moment Daylight UI
-- draws the tooltips again (asked for each tooltip, so no /reload), and so a line never shows twice.
--
--   ns.TipFallback(fn)     fn(lines, data) as for me.AddTooltipLines("item", fn);
--                          data = { link, itemID, style = "simple" }
--
-- How it gets there: the game's own call after an item tooltip is filled
-- (TooltipDataProcessor.AddTooltipPostCall, Blizzard_SharedXMLGame\Tooltip\TooltipDataHandler.lua:199),
-- the one Daylight UI's own Simple look uses (DaylightUI_Tooltip\Tooltip.lua). The item's link is
-- read as the game's own helper reads it (TooltipUtil.lua:9-23: the data's guid, else its
-- hyperlink). In a fight the game may keep a tooltip's values secret: a secret value is never
-- read or compared, the item is then simply not known and nothing is added.
-- luacheck: read globals geterrorhandler
local _, ns = ...
if ns.off or not ns.ok then return end

local secret = _G.issecretvalue
local function plain(v)
	if secret and secret(v) then return nil end
	return v
end

-- Whether Daylight UI draws the tooltips now (then it runs our lines itself). A Daylight UI
-- too old to say (before API 1.12) is left to it.
local function DuiDraws()
	local API = ns.API
	if type(API) ~= "table" or type(API.TooltipStyle) ~= "function" then return true end
	local ok, style = pcall(API.TooltipStyle)
	return not ok or style ~= nil
end

local LABEL, VALUE = { 1, 0.82, 0 }, { 1, 1, 1 }   -- the game's own gold for a label, white for its value
local function rgb(c, fallback)
	if type(c) == "table" and type(c[1]) == "number" and type(c[2]) == "number" and type(c[3]) == "number" then
		return c[1], c[2], c[3]
	end
	return fallback[1], fallback[2], fallback[3]
end
local function accent()
	local API = ns.API
	if type(API) == "table" and type(API.Accent) == "function" then
		local ok, r, g, b = pcall(API.Accent)
		if ok and type(r) == "number" and type(g) == "number" and type(b) == "number" then return r, g, b end
	end
	return LABEL[1], LABEL[2], LABEL[3]
end
local function str(v)
	v = plain(v)
	if v == nil then return nil end
	return tostring(v)
end

-- Whether the tooltip already has the line (an item tooltip fills several times a second).
local function HasLine(tip, left, right)
	local name = type(tip.GetName) == "function" and tip:GetName() or nil
	local n = type(tip.NumLines) == "function" and plain(tip:NumLines()) or nil
	if type(name) ~= "string" or type(n) ~= "number" then return false end
	for i = 1, n do
		local l = _G[name .. "TextLeft" .. i]
		local text = l and l.GetText and plain(l:GetText())
		if text == left then
			if right == nil then return true end
			local r = _G[name .. "TextRight" .. i]
			local other = r and r.GetText and plain(r:GetText())
			if (other or "") == right then return true end
		end
	end
	return false
end

local adding, added   -- the tooltip the pieces write to while our functions run

local function row(left, right, color)
	local tip = adding
	if not tip or type(left) ~= "string" then return end
	right = str(right) or ""
	if HasLine(tip, left, right) then return end
	local r, g, b = rgb(color, VALUE)
	tip:AddDoubleLine(left, right, LABEL[1], LABEL[2], LABEL[3], r, g, b)
	added = true
end
local function line(text, r, g, b)
	local tip = adding
	if not tip or type(text) ~= "string" or HasLine(tip, text) then return end
	tip:AddLine(text, r, g, b, true)
	added = true
end

-- The pieces, as Daylight UI's Simple look writes them (API.md's table of tooltip pieces).
local LINES = {
	Line = row,
	Row = row,
	Text = function(text, color) line(text, rgb(color, VALUE)) end,
	Hint = function(text) line(text, accent()) end,
	Gap = function()
		if not adding then return end
		adding:AddLine(" ")
		added = true
	end,
	Bar = function(label, value, max, color)
		value, max = plain(value), plain(max)
		if type(label) ~= "string" or type(value) ~= "number" or type(max) ~= "number" then return end
		row(label, tostring(value) .. " / " .. tostring(max), color)
	end,
	Tag = function(text, color) line(text, rgb(color, { 0.75, 0.75, 0.75 })) end,
	Section = function(title) line(title, accent()) end,
	Tiles = function(list)
		if type(list) ~= "table" then return end
		local words = {}
		for _, t in ipairs(list) do
			local value, caption = type(t) == "table" and str(t[1]), type(t) == "table" and str(t[2])
			if value then words[#words + 1] = caption and (value .. " " .. caption) or value end
		end
		if #words > 0 then line(table.concat(words, " · "), VALUE[1], VALUE[2], VALUE[3]) end
	end,
}

-- The item a tooltip shows: its link and ID, each nil when it can't be read.
local function ItemOf(tip, data)
	local link, id
	if type(data) == "table" then
		id = plain(data.id)
		local guid = plain(data.guid)
		local byGuid = _G.C_Item and _G.C_Item.GetItemLinkByGUID
		if type(guid) == "string" and type(byGuid) == "function" then
			local ok, got = pcall(byGuid, guid)
			if ok then link = plain(got) end
		end
		if type(link) ~= "string" then link = plain(data.hyperlink) end
	end
	if type(link) ~= "string" and type(tip.GetItem) == "function" then
		local ok, _, got = pcall(tip.GetItem, tip)
		if ok then link = plain(got) end
	end
	return type(link) == "string" and link ~= "" and link or nil, type(id) == "number" and id or nil
end

local fns = {}

local function OnItem(tip, data)
	if #fns == 0 or DuiDraws() then return end
	if type(tip) ~= "table" or type(tip.AddDoubleLine) ~= "function" or type(tip.AddLine) ~= "function" then return end
	if type(tip.IsForbidden) == "function" and tip:IsForbidden() then return end
	local link, id = ItemOf(tip, data)
	local info = { link = link, itemID = id, style = "simple" }
	adding, added = tip, false
	for _, fn in ipairs(fns) do
		local ok, err = pcall(fn, LINES, info)
		if not ok then
			adding = nil
			geterrorhandler()(err)
			adding = tip
		end
	end
	adding = nil
	-- (A tooltip already up is fitted to its new lines; one still being filled is shown by the
	-- game right after, lines and all.)
	if added and type(tip.IsShown) == "function" and tip:IsShown() then tip:Show() end
end

local hooked = false
local function Hook()
	if hooked then return true end
	local TDP = _G.TooltipDataProcessor
	local kinds = _G.Enum and _G.Enum.TooltipDataType
	if type(TDP) ~= "table" or type(TDP.AddTooltipPostCall) ~= "function" or type(kinds) ~= "table" or kinds.Item == nil then
		return false
	end
	hooked = true
	TDP.AddTooltipPostCall(kinds.Item, function(tip, data)
		local ok, err = pcall(OnItem, tip, data)
		if not ok then
			adding = nil
			geterrorhandler()(err)
		end
	end)
	return true
end

-- True when the lines will be written (the game has the call); false leaves things as they were.
ns.TipFallback = function(fn)
	if type(fn) ~= "function" or not Hook() then return false end
	fns[#fns + 1] = fn
	return true
end
