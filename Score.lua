-- Glowey's Gear: what an item is worth to a spec, and whether the character can wear it.
--
--   Score.Value(stats, weights)        -> number
--   Score.CanDualWield(who)            -> boolean
--   Score.Usable(rec, who, opts)       -> usable, reason, atLevel
--        who  = { class = "WARRIOR", level = 23 }
--        opts = { bestArmor = true }   only the heaviest armor type the class wears now
--        reason: nil when usable, else "level" (wearable at atLevel), "armor", "weapon", "skill"
--                (a weapon type the class can train but the character has not), "dualwield",
--                "tool" (a fishing pole, a mining pick: never advice), "lighter" (bestArmor)
--
-- Pure Lua apart from ns.Game.KnowsSkill and ns.Game.KnowsSpell.

local _, ns = ...

local Score = {}
ns.Score = Score

-- ---------------------------------------------------------------------------------------------
-- The score
-- ---------------------------------------------------------------------------------------------
-- score = the sum over the item's stats of (amount x the spec's weight for that stat).
-- A stat the spec has no weight for adds nothing; a negative weight takes away. Nothing is
-- derived, capped or scaled here in stage 1: the weights say everything (design/data-format.md,
-- rule 5). The number has no unit of its own; only differences and ratios between two scores
-- made with the same weights mean anything, which is all Compare and Rank use.
function Score.Value(stats, weights)
	local total = 0
	if not stats or not weights then return total end
	for key, amount in pairs(stats) do
		local w = weights[key]
		if w then total = total + amount * w end
	end
	return total
end

-- ---------------------------------------------------------------------------------------------
-- Who can wear what
-- ---------------------------------------------------------------------------------------------
-- Item class and subclass numbers are the game's own enums (DOC ItemConstantsDocumentation /
-- Enum.ItemArmorSubclass, Enum.ItemWeaponSubclass): armor 1 cloth, 2 leather, 3 mail, 4 plate,
-- 6 shield, 7 libram, 8 idol, 9 totem; weapons as named below.
local WEAPON, ARMOR = 2, 4

local AXE, AXE2, BOW, GUN, MACE, MACE2, POLEARM, SWORD, SWORD2 = 0, 1, 2, 3, 4, 5, 6, 7, 8
local STAFF, FIST, TOOL, DAGGER, THROWN, CROSSBOW, WAND, FISHING = 10, 13, 14, 15, 16, 18, 19, 20

local function set(...)
	local t = {}
	for i = 1, select("#", ...) do t[(select(i, ...))] = true end
	return t
end

-- What each class can ever wear and wield under classic-era rules: common game knowledge,
-- written out here by hand.
--   armor      the heaviest armor type from level 1
--   armor40    the heavier type the class learns at level 40, when it has one
--   shield     can use shields
--   relic      the armor subclass of its relic (libram, idol, totem), when it has one
--   weapons    the weapon types it can train
--   dual       the level it can hold a weapon in the off hand from, when it can
local CAN = {
	WARRIOR = { armor = 3, armor40 = 4, shield = true, dual = 20,
		weapons = set(AXE, AXE2, BOW, GUN, MACE, MACE2, POLEARM, SWORD, SWORD2, STAFF, FIST, DAGGER, THROWN, CROSSBOW) },
	PALADIN = { armor = 3, armor40 = 4, shield = true, relic = 7,
		weapons = set(AXE, AXE2, MACE, MACE2, POLEARM, SWORD, SWORD2) },
	HUNTER = { armor = 2, armor40 = 3, dual = 20,
		weapons = set(AXE, AXE2, BOW, GUN, POLEARM, SWORD, SWORD2, STAFF, FIST, DAGGER, THROWN, CROSSBOW) },
	ROGUE = { armor = 2, dual = 10,
		weapons = set(BOW, GUN, MACE, SWORD, FIST, DAGGER, THROWN, CROSSBOW) },
	PRIEST = { armor = 1, weapons = set(MACE, STAFF, DAGGER, WAND) },
	SHAMAN = { armor = 2, armor40 = 3, shield = true, relic = 9,
		weapons = set(AXE, AXE2, MACE, MACE2, STAFF, FIST, DAGGER) },
	MAGE = { armor = 1, weapons = set(SWORD, STAFF, DAGGER, WAND) },
	WARLOCK = { armor = 1, weapons = set(SWORD, STAFF, DAGGER, WAND) },
	DRUID = { armor = 2, relic = 8, weapons = set(MACE, MACE2, STAFF, FIST, DAGGER) },
}
Score.CAN = CAN

