-- Glowey's Gear: an item link turned into a plain table of stats the scorer can read.
--
--   Stats.Of(link)        -> record | nil, why     why: "pending" (the game has not loaded the item
--                                                  yet: ask again later), "notgear", "bad"
--   Stats.Key(link)       -> the link's identity for caches and "is it the same item" checks;
--                            "item:" .. key is a link the game accepts
--   Stats.ItemID(link)    -> number | nil
--   Stats.IsRolled(link)  -> the link carries a random roll ("... of the Bear")
--   Stats.Normalize(raw, equipLoc) -> { STR = 5, CRIT = 1, ... }     (pure: no game call)
--   Stats.Classify(gameKey)        -> "scored" | "weapon" | "ignored" | nil (never seen before)
--   Stats.Uncounted(rec)  -> how many of the item's effects the score leaves out (0 when none,
--                            or when the game cannot say); asked only for items that are shown
--   Stats.Forget()        -> drops the cache (item data arrived, or a test starts over)
--
-- A record: { key, id, link, name, quality, minLevel, equipLoc, classID, subclassID, sellPrice,
--             unique, speed, stats = { <canonical key> = number }, counted = <stat lines read> }
--
-- WHERE THE TABLES BELOW COME FROM. C_Item.GetItemStats answers a table whose keys are the names
-- of the game's own global strings (the public wiki's page for the call says so and shows
-- ITEM_MOD_STAMINA_SHORT, RESISTANCE0_NAME and others). The full set of those names was read out
-- of this client's own GlobalStrings database (file 1394440 in the installed game, read with
-- Tools/client_facts.py: 234 names starting ITEM_MOD_, RESISTANCE0_NAME to RESISTANCE6_NAME, 23
-- starting EMPTY_SOCKET_), together with the English sentence each name stands for, which is
-- what decides where a stat is filed ("Increases healing done by magical spells and effects by
-- up to %s." is healing). Every one of those names is either scored here or listed as known and
-- left out; Tools/tests/test_stats.lua holds the client's list and fails if one is neither.
-- The rating figures are the client's own combat ratings table (file 1391669, the same number
-- on every one of its 123 level rows), with the wowsims/forever simulator (MIT) as the second
-- reference (Data/README.md). design/data-format.md, sections 2 and 3, is the contract.
--
-- Pure Lua apart from ns.Game, which the tests replace.

local _, ns = ...

local Stats = {}
ns.Stats = Stats

-- ---------------------------------------------------------------------------------------------
-- Canonical keys (what a weights table may name)
-- ---------------------------------------------------------------------------------------------
local KEYS = {}
for word in ([[
	STR AGI STA INT SPI ARMOR HEALTH MANA
	AP RAP FERAL_AP
	SPELL_DMG HEAL
	SPELL_DMG_ARCANE SPELL_DMG_FIRE SPELL_DMG_FROST SPELL_DMG_HOLY SPELL_DMG_NATURE SPELL_DMG_SHADOW
	HIT CRIT SPELL_HIT SPELL_CRIT HASTE EXPERTISE ARMOR_PEN
	DODGE PARRY BLOCK BLOCK_VALUE DEFENSE
	MP5 HP5 SPELL_PEN
	RES_FIRE RES_NATURE RES_FROST RES_SHADOW RES_ARCANE
	MH_DPS OH_DPS RANGED_DPS MH_SPEED OH_SPEED RANGED_SPEED
]]):gmatch("%S+") do
	KEYS[word] = true
end
Stats.KEYS = KEYS

