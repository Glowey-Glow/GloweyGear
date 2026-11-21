-- Score.lua: the weighted sum, and who can wear what.
local Score, Stats = NS.Score, NS.Stats

local CLOTH, LEATHER, MAIL, PLATE, SHIELD, LIBRAM, IDOL, TOTEM = 1, 2, 3, 4, 6, 7, 8, 9

local function rec(def) return (Stats.Of(T.item(def))) end
local function armor(sub, loc, minLevel) return rec({ equipLoc = loc or "INVTYPE_CHEST", classID = 4, subclassID = sub, minLevel = minLevel }) end
local function weapon(sub, loc, minLevel) return rec({ equipLoc = loc or "INVTYPE_WEAPON", classID = 2, subclassID = sub, minLevel = minLevel }) end
local function who(class, level) return { class = class, level = level or 60 } end

T.case("the score is the weighted sum", function()
	T.near(Score.Value({ STR = 10, STA = 5 }, { STR = 1, STA = 0.5 }), 12.5, "two stats")
	T.near(Score.Value({ STR = 10, SPI = 30 }, { STR = 2 }), 20, "a stat with no weight adds nothing")
	T.near(Score.Value({ STR = 10, SPI = 4 }, { STR = 1, SPI = -0.5 }), 8, "a negative weight takes away")
	T.near(Score.Value({ CRIT = 0.5 }, { CRIT = 14 }), 7, "half a percent counts as half")
	T.near(Score.Value({}, { STR = 1 }), 0, "no stats"); T.near(Score.Value({ STR = 3 }, {}), 0, "no weights")
	T.near(Score.Value(nil, { STR = 1 }), 0, "nil stats"); T.near(Score.Value({ STR = 3 }, nil), 0, "nil weights")
end)

T.case("armor types by class", function()
	T.reset()
	local cloth, leather, mail, plate = armor(CLOTH), armor(LEATHER), armor(MAIL), armor(PLATE)
	local can = {
		WARRIOR = { true, true, true, true }, PALADIN = { true, true, true, true },
		HUNTER = { true, true, true, false }, SHAMAN = { true, true, true, false },
		ROGUE = { true, true, false, false }, DRUID = { true, true, false, false },
		PRIEST = { true, false, false, false }, MAGE = { true, false, false, false }, WARLOCK = { true, false, false, false },
	}
	for class, row in pairs(can) do
		for i, piece in ipairs({ cloth, leather, mail, plate }) do
			local ok, reason = Score.Usable(piece, who(class, 60))
			T.eq(ok, row[i], class .. " armor type " .. i)
			if not row[i] then T.eq(reason, "armor", class .. " reason") end
		end
	end
end)

T.case("the heavier armor comes at level 40", function()
	T.reset()
	local plate, mail = armor(PLATE, nil, 0), armor(MAIL, nil, 0)
	local ok, reason, at = Score.Usable(plate, who("WARRIOR", 39))
	T.eq(ok, false, "plate at 39"); T.eq(reason, "level", "is a matter of level"); T.eq(at, 40, "wearable at 40")
	T.eq(Score.Usable(plate, who("WARRIOR", 40)), true, "plate at 40")
	T.eq(Score.Usable(mail, who("WARRIOR", 1)), true, "a warrior wears mail from the start")
	ok, reason, at = Score.Usable(mail, who("HUNTER", 20))
	T.eq(ok, false, "hunter mail at 20"); T.eq(reason, "level", "a matter of level"); T.eq(at, 40, "at 40")
	T.eq(Score.Usable(mail, who("SHAMAN", 45)), true, "shaman mail at 45")
	ok, reason = Score.Usable(plate, who("HUNTER", 60))
	T.eq(ok, false, "a hunter never wears plate"); T.eq(reason, "armor", "not a matter of level")
end)

T.case("level requirement", function()
	T.reset()
	local helm = armor(CLOTH, "INVTYPE_HEAD", 30)
	local ok, reason, at = Score.Usable(helm, who("MAGE", 29))
	T.eq(ok, false, "too low"); T.eq(reason, "level", "reason"); T.eq(at, 30, "atLevel")
	T.eq(Score.Usable(helm, who("MAGE", 30)), true, "at the level")
end)

T.case("cloaks, rings, necks, trinkets and held items are for everyone", function()
	T.reset()
	for _, class in ipairs({ "WARRIOR", "MAGE", "DRUID" }) do
		T.eq(Score.Usable(armor(CLOTH, "INVTYPE_CLOAK"), who(class), { bestArmor = true }), true, class .. " cloak, even with best armor only")
		T.eq(Score.Usable(armor(0, "INVTYPE_FINGER"), who(class)), true, class .. " ring")
		T.eq(Score.Usable(armor(0, "INVTYPE_NECK"), who(class)), true, class .. " neck")
		T.eq(Score.Usable(armor(0, "INVTYPE_TRINKET"), who(class)), true, class .. " trinket")
		T.eq(Score.Usable(armor(0, "INVTYPE_HOLDABLE"), who(class)), true, class .. " held in off hand")
	end
end)

