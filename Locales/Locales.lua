-- Glowey's Gear's text in the game's language.
--
-- The English text is the key: L["Spec"] is "Spec" on an English client, and on any other client
-- whose file has no line for it, so a missing line only shows English. Nothing is ever written to
-- L on a miss.
--
-- One file per language sits next to this one and returns at once on any other client:
--   local _, ns = ...
--   if ns.LOCALE ~= "deDE" then return end
--   local L = ns.L
--   L["Spec"] = "Spezialisierung"
-- Sentences are whole format strings ("Scoring gear for %s, level %d."), never glued from pieces,
-- so each language can put the words in its own order. What is saved or typed stays English:
-- setting keys, dropdown keys, spec keys, slash words.
--
-- Where the game has its own word for a thing, the game's word is used on other clients: slot
-- names, stat names and talent tree names never pass through this table at all (the game hands
-- them over already translated), and the few keys in GAME below take a global string.
-- Tools/locales.py checks that every key the code uses has a line in every language, that no
-- line is left over, and that the format holes match.

local ADDON, ns = ...

-- The language of the addon's own text, ns.LOCALE: Daylight UI's own pick while it runs (its Home >
-- Language, since 2.2.5), else the Language picked on the General page of Glowey's Plugins window
-- (Host.lua), else the game's. One of the seven there are files for; enGB reads enUS, esMX esES.
-- The game's own words (GAME below, ns.GameText) stay in the game's language.
local CLIENT = GetLocale and GetLocale() or "enUS"
local FOLD = { enGB = "enUS", esMX = "esES" }
local HAVE = { enUS = true, deDE = true, esES = true, frFR = true, ruRU = true, koKR = true, zhCN = true }
local function Picked()
	local D = rawget(_G, "DaylightUI")
	if type(D) == "table" and type(D.API) == "table" and D.API.major == 1 then
		-- (Its pick is on from its own ADDON_LOADED, which comes before any addon loading after it:
		-- DaylightUI/Locales/Locales.lua:16-20, Core.lua:984-992. Its saved pick, should it not be.)
		local pick = D.LOCALE
		local db = rawget(_G, "DaylightUIDB")
		local saved = type(db) == "table" and db.language
		if type(saved) == "string" and saved ~= "auto" and pick == D.CLIENT_LOCALE then pick = saved end
		return pick
	end
	-- (Kept in every Glowey addon's <Addon>Settings, the newest counting. Ours can be read this early
	-- because the .toc loads the saved variables first: LoadSavedVariablesFirst.)
	local best, at
	local own = rawget(_G, ADDON .. "Settings")
	if type(own) == "table" and type(own.general) == "table" then best, at = own.general.language, own.generalAt or 0 end
	local host = rawget(_G, "GloweyHost")
	local S = type(host) == "table" and host.state
	if type(S) == "table" and type(S.general) == "table" and (S.generalAt or -1) >= (at or -1) then best = S.general.language end
	return best
end
local pick = Picked()
pick = type(pick) == "string" and (FOLD[pick] or pick) or nil
ns.LOCALE = (pick and HAVE[pick]) and pick or (FOLD[CLIENT] or CLIENT)
-- ENGLISH: the game's words don't stand in for ours (an English game, or our text picked in another
-- language than the game's).
local ENGLISH = CLIENT:sub(1, 2) == "en" or ns.LOCALE ~= (FOLD[CLIENT] or CLIENT)

-- Keys whose English is word for word one of the game's global strings, in the same sense: on a
-- non-English client the game's own translation stands in for ours, which stays as the fallback
-- when the client lacks the global. English clients keep ours.
local GAME = {
	["Auto"] = "SELF_CAST_AUTO",
}

-- The game's text for a key in GAME, on a non-English client that has it; else nil.
local function Game(key)
	local global = not ENGLISH and GAME[key]
	local v = global and _G[global]
	if type(v) == "string" and v ~= "" then return v end
	return nil
end

-- A language file's line for a key in GAME is kept only where the game has no text for it.
ns.L = setmetatable({}, {
	__index = function(_, key) return Game(key) or key end,
	__newindex = function(t, key, value) rawset(t, key, Game(key) or value) end,
})

-- The game's own string (a global such as INVTYPE_HEAD) on any client that has it; else ours.
-- For words the game already has in every language: slot and stat names.
function ns.GameText(global, ours)
	local v = _G[global]
	if type(v) == "string" and v ~= "" then return v end
	return ours
end

local FORM
if ns.LOCALE == "ruRU" then
	FORM = function(n)
		local ten, hundred = n % 10, n % 100
		if ten == 1 and hundred ~= 11 then return "one" end
		if ten >= 2 and ten <= 4 and (hundred < 12 or hundred > 14) then return "few" end
		return "many"
	end
elseif ns.LOCALE == "frFR" then
	FORM = function(n) return n <= 1 and "one" or "many" end
elseif ns.LOCALE == "koKR" or ns.LOCALE == "zhCN" then
	FORM = function() return "many" end
else
	FORM = function(n) return n == 1 and "one" or "many" end
end

-- Counted words: ns.Plural(n, L["%d upgrade"], L["%d upgrades"], L["%d upgrades#few"]).
-- Russian has three forms; its third ("few": 2-4, 22-24, ...) is a key ending in "#few" that
-- only ruRU.lua carries. French uses "one" for 0 and 1; Korean and Chinese have a single form.
function ns.Plural(n, one, many, few)
	n = tonumber(n) or 0
	local form = FORM(math.floor(math.abs(n)))
	local text = form == "one" and one or (form == "few" and few) or many
	return text:format(n)
end