-- ---------------------------------------------------------------------------------------------
-- Ratings
-- ---------------------------------------------------------------------------------------------
-- How many points of a rating make one unit of the canonical stat. Each figure is the column of
-- the client's combat ratings table named beside it; the table holds the same figure at every
-- level from 1 to 123, so one number each is enough.
local RATING_PER_UNIT = {
	HIT = 10,          -- "Hit - Melee", "Hit - Ranged"
	SPELL_HIT = 10,    -- "Hit - Spell"
	CRIT = 14,         -- "Crit - Melee", "Crit - Ranged"
	SPELL_CRIT = 14,   -- "Crit - Spell"
	HASTE = 10,        -- "Haste - Melee", "Haste - Ranged", "Haste - Spell"
	EXPERTISE = 10,    -- "Expertise"
	ARMOR_PEN = 10,    -- "Armor Penetration"
	DODGE = 12,        -- "Dodge"
	PARRY = 15,        -- "Parry"
	BLOCK = 5,         -- "Block"
	DEFENSE = 1,       -- "Defense Skill": one rating is one point of skill
}
Stats.RATING_PER_PERCENT = RATING_PER_UNIT

-- ---------------------------------------------------------------------------------------------
-- The game's stat names
-- ---------------------------------------------------------------------------------------------
-- A stat has up to two names in the game, one ending in _SHORT and one without (the long
-- sentence and the short label of the same stat). The stat call mostly answers the _SHORT name,
-- but not always: a healing bonus has been seen to arrive under the bare name. So a name is
-- reduced to its STEM, with "ITEM_MOD_" and a trailing "_SHORT" taken off, and every stem below
-- answers for both.
local function Stem(key)
	local stem = key:match("^ITEM_MOD_(.+)$")
	if not stem then return nil end
	return (stem:gsub("_SHORT$", ""))
end

-- stem -> what it adds to. One entry per line of meaning:
--   to     the canonical key, or a list of them (the amount goes to each)
--   rated  true when the game's number is a rating (divided by RATING_PER_UNIT of each target)
local READ = {}

local function points(stems, to)
	for stem in stems:gmatch("%S+") do READ[stem] = { to = to } end
end
local function rating(stems, to)
	for stem in stems:gmatch("%S+") do READ[stem] = { to = to, rated = true } end
end

-- The five attributes, and the two pools.
points("STRENGTH", "STR")
points("AGILITY", "AGI")
points("STAMINA", "STA")
points("INTELLECT", "INT")
points("SPIRIT", "SPI")
points("HEALTH", "HEALTH")
points("MANA", "MANA")

-- Regeneration: "Mana Per 5 Sec." (power type 0 is mana) and "Restores %s mana per 5 sec.";
-- "Health Per 5 Sec." and "Restores %s health per 5 sec.".
points("POWER_REGEN0 MANA_REGENERATION", "MP5")
points("HEALTH_REGEN HEALTH_REGENERATION", "HP5")

-- Attack power. "Increases attack power by %s." raises melee and ranged attack power alike, so
-- it is filed under both: what such a point is worth to a spec is its AP weight plus its RAP
-- weight (a hunter's table holds a small melee share and a large ranged one; a warrior's has no
-- RAP weight at all). "Melee Attack Power" and "ranged attack power" go to their one side;
-- "Attack Power In Forms" is the druid's.
points("ATTACK_POWER", { "AP", "RAP" })
points("MELEE_ATTACK_POWER", "AP")
points("RANGED_ATTACK_POWER", "RAP")
points("FERAL_ATTACK_POWER", "FERAL_AP")

-- Spell power. "Increases spell power by %s." is damage and healing in one; the damage-only and
-- healing-only sentences are stats of their own that an item lists beside it, so adding all
-- three never counts a point twice. A school's damage ("Increases fire damage done by up to
-- %s.") is its own key and is not folded into SPELL_DMG.
points("SPELL_POWER", { "SPELL_DMG", "HEAL" })
points("SPELL_DAMAGE_DONE", "SPELL_DMG")
points("SPELL_HEALING_DONE", "HEAL")
for school in ("ARCANE FIRE FROST HOLY NATURE SHADOW"):gmatch("%S+") do
	points(school .. "_DAMAGE_DONE", "SPELL_DMG_" .. school)
