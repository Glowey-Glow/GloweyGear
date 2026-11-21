-- Glowey's Gear: every read of the game the engine makes, in one place.
-- The engine (Stats, Spec, Score, Compare, Rank) never calls the game itself: it calls ns.Game.
-- The offline tests replace this whole table with a mock (Tools/tests/mocks.lua), so this file is
-- the only part of the engine that cannot be tested outside the game. Keep it thin: one guarded
-- call per function, no decisions.
--
-- Every call here was checked in the client's generated API docs (DOC = Blizzard_APIDocumentation
-- Generated, branch forever) or, where the docs have no entry, in the client's own UI source (FX).
-- None of them is a character-sheet stat call: those (UnitStat, GetCombatRating, GetHitModifier,
-- GetSpellHitModifier) turn secret in a fight (DOC PlayerScriptDocumentation.lua:303, :533, :1113)
-- and this plugin never reads them. What is read here carries no secret marker on its returns;
-- values are still passed through Plain() so a later client that marks one cannot raise an error.
--
-- luacheck: read globals C_Item C_Traits C_SpecializationInfo C_SkillInfo C_SpellBook C_Container
-- luacheck: read globals GetInventoryItemLink UnitClass UnitLevel InCombatLockdown debugprofilestop
-- luacheck: read globals issecretvalue NUM_BAG_SLOTS IsSpellKnown C_TooltipInfo Enum UnitGUID
-- luacheck: read globals GetProfessions GetProfessionInfo C_TradeSkillUI
-- luacheck: read globals UnitName UnitFactionGroup GetRealmName GetRealmID GetTimePreciseSec GetTime

local _, ns = ...

local Game = {}
ns.Game = Game

local secret = issecretvalue

-- A value the addon may compare and do arithmetic on, or nil.
local function Plain(v)
	if v == nil or (secret and secret(v)) then return nil end
	return v
end

-- C_Item.GetItemStats(link) -> { ITEM_MOD_STRENGTH_SHORT = 5, ... }, or nil while the item's data
-- has not arrived (DOC ItemDocumentation.lua:1004-1018, "MayReturnNothing"). The keys are names of
-- the game's global strings (Stats.lua says where its list of them comes from). A table holding
-- anything the addon may not read is treated as "not there yet": the engine does arithmetic on
-- these numbers, and one unreadable value inside the bag mark's callback would cost the mark
-- for the session.
function Game.ItemStats(link)
	local f = C_Item and C_Item.GetItemStats
	if not f then return nil end
	local ok, t = pcall(f, link)
	if not ok or type(t) ~= "table" then return nil end
	if secret then
		for key, value in pairs(t) do
			if secret(key) or secret(value) then return nil end
		end
	end
	return t
end

-- What kind of thing a link is, with no wait on the server:
-- equipLoc, classID, subclassID (C_Item.GetItemInfoInstant, DOC ItemDocumentation.lua:659-678).
function Game.ItemInstant(link)
	local f = C_Item and C_Item.GetItemInfoInstant
	if not f then return nil end
	local ok, id, _, _, equipLoc, _, classID, subclassID = pcall(f, link)
	if ok and id then return equipLoc, classID, subclassID end
	return nil
end

-- name, quality, minLevel, sellPrice; nil while the item is not cached
-- (C_Item.GetItemInfo, DOC ItemDocumentation.lua:626-656: returns 1, 3, 5 and 11).
function Game.ItemInfo(link)
	local f = C_Item and C_Item.GetItemInfo
	if not f then return nil end
	local ok, name, _, quality, _, minLevel, _, _, _, _, _, sellPrice = pcall(f, link)
	if ok and Plain(name) then return name, Plain(quality), Plain(minLevel), Plain(sellPrice) end
	return nil
end

-- A weapon's swing time in seconds. No call gives it without reading the tooltip's text
-- (design/data-format.md, 3.6), so stage 1 answers nil and the speed weights count for nothing.
function Game.ItemSpeed(_link)
	return nil
end

