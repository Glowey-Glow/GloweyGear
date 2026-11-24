-- Stats.lua: the game's stat table as canonical stats, link identity, records and their cache,
-- and the two sets of facts the tables rest on (Tools/tests/fixtures, read from the installed
-- game by Tools/client_facts.py).
local Stats = NS.Stats

local function fixture(name)
	local handle = assert(io.open(ADDON_ROOT .. "/Tools/tests/fixtures/" .. name, "r"))
	local rows = {}
	for line in handle:lines() do
		if line:sub(1, 1) ~= "#" and line ~= "" then
			local key, rest = line:match("^([^\t]*)\t?(.*)$")
			rows[#rows + 1] = { key, rest }
		end
	end
	handle:close()
	return rows
end

-- The stats one call's table gives (Normalize answers two values; this takes the first).
local function norm(raw, loc) return (Stats.Normalize(raw, loc)) end

T.case("every stat name the client has is either scored or known and left out", function()
	T.reset()
	local names = fixture("client_stat_keys.txt")
	T.check(#names >= 260, "the client's list is there (" .. #names .. " names)")
	local scored, ignored, weapon = 0, 0, 0
	for _, row in ipairs(names) do
		local what = Stats.Classify(row[1])
		T.check(what ~= nil, row[1] .. " is in neither list")
		if what == "scored" then scored = scored + 1 elseif what == "weapon" then weapon = weapon + 1 else ignored = ignored + 1 end
		norm({ [row[1]] = 1 }, "INVTYPE_WEAPON")
	end
	T.eq(next(Stats.unknown), nil, "none of the client's names is tallied as unknown")
	T.check(scored >= 80 and ignored >= 100 and weapon == 1, ("%d scored, %d left out, %d weapon"):format(scored, ignored, weapon))
end)

T.case("a stat answers under both of its names, with and without _SHORT", function()
	T.reset()
	for _, row in ipairs(fixture("client_stat_keys.txt")) do
		local name = row[1]
		if name:find("^ITEM_MOD_") and Stats.Classify(name) == "scored" then
			local other = name:find("_SHORT$") and name:gsub("_SHORT$", "") or (name .. "_SHORT")
			local a, b = norm({ [name] = 30 }, "INVTYPE_HEAD"), norm({ [other] = 30 }, "INVTYPE_HEAD")
			for key, value in pairs(a) do T.eq(b[key], value, name .. " and " .. other .. " give the same " .. key) end
			T.check(next(a) ~= nil, name .. " gives something")
		end
	end
	T.eq(next(Stats.unknown), nil, "and neither spelling is unknown")
end)

T.case("healing arrives under the bare name too (the audit's H1)", function()
	T.reset()
	T.eq(norm({ ITEM_MOD_SPELL_HEALING_DONE = 40 }, "INVTYPE_FINGER").HEAL, 40, "without _SHORT")
	T.eq(norm({ ITEM_MOD_SPELL_HEALING_DONE_SHORT = 40 }, "INVTYPE_FINGER").HEAL, 40, "with _SHORT")
	T.eq(norm({ ITEM_MOD_SPELL_HEALING_DONE = 40 }, "INVTYPE_FINGER").SPELL_DMG, nil, "healing is not damage")
	T.eq(next(Stats.unknown), nil, "nothing unknown")
	-- through a record and a healer's weights
	local link = T.item({ equipLoc = "INVTYPE_FINGER", raw = { ITEM_MOD_SPELL_HEALING_DONE = 40 } })
	T.near(NS.Score.Value(Stats.Of(link).stats, { HEAL = 1 }), 40, "a healer's ring scores its healing")
end)

T.case("the rating figures are the client's own table, the same at every level", function()
	local column = {}
	for _, row in ipairs(fixture("client_combat_ratings.txt")) do column[row[1]] = row[2] end
	local R = Stats.RATING_PER_PERCENT
	local expect = {
		HIT = { "Hit - Melee", "Hit - Ranged" }, SPELL_HIT = { "Hit - Spell" },
		CRIT = { "Crit - Melee", "Crit - Ranged" }, SPELL_CRIT = { "Crit - Spell" },
		HASTE = { "Haste - Melee", "Haste - Ranged", "Haste - Spell" },
		EXPERTISE = { "Expertise" }, ARMOR_PEN = { "Armor Penetration" },
		DODGE = { "Dodge" }, PARRY = { "Parry" }, BLOCK = { "Block" }, DEFENSE = { "Defense Skill" },
	}
	local n = 0
	for key, columns in pairs(expect) do
		for _, name in ipairs(columns) do
			n = n + 1
			T.check(column[name] ~= nil, "the client's table has a column " .. name)
			T.eq(column[name], tostring(R[key]), key .. " is the one value of " .. name .. " at every level")
		end
	end
	T.eq(n, 15, "fifteen columns checked")
	for key in pairs(R) do T.check(expect[key] ~= nil, key .. " has a column behind it") end
end)

T.case("attributes, armor and the pools are copied", function()
	local s = norm({ ITEM_MOD_STRENGTH_SHORT = 5, ITEM_MOD_AGILITY_SHORT = 4, ITEM_MOD_STAMINA_SHORT = 3,
		ITEM_MOD_INTELLECT_SHORT = 2, ITEM_MOD_SPIRIT_SHORT = 1, RESISTANCE0_NAME = 120,
		ITEM_MOD_HEALTH_SHORT = 50, ITEM_MOD_MANA_SHORT = 60 }, "INVTYPE_CHEST")
	T.eq(s.STR, 5, "STR"); T.eq(s.AGI, 4, "AGI"); T.eq(s.STA, 3, "STA")
	T.eq(s.INT, 2, "INT"); T.eq(s.SPI, 1, "SPI"); T.eq(s.ARMOR, 120, "ARMOR")
	T.eq(s.HEALTH, 50, "HEALTH"); T.eq(s.MANA, 60, "MANA")
end)

T.case("ratings become percent, unrounded", function()
	local s = norm({ ITEM_MOD_CRIT_RATING_SHORT = 14, ITEM_MOD_HIT_RATING_SHORT = 20,
		ITEM_MOD_DODGE_RATING_SHORT = 12, ITEM_MOD_PARRY_RATING_SHORT = 15, ITEM_MOD_BLOCK_RATING_SHORT = 10,
		ITEM_MOD_EXPERTISE_RATING_SHORT = 10, ITEM_MOD_HASTE_RATING_SHORT = 5,
		ITEM_MOD_ARMOR_PENETRATION_RATING_SHORT = 30, ITEM_MOD_DEFENSE_SKILL_RATING_SHORT = 7 }, "INVTYPE_HEAD")
	T.near(s.CRIT, 1, "14 crit rating is 1%"); T.near(s.HIT, 2, "20 hit rating is 2%")
	T.near(s.DODGE, 1, "12 dodge rating is 1%"); T.near(s.PARRY, 1, "15 parry rating is 1%")
	T.near(s.BLOCK, 2, "10 block rating is 2%"); T.near(s.EXPERTISE, 1, "10 expertise rating is 1%")
	T.near(s.HASTE, 0.5, "5 haste rating is half a percent, not rounded")
	T.near(s.ARMOR_PEN, 3, "30 armor penetration rating is 3%")
	T.near(s.DEFENSE, 7, "defense rating is skill points, one for one")
end)

T.case("a general hit or crit rating counts for spells too; one-sided ratings do not", function()
	local s = norm({ ITEM_MOD_CRIT_RATING_SHORT = 28, ITEM_MOD_HIT_RATING_SHORT = 10 }, "INVTYPE_HEAD")
	T.near(s.CRIT, 2, "CRIT"); T.near(s.SPELL_CRIT, 2, "SPELL_CRIT")
	T.near(s.HIT, 1, "HIT"); T.near(s.SPELL_HIT, 1, "SPELL_HIT")
	s = norm({ ITEM_MOD_CRIT_SPELL_RATING_SHORT = 14, ITEM_MOD_HIT_MELEE_RATING_SHORT = 10,
		ITEM_MOD_CRIT_RANGED_RATING_SHORT = 14, ITEM_MOD_HIT_SPELL_RATING_SHORT = 10 }, "INVTYPE_HEAD")
	T.near(s.SPELL_CRIT, 1, "spell crit only"); T.near(s.CRIT, 1, "ranged crit feeds CRIT only")
	T.near(s.HIT, 1, "melee hit only"); T.near(s.SPELL_HIT, 1, "spell hit only")
	s = norm({ ITEM_MOD_CRIT_RATING_SHORT = 14, ITEM_MOD_CRIT_MELEE_RATING_SHORT = 14 }, "INVTYPE_HEAD")
	T.near(s.CRIT, 2, "the same percent from two names adds up"); T.near(s.SPELL_CRIT, 1, "on its own side")
end)

T.case("spell power: combined feeds damage and healing, the one-sided bonuses one each", function()
	local s = norm({ ITEM_MOD_SPELL_POWER_SHORT = 18, ITEM_MOD_SPELL_DAMAGE_DONE_SHORT = 6 }, "INVTYPE_FEET")
	T.eq(s.SPELL_DMG, 24, "SPELL_DMG"); T.eq(s.HEAL, 18, "HEAL")
	s = norm({ ITEM_MOD_SPELL_HEALING_DONE_SHORT = 40 }, "INVTYPE_FEET")
	T.eq(s.HEAL, 40, "healing only"); T.eq(s.SPELL_DMG, nil, "no damage from a healing bonus")
end)

T.case("school damage has the client's spelling, and is never folded into SPELL_DMG", function()
	T.reset()
	local s = norm({ ITEM_MOD_FIRE_DAMAGE_DONE_SHORT = 10, ITEM_MOD_SHADOW_DAMAGE_DONE = 7 }, "INVTYPE_HEAD")
	T.eq(s.SPELL_DMG_FIRE, 10, "fire"); T.eq(s.SPELL_DMG_SHADOW, 7, "shadow"); T.eq(s.SPELL_DMG, nil, "not general")
	norm({ ITEM_MOD_FIRE_SPELL_DAMAGE_DONE_SHORT = 10 }, "INVTYPE_HEAD")
	T.eq(Stats.unknown.ITEM_MOD_FIRE_SPELL_DAMAGE_DONE_SHORT, 1, "a spelling the client does not have is reported, not guessed at")
	T.eq(norm({ ITEM_MOD_PHYSICAL_DAMAGE_DONE_SHORT = 9 }, "INVTYPE_HEAD").SPELL_DMG, nil, "physical damage is not a school of spells")
end)

T.case("attack power: general feeds melee and ranged; melee, ranged and forms have their own", function()
	local s = norm({ ITEM_MOD_ATTACK_POWER_SHORT = 20, ITEM_MOD_RANGED_ATTACK_POWER_SHORT = 8,
		ITEM_MOD_MELEE_ATTACK_POWER_SHORT = 5, ITEM_MOD_FERAL_ATTACK_POWER_SHORT = 100 }, "INVTYPE_2HWEAPON")
	T.eq(s.AP, 25, "AP: general plus melee-only"); T.eq(s.RAP, 28, "RAP: general plus ranged-only"); T.eq(s.FERAL_AP, 100, "FERAL_AP")
	-- what a general point is worth: the melee share plus the ranged share, by the spec's weights
	local general = norm({ ITEM_MOD_ATTACK_POWER_SHORT = 10 }, "INVTYPE_HEAD")
	T.near(NS.Score.Value(general, { AP = 0.1, RAP = 0.4 }), 5, "a hunter: both shares")
	T.near(NS.Score.Value(general, { AP = 0.45 }), 4.5, "a warrior: melee only")
end)

T.case("regeneration, resistances and piercing", function()
	local s = norm({ ITEM_MOD_POWER_REGEN0_SHORT = 3, ITEM_MOD_MANA_REGENERATION_SHORT = 2,
		ITEM_MOD_HEALTH_REGEN_SHORT = 4, ITEM_MOD_HEALTH_REGENERATION = 1, RESISTANCE2_NAME = 10, RESISTANCE3_NAME = 11,
		RESISTANCE4_NAME = 12, RESISTANCE5_NAME = 13, RESISTANCE6_NAME = 5, RESISTANCE1_NAME = 99,
		ITEM_MOD_SPELL_PENETRATION_SHORT = 9, ITEM_MOD_BLOCK_VALUE_SHORT = 23 }, "INVTYPE_NECK")
	T.eq(s.MP5, 5, "MP5"); T.eq(s.HP5, 5, "HP5")
	T.eq(s.RES_FIRE, 10, "fire"); T.eq(s.RES_NATURE, 11, "nature"); T.eq(s.RES_FROST, 12, "frost")
	T.eq(s.RES_SHADOW, 13, "shadow"); T.eq(s.RES_ARCANE, 5, "arcane")
	T.eq(s.SPELL_PEN, 9, "SPELL_PEN"); T.eq(s.BLOCK_VALUE, 23, "BLOCK_VALUE")
	s = norm({ ITEM_MOD_SPELL_RESISTANCE_ALL_SCHOOLS_SHORT = 4, RESISTANCE2_NAME = 1 }, "INVTYPE_NECK")
	T.eq(s.RES_FIRE, 5, "all-schools resistance adds to each"); T.eq(s.RES_ARCANE, 4, "each of the five")
	T.eq(norm({ ITEM_MOD_POWER_REGEN3_SHORT = 5 }, "INVTYPE_NECK").MP5, nil, "another power's regeneration is not mana")
end)

T.case("weapon DPS is filed by where the weapon is held", function()
	local raw = { ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 41.5 }
	T.eq(norm(raw, "INVTYPE_2HWEAPON").MH_DPS, 41.5, "two-hand")
	T.eq(norm(raw, "INVTYPE_WEAPONMAINHAND").MH_DPS, 41.5, "main hand")
	T.eq(norm(raw, "INVTYPE_WEAPON").MH_DPS, 41.5, "a one-hand weapon is read as a main hand (Compare tries the off hand)")
	T.eq(norm(raw, "INVTYPE_WEAPONOFFHAND").OH_DPS, 41.5, "off hand")
	T.eq(norm(raw, "INVTYPE_WEAPONOFFHAND").MH_DPS, nil, "off hand is not main hand")
	T.eq(norm(raw, "INVTYPE_RANGED").RANGED_DPS, 41.5, "bow")
	T.eq(norm(raw, "INVTYPE_RANGEDRIGHT").RANGED_DPS, 41.5, "gun or wand")
	T.eq(norm(raw, "INVTYPE_THROWN").RANGED_DPS, 41.5, "thrown")
	T.eq(next(norm(raw, "INVTYPE_CHEST")), nil, "DPS on armor is dropped")
	T.eq(Stats.Classify("ITEM_MOD_DAMAGE_PER_SECOND_SHORT"), "weapon", "classified as the weapon's")
end)

T.case("names in neither list, and odd values", function()
	T.reset()
	local s = norm({ ITEM_MOD_SOMETHING_NEW_SHORT = 5, BRAND_NEW_THING = 2, EMPTY_SOCKET_RED = 1, ITEM_MOD_STRENGTH_SHORT = "x",
		ITEM_MOD_AGILITY_SHORT = 3, ITEM_MOD_SWORDS_SHORT = 4, ITEM_MOD_CR_SPEED_SHORT = 2, [7] = 7 }, "INVTYPE_HEAD")
	T.eq(s.AGI, 3, "the known stat still reads"); T.eq(s.STR, nil, "a non-number is skipped")
	T.eq(Stats.unknown.ITEM_MOD_SOMETHING_NEW_SHORT, 1, "an ITEM_MOD_ name the client's list lacks is tallied")
	T.eq(Stats.unknown.BRAND_NEW_THING, 1, "so is a name of another family")
	T.eq(Stats.unknown.EMPTY_SOCKET_RED, nil, "a socket is known and left out, not unknown")
	T.eq(Stats.unknown.ITEM_MOD_SWORDS_SHORT, nil, "a weapon skill is known and left out")
	T.eq(Stats.unknown.ITEM_MOD_CR_SPEED_SHORT, nil, "so are the stats this game's rules do not have")
	local count = 0
	for _ in pairs(Stats.unknown) do count = count + 1 end
	T.eq(count, 2, "exactly the two")
	T.eq(Stats.Classify("ITEM_MOD_SOMETHING_NEW_SHORT"), nil, "Classify says 'never seen'")
	T.eq(Stats.Classify("ITEM_MOD_EXTRA_ARMOR_SHORT"), "ignored", "bonus armor is known and left out")
	T.eq(Stats.Classify(nil), nil, "nil in")
	T.eq(next(norm(nil, "INVTYPE_HEAD")), nil, "nil gives an empty table")
	norm({ ITEM_MOD_SOMETHING_NEW_SHORT = 5 }, "INVTYPE_HEAD")
	T.eq(Stats.unknown.ITEM_MOD_SOMETHING_NEW_SHORT, 2, "counted each time it is met")
end)

T.case("every canonical key the reader can produce is in KEYS", function()
	T.reset()
	local raw = {}
	for _, row in ipairs(fixture("client_stat_keys.txt")) do raw[row[1]] = 1 end
	local seen = {}
	for _, loc in ipairs({ "INVTYPE_WEAPON", "INVTYPE_WEAPONOFFHAND", "INVTYPE_RANGED" }) do
		for key in pairs(norm(raw, loc)) do
			seen[key] = true
			T.check(Stats.KEYS[key], "produced a key that is not canonical: " .. tostring(key))
		end
	end
	for key in pairs(Stats.KEYS) do
		if not key:find("_SPEED$") then T.check(seen[key], "nothing in the client's list produces " .. key) end
	end
end)

T.case("link identity: the item and its roll, nothing else", function()
	T.eq(Stats.ItemID("|cff1eff00|Hitem:7429::::::::25:1489:::::|h[x]|h|r"), 7429, "item ID from a link")
	T.eq(Stats.ItemID("item:15"), 15, "from an item string"); T.eq(Stats.ItemID(15), 15, "from a number")
	T.eq(Stats.ItemID("hello"), nil, "not a link"); T.eq(Stats.ItemID(nil), nil, "nil")
	T.eq(Stats.Key("item:7429"), "7429", "bare"); T.eq(Stats.Key(7429), "7429", "a number")
	T.eq(Stats.Key("item:7429::::::::::::"), "7429", "trailing empty fields dropped")
	T.eq(Stats.Key("item:7429:2504:11:12:::::60:1489::5:::"), "7429", "enchant, gems, level, spec and context are not the item")
	-- the three shapes of one rolled item the game itself saved (design/audit-stage1.md, M6)
	local plain = "item:7444::::::::33:1489:::1:12751::::::"
	local context = "item:7444::::::::33:1489::1:1:12751::::::"
	local modifier = "item:7444::::::::33:1489::1:1:12751:1:28:4522:::::"
	T.eq(Stats.Key(plain), "7444::::::::::::1:12751", "a roll: the bonus ID, in the real shape")
	T.eq(Stats.Key(context), Stats.Key(plain), "an item context does not make another item")
	T.eq(Stats.Key(modifier), Stats.Key(plain), "nor does a modifier after the roll")
	T.eq(Stats.Key("item:7444::::::::60:71::9:1:12751:2:28:1199:9:35:::::"), Stats.Key(plain), "nor two modifiers, another level and spec")
	T.eq(Stats.Key("item:6694::::::::30:1489::1::1:28:5246:::::"), "6694", "no roll, context and a modifier: the plain item")
	T.check(Stats.Key("item:7444::::::::33:1489:::1:12752::::::") ~= Stats.Key(plain), "another roll is another item")
	T.check(Stats.Key(plain) ~= Stats.Key("item:7444"), "a roll is not the plain item")
	T.eq(Stats.Key("item:7444::::::::33:1489:::2:900:12751::::::"), "7444::::::::::::2:900:12751", "two bonus IDs")
	T.eq(Stats.Key("item:7444::::::::33:1489:::2:12751:900::::::"), "7444::::::::::::2:900:12751", "in any order: the same key")
	-- the key is itself a link the game takes, and reads back to itself
	for _, link in ipairs({ plain, context, modifier, "item:7429", "item:7429::::::1234:99:60:::::" }) do
		local key = Stats.Key(link)
		T.eq(Stats.Key("item:" .. key), key, "item:" .. key .. " reads back to the same key")
		T.eq(Stats.IsRolled("item:" .. key), Stats.IsRolled(link), "and is rolled or not as the link was")
	end
	-- the old-style suffix (field 7, with the number it scales by in field 8)
	T.eq(Stats.Key("|cff1eff00|Hitem:7429:2504:::::1234:99:25:70::::|h[x]|h|r"), "7429::::::1234:99", "a suffix roll keeps fields 7 and 8")
	T.eq(Stats.Key("item:7429::::::-12:5550000"), "7429::::::-12:5550000", "negative suffix IDs are kept")
	T.eq(Stats.Key("item:7429:::::::5550000"), "7429", "a unique ID without a suffix is not kept")
	T.check(Stats.Key("item:7429::::::1234:99") ~= Stats.Key("item:7429::::::1235:99"), "two suffixes are two items")
	T.eq(Stats.Key("item:7429::::::0:0:60"), "7429", "suffix 0 is no suffix")
	T.eq(Stats.Key("spell:133"), nil, "not an item"); T.eq(Stats.Key(nil), nil, "nil"); T.eq(Stats.Key("item:"), nil, "empty")
	T.check(Stats.IsRolled(plain), "bonus IDs mean rolled"); T.check(Stats.IsRolled("item:7429::::::1234:99"), "a suffix means rolled")
	T.check(not Stats.IsRolled("item:7429"), "a plain item is not rolled")
	T.check(not Stats.IsRolled("item:6694::::::::30:1489::1::1:28:5246:::::"), "context and modifiers alone are not a roll")
	T.check(not Stats.IsRolled("item:7429::::::0:0:60"), "suffix 0 is not rolled"); T.check(not Stats.IsRolled(nil), "nil is not rolled")
end)

T.case("the test world writes links the way the client does", function()
	T.reset()
	local link = T.item({ id = 7444, roll = 12751, name = "Sentinel Boots of the Bandit", equipLoc = "INVTYPE_FEET" })
	T.check(link:find("item:7444::::::::60:1489:::1:12751:", 1, true), "bonus IDs in fields 13 and 14, field 7 empty: " .. link)
	T.eq(Stats.Key(link), "7444::::::::::::1:12751", "its key")
	local same = T.link(7444, 12751, "Sentinel Boots of the Bandit", 33, nil, { context = 1, modifiers = "28:4522" })
	T.check(same:find("item:7444::::::::33:1489::1:1:12751:1:28:4522:", 1, true), "context and modifier where the client puts them: " .. same)
	T.check(Stats.Of(same) == Stats.Of(link), "one record for both")
end)

T.case("a record carries what the engine needs", function()
	T.reset()
	local link = T.item({ id = 501, name = "Test Blade", equipLoc = "INVTYPE_WEAPON", classID = 2, subclassID = 7,
		minLevel = 31, quality = 3, sellPrice = 4200, unique = true,
		raw = { ITEM_MOD_STRENGTH_SHORT = 9, ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 30, ITEM_MOD_CRIT_RATING_SHORT = 14 } })
	local r = Stats.Of(link)
	T.eq(r.id, 501, "id"); T.eq(r.name, "Test Blade", "name"); T.eq(r.minLevel, 31, "minLevel")
	T.eq(r.quality, 3, "quality"); T.eq(r.sellPrice, 4200, "sellPrice"); T.eq(r.unique, true, "unique")
	T.eq(r.equipLoc, "INVTYPE_WEAPON", "equipLoc"); T.eq(r.classID, 2, "classID"); T.eq(r.subclassID, 7, "subclassID")
	T.eq(r.stats.STR, 9, "STR"); T.eq(r.stats.MH_DPS, 30, "MH_DPS"); T.eq(r.key, Stats.Key(link), "key")
	T.eq(r.speed, nil, "no speed in stage 1"); T.eq(r.counted, 1, "one bonus the tooltip shows as an effect line (the crit)")
end)

T.case("rolled items: the full link decides the stats", function()
	T.reset()
	local base = T.item({ id = 600, name = "Plain Belt", equipLoc = "INVTYPE_WAIST", raw = { RESISTANCE0_NAME = 50 } })
	local bear = T.item({ id = 600, roll = 12722, name = "Plain Belt of the Bear", equipLoc = "INVTYPE_WAIST",
		raw = { RESISTANCE0_NAME = 50, ITEM_MOD_STRENGTH_SHORT = 6, ITEM_MOD_STAMINA_SHORT = 6 } })
	local owl = T.item({ id = 600, roll = 12733, name = "Plain Belt of the Owl", equipLoc = "INVTYPE_WAIST",
		raw = { RESISTANCE0_NAME = 50, ITEM_MOD_INTELLECT_SHORT = 6, ITEM_MOD_SPIRIT_SHORT = 6 } })
	local old = T.item({ id = 600, oldSuffix = 754, name = "Plain Belt of the Monkey", equipLoc = "INVTYPE_WAIST",
		raw = { RESISTANCE0_NAME = 50, ITEM_MOD_AGILITY_SHORT = 6 } })
	local a, b, c, d = Stats.Of(base), Stats.Of(bear), Stats.Of(owl), Stats.Of(old)
	T.eq(a.stats.STR, nil, "the base item has no roll's stats")
	T.eq(b.stats.STR, 6, "of the Bear"); T.eq(b.stats.INT, nil, "of the Bear has no Intellect")
	T.eq(c.stats.INT, 6, "of the Owl"); T.eq(c.name, "Plain Belt of the Owl", "the roll's own name")
	T.eq(d.stats.AGI, 6, "an old-style suffix roll reads too")
	T.check(a ~= b and b ~= c and c ~= d, "four records"); T.eq(b.id, 600, "same item ID")
	-- read back from its saved key, as Market.lua does
	Stats.Forget()
	T.eq(Stats.Of("item:" .. b.key).stats.STR, 6, "the saved key gives the roll's stats again")
end)

T.case("the cache: one read per item, whoever links it and wherever it came from", function()
	T.reset()
	local link = T.item({ id = 700, roll = 12722, equipLoc = "INVTYPE_HEAD", raw = { ITEM_MOD_STAMINA_SHORT = 4 } })
	local first = Stats.Of(link)
	T.check(first == Stats.Of(T.link(700, 12722, "Item 700", 12, 2504)), "another character's link and an enchanted copy")
	T.check(first == Stats.Of(T.link(700, 12722, "Item 700", 33, nil, { context = 1 })), "a copy with an item context")
	T.check(first == Stats.Of(T.link(700, 12722, "Item 700", 33, nil, { context = 1, modifiers = "28:4522" })), "and one with a modifier")
	T.eq(WORLD.calls.ItemStats, 1, "the stat call ran once")
	Stats.Forget()
	T.check(Stats.Of(link) ~= first, "Forget starts over"); T.eq(WORLD.calls.ItemStats, 2, "and reads again")
end)

T.case("not loaded yet is 'pending', and is asked again", function()
	T.reset()
	local link = T.item({ id = 800, equipLoc = "INVTYPE_HEAD", loaded = false, raw = { ITEM_MOD_STAMINA_SHORT = 4 } })
	local r, why = Stats.Of(link)
	T.eq(r, nil, "no record yet"); T.eq(why, "pending", "pending")
	T.eq(Stats.Cached(), 0, "a pending item is not cached")
	T.load(link)
	T.eq(Stats.Of(link).stats.STA, 4, "read once loaded")
	local unknown, reason = Stats.Of("item:999999")
	T.eq(unknown, nil, "an item the game knows nothing of"); T.eq(reason, "pending", "is pending, not an error")
	-- the item's data is in, and the stat call answers nothing: an item with no stats, not
	-- waited for; an answer that cannot be believed still waits
	local bare = T.item({ id = 801, equipLoc = "INVTYPE_TRINKET" })
	local base = NS.Game.ItemStats
	NS.Game.ItemStats = function() return nil, "secret" end
	local none, still = Stats.Of(bare)
	T.eq(none, nil, "unreadable: no record"); T.eq(still, "pending", "still pending")
	NS.Game.ItemStats = function() return nil end
	local rec = Stats.Of(bare)
	NS.Game.ItemStats = base
	T.check(rec ~= nil, "no stat table: a record"); T.eq(next(rec.stats), nil, "with no stats")
end)

T.case("what is not gear", function()
	T.reset()
	local shirt = T.item({ id = 900, equipLoc = "INVTYPE_BODY" })
	local tabard = T.item({ id = 901, equipLoc = "INVTYPE_TABARD" })
	local bag = T.item({ id = 902, equipLoc = "INVTYPE_BAG" })
	local ore = T.item({ id = 903, equipLoc = "" })
	local ammo = T.item({ id = 904, equipLoc = "INVTYPE_AMMO" })
	for name, link in pairs({ shirt = shirt, tabard = tabard, bag = bag, ore = ore, ammo = ammo }) do
		local r, why = Stats.Of(link)
		T.eq(r, nil, name); T.eq(why, "notgear", name .. " is not gear")
	end
	Stats.Of(shirt)
	T.eq(WORLD.calls.ItemStats, nil, "stats are never read for what is not gear")
	T.eq(WORLD.calls.ItemInstant, 5, "and the verdict is remembered")
	local r, why = Stats.Of("not a link")
	T.eq(r, nil, "junk in"); T.eq(why, "bad", "is 'bad'")
	local n = 0
	for _ in pairs(Stats.GEAR) do n = n + 1 end
	T.eq(n, 23, "twenty-three equip locations are gear")
end)

T.case("an item with no stats is a real record", function()
	T.reset()
	local link = T.item({ id = 950, equipLoc = "INVTYPE_TRINKET", raw = {} })
	local r = Stats.Of(link)
	T.check(r ~= nil, "a record"); T.eq(next(r.stats), nil, "with no stats"); T.eq(r.counted, 0, "and no bonuses")
end)

T.case("speed, when a later stage supplies it", function()
	T.reset()
	local link = T.item({ id = 960, equipLoc = "INVTYPE_2HWEAPON", classID = 2, subclassID = 1,
		raw = { ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 50 } })
	WORLD.speed["960:"] = 3.6
	local r = Stats.Of(link)
	T.eq(r.speed, 3.6, "speed"); T.eq(r.stats.MH_SPEED, 3.6, "filed with the hand")
end)

T.case("effects the score leaves out are counted from the tooltip's line types (the audit's M1)", function()
	T.reset()
	local function item(raw, effects) return Stats.Of(T.item({ equipLoc = "INVTYPE_TRINKET", raw = raw, effects = effects })) end
	-- every equip line is a bonus the stat call gave: nothing is left out
	local full = item({ ITEM_MOD_CRIT_RATING_SHORT = 14, ITEM_MOD_ATTACK_POWER_SHORT = 20, ITEM_MOD_STAMINA_SHORT = 5 }, { equip = 2 })
	T.eq(full.counted, 2, "two bonuses read (Stamina is a plain stat line)"); T.eq(Stats.Uncounted(full), 0, "two equip lines, two bonuses: complete")
	-- one equip line more than the stat call answered
	local short = item({ ITEM_MOD_CRIT_RATING_SHORT = 14 }, { equip = 2 })
	T.eq(Stats.Uncounted(short), 1, "two equip lines, one bonus: one effect is not counted")
	-- an equip effect on an item with no bonus stats at all
	T.eq(Stats.Uncounted(item({ ITEM_MOD_STAMINA_SHORT = 9 }, { equip = 1 })), 1, "an equip line and only attributes")
	-- Use and proc lines are never counted by the score
	T.eq(Stats.Uncounted(item({ ITEM_MOD_STAMINA_SHORT = 9 }, { use = 1 })), 1, "a Use effect")
	T.eq(Stats.Uncounted(item({ ITEM_MOD_STAMINA_SHORT = 9 }, { proc = 1 })), 1, "a chance-on-hit effect")
	T.eq(Stats.Uncounted(item({ ITEM_MOD_CRIT_RATING_SHORT = 14 }, { equip = 1, use = 1, proc = 1 })), 2, "use and proc beside a counted equip line")
	-- a bonus that is known and left out is still a line the tooltip shows: not "missing"
	T.eq(Stats.Uncounted(item({ ITEM_MOD_SWORDS_SHORT = 5 }, { equip = 1 })), 0, "a left-out stat accounts for its own line")
	-- more bonuses than lines (this client may type only spell effects): never negative
	T.eq(Stats.Uncounted(item({ ITEM_MOD_CRIT_RATING_SHORT = 14, ITEM_MOD_HIT_RATING_SHORT = 10 }, { equip = 0 })), 0, "no lines, two bonuses")
	-- the game cannot say: nothing is claimed, and it is asked again
	local blind = item({ ITEM_MOD_STAMINA_SHORT = 9 }, nil)
	T.eq(Stats.Uncounted(blind), 0, "no line types from the game: 0"); T.eq(blind.uncounted, nil, "and not kept")
	WORLD.effects[T_ident(blind.link)] = { use = 1 }
	T.eq(Stats.Uncounted(blind), 1, "asked again once the game answers")
	-- a client that never answers is asked three times for an item, then left alone
	local never = item({ ITEM_MOD_STAMINA_SHORT = 9 }, nil)
	local asked = WORLD.calls.ItemEffects
	for _ = 1, 10 do Stats.Uncounted(never) end
	T.eq(WORLD.calls.ItemEffects - asked, 3, "three tries, not one per repaint"); T.eq(never.uncounted, 0, "then it stands at 0")
	-- kept on the record: the tooltip data is built once
	local calls = WORLD.calls.ItemEffects
	Stats.Uncounted(short); Stats.Uncounted(short); Stats.Uncounted(full)
	T.eq(WORLD.calls.ItemEffects, calls, "the answer is kept")
	T.eq(short.effects.equip, 2, "with the counts, for /gear debug")
	-- reading a record never builds tooltip data by itself
	T.reset()
	Stats.Of(T.item({ equipLoc = "INVTYPE_HEAD", effects = { equip = 3 } }))
	T.eq(WORLD.calls.ItemEffects, nil, "Stats.Of does not ask for the tooltip")
	T.eq(Stats.Uncounted(nil), 0, "nil in")
end)

T.case("names the stat call answers that are not in the client's readable list (seen in play)", function()
	-- The owner's /gear debug of 2026-11-20 reported these five as unknown, a few hundred times each.
	T.reset()
	local s2 = norm({ ITEM_MOD_FIRE_RESISTANCE_SHORT = 10, ITEM_MOD_NATURE_RESISTANCE_SHORT = 11, ITEM_MOD_FROST_RESISTANCE_SHORT = 12,
		ITEM_MOD_SHADOW_RESISTANCE_SHORT = 13, ITEM_MOD_ARCANE_RESISTANCE_SHORT = 14, ITEM_MOD_HOLY_RESISTANCE_SHORT = 15,
		RESISTANCE2_NAME = 1 }, "INVTYPE_FINGER")
	T.eq(s2.RES_FIRE, 11, "fire, added to the other spelling of the same resistance"); T.eq(s2.RES_NATURE, 11, "nature")
	T.eq(s2.RES_FROST, 12, "frost"); T.eq(s2.RES_SHADOW, 13, "shadow"); T.eq(s2.RES_ARCANE, 14, "arcane")
	T.eq(next(Stats.unknown), nil, "none of them is unknown any more, holy included")
	T.eq(Stats.Classify("ITEM_MOD_FIRE_RESISTANCE_SHORT"), "scored", "classified"); T.eq(Stats.Classify("ITEM_MOD_FIRE_RESISTANCE"), "scored", "under both spellings")
	T.eq(Stats.Classify("ITEM_MOD_HOLY_RESISTANCE_SHORT"), "ignored", "holy resistance is known and left out")
	local rows = 0
	for _, row in ipairs(fixture("client_stat_keys.txt")) do
		rows = rows + 1
		for school in ("ARCANE FIRE FROST NATURE SHADOW HOLY"):gmatch("%S+") do
			T.check(not row[1]:find("^ITEM_MOD_" .. school .. "_RESISTANCE"), "which the readable list indeed lacks: " .. row[1])
		end
	end
	T.check(rows > 200, "(the list was read)")
end)

T.case("a record can be read without being kept", function()
	T.reset()
	local link = T.item({ equipLoc = "INVTYPE_HEAD", raw = { ITEM_MOD_STAMINA_SHORT = 4 } })
	local rec = Stats.Read(link)
	T.eq(rec.stats.STA, 4, "read"); T.eq(Stats.Cached(), 0, "not kept")
	T.check(Stats.Read(link) ~= rec, "so the next read reads again")
	Stats.Keep(rec)
	T.eq(Stats.Cached(), 1, "kept when asked"); T.check(Stats.Read(link) == rec and Stats.Of(link) == rec, "and found from then on")
	Stats.Keep(rec); T.eq(Stats.Cached(), 1, "keeping twice counts once")
	T.check(Stats.Of(T.item({ equipLoc = "INVTYPE_HEAD" })) ~= nil and Stats.Cached() == 2, "Stats.Of reads and keeps")
end)

return T.done()