end
points("SPELL_PENETRATION", "SPELL_PEN")

-- A school's resistance on gear. These five names are NOT in the client's readable string list:
-- they were met in play (the owner's /gear debug of 2026-11-20 reported each a few hundred
-- times as unknown), which is the report doing its job. Holy has no gear and is left out.
for school in ("ARCANE FIRE FROST NATURE SHADOW"):gmatch("%S+") do
	points(school .. "_RESISTANCE", "RES_" .. school)
end

-- Defense that is not a rating.
points("BLOCK_VALUE", "BLOCK_VALUE")
points("SPELL_RESISTANCE_ALL_SCHOOLS", { "RES_FIRE", "RES_NATURE", "RES_FROST", "RES_SHADOW", "RES_ARCANE" })

-- Ratings. "Increases your hit by %s." and "Increases your critical strike by %s." are the
-- general ones: the game has separate sentences for melee, ranged and spell hit and crit, and
-- the general rating moves all three, so it is filed under the physical and the spell key. A
-- spec's table weights the side it uses (design/data-format.md, 3.2).
rating("HIT_RATING", { "HIT", "SPELL_HIT" })
rating("HIT_MELEE_RATING HIT_RANGED_RATING", "HIT")
rating("HIT_SPELL_RATING", "SPELL_HIT")
rating("CRIT_RATING", { "CRIT", "SPELL_CRIT" })
rating("CRIT_MELEE_RATING CRIT_RANGED_RATING", "CRIT")
rating("CRIT_SPELL_RATING", "SPELL_CRIT")
rating("HASTE_RATING", "HASTE")
rating("EXPERTISE_RATING", "EXPERTISE")
rating("ARMOR_PENETRATION_RATING", "ARMOR_PEN")
rating("DODGE_RATING", "DODGE")
rating("PARRY_RATING", "PARRY")
rating("BLOCK_RATING", "BLOCK")
rating("DEFENSE_SKILL_RATING", "DEFENSE")

-- Names that are not ITEM_MOD_ ones: armor and the resistances, numbered by school as the
-- game's own labels read ("Armor", "Holy Resistance", "Fire Resistance", "Nature Resistance",
-- "Frost Resistance", "Shadow Resistance", "Arcane Resistance").
local OTHER = {
	RESISTANCE0_NAME = "ARMOR",
	RESISTANCE2_NAME = "RES_FIRE",
	RESISTANCE3_NAME = "RES_NATURE",
	RESISTANCE4_NAME = "RES_FROST",
	RESISTANCE5_NAME = "RES_SHADOW",
	RESISTANCE6_NAME = "RES_ARCANE",
}

-- A weapon's damage per second: one number, filed by the hand the weapon is held in.
local DPS_STEM = "DAMAGE_PER_SECOND"
local DPS_KEY = {
	INVTYPE_2HWEAPON = "MH_DPS", INVTYPE_WEAPONMAINHAND = "MH_DPS", INVTYPE_WEAPON = "MH_DPS",
	INVTYPE_WEAPONOFFHAND = "OH_DPS",
	INVTYPE_RANGED = "RANGED_DPS", INVTYPE_RANGEDRIGHT = "RANGED_DPS", INVTYPE_THROWN = "RANGED_DPS",
}
local SPEED_KEY = { MH_DPS = "MH_SPEED", OH_DPS = "OH_SPEED", RANGED_DPS = "RANGED_SPEED" }
Stats.DPS_KEY = DPS_KEY