-- How many effect lines an item's tooltip has, by kind: equip, use, proc; nil when the game
-- cannot say. Language-free: C_TooltipInfo.GetHyperlink (DOC TooltipInfoDocumentation.lua:337-353)
-- answers the tooltip as data, each line with a `type` (the client's own tooltip code reads
-- lineData.type: FX Blizzard_SharedXMLGame\Tooltip\TooltipDataHandler.lua:320-334), and the
-- line types include ItemSpellTriggerOnUse (44), ItemSpellTriggerOnEquip (45) and
-- ItemSpellTriggerOnProc (46) (DOC TooltipInfoSharedDocumentation.lua:78-80; the public wiki's
-- Enum.TooltipDataLineType page lists the same three, added in 12.1.0). Only the types are read,
-- never the text. Whether this client fills those types for every "Equip:" line, or only for
-- effects that are spells, is a game check (design/in-game-check.md): Stats.Uncounted is written
-- to be right either way.
function Game.ItemEffects(link)
	local f = C_TooltipInfo and C_TooltipInfo.GetHyperlink
	local kinds = Enum and Enum.TooltipDataLineType
	if not f or type(kinds) ~= "table" then return nil end
	local onEquip, onUse, onProc = kinds.ItemSpellTriggerOnEquip, kinds.ItemSpellTriggerOnUse, kinds.ItemSpellTriggerOnProc
	if not (onEquip and onUse and onProc) then return nil end
	local ok, data = pcall(f, link)
	if not ok or type(data) ~= "table" or type(data.lines) ~= "table" then return nil end
	local equip, use, proc = 0, 0, 0
	for _, line in ipairs(data.lines) do
		local kind = type(line) == "table" and Plain(line.type) or nil
		if kind == onEquip then
			equip = equip + 1
		elseif kind == onUse then
			use = use + 1
		elseif kind == onProc then
			proc = proc + 1
		end
	end
	return equip, use, proc
end

-- For /gear debug only: the names of the fields the game puts on an item's effect lines
-- ("type, leftText, leftColor, ..."), so one look in the game says whether such a line carries
-- anything beyond its text (the docs type a line's extras loosely, as TooltipDataArg:
-- DOC TooltipInfoSharedDocumentation.lua:163-174). Names only; no value is read.
function Game.ItemEffectFields(link)
	local f = C_TooltipInfo and C_TooltipInfo.GetHyperlink
	local kinds = Enum and Enum.TooltipDataLineType
	if not f or type(kinds) ~= "table" then return nil end
	local ok, data = pcall(f, link)
	if not ok or type(data) ~= "table" or type(data.lines) ~= "table" then return nil end
	local seen, names = {}, {}
	for _, line in ipairs(data.lines) do
		local kind = type(line) == "table" and Plain(line.type) or nil
		if kind ~= nil and (kind == kinds.ItemSpellTriggerOnEquip or kind == kinds.ItemSpellTriggerOnUse
			or kind == kinds.ItemSpellTriggerOnProc) then
			for key in pairs(line) do
				if type(key) == "string" and not seen[key] then
					seen[key] = true
					names[#names + 1] = key
				end
			end
		end
	end
	table.sort(names)
	return names
end

-- Whether only one of the item can be worn (C_Item.GetItemUniquenessByID, DOC
-- ItemDocumentation.lua:1055-1072; its argument is an "ItemInfo": an ID, a name or a link).
function Game.ItemUnique(link)
	local f = C_Item and C_Item.GetItemUniquenessByID
	if not f then return false end
	local ok, unique = pcall(f, link)
	return ok and Plain(unique) == true
end

-- Whether the game has an item's data already: true, false, or nil when it cannot say.
-- C_Item.IsItemDataCachedByID (DOC ItemDocumentation.lua:1520-1533; the argument is an
-- "ItemInfo": an ID, a name or a link; the client's own item object asks the same way,
-- FX Blizzard_ObjectAPI\Mainline\Item.lua:295). Asking does not make the game load anything,
-- which C_Item.GetItemInfo on an item it has not got does.
function Game.ItemCached(link)
	local f = C_Item and C_Item.IsItemDataCachedByID
	if not f then return nil end
	local ok, cached = pcall(f, link)
	if not ok then return nil end
	cached = Plain(cached)
	if type(cached) == "boolean" then return cached end
	return nil
end

-- Asks the game to load an item's data; ITEM_DATA_LOAD_RESULT follows (DOC
-- ItemDocumentation.lua:1710, event :1857).
function Game.RequestItem(itemID)
	local f = C_Item and C_Item.RequestLoadItemDataByID
	if f and type(itemID) == "number" then pcall(f, itemID) end
end

-- The player's class token ("WARRIOR"): UnitClass's second return, classFilename, which is not a
-- conditional secret (DOC UnitDocumentation.lua:911-926). Kept once read: it never changes.
local classToken
function Game.Class()
	if classToken then return classToken end
	local ok, _, token = pcall(UnitClass, "player")
	token = ok and Plain(token) or nil
	if type(token) == "string" then classToken = token end
	return classToken
