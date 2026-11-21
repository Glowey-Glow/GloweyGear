-- TipFallback.lua on a stand-in for the game's tooltip call: our lines go into the game's own
-- tooltip only while Daylight UI's tooltips are off, never twice, never from a secret value,
-- and a function that raises doesn't stop the others.
-- (The stand-ins follow Blizzard_SharedXMLGame\Tooltip\TooltipDataHandler.lua:199 for
-- TooltipDataProcessor.AddTooltipPostCall and DaylightUI\API.lua:823-828 for API.TooltipStyle.)
-- luacheck: ignore 111 112 113 121 122 212
setmetatable(_G, nil)

local function read(rel)
	local handle = assert(io.open(ADDON_ROOT .. "/" .. rel, "r"))
	local source = handle:read("*a")
	handle:close()
	return source
end

local posts, errors = {}, {}
local SECRET = {}
issecretvalue = function(v) return v == SECRET end
geterrorhandler = function() return function(err) errors[#errors + 1] = tostring(err) end end
Enum = { TooltipDataType = { Item = 0 } }
TooltipDataProcessor = { AddTooltipPostCall = function(kind, fn) posts[#posts + 1] = { kind = kind, fn = fn } end }
C_Item = { GetItemLinkByGUID = function(guid) return guid == "Item-1" and "item:101" or nil end }

-- A tooltip as the game's: named lines with a left and a right text.
local function tooltip(name)
	local tip = { name = name, lines = {}, shown = false, shows = 0 }
	function tip:GetName() return self.name end
	function tip:NumLines() return #self.lines end
	local function put(self, left, right)
		local i = #self.lines + 1
		self.lines[i] = { left, right }
		_G[self.name .. "TextLeft" .. i] = { GetText = function() return left end }
		_G[self.name .. "TextRight" .. i] = { GetText = function() return right end }
	end
	function tip:AddLine(text) put(self, text, nil) end
	function tip:AddDoubleLine(left, right) put(self, left, right) end
	function tip:IsShown() return self.shown end
	function tip:Show() self.shows = self.shows + 1 end
	function tip:GetItem() return "Name", self.link end
	return tip
end

local style = "rich"
local ns = { ok = true, API = { TooltipStyle = function() return style end, Accent = function() return 0.2, 0.4, 0.6 end } }
assert(loadstring(read("TipFallback.lua"), "@TipFallback.lua"))("GloweyGear", ns)

T.case("nothing is hooked until someone asks, and then once", function()
	T.eq(#posts, 0, "no call asked of the game at load")
	T.eq(ns.TipFallback("no"), false, "not a function: refused")
	T.eq(#posts, 0, "and still nothing asked")
end)

local seen = {}
local function mine(lines, data)
	seen[#seen + 1] = data
	lines.Row("Gear Advice", "+12%", { 0, 1, 0 })
	lines.Text("A sentence.")
end

T.case("Daylight UI drawing the tooltips: left to it", function()
	T.eq(ns.TipFallback(mine), true, "taken")
	T.eq(#posts, 1, "one call asked of the game"); T.eq(posts[1].kind, 0, "for items")
	local tip = tooltip("TipA")
	posts[1].fn(tip, { id = 101, hyperlink = "item:101" })
	T.eq(#tip.lines, 0, "nothing written while Daylight UI draws them (rich)")
	style = "simple"
	posts[1].fn(tip, { id = 101, hyperlink = "item:101" })
	T.eq(#tip.lines, 0, "nor in its Simple look"); T.eq(#seen, 0, "our function was not run")
end)

T.case("Daylight UI's tooltips off: the lines go into the game's own tooltip", function()
	style = nil
	local tip = tooltip("TipB")
	posts[1].fn(tip, { id = 101, hyperlink = "item:101" })
	T.eq(#tip.lines, 2, "a row and a sentence")
	T.eq(tip.lines[1][1], "Gear Advice", "the label"); T.eq(tip.lines[1][2], "+12%", "its value")
	T.eq(tip.lines[2][1], "A sentence.", "the sentence")
	T.eq(seen[#seen].link, "item:101", "told the link"); T.eq(seen[#seen].itemID, 101, "the item")
	T.eq(seen[#seen].style, "simple", "and that the look is the plain one")
	T.eq(tip.shows, 0, "a tooltip still being filled is not shown by us")
	-- the same fill again (tooltips refill): never twice
	posts[1].fn(tip, { id = 101, hyperlink = "item:101" })
	T.eq(#tip.lines, 2, "a line already there is not added again")
	-- one that is up is fitted to its new lines
	local up = tooltip("TipC")
	up.shown = true
	posts[1].fn(up, { id = 101, hyperlink = "item:101" })
	T.eq(up.shows, 1, "a tooltip on show is fitted again")
end)

T.case("the link: by guid first, else the data's, else the tooltip's", function()
	local tip = tooltip("TipD")
	posts[1].fn(tip, { id = 5, guid = "Item-1", hyperlink = "item:999" })
	T.eq(seen[#seen].link, "item:101", "the guid's link wins")
	tip = tooltip("TipE")
	tip.link = "item:77"
	posts[1].fn(tip, { id = 77 })
	T.eq(seen[#seen].link, "item:77", "the tooltip's own, when the data has none")
end)

T.case("secret values are never read", function()
	local tip = tooltip("TipF")
	posts[1].fn(tip, { id = SECRET, hyperlink = SECRET })
	T.eq(seen[#seen].link, nil, "a secret link is no link"); T.eq(seen[#seen].itemID, nil, "a secret ID is no ID")
end)

T.case("every piece writes a plain line; one that raises doesn't stop the rest", function()
	ns.TipFallback(function() error("broken") end)
	ns.TipFallback(function(lines)
		lines.Line("L", 3)
		lines.Hint("H")
		lines.Gap()
		lines.Bar("B", 2, 5)
		lines.Tag("T")
		lines.Section("S")
		lines.Tiles({ { 1, "a" }, { 2, "b" } })
		lines.Bar("Bad", SECRET, 5)
	end)
	local tip = tooltip("TipG")
	local before = #errors
	posts[1].fn(tip, { id = 101, hyperlink = "item:101" })
	T.eq(#errors, before + 1, "the broken one is reported")
	local got = {}
	for _, l in ipairs(tip.lines) do got[#got + 1] = l[1] .. (l[2] and ("=" .. l[2]) or "") end
	T.eq(table.concat(got, "|"), "Gear Advice=+12%|A sentence.|L=3|H| |B=2 / 5|T|S|1 a · 2 b", "each piece, in order")
end)

T.case("a tooltip that can't take lines is left alone", function()
	local n = #seen
	posts[1].fn({}, { id = 1 })
	posts[1].fn(nil, { id = 1 })
	local forbidden = tooltip("TipH")
	function forbidden.IsForbidden() return true end
	posts[1].fn(forbidden, { id = 1 })
	T.eq(#seen, n, "our functions were not run"); T.eq(#forbidden.lines, 0, "and nothing written")
end)

return T.done()