-- Known and left out, on purpose. Stems the client has a name for that no weights table can
-- value: either the stat does not exist under this game's rules, or it says nothing a single
-- number per spec could use.
local LEFT_OUT = {}
for stem in ([[
	EXTRA_ARMOR
	PHYSICAL_DAMAGE_DONE
	ARCANE_PENETRATION FIRE_PENETRATION FROST_PENETRATION NATURE_PENETRATION SHADOW_PENETRATION
	POWER_REGEN1 POWER_REGEN2 POWER_REGEN3 POWER_REGEN4 POWER_REGEN5 POWER_REGEN6
	ATTACK_POWER_VS_BEAST ATTACK_POWER_VS_DEMON ATTACK_POWER_VS_DRAGONKIN ATTACK_POWER_VS_ELEMENTAL
	ATTACK_POWER_VS_GIANT ATTACK_POWER_VS_HUMANOID ATTACK_POWER_VS_MECHANICAL ATTACK_POWER_VS_UNDEAD
	SPELL_DAMAGE_VS_BEAST SPELL_DAMAGE_VS_DEMON SPELL_DAMAGE_VS_DRAGONKIN SPELL_DAMAGE_VS_ELEMENTAL
	SPELL_DAMAGE_VS_GIANT SPELL_DAMAGE_VS_HUMANOID SPELL_DAMAGE_VS_MECHANICAL SPELL_DAMAGE_VS_UNDEAD
	HIT_TAKEN_RATING HIT_TAKEN_MELEE_RATING HIT_TAKEN_RANGED_RATING HIT_TAKEN_SPELL_RATING
	CRIT_TAKEN_RATING CRIT_TAKEN_MELEE_RATING CRIT_TAKEN_RANGED_RATING CRIT_TAKEN_SPELL_RATING
	RESILIENCE_RATING PVP_POWER PVP_PRIMARY_STAT
	MASTERY_RATING MASTERY_RATING_SPELL MASTERY_RATING_TWO_SPELLS VERSATILITY
	CORRUPTION CORRUPTION_RESISTANCE
	AGILITY_OR_INTELLECT AGILITY_OR_STRENGTH AGILITY_OR_STRENGTH_OR_INTELLECT STRENGTH_OR_INTELLECT
	AXES TWOHANDED_AXES BOWS CROSSBOWS DAGGERS FIST_WEAPONS GUNS MACES TWOHANDED_MACES POLEARMS
	STAVES SWORDS TWOHANDED_SWORDS THROWN WANDS DUAL_WIELD
	ALCHEMY BLACKSMITHING COOKING ENCHANTING ENGINEERING FIRST_AID FISHING HERBALISM
	JEWELCRAFTING LEATHERWORKING MINING SKINNING TAILORING
	CRAFTING_SPEED DEFTNESS FINESSE INGENUITY INSPIRATION MULTICRAFT PERCEPTION RESOURCEFULNESS
	MODIFIED_CRAFTING_STAT_1 MODIFIED_CRAFTING_STAT_2
	HOLY_RESISTANCE
]]):gmatch("%S+") do
	LEFT_OUT[stem] = true