end

-- The player's level (UnitLevel, DOC UnitDocumentation.lua:2474-2486: no secret marker).
function Game.Level()
	local ok, level = pcall(UnitLevel, "player")
	level = ok and Plain(level) or nil
	if type(level) == "number" and level > 0 then return level end
	return nil
end

-- The three talent trees of the active build, left to right:
--   { { name = "Arms", spent = 31 }, { ... }, { ... } }, or nil while the game has none to give.
-- This client keeps classic's three trees in the trait system; its own talent window reads them
-- this way (FX Blizzard_PlayerSpells\Camelot\ClassTalents\Blizzard_ClassTalentsFrame.lua:86-108,
-- :111-120, :183), and each call is in the generated docs (the second reference):
--   GetActiveSpecGroup            DOC SpecializationInfoDocumentation.lua:41-56
--   GetCombatConfigIDForSpecGroup DOC SpecializationInfoDocumentation.lua:90-104
--   C_Traits.GetConfigInfo        DOC SharedTraitsDocumentation.lua:201-215
--   GetGroupDisplayInfoByTreeID   DOC SharedTraitsDocumentation.lua:297-310 (struct :1080-1091)
--   GetGroupCurrencyInfo          DOC SharedTraitsDocumentation.lua:281-295
function Game.Trees()
	local S, T = C_SpecializationInfo, C_Traits
	if not (S and T and S.GetActiveSpecGroup and S.GetCombatConfigIDForSpecGroup and T.GetConfigInfo
		and T.GetGroupDisplayInfoByTreeID and T.GetGroupCurrencyInfo) then
		return nil
	end
	local ok, trees = pcall(function()
		local group = S.GetActiveSpecGroup()
		local configID = group and S.GetCombatConfigIDForSpecGroup(group)
		if not configID then return nil end
		local config = T.GetConfigInfo(configID)
		local treeID = config and config.treeIDs and config.treeIDs[1]
		if not treeID then return nil end
		local shown = T.GetGroupDisplayInfoByTreeID(treeID)
		if type(shown) ~= "table" or #shown == 0 then return nil end
		local ids = {}
		for i, info in ipairs(shown) do ids[i] = info.groupID end
		-- (Matched by ID: nothing says the answer comes back in the order asked.)
		local spent = {}
		for _, info in ipairs(T.GetGroupCurrencyInfo(configID, ids) or {}) do
			local currency = info.currencyInfos and info.currencyInfos[1]
			if currency then spent[info.traitNodeGroupID] = Plain(currency.spent) end
		end
		local out = {}
		for i, info in ipairs(shown) do
			out[i] = { name = Plain(info.displayName), order = Plain(info.orderIndex) or i,
				spent = spent[info.groupID] or 0 }
		end
		table.sort(out, function(a, b) return a.order < b.order end)
		return out
	end)
	if ok and type(trees) == "table" then return trees end
	return nil
end

-- Whether the character has a skill line (a weapon skill): true, false, or nil when the game
-- cannot say. C_SkillInfo.GetSkillLineInfoByID (DOC SkillInfoDocumentation.lua:74-87) is typed
-- as answering nil for some IDs, and the client's character sheet reads weapon skills with it
-- and shows a row only when it answers (FX Blizzard_UIPanels_Game\Camelot\PaperDollFrame.lua
-- :729-741). Whether nil means exactly "not learned" is a game check; Score.lua is safe either
-- way (no skill readable at all = the class table decides).
function Game.KnowsSkill(line)
	local f = C_SkillInfo and C_SkillInfo.GetSkillLineInfoByID
	if not f then return nil end
	local ok, info = pcall(f, line)
	if not ok then return nil end
	return type(info) == "table"
end