-- Weapon subclass -> the skill line the character must have learned to wield it now. The
-- numbers are the client's own: its character sheet maps each weapon subclass to the skill it
-- shows for it (FX Blizzard_UIPanels_Game\Camelot\PaperDollFrameStats.lua:22-38,
-- WEAPON_SUBCLASS_TO_SKILL_ID; the same IDs by name in PaperDollFrameConstants.lua:1-16). Note
-- that it files the fist-weapon subclass under Unarmed (162), which every character has, and
-- not under Fist Weapons (473). A class can often train a type it has not learned yet (a weapon
-- master teaches it): such a weapon is not advice until it is learned.
local SKILL = {
	[SWORD] = 43, [AXE] = 44, [BOW] = 45, [GUN] = 46, [MACE] = 54, [SWORD2] = 55,
	[STAFF] = 136, [MACE2] = 160, [FIST] = 162, [AXE2] = 172, [DAGGER] = 173,
	[THROWN] = 176, [CROSSBOW] = 226, [WAND] = 228, [POLEARM] = 229,
}
Score.SKILL = SKILL

local DUAL_WIELD = 674   -- the Dual Wield spell, for a character taught it some other way

-- Armor pieces whose armor type says nothing about who can wear them.
local ANY_ARMOR = { INVTYPE_CLOAK = true, INVTYPE_NECK = true, INVTYPE_FINGER = true,
	INVTYPE_TRINKET = true, INVTYPE_HOLDABLE = true }

-- Whether any weapon skill can be read at all: every character has at least one, so when the
-- game shows none the answer is "cannot say" and the class table alone decides. Asked once per
-- evaluation pass (Score.Fresh() starts a new one).
local skills
function Score.Fresh() skills = nil end

local function knows(line)
	if skills == nil then
		skills = false
		local any, known = false, {}
		for _, id in pairs(SKILL) do
			local has = ns.Game.KnowsSkill(id)
			if has == true then any, known[id] = true, true end
		end
		if any then skills = known end
	end
	return not skills or skills[line] == true
end

-- Whether the character can hold a weapon in the off hand now: the class's level for it, or
-- the Dual Wield spell learned some other way.
function Score.CanDualWield(who)
	local can = CAN[who.class]
	if not can then return false end
	if can.dual and (who.level or 1) >= can.dual then return true end
	return ns.Game.KnowsSpell(DUAL_WIELD) and true or false
end

function Score.Usable(rec, who, opts)
	local can = CAN[who.class]
	local level = who.level or 1
	local atLevel = rec.minLevel or 0
	if not can then return false, "armor", atLevel end
	local sub = rec.subclassID

	if rec.classID == ARMOR and not ANY_ARMOR[rec.equipLoc] and sub then
		if sub >= 1 and sub <= 4 then
			if sub > can.armor then
				if not (can.armor40 and sub <= can.armor40) then return false, "armor", atLevel end
				if atLevel < 40 then atLevel = 40 end
			end
			if opts and opts.bestArmor then
				-- The heaviest type the character wears today; lighter pieces are left out.
				local best = (can.armor40 and level >= 40) and can.armor40 or can.armor
				if sub < best then return false, "lighter", atLevel end
			end
		elseif sub == 6 then
			if not can.shield then return false, "armor", atLevel end
		elseif sub >= 7 and sub <= 11 then
			if can.relic ~= sub then return false, "armor", atLevel end
		end
	elseif rec.classID == WEAPON and sub then
		if sub == TOOL or sub == FISHING then return false, "tool", atLevel end
		if not can.weapons[sub] then return false, "weapon", atLevel end
		if rec.equipLoc == "INVTYPE_WEAPONOFFHAND" and not Score.CanDualWield(who) then
			local from = can.dual
			if not from then return false, "dualwield", atLevel end
			if atLevel < from then atLevel = from end
		end
		if SKILL[sub] and not knows(SKILL[sub]) then return false, "skill", atLevel end
	end

	if atLevel > level then return false, "level", atLevel end
	return true, nil, atLevel
end