end
-- Why some of them, for whoever tunes this later:
--   EXTRA_ARMOR ("Bonus Armor") is taken to be inside the armor figure already (RESISTANCE0_NAME
--     is all the item's armor); adding it would count it twice. A game check is listed.
--   The weapon skills (SWORDS, ...), the "versus beasts" bonuses and school piercing are real
--     under classic rules but worth something only against one kind of target or with one kind
--     of weapon; no weights table has a key for them.
--   RESISTANCE1_NAME (Holy Resistance) and the empty-socket names are left out below.

-- Whole families the client names with a number or a word after a fixed start.
local function leftOutFamily(key)
	return key:find("^EMPTY_SOCKET_") ~= nil or key:find("^ITEM_MOD_CR_") ~= nil or key == "RESISTANCE1_NAME"
end

-- What a name from the stat call is to this file. nil = never seen: Normalize tallies it in
-- Stats.unknown and /gear debug prints the tally, so a name the client starts answering that is
-- in neither list shows up in one look.
function Stats.Classify(key)
	if type(key) ~= "string" then return nil end
	if OTHER[key] then return "scored" end
	if leftOutFamily(key) then return "ignored" end
	local stem = Stem(key)
	if not stem then return nil end
	if stem == DPS_STEM then return "weapon" end
	if READ[stem] then return "scored" end
	if LEFT_OUT[stem] then return "ignored" end
	return nil
end

-- Equip locations that are gear this plugin advises on. Shirts, tabards, bags, quivers and
-- ammunition are not.
local GEAR = {}
for loc in ([[
	HEAD NECK SHOULDER CHEST ROBE WAIST LEGS FEET WRIST HAND FINGER TRINKET CLOAK
	WEAPON SHIELD 2HWEAPON WEAPONMAINHAND WEAPONOFFHAND HOLDABLE RANGED RANGEDRIGHT THROWN RELIC
]]):gmatch("%S+") do
	GEAR["INVTYPE_" .. loc] = true
end
Stats.GEAR = GEAR

-- Names met that are in neither list, with how often.
Stats.unknown = {}

local function add(out, key, value)
	out[key] = (out[key] or 0) + value
end

local function give(out, to, value, rated)
	if type(to) == "string" then
		add(out, to, rated and value / RATING_PER_UNIT[to] or value)
	else
		for i = 1, #to do
			add(out, to[i], rated and value / RATING_PER_UNIT[to[i]] or value)
		end
	end
end

-- The game's stat table as canonical stats. Pure: the same input gives the same output, no game
-- call. Values that are not plain numbers are skipped. A rating is not rounded after dividing:
-- 7 crit rating is half a percent, and a weight multiplies it as such.
-- Second return: how many of the table's entries are bonuses the tooltip writes as an effect
-- line rather than as a plain "+5 Stamina" (everything but the attributes, armor, resistances
-- and weapon damage), for Stats.Uncounted.
local BASE = { STR = true, AGI = true, STA = true, INT = true, SPI = true }
function Stats.Normalize(raw, equipLoc)
	local out, bonuses = {}, 0
	if type(raw) ~= "table" then return out, bonuses end
	for key, value in pairs(raw) do
		if type(value) == "number" and type(key) == "string" then
			local other = OTHER[key]
			local stem = not other and Stem(key)
			local read = stem and READ[stem]
			if other then
				add(out, other, value)
			elseif read then
				give(out, read.to, value, read.rated)
				if not BASE[read.to] then bonuses = bonuses + 1 end
			elseif stem == DPS_STEM then
				local to = DPS_KEY[equipLoc or ""]
				if to then add(out, to, value) end
			elseif not ((stem and LEFT_OUT[stem]) or leftOutFamily(key)) then
				Stats.unknown[key] = (Stats.unknown[key] or 0) + 1
			else
				-- (Known and left out: still a line the tooltip shows, so it is not "missing".)
				if stem then bonuses = bonuses + 1 end
			end
		end
	end
	return out, bonuses
end

-- ---------------------------------------------------------------------------------------------
-- Links
-- ---------------------------------------------------------------------------------------------
-- An item string is "item:" and fields split by colons. The game's own format (the same order
-- in the public wiki's ItemLink page and in the client's bug-report code, which spells the
-- fields out: FX Blizzard_PTRFeedback\Blizzard_Reports.lua:391):
--
--    1 item ID          2 enchant           3-6 gems           7 suffix ID      8 unique ID
--    9 the linking character's level       10 its specialization
--   11 a mask no longer used               12 where the item came from (its "context")
--   13 how many bonus IDs follow, then the bonus IDs
--   then how many modifiers follow, then pairs of (type, value); then relic and crafter fields.
--
-- What makes two links the same item FOR SCORING is the item and its roll, nothing else:
--   kept     1 (the item), 7 and 8 (a classic-style random suffix and the number it scales by),
--            and the bonus IDs (on this client a "... of the Bear" roll travels there: the links
--            the game itself wrote into saved variables carry it as "1:<bonus ID>" in fields 13
--            and 14, with field 7 empty);
--   dropped  2 to 6 (enchant and gems: not part of the item's own stats), 9 and 10 (whoever made
--            the link), 11, 12 (context: 143 of 1,973 real links carried one, same item, same
--            roll), and everything after the bonus IDs (modifiers such as type 28, a content
--            tuning number that differs by where the item dropped; relics; the crafter).
-- The key is written as an item string again, so "item:" .. key is a link every game call
-- takes, and bonus IDs are sorted so the same set always gives the same key:
--   "7429"                           a plain item
--   "7429::::::1234:99"              a suffix roll
--   "7444::::::::::::1:12751"        a bonus-ID roll