-- The character's skill in a profession (its skill line): a number, false when the character has
-- not learned it, nil when the game cannot say. The profession list first: GetProfessions and
-- GetProfessionInfo are what the client's own profession book reads (FX Blizzard_ProfessionsBook\
-- Camelot\Blizzard_ProfessionsBook.lua:21, :55: rank the 3rd value, the skill line the 7th, the
-- rank's modifier the 8th). A line that list does not hold (Herbalism is in it, a weapon skill is
-- not) is asked of C_SkillInfo.GetSkillLineInfoByID (rank, modifier: DOC
-- SkillInfoDocumentation.lua:113-132). The modifier (a racial or worn bonus) counts: the game
-- shows a skill as rank plus modifier (FX Blizzard_UIPanels_Game\Camelot\PaperDollFrameStats.lua:
-- 710-717), and an item's requirement is met by that value.
function Game.SkillRank(line)
	local listed = false
	if GetProfessions and GetProfessionInfo then
		local ok, a, b, c, d, e, f = pcall(GetProfessions)
		if ok then
			listed = true
			for _, index in pairs({ a, b, c, d, e, f }) do
				local fine, _, _, rank, _, _, _, skillLine, modifier = pcall(GetProfessionInfo, index)
				if fine and Plain(skillLine) == line and type(Plain(rank)) == "number" then
					modifier = Plain(modifier)
					return rank + (type(modifier) == "number" and modifier or 0)
				end
			end
		end
	end
	local f = C_SkillInfo and C_SkillInfo.GetSkillLineInfoByID
	if f then
		local ok, info = pcall(f, line)
		if ok and type(info) == "table" then
			local rank, modifier = Plain(info.rank), Plain(info.modifier)
			if type(rank) == "number" then return rank + (type(modifier) == "number" and modifier or 0) end
		end
		if ok then return false end
	end
	if listed then return false end
	return nil
end

-- A profession's name in the player's language by its skill line, or nil: the game's own
-- (C_TradeSkillUI.GetTradeSkillDisplayName, DOC TradeSkillUIDocumentation.lua:882).
function Game.SkillName(line)
	local f = C_TradeSkillUI and C_TradeSkillUI.GetTradeSkillDisplayName
	if not f then return nil end
	local ok, name = pcall(f, line)
	name = ok and Plain(name) or nil
	return type(name) == "string" and name ~= "" and name or nil
end

-- Whether the character knows a spell (C_SpellBook.IsSpellKnown, DOC
-- SpellBookDocumentation.lua:738-753; the older global where the namespace lacks it).
function Game.KnowsSpell(spellID)
	local f = (C_SpellBook and C_SpellBook.IsSpellKnown) or IsSpellKnown
	if not f then return false end
	local ok, known = pcall(f, spellID)
	return ok and Plain(known) == true
end

-- The link of what is worn in a slot (1 to 18). GetInventoryItemLink is not in the generated
-- docs; the client's own character sheet calls it (FX Blizzard_UIPanels_Game\Camelot\
-- PaperDollFrame.lua:2172) and so does its inspect window.
function Game.WornLink(slot)
	if not GetInventoryItemLink then return nil end
	local ok, link = pcall(GetInventoryItemLink, "player", slot)
	link = ok and Plain(link) or nil
	if type(link) == "string" then return link end
	return nil
end