T.case("shields and relics", function()
	T.reset()
	local shield = armor(SHIELD, "INVTYPE_SHIELD")
	for class, ok in pairs({ WARRIOR = true, PALADIN = true, SHAMAN = true, DRUID = false, ROGUE = false, MAGE = false, HUNTER = false }) do
		T.eq(Score.Usable(shield, who(class)), ok, class .. " shield")
	end
	local libram, idol, totem = armor(LIBRAM, "INVTYPE_RELIC"), armor(IDOL, "INVTYPE_RELIC"), armor(TOTEM, "INVTYPE_RELIC")
	T.eq(Score.Usable(libram, who("PALADIN")), true, "libram"); T.eq(Score.Usable(libram, who("DRUID")), false, "not a druid's")
	T.eq(Score.Usable(idol, who("DRUID")), true, "idol"); T.eq(Score.Usable(idol, who("SHAMAN")), false, "not a shaman's")
	T.eq(Score.Usable(totem, who("SHAMAN")), true, "totem"); T.eq(Score.Usable(totem, who("WARRIOR")), false, "not a warrior's")
end)

T.case("only my best armor type", function()
	T.reset()
	local cloth, leather, mail, plate = armor(CLOTH), armor(LEATHER), armor(MAIL), armor(PLATE)
	local best = { bestArmor = true }
	local ok, reason = Score.Usable(mail, who("WARRIOR", 60), best)
	T.eq(ok, false, "a level 60 warrior passes on mail"); T.eq(reason, "lighter", "reason")
	T.eq(Score.Usable(plate, who("WARRIOR", 60), best), true, "and takes plate")
	T.eq(Score.Usable(mail, who("WARRIOR", 30), best), true, "at 30 mail is the best there is")
	T.eq(Score.Usable(leather, who("WARRIOR", 30), best), false, "leather is not")
	T.eq(Score.Usable(cloth, who("MAGE", 60), best), true, "cloth is a mage's best")
	T.eq(Score.Usable(leather, who("DRUID", 60), best), true, "leather is a druid's best")
	T.eq(Score.Usable(cloth, who("DRUID", 60), best), false, "cloth is lighter")
	T.eq(Score.Usable(cloth, who("DRUID", 60)), true, "without the setting cloth is fine")
end)

T.case("weapon types by class", function()
	T.reset()
	local SWORD, SWORD2, WAND, STAFF, DAGGER, BOW, POLEARM, MACE, FIST = 7, 8, 19, 10, 15, 2, 6, 4, 13
	T.eq(Score.Usable(weapon(SWORD), who("MAGE")), true, "a mage can use a sword")
	T.eq(Score.Usable(weapon(WAND, "INVTYPE_RANGEDRIGHT"), who("MAGE")), true, "and a wand")
	local ok, reason = Score.Usable(weapon(WAND, "INVTYPE_RANGEDRIGHT"), who("WARRIOR"))
	T.eq(ok, false, "a warrior cannot use a wand"); T.eq(reason, "weapon", "reason")
	T.eq(Score.Usable(weapon(SWORD2, "INVTYPE_2HWEAPON"), who("ROGUE")), false, "a rogue cannot use a two-hand sword")
	T.eq(Score.Usable(weapon(BOW, "INVTYPE_RANGED"), who("ROGUE")), true, "a rogue can use a bow")
	T.eq(Score.Usable(weapon(POLEARM, "INVTYPE_2HWEAPON"), who("DRUID")), false, "a druid cannot use a polearm")
	T.eq(Score.Usable(weapon(STAFF, "INVTYPE_2HWEAPON"), who("DRUID")), true, "a druid can use a staff")
	T.eq(Score.Usable(weapon(MACE), who("PRIEST")), true, "a priest can use a mace")
	T.eq(Score.Usable(weapon(DAGGER), who("PALADIN")), false, "a paladin cannot use a dagger")
	T.eq(Score.Usable(weapon(FIST), who("SHAMAN")), true, "a shaman can use a fist weapon")
	T.eq(Score.Usable(weapon(BOW, "INVTYPE_RANGED"), who("PRIEST")), false, "a priest cannot use a bow")
end)