function Stats.ItemID(link)
	if type(link) == "number" then return link end
	if type(link) ~= "string" then return nil end
	return tonumber(link:match("item:(%d+)"))
end

local fields, bonus = {}, {}

-- Splits a link's item string into `fields`; returns how many, or nil for what is no item link.
local function Split(link)
	if type(link) ~= "string" then return nil end
	local body = link:match("item:([%-%d:]+)")
	if not body then return nil end
	local n = 0
	for field in (body .. ":"):gmatch("([^:]*):") do
		n = n + 1
		fields[n] = field
	end
	if not tonumber(fields[1]) then return nil end
	return n
end

local function numerically(a, b) return (tonumber(a) or 0) < (tonumber(b) or 0) end

function Stats.Key(link)
	if type(link) == "number" then return tostring(link) end
	local n = Split(link)
	if not n then return nil end
	local id = fields[1]
	local suffix = n >= 7 and fields[7] or ""
	if suffix == "0" then suffix = "" end
	local unique = (suffix ~= "" and n >= 8) and fields[8] or ""
	if unique == "0" then unique = "" end
	local count = n >= 13 and tonumber(fields[13]) or 0
	local have = 0
	for i = 1, count do
		local b = fields[13 + i]
		if b and b ~= "" then
			have = have + 1
			bonus[have] = b
		end
	end
	for i = #bonus, have + 1, -1 do bonus[i] = nil end
	if have > 0 then
		table.sort(bonus, numerically)
		return id .. "::::::" .. suffix .. ":" .. unique .. ":::::" .. have .. ":" .. table.concat(bonus, ":", 1, have)
	end
	if suffix ~= "" then
		if unique ~= "" then return id .. "::::::" .. suffix .. ":" .. unique end
		return id .. "::::::" .. suffix
	end
	return id
end

-- Whether a link carries a roll in its fields: a suffix (field 7) or bonus IDs (field 13 on).
function Stats.IsRolled(link)
	local n = Split(type(link) == "number" and tostring(link) or link)
	if not n then return false end
	local suffix = n >= 7 and fields[7] or ""
	if suffix ~= "" and suffix ~= "0" then return true end
	return (n >= 13 and tonumber(fields[13]) or 0) > 0
end

-- ---------------------------------------------------------------------------------------------
-- Records
-- ---------------------------------------------------------------------------------------------
-- Kept per key until Stats.Forget(): what is owned, what was hovered, and the upgrades a list
-- found. NOT everything a list holds: a real Auction House has had 16,159 distinct pieces of
-- gear, and keeping a record for each was megabytes for nothing (Rank.lua reads a candidate
-- with Stats.Read and keeps it with Stats.Keep only when it is an upgrade). The cap stops a
-- very long session from growing the cache without end (it is then simply started over).
local CAP = 8000
local cache, cached = {}, 0
local NOT_GEAR = {}

function Stats.Forget()
	cache, cached = {}, 0
end

function Stats.Cached() return cached end

local function keep(key, value)
	if cached >= CAP then Stats.Forget() end
	if cache[key] == nil then cached = cached + 1 end
	cache[key] = value
	return value
end

-- Stats.Read(link, key) -> record | nil, why. Reads the item (from the cache when it is there)
-- and does NOT keep the record; Stats.Keep(record) does. Stats.Of is the two together.
function Stats.Keep(rec)
	if type(rec) == "table" and rec.key and cache[rec.key] ~= rec then keep(rec.key, rec) end
	return rec