-- The links of everything in the bags (the backpack and the four bag slots), into `out`.
-- C_Container.GetContainerNumSlots / GetContainerItemLink (DOC ContainerDocumentation.lua:313,
-- :209). The bank is not read: "carried" means on the character.
function Game.BagLinks(out)
	out = out or {}
	local C = C_Container
	if not (C and C.GetContainerNumSlots and C.GetContainerItemLink) then return out end
	for bag = 0, (NUM_BAG_SLOTS or 4) do
		local ok, slots = pcall(C.GetContainerNumSlots, bag)
		slots = ok and Plain(slots) or nil
		for slot = 1, tonumber(slots) or 0 do
			local got, link = pcall(C.GetContainerItemLink, bag, slot)
			link = got and Plain(link) or nil
			if type(link) == "string" then out[#out + 1] = link end
		end
	end
	return out
end

-- The frame's time in seconds: the same value for everything that runs in one frame (GetTime,
-- the global every part of the client's UI uses for it).
function Game.Time()
	if not GetTime then return 0 end
	local ok, t = pcall(GetTime)
	return ok and type(t) == "number" and t or 0
end

-- The part of the character's hit chance that does not come from ratings (talents, mostly):
-- melee, ranged, spell, in percent; nil when the game keeps them secret (in a fight). The
-- client's own character sheet adds exactly these to the rating's share (FX Blizzard_UIPanels_
-- Game\Camelot\PaperDollFrameStats.lua:524-527); the docs mark all three as secret while unit
-- stats are restricted (DOC PlayerScriptDocumentation.lua:533-541, :946, :1113).
function Game.HitModifiers()
	local m, r, s = rawget(_G, "GetHitModifier"), rawget(_G, "GetRangedHitModifier"), rawget(_G, "GetSpellHitModifier")
	if type(m) ~= "function" or type(s) ~= "function" then return nil end
	local okM, melee = pcall(m)
	local okS, spell = pcall(s)
	local okR, ranged = false, nil
	if type(r) == "function" then okR, ranged = pcall(r) end
	melee, spell, ranged = okM and Plain(melee) or nil, okS and Plain(spell) or nil, okR and Plain(ranged) or nil
	if type(melee) ~= "number" or type(spell) ~= "number" then return nil end
	return melee, type(ranged) == "number" and ranged or melee, spell
end

-- The rewards a quest lets the player choose between, while its reward page is up: fills
-- out[i] = { link = (nil while the item is not loaded), count = } and returns how many.
-- GetNumQuestChoices, GetQuestItemLink(type, index), GetQuestItemInfo(type, index) -> name,
-- texture, count, quality, usable, itemID: the game's own quest frame calls them so (FX
-- Blizzard_UIPanels_Game\Mainline\QuestInfo.lua:526, :647; QuestFrame.lua:743).
-- kind = "reward": the rewards given without a choice instead (GetNumQuestRewards, the
-- same two item calls with "reward": FX ...\Mainline\QuestInfo.lua:526, :546, :646).
function Game.QuestChoices(out, kind)
	kind = kind == "reward" and "reward" or "choice"
	local num, link, info = rawget(_G, kind == "reward" and "GetNumQuestRewards" or "GetNumQuestChoices"),
		rawget(_G, "GetQuestItemLink"), rawget(_G, "GetQuestItemInfo")
	if type(num) ~= "function" or type(link) ~= "function" then return 0 end
	local ok, n = pcall(num)
	n = ok and Plain(n) or 0
	if type(n) ~= "number" then return 0 end
	for i = 1, n do
		local okL, l = pcall(link, kind, i)
		l = okL and Plain(l) or nil
		local count = 1
		if type(info) == "function" then
			local okI, _, _, c = pcall(info, kind, i)
			c = okI and Plain(c) or nil
			if type(c) == "number" and c > 0 then count = c end
		end
		out[i] = { link = type(l) == "string" and l ~= "" and l or nil, count = count }
	end
	return n
end

function Game.InCombat()
	return InCombatLockdown and InCombatLockdown() and true or false
end

-- Milliseconds, for work spread over frames. GetTimePreciseSec (DOC OsDocumentation.lua:27) is
-- a clock nobody can reset; debugprofilestop (DOC FrameScriptDocumentation.lua:533) is the
-- stand-by, and another addon calling debugprofilestart sets that one back to zero.
function Game.Clock()
	if GetTimePreciseSec then
		local ok, t = pcall(GetTimePreciseSec)
		if ok and type(t) == "number" then return t * 1000 end
	end
	return debugprofilestop and debugprofilestop() or 0
end

-- Who this character is, whatever the game says the realm is called.
-- UnitGUID("player") is "Player-<realm number>-<character number>" (DOC UnitDocumentation.lua
-- :1241-1254; the public wiki's GUID page gives the same three parts), and it stays the same
-- when a realm is renamed or, as on this client since 2026-11-20, GetRealmName() answers an
-- empty string (Daylight UI 2.1.2 keys its own characters by GUID for the same reason:
-- DUI DaylightUI\DB.lua:181-316).
--   Game.Guid()    -> the GUID, or nil while the game does not know the character
--   Game.Name()    -> the character's name, or nil
--   Game.Realm()   -> the realm's name, or nil when the game gives none (never "")
--   Game.RealmID() -> the realm's number: GetRealmID() (DOC ConnectionDocumentation.lua:60-67)
--                     when it is above 0, else the middle part of the GUID; nil when neither
--   Game.Faction() -> "Alliance" | "Horde" | nil
local function text(fn, ...)
	if not fn then return nil end
	local ok, v = pcall(fn, ...)
	v = ok and Plain(v) or nil
	if type(v) == "string" and v ~= "" then return v end
	return nil
end

function Game.Guid() return text(UnitGUID, "player") end
function Game.Name() return text(UnitName, "player") end
function Game.Realm() return text(GetRealmName) end
function Game.Faction() return text(UnitFactionGroup, "player") end

function Game.RealmID()
	if GetRealmID then
		local ok, id = pcall(GetRealmID)
		id = ok and Plain(id) or nil
		if type(id) == "number" and id > 0 then return id end
	end
	local guid = Game.Guid()
	return guid and tonumber(guid:match("^Player%-(%d+)%-")) or nil
end
