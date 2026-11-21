-- Compare.lua: what a candidate replaces, against the best of worn and carried.
local Compare, Stats = NS.Compare, NS.Stats

-- Made-up weights: Strength 1, Stamina 0.5, weapon damage 2 (main hand), 1 (off hand), 3 (ranged).
local W = { STR = 1, STA = 0.5, MH_DPS = 2, OH_DPS = 1, RANGED_DPS = 3 }

local function piece(loc, str, more)
	local def = { equipLoc = loc, classID = 4, subclassID = 0, raw = { ITEM_MOD_STRENGTH_SHORT = str } }
	for k, v in pairs(more or {}) do def[k] = v end
	return T.item(def)
end
local function arm(loc, dps, more)
	local def = { equipLoc = loc, classID = 2, subclassID = (loc == "INVTYPE_2HWEAPON") and 8 or 7,
		raw = { ITEM_MOD_DAMAGE_PER_SECOND_SHORT = dps } }
	for k, v in pairs(more or {}) do def[k] = v end
	return T.item(def)
end
local function ctx(worn, carried, opts, who)
	who = who or { class = "WARRIOR", level = 60, weights = W }
	return Compare.Context(who, worn, carried, opts)
end
local function eval(link, c, opts) return Compare.Evaluate(Stats.Of(link), c, opts) end