T.case("tools are never advice", function()
	T.reset()
	local ok, reason = Score.Usable(weapon(20, "INVTYPE_2HWEAPON"), who("WARRIOR"))
	T.eq(ok, false, "a fishing pole"); T.eq(reason, "tool", "reason")
	T.eq(Score.Usable(weapon(14, "INVTYPE_WEAPON"), who("WARRIOR")), false, "a mining pick")
end)

T.case("a weapon type the class can train but the character has not", function()
	T.reset()
	local sword, mace = weapon(7), weapon(4)
	WORLD.skills = { [43] = true }   -- swords only
	Score.Fresh()
	T.eq(Score.Usable(sword, who("WARRIOR")), true, "swords are learned")
	local ok, reason = Score.Usable(mace, who("WARRIOR"))
	T.eq(ok, false, "maces are not"); T.eq(reason, "skill", "reason")
	WORLD.skills = { [43] = true, [54] = true }
	T.eq(Score.Usable(mace, who("WARRIOR")), false, "the answer is kept for the pass")
	Score.Fresh()
	T.eq(Score.Usable(mace, who("WARRIOR")), true, "a new pass sees the new skill")
	WORLD.skills = nil
	Score.Fresh()
	T.eq(Score.Usable(mace, who("WARRIOR")), true, "when the game cannot list skills, the class table decides")
	WORLD.skills = {}
	Score.Fresh()
	T.eq(Score.Usable(mace, who("WARRIOR")), true, "no weapon skill at all means 'cannot say', not 'none'")
end)

T.case("an off-hand weapon needs dual wield", function()
	T.reset()
	local off = weapon(15, "INVTYPE_WEAPONOFFHAND")
	T.eq(Score.Usable(off, who("ROGUE", 10)), true, "a rogue from level 10")
	local ok, reason, at = Score.Usable(off, who("ROGUE", 9))
	T.eq(ok, false, "not at 9"); T.eq(reason, "level", "a matter of level"); T.eq(at, 10, "at 10")
	T.eq(Score.Usable(off, who("WARRIOR", 19)), false, "a warrior not at 19")
	T.eq(Score.Usable(off, who("WARRIOR", 20)), true, "a warrior from 20")
	ok, reason = Score.Usable(off, who("SHAMAN", 60))
	T.eq(ok, false, "a shaman has no dual wield"); T.eq(reason, "dualwield", "reason")
	ok, reason = Score.Usable(off, who("MAGE", 60))
	T.eq(ok, false, "nor a mage"); T.eq(reason, "dualwield", "reason")
	WORLD.spells[674] = true
	T.eq(Score.Usable(off, who("SHAMAN", 60)), true, "unless the character knows Dual Wield")
	T.eq(Score.Usable(off, who("WARRIOR", 12)), true, "knowing it early counts too")
	T.eq(Score.Usable(weapon(15, "INVTYPE_WEAPON"), who("MAGE", 60)), true, "a one-hand dagger needs no dual wield")
end)

T.case("an unknown class can wear nothing", function()
	T.reset()
	T.eq(Score.Usable(armor(CLOTH), who("MONK")), false, "no table, no advice")
end)

T.case("the weapon skill numbers are the client's own character sheet's", function()
	-- FX Blizzard_UIPanels_Game\Camelot\PaperDollFrameStats.lua:22-38 (weapon subclass -> skill line)
	local client = { [7] = 43, [0] = 44, [2] = 45, [3] = 46, [4] = 54, [8] = 55, [10] = 136, [5] = 160, [1] = 172,
		[15] = 173, [16] = 176, [18] = 226, [19] = 228, [6] = 229, [13] = 162 }
	local n = 0
	for subclass, line in pairs(client) do
		n = n + 1
		T.eq(Score.SKILL[subclass], line, "weapon subclass " .. subclass)
	end
	for subclass in pairs(Score.SKILL) do T.check(client[subclass] ~= nil, "no skill of our own invention for subclass " .. subclass) end
	T.eq(n, 15, "fifteen weapon types")
	-- a fist weapon goes by Unarmed, which every character has
	T.reset()
	WORLD.skills = { [162] = true, [43] = true }
	Score.Fresh()
	T.eq(Score.Usable(weapon(13), who("ROGUE")), true, "a fist weapon is usable with Unarmed alone")
	T.eq(Score.CanDualWield(who("ROGUE", 10)), true, "a rogue dual wields from 10"); T.eq(Score.CanDualWield(who("ROGUE", 9)), false, "not at 9")
	T.eq(Score.CanDualWield(who("MAGE", 60)), false, "a mage does not"); T.eq(Score.CanDualWield(who("MONK", 60)), false, "nor an unknown class")
	WORLD.spells[674] = true
	T.eq(Score.CanDualWield(who("MAGE", 60)), true, "unless the spell is known")
end)

return T.done()