end

function Stats.Of(link)
	local rec, why = Stats.Read(link)
	if rec then return Stats.Keep(rec) end
	return nil, why
end

function Stats.Read(link, key)
	key = key or Stats.Key(link)
	if not key then return nil, "bad" end
	local hit = cache[key]
	if hit == NOT_GEAR then return nil, "notgear" end
	if hit then return hit end

	local G = ns.Game
	if type(link) == "number" then link = "item:" .. link end
	local equipLoc, classID, subclassID = G.ItemInstant(link)
	if equipLoc == nil then return nil, "pending" end
	if not GEAR[equipLoc] then
		keep(key, NOT_GEAR)
		return nil, "notgear"
	end
	local name, quality, minLevel, sellPrice = G.ItemInfo(link)
	if not name then return nil, "pending" end
	local raw, unreadable = G.ItemStats(link)
	-- (An empty table is an item with no stats, such as a trinket that only has a Use effect: a
	-- real record that scores zero. So is no table at all for an item whose own data is in (its
	-- name was just read): counted "pending", such an item was waited for for ever, and while
	-- one owned piece waited every item event at an Auction House read the bags again. Only an
	-- answer that cannot be believed (Game.ItemStats' reason) still waits.)
	if not raw then
		if unreadable then return nil, "pending" end
		raw = {}
	end

	local stats, counted = Stats.Normalize(raw, equipLoc)
	local speed = G.ItemSpeed(link)
	if type(speed) == "number" and speed > 0 then
		local to = DPS_KEY[equipLoc]
		if to then stats[SPEED_KEY[to]] = speed end
	else
		speed = nil
	end
	return {
		key = key, id = Stats.ItemID(link), link = link,
		name = name, quality = quality or 1, minLevel = minLevel or 0,
		equipLoc = equipLoc, classID = classID, subclassID = subclassID,
		sellPrice = sellPrice or 0,
		unique = G.ItemUnique(link) and true or false,
		speed = speed, stats = stats, counted = counted,
	}
end

-- ---------------------------------------------------------------------------------------------
-- What the score leaves out
-- ---------------------------------------------------------------------------------------------
-- The stat call does not promise every bonus. An item can carry an effect that is a spell
-- rather than a stat ("Equip: ...", "Use: ...", "Chance on hit: ..."), and its size is written
-- only in the tooltip's sentence, in the client's language. This plugin does not read
-- sentences. What it can do without them: the tooltip's data marks each such line with a type
-- (Game.ItemEffects), so the lines can be COUNTED:
--   every "Use" and "Chance on hit" line is an effect the score leaves out;
--   "Equip" lines are left out only as far as there are more of them than bonuses the stat
--   call did answer (an item with two equip lines and two bonus stats is fully counted; one
--   with three lines and two stats has one effect the score does not know).
-- The answer is a count, kept on the record. 0 when the game gives no line types (then nothing
-- can be said, and nothing is). Asked only for items that are shown, never while scoring a
-- whole Auction House: building tooltip data costs far more than the stat call.
function Stats.Uncounted(rec)
	if type(rec) ~= "table" then return 0 end
	if rec.uncounted ~= nil then return rec.uncounted end
	local equip, use, proc = ns.Game.ItemEffects(rec.link)
	if equip == nil then
		-- (The tooltip's data may not be there yet: asked again, but only a few times. A client
		-- that never answers must not be asked on every repaint of every row.)
		rec.effectTries = (rec.effectTries or 0) + 1
		if rec.effectTries >= 3 then rec.uncounted = 0 end
		return 0
	end
	local n = use + proc + math.max(0, equip - (rec.counted or 0))
	rec.uncounted, rec.effects = n, { equip = equip, use = use, proc = proc }
	return n
end