T.case("every equip location has a group, and every group a slot", function()
	local n = 0
	for loc in pairs(Stats.GEAR) do
		n = n + 1
		local group = Compare.GROUP_OF[loc]
		T.check(group ~= nil, loc .. " has a group")
		T.check(group and Compare.SLOT_OF[group], loc .. " has a slot")
	end
	T.eq(n, 23, "the gear locations")
	local listed = {}
	for _, g in ipairs(Compare.GROUPS) do listed[g] = true end
	for loc, group in pairs(Compare.GROUP_OF) do
		T.check(listed[group] or group == "TWOHAND", loc .. " is listed (" .. group .. ")")
		T.check(Stats.GEAR[loc], loc .. " is gear")
	end
	T.eq(#Compare.GROUPS, 15, "fifteen rows")
	local expect = { INVTYPE_HEAD = 1, INVTYPE_NECK = 2, INVTYPE_SHOULDER = 3, INVTYPE_CHEST = 5, INVTYPE_ROBE = 5,
		INVTYPE_WAIST = 6, INVTYPE_LEGS = 7, INVTYPE_FEET = 8, INVTYPE_WRIST = 9, INVTYPE_HAND = 10, INVTYPE_FINGER = 11,
		INVTYPE_TRINKET = 13, INVTYPE_CLOAK = 15, INVTYPE_WEAPON = 16, INVTYPE_WEAPONMAINHAND = 16, INVTYPE_2HWEAPON = 16,
		INVTYPE_WEAPONOFFHAND = 17, INVTYPE_SHIELD = 17, INVTYPE_HOLDABLE = 17, INVTYPE_RANGED = 18,
		INVTYPE_RANGEDRIGHT = 18, INVTYPE_THROWN = 18, INVTYPE_RELIC = 18 }
	for loc, slot in pairs(expect) do T.eq(Compare.SLOT_OF[Compare.GROUP_OF[loc]], slot, loc .. " slot") end
end)

T.case("a one-slot place: against what is worn", function()
	T.reset()
	local worn = piece("INVTYPE_HEAD", 10)
	local c = ctx({ [1] = worn }, {})
	local v = eval(piece("INVTYPE_HEAD", 15), c)
	T.eq(v.usable, true, "usable"); T.eq(v.group, "HEAD", "group"); T.eq(v.slot, 1, "slot")
	T.near(v.score, 15, "score"); T.near(v.base, 10, "base"); T.near(v.gain, 5, "gain"); T.near(v.pct, 50, "percent")
	T.eq(v.replaces.key, Stats.Key(worn), "replaces the worn helm"); T.eq(v.empty, false, "not empty")
	v = eval(piece("INVTYPE_HEAD", 8), c)
	T.near(v.gain, -2, "a worse item has a negative gain")
	v = eval(piece("INVTYPE_HEAD", 10), c)
	T.near(v.gain, 0, "an equal item gains nothing")
end)

T.case("a robe and a chest piece share the chest", function()
	T.reset()
	local c = ctx({ [5] = piece("INVTYPE_ROBE", 10) }, {})
	local v = eval(piece("INVTYPE_CHEST", 14), c)
	T.eq(v.group, "CHEST", "group"); T.near(v.gain, 4, "against the robe")
end)

T.case("an empty slot: no percent, said in words", function()
	T.reset()
	local v = eval(piece("INVTYPE_HEAD", 7), ctx({}, {}))
	T.near(v.gain, 7, "the whole score is gain"); T.eq(v.pct, nil, "no percent"); T.eq(v.empty, true, "empty")
	T.eq(v.replaces, nil, "replaces nothing")
end)

T.case("the best of worn and carried is the one to beat", function()
	T.reset()
	local worn, inBag, junk = piece("INVTYPE_LEGS", 10), piece("INVTYPE_LEGS", 18), piece("INVTYPE_LEGS", 3)
	local c = ctx({ [7] = worn }, { junk, inBag })
	local v = eval(piece("INVTYPE_LEGS", 15), c)
	T.near(v.base, 18, "the carried legs are better than the worn"); T.near(v.gain, -3, "so this is no upgrade")
	T.eq(v.replaces.key, Stats.Key(inBag), "and that is what it is measured against")
	v = eval(piece("INVTYPE_LEGS", 15), c, { wornOnly = true })
	T.near(v.gain, 5, "against the worn only, it is")
end)

T.case("a carried item the character cannot wear does not count", function()
	T.reset()
	local worn = piece("INVTYPE_CHEST", 10, { subclassID = 3 })
	local plate = piece("INVTYPE_CHEST", 40, { subclassID = 4 })
	local tooHigh = piece("INVTYPE_CHEST", 50, { subclassID = 3, minLevel = 45 })
	local c = ctx({ [5] = worn }, { plate, tooHigh }, nil, { class = "WARRIOR", level = 30, weights = W })
	T.near(eval(piece("INVTYPE_CHEST", 12, { subclassID = 3 }), c).base, 10, "plate and level-45 mail in the bags are ignored at 30")
	c = ctx({ [5] = worn }, { plate, tooHigh }, nil, { class = "WARRIOR", level = 45, weights = W })
	T.near(eval(piece("INVTYPE_CHEST", 12, { subclassID = 3 }), c).base, 50, "at 45 both count")
end)

T.case("what is worn always counts, whatever the rules say", function()
	T.reset()
	local odd = piece("INVTYPE_CHEST", 22, { subclassID = 4, minLevel = 60 })
	local c = ctx({ [5] = odd }, {}, nil, { class = "MAGE", level = 10, weights = W })
	T.near(eval(piece("INVTYPE_CHEST", 5, { subclassID = 1 }), c).base, 22, "worn is worn")
end)

T.case("the verdict on a carried item leaves its own copy out", function()
	T.reset()
	local worn, inBag = piece("INVTYPE_FEET", 10), piece("INVTYPE_FEET", 16)
	local c = ctx({ [8] = worn }, { inBag })
	T.near(eval(inBag, c).gain, 0, "counted against itself it gains nothing")
	local v = eval(inBag, c, { exclude = Stats.Key(inBag) })
	T.near(v.gain, 6, "left out, it is measured against the worn boots"); T.near(v.pct, 60, "percent")
	-- two copies in the bags: one is left out, the other still counts
	c = ctx({ [8] = worn }, { inBag, inBag })
	T.near(eval(inBag, c, { exclude = Stats.Key(inBag) }).gain, 0, "a second copy is still owned")
	-- the worn item is never the copy left out
	c = ctx({ [8] = inBag }, {})
	T.near(eval(inBag, c, { exclude = Stats.Key(inBag) }).gain, 0, "the same item already worn gains nothing")
end)

T.case("rings: the weaker of the two is replaced", function()
	T.reset()
	local r1, r2 = piece("INVTYPE_FINGER", 10), piece("INVTYPE_FINGER", 4)
	local c = ctx({ [11] = r1, [12] = r2 }, {})
	local v = eval(piece("INVTYPE_FINGER", 7), c)
	T.eq(v.group, "FINGER", "group"); T.near(v.base, 4, "the weaker ring"); T.near(v.gain, 3, "gain"); T.near(v.pct, 75, "percent")
	T.eq(v.replaces.key, Stats.Key(r2), "replaces the weaker ring")
	T.near(eval(piece("INVTYPE_FINGER", 3), c).gain, -1, "worse than both")
	T.near(eval(piece("INVTYPE_FINGER", 12), c).gain, 8, "better than both still replaces the weaker")
	c = ctx({ [11] = r2, [12] = r1 }, {})
	T.near(eval(piece("INVTYPE_FINGER", 7), c).base, 4, "whichever finger it is on")
end)

T.case("rings: one empty finger, and none", function()
	T.reset()
	local c = ctx({ [11] = piece("INVTYPE_FINGER", 10) }, {})
	local v = eval(piece("INVTYPE_FINGER", 2), c)
	T.near(v.gain, 2, "it fills the empty finger"); T.eq(v.empty, true, "empty"); T.eq(v.replaces, nil, "nothing replaced")
	T.near(v.pct, 40, "its percent is against half a typical worn piece (10 / 2)")
	v = eval(piece("INVTYPE_FINGER", 2), ctx({}, {}))
	T.near(v.gain, 2, "no rings at all"); T.eq(v.empty, true, "empty")
end)

T.case("rings: carried rings join the pair", function()
	T.reset()
	local r1, r2, bag = piece("INVTYPE_FINGER", 10), piece("INVTYPE_FINGER", 4), piece("INVTYPE_FINGER", 9)
	local c = ctx({ [11] = r1, [12] = r2 }, { bag })
	local v = eval(piece("INVTYPE_FINGER", 7), c)
	T.near(v.base, 9, "the best two owned are 10 and 9"); T.near(v.gain, -2, "so a 7 is no upgrade")
	T.near(eval(piece("INVTYPE_FINGER", 11), c).gain, 2, "an 11 replaces the 9")
	v = eval(bag, c, { exclude = Stats.Key(bag) })
	T.near(v.gain, 5, "the carried ring itself is an upgrade over the worn 4")
end)

T.case("trinkets pair up the same way", function()
	T.reset()
	local c = ctx({ [13] = piece("INVTYPE_TRINKET", 6), [14] = piece("INVTYPE_TRINKET", 2) }, {})
	local v = eval(piece("INVTYPE_TRINKET", 5), c)
	T.eq(v.group, "TRINKET", "group"); T.eq(v.slot, 13, "slot"); T.near(v.gain, 3, "against the weaker trinket")
end)

T.case("unique-equipped: a second copy can only replace the first", function()
	T.reset()
	local uniq = piece("INVTYPE_FINGER", 10, { id = 4242, unique = true })
	local weak = piece("INVTYPE_FINGER", 4)
	local c = ctx({ [11] = uniq, [12] = weak }, {})
	local v = eval(uniq, c)
	T.near(v.gain, 0, "the same unique ring again gains nothing"); T.eq(v.replaces.key, Stats.Key(uniq), "it replaces itself")
	-- another roll of the same unique item, better: measured against its own copy, not the weak ring
	local better = T.item({ id = 4242, suffix = 77, equipLoc = "INVTYPE_FINGER", unique = true, raw = { ITEM_MOD_STRENGTH_SHORT = 13 } })
	v = eval(better, c)
	T.near(v.base, 10, "against its own copy"); T.near(v.gain, 3, "gain")
	-- the copy is the weaker of the two: same answer as the plain rule
	c = ctx({ [11] = piece("INVTYPE_FINGER", 20), [12] = uniq }, {})
	T.near(eval(better, c).base, 10, "copy in the second place")
	-- a unique ring the character does not have follows the plain rule
	local other = piece("INVTYPE_FINGER", 12, { unique = true })
	c = ctx({ [11] = uniq, [12] = weak }, {})
	T.near(eval(other, c).base, 4, "a different unique ring replaces the weaker")
	-- a non-unique ring may be worn twice
	local plain = piece("INVTYPE_FINGER", 10)
	c = ctx({ [11] = plain, [12] = weak }, {})
	T.near(eval(plain, c).gain, 6, "a second copy of a plain ring replaces the weak one")
end)

local PALADIN = { class = "PALADIN", level = 60, weights = W }   -- cannot dual wield
local ROGUE = { class = "ROGUE", level = 60, weights = W }       -- can

T.case("weapons: a main hand against a main hand (a class that cannot dual wield)", function()
	T.reset()
	local main, shield = arm("INVTYPE_WEAPONMAINHAND", 20), piece("INVTYPE_SHIELD", 6, { subclassID = 6 })
	local c = ctx({ [16] = main, [17] = shield }, {}, nil, PALADIN)
	T.eq(c.dual, false, "a paladin cannot dual wield")
	local v = eval(arm("INVTYPE_WEAPON", 25), c)
	T.eq(v.group, "MAINHAND", "a one-hander goes in the main hand"); T.eq(v.slot, 16, "slot"); T.eq(v.twoHand, false, "not two-hand")
	T.eq(v.offHand, false, "not the off hand")
	T.near(v.score, 50, "score"); T.near(v.base, 40, "against the main hand only"); T.near(v.gain, 10, "gain"); T.near(v.pct, 25, "percent")
	T.eq(v.replaces.key, Stats.Key(main), "replaces the main hand")
end)

T.case("weapons: a dual wielder's one-hander is tried in both hands (the audit's M4)", function()
	T.reset()
	-- A rogue with a 28 DPS sword in the main hand and an 18 DPS one-hand sword in the off hand,
	-- looking at a 26 DPS one-hand sword. Weights: main-hand damage 2, off-hand damage 1.
	local main, off = arm("INVTYPE_WEAPON", 28), arm("INVTYPE_WEAPON", 18)
	local c = ctx({ [16] = main, [17] = off }, {}, nil, ROGUE)
	T.eq(c.dual, true, "a rogue can dual wield")
	local v = eval(arm("INVTYPE_WEAPON", 26), c)
	-- today: 28 main (56) + 18 off (18) = 74. As off hand: 56 + 26 = 82. As main hand: 52 + 28 off = 80.
	T.eq(v.group, "OFFHAND", "it is an off-hand upgrade"); T.eq(v.slot, 17, "slot 17"); T.eq(v.offHand, true, "flagged")
	T.near(v.score, 26, "scored with the off-hand weight"); T.near(v.base, 18, "against the worn off hand"); T.near(v.gain, 8, "gain")
	T.eq(v.replaces.key, Stats.Key(off), "it replaces the off-hand sword"); T.eq(v.usable, true, "usable")
	-- a sword better than the main hand goes in the main hand
	v = eval(arm("INVTYPE_WEAPON", 40), c)
	-- as main: 80 + 28 off = 108 (gain 34); as off: 56 + 40 = 96 (gain 22)
	T.eq(v.group, "MAINHAND", "a big one goes in the main hand"); T.near(v.gain, 34, "with the old main hand moved to the off hand")
	T.near(v.base, 46, "what it must beat on its own: the set less its partner"); T.eq(v.replaces.key, Stats.Key(main), "replaces the main hand")
	-- no better in either hand
	v = eval(arm("INVTYPE_WEAPON", 17), c)
	T.check(v.gain < 0, "a worse sword is no upgrade in either hand")
	-- an owned one-hander is never paired with itself
	c = ctx({ [16] = main }, {}, nil, ROGUE)
	v = eval(arm("INVTYPE_WEAPON", 10), c)
	T.eq(v.group, "OFFHAND", "with an empty off hand, a second sword fills it"); T.near(v.gain, 10, "its whole off-hand score")
	T.eq(v.empty, true, "the off hand was empty"); T.near(v.base, 0, "nothing to beat")
	-- a main-hand-only weapon is not tried in the off hand, an off-hand-only one not in the main
	c = ctx({ [16] = main, [17] = off }, {}, nil, ROGUE)
	T.eq(eval(arm("INVTYPE_WEAPONMAINHAND", 26), c).group, "MAINHAND", "main-hand-only stays in the main hand")
	v = eval(arm("INVTYPE_WEAPONOFFHAND", 26), c)
	T.eq(v.group, "OFFHAND", "off-hand-only stays in the off hand"); T.near(v.gain, 8, "26 over 18, both by the off-hand weight")
	-- a carried one-hander joins both hands' pools; the verdict on it leaves its own copy out of both
	local spare = arm("INVTYPE_WEAPON", 30)
	c = ctx({ [16] = main, [17] = off }, { spare }, nil, ROGUE)
	v = eval(arm("INVTYPE_WEAPON", 26), c)
	-- owned best: 30 main (60) + 28 off (28) = 88; candidate as off: 60 + 26 = 86
	T.check(v.gain < 0, "with a better sword in the bags, the 26 is no upgrade")
	v = eval(spare, c, { exclude = Stats.Key(spare) })
	T.near(v.gain, 14, "the carried sword itself: 60 + 28 against the worn 74"); T.eq(v.group, "MAINHAND", "in the main hand")
	-- below the level for it, a warrior is not a dual wielder
	c = ctx({ [16] = main, [17] = piece("INVTYPE_SHIELD", 6, { subclassID = 6 }) }, {}, nil, { class = "WARRIOR", level = 19, weights = W })
	T.eq(c.dual, false, "a level 19 warrior cannot dual wield")
	T.eq(eval(arm("INVTYPE_WEAPON", 30), c).group, "MAINHAND", "so a one-hander is a main hand")
	WORLD.spells[674] = true
	c = ctx({ [16] = main }, {}, nil, { class = "WARRIOR", level = 19, weights = W })
	T.eq(c.dual, true, "unless the character knows Dual Wield")
end)

T.case("weapons: a dual wielder's shield and held item still compete for the off hand", function()
	T.reset()
	local main, off = arm("INVTYPE_WEAPON", 28), arm("INVTYPE_WEAPON", 18)
	local c = ctx({ [16] = main, [17] = off }, {})   -- a level 60 warrior
	local v = eval(piece("INVTYPE_SHIELD", 25, { subclassID = 6 }), c)
	T.eq(v.group, "OFFHAND", "a shield is an off hand"); T.near(v.base, 18, "against the off-hand sword"); T.near(v.gain, 7, "gain")
	v = eval(piece("INVTYPE_HOLDABLE", 20), c)
	T.near(v.gain, 2, "a held item against the off-hand sword")
end)

T.case("weapons: an off hand against an off hand", function()
	T.reset()
	local main, shield = arm("INVTYPE_WEAPON", 20), piece("INVTYPE_SHIELD", 6, { subclassID = 6 })
	local c = ctx({ [16] = main, [17] = shield }, {}, nil, PALADIN)
	local v = eval(piece("INVTYPE_SHIELD", 9, { subclassID = 6 }), c)
	T.eq(v.group, "OFFHAND", "group"); T.eq(v.slot, 17, "slot")
	T.near(v.base, 6, "against the shield only"); T.near(v.gain, 3, "gain"); T.eq(v.replaces.key, Stats.Key(shield), "replaces the shield")
	v = eval(piece("INVTYPE_HOLDABLE", 8), c)
	T.near(v.gain, 2, "a held item competes for the same hand")
	v = eval(arm("INVTYPE_WEAPONOFFHAND", 7), c)
	T.near(v.score, 7, "an off-hand weapon scores with the off-hand weight"); T.near(v.gain, 1, "gain")
	T.eq(v.usable, false, "though a paladin cannot hold one"); T.eq(v.reason, "dualwield", "and is told why")
end)

T.case("weapons: a two-hander against main hand plus off hand", function()
	T.reset()
	local main, shield = arm("INVTYPE_WEAPON", 20), piece("INVTYPE_SHIELD", 6, { subclassID = 6 })
	local c = ctx({ [16] = main, [17] = shield }, {}, nil, PALADIN)
	local v = eval(arm("INVTYPE_2HWEAPON", 25), c)
	T.eq(v.group, "MAINHAND", "listed with the main hand"); T.eq(v.twoHand, true, "two-hand"); T.eq(v.slot, 16, "slot")
	T.near(v.score, 50, "score"); T.near(v.base, 46, "main hand 40 plus shield 6"); T.near(v.gain, 4, "gain")
	T.near(eval(arm("INVTYPE_2HWEAPON", 22), c).gain, -2, "a two-hander that beats the sword but not the pair is no upgrade")
end)

T.case("weapons: holding a two-hander", function()
	T.reset()
	local two = arm("INVTYPE_2HWEAPON", 30)
	local c = ctx({ [16] = two }, {}, nil, PALADIN)
	local v = eval(arm("INVTYPE_2HWEAPON", 33), c)
	T.near(v.base, 60, "two-hander against two-hander"); T.near(v.gain, 6, "gain"); T.eq(v.replaces.key, Stats.Key(two), "replaces it")
	v = eval(arm("INVTYPE_WEAPON", 28), c)
	T.near(v.gain, -4, "a one-hander alone must beat the whole two-hander")
	T.eq(v.replaces.key, Stats.Key(two), "and that is what it would replace")
	v = eval(piece("INVTYPE_SHIELD", 9, { subclassID = 6 }), c)
	T.near(v.gain, -51, "a shield alone is no reason to drop a two-hander")
	-- with a good off hand in the bags, the same one-hander wins as a pair
	local shield = piece("INVTYPE_SHIELD", 9, { subclassID = 6 })
	c = ctx({ [16] = two }, { shield }, nil, PALADIN)
	v = eval(arm("INVTYPE_WEAPON", 28), c)
	T.near(v.gain, 5, "one-hander 56 plus carried shield 9 against two-hander 60")
	T.near(v.base, 51, "base is what the candidate must beat on its own")
end)

T.case("weapons: a better pair in the bags is what a two-hander must beat", function()
	T.reset()
	local two, main, shield = arm("INVTYPE_2HWEAPON", 30), arm("INVTYPE_WEAPON", 29), piece("INVTYPE_SHIELD", 9, { subclassID = 6 })
	local c = ctx({ [16] = two }, { main, shield }, nil, PALADIN)
	local v = eval(arm("INVTYPE_2HWEAPON", 32), c)
	T.near(v.base, 67, "the carried pair (58 + 9) beats the worn two-hander (60)"); T.near(v.gain, -3, "so 64 is no upgrade")
end)

T.case("weapons: nothing in hand", function()
	T.reset()
	local v = eval(arm("INVTYPE_WEAPON", 5), ctx({}, {}))
	T.near(v.gain, 10, "anything beats bare hands"); T.eq(v.empty, true, "empty"); T.eq(v.pct, nil, "no percent")
end)

T.case("ranged is a place of its own", function()
	T.reset()
	local bow = T.item({ equipLoc = "INVTYPE_RANGED", classID = 2, subclassID = 2, raw = { ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 10 } })
	local c = ctx({ [16] = arm("INVTYPE_2HWEAPON", 30), [18] = bow }, {})
	local gun = T.item({ equipLoc = "INVTYPE_RANGEDRIGHT", classID = 2, subclassID = 3, raw = { ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 12 } })
	local v = eval(gun, c)
	T.eq(v.group, "RANGED", "group"); T.eq(v.slot, 18, "slot"); T.near(v.base, 30, "against the bow"); T.near(v.gain, 6, "gain")
	local thrown = T.item({ equipLoc = "INVTYPE_THROWN", classID = 2, subclassID = 16, raw = { ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 11 } })
	T.near(eval(thrown, c).gain, 3, "a thrown weapon competes with the bow")
end)

T.case("unusable candidates say why, and still carry their numbers", function()
	T.reset()
	local c = ctx({ [5] = piece("INVTYPE_CHEST", 10, { subclassID = 1 }) }, {}, nil, { class = "MAGE", level = 20, weights = W })
	local v = eval(piece("INVTYPE_CHEST", 30, { subclassID = 4 }), c)
	T.eq(v.usable, false, "plate on a mage"); T.eq(v.reason, "armor", "reason"); T.near(v.gain, 20, "the gain is still worked out")
	v = eval(piece("INVTYPE_CHEST", 30, { subclassID = 1, minLevel = 25 }), c)
	T.eq(v.usable, false, "too high"); T.eq(v.reason, "level", "reason"); T.eq(v.atLevel, 25, "at 25")
	v = eval(arm("INVTYPE_2HWEAPON", 30), c)
	T.eq(v.usable, false, "a two-hand sword on a mage"); T.eq(v.reason, "weapon", "reason")
end)

T.case("the best-armor preference is about candidates, not about what is owned", function()
	T.reset()
	local mailWorn = piece("INVTYPE_CHEST", 10, { subclassID = 3 })
	local c = ctx({ [5] = mailWorn }, { piece("INVTYPE_CHEST", 14, { subclassID = 3 }) }, { bestArmor = true })
	local v = eval(piece("INVTYPE_CHEST", 30, { subclassID = 3 }), c)
	T.eq(v.usable, false, "mail is passed over for a level 60 warrior"); T.eq(v.reason, "lighter", "reason")
	T.near(v.base, 14, "but the carried mail still counts as owned")
	T.eq(eval(piece("INVTYPE_CHEST", 30, { subclassID = 4 }), c).usable, true, "plate is fine")
end)

T.case("owned items the game has not loaded are counted as pending", function()
	T.reset()
	local late = T.item({ equipLoc = "INVTYPE_HEAD", loaded = false, raw = { ITEM_MOD_STRENGTH_SHORT = 9 } })
	local c = ctx({ [1] = late }, { late, piece("INVTYPE_HEAD", 3) })
	T.eq(c.pending, 2, "two links not readable yet")
	T.near(eval(piece("INVTYPE_HEAD", 5), c).base, 3, "the rest is used meanwhile")
	T.load(late)
	c = ctx({ [1] = late }, {})
	T.eq(c.pending, 0, "none pending once loaded"); T.near(eval(piece("INVTYPE_HEAD", 5), c).base, 9, "and it counts")
end)

T.case("things that are not gear in the bags are ignored", function()
	T.reset()
	local c = ctx({}, { T.item({ equipLoc = "" }), T.item({ equipLoc = "INVTYPE_BAG" }), "not a link" })
	T.eq(c.pending, 0, "nothing pending"); T.eq(next(c.pools), nil, "nothing owned")
end)

T.case("negative scores never make a percent", function()
	T.reset()
	local c = Compare.Context({ class = "WARRIOR", level = 60, weights = { STR = 1, SPI = -1 } },
		{ [1] = T.item({ equipLoc = "INVTYPE_HEAD", raw = { ITEM_MOD_SPIRIT_SHORT = 5 } }) }, {})
	local v = eval(piece("INVTYPE_HEAD", 4), c)
	T.near(v.base, -5, "a worn item that scores below zero"); T.near(v.gain, 9, "gain"); T.eq(v.pct, nil, "no percent of a negative")
	T.eq(v.empty, false, "the slot is not empty"); T.check(v.replaces ~= nil, "it holds the item that would be replaced")
end)

T.case("the percent has a floor: a near-worthless item in the slot (the audit's M2)", function()
	T.reset()
	-- Worn: a chest and legs worth 20 each, and a neck worth 0.1. A typical piece is (20 + 20 + 0.1) / 3.
	local neck = T.item({ equipLoc = "INVTYPE_NECK", raw = { ITEM_MOD_STAMINA_SHORT = 0.2 } })
	local c = ctx({ [5] = piece("INVTYPE_CHEST", 20), [7] = piece("INVTYPE_LEGS", 20), [2] = neck }, {})
	T.near(c.typical, 40.1 / 3, "what a worn piece is worth on average")
	local v = eval(piece("INVTYPE_NECK", 6), c)
	T.near(v.gain, 5.9, "the gain is untouched: it is what ranking uses"); T.near(v.base, 0.1, "and so is the base")
	T.near(v.pct, 5.9 / (40.1 / 6) * 100, "the percent is against half a typical piece, not against 0.1")
	T.check(v.pct < 100, "so it reads about 88%, not 5900%"); T.eq(v.far, false, "not 'far'")
	T.eq(v.empty, false, "the slot is not empty"); T.eq(v.replaces.key, Stats.Key(neck), "and what is replaced is named")
	-- a normal baseline is left alone
	v = eval(piece("INVTYPE_CHEST", 25), c)
	T.near(v.pct, 25, "25 over 20 is still +25%")
	-- beyond the cap the surfaces use words
	v = eval(piece("INVTYPE_NECK", 30), c)
	T.check(v.pct > NS.Compare.FAR, "a neck worth more than the chest"); T.eq(v.far, true, "is 'far better'")
	T.eq(NS.Compare.FAR, 200, "the cap")
	v = eval(piece("INVTYPE_CHEST", 60), c)
	T.near(v.pct, 200, "exactly at the cap is still a figure"); T.eq(v.far, false, "not yet 'far'")
end)

T.case("a worn item that scores nothing is not an empty slot (the audit's M3)", function()
	T.reset()
	local spiritNeck = T.item({ equipLoc = "INVTYPE_NECK", raw = { ITEM_MOD_SPIRIT_SHORT = 12 } })
	local c = ctx({ [2] = spiritNeck, [5] = piece("INVTYPE_CHEST", 20) }, {})
	local v = eval(piece("INVTYPE_NECK", 5), c)
	T.near(v.base, 0, "the worn neck scores 0 for this spec"); T.eq(v.empty, false, "but the slot is not empty")
	T.eq(v.replaces.key, Stats.Key(spiritNeck), "the neck is what would be replaced"); T.near(v.pct, 50, "5 against half a typical piece (10)")
	-- nothing worn scores at all: no percent, still not empty
	c = ctx({ [2] = spiritNeck }, {})
	v = eval(piece("INVTYPE_NECK", 5), c)
	T.eq(v.pct, nil, "nothing to measure against"); T.eq(v.empty, false, "not empty"); T.near(c.typical, 0, "no typical piece")
	-- truly empty
	v = eval(piece("INVTYPE_HEAD", 5), c)
	T.eq(v.empty, true, "a slot with nothing in it is empty"); T.eq(v.replaces, nil, "nothing replaced")
end)

T.case("FromGame reads worn and carried through the game table", function()
	T.reset()
	WORLD.worn[1] = piece("INVTYPE_HEAD", 10)
	WORLD.bags = { piece("INVTYPE_HEAD", 12), piece("INVTYPE_LEGS", 3) }
	local c = Compare.FromGame({ class = "WARRIOR", level = 60, weights = W })
	T.near(eval(piece("INVTYPE_HEAD", 15), c).base, 12, "bags counted")
	WORLD.bags = {}
	c = Compare.FromGame({ class = "WARRIOR", level = 60, weights = W })
	T.near(eval(piece("INVTYPE_HEAD", 15), c).base, 10, "the bag list is read afresh each time")
end)

T.case("Evaluate fills the table it is given", function()
	T.reset()
	local c = ctx({ [1] = piece("INVTYPE_HEAD", 10) }, {})
	local out = { pct = 99, replaces = "stale", empty = true, far = true, offHand = true }
	local v = Compare.Evaluate(Stats.Of(piece("INVTYPE_HEAD", 10)), c, nil, out)
	T.check(v == out, "the same table"); T.near(out.pct, 0, "stale fields are overwritten"); T.eq(out.empty, false, "empty reset")
	T.eq(out.far, false, "far reset"); T.eq(out.offHand, false, "offHand reset")
	Compare.Evaluate(Stats.Of(piece("INVTYPE_HEAD", 4)), ctx({}, {}), nil, out)
	T.eq(out.pct, nil, "pct cleared"); T.eq(out.replaces, nil, "replaces cleared")
end)

return T.done()
