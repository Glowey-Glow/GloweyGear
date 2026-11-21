-- Spec.lua: checking the weights data, telling the spec from talent points, level brackets.
local Spec = NS.Spec

local function spec(tab, weights, more)
	local s = { tab = tab, role = "melee", source = "authored", confidence = "low", weights = weights or { STR = 1 } }
	for k, v in pairs(more or {}) do s[k] = v end
	return s
end

local function data()
	return {
		format = 1,
		WARRIOR = {
			default = "ARMS", order = { "ARMS", "FURY", "PROTECTION" },
			specs = {
				ARMS = spec(1, { STR = 1, STA = 0.1, HIT = 10 }, { brackets = {
					{ upTo = 19, weights = { STA = 0.8, HIT = 0 } },
					{ upTo = 39, weights = { STA = 0.5 } },
				} }),
				FURY = spec(2, { STR = 1, CRIT = 12 }, { source = "wowsims", sourcePath = "ui/x/presets.ts", sourceCommit = "abc1234" }),
				PROTECTION = spec(3, { STA = 1, ARMOR = 0.05 }, { role = "tank" }),
			},
		},
		DRUID = {
			default = "CAT", order = { "BALANCE", "BEAR", "CAT", "RESTORATION" },
			specs = {
				BALANCE = spec(1, { SPELL_DMG = 1 }),
				BEAR = spec(2, { STA = 1 }, { manual = true }),
				CAT = spec(2, { AGI = 1 }),
				RESTORATION = spec(3, { HEAL = 1 }),
			},
		},
	}
end

local function trees(a, b, c) return { { name = "One", spent = a }, { name = "Two", spent = b }, { name = "Three", spent = c } } end

T.case("good data loads whole", function()
	local problems = Spec.Load(data())
	T.eq(#problems, 0, "no problems: " .. table.concat(problems, "; "))
	T.check(Spec.HasClass("WARRIOR"), "warrior"); T.check(Spec.HasClass("DRUID"), "druid")
	T.check(not Spec.HasClass("MAGE"), "a class with no data")
	T.eq(table.concat(Spec.List("WARRIOR"), ","), "ARMS,FURY,PROTECTION", "picker order")
	T.eq(#Spec.List("MAGE"), 0, "an empty list for a class with no data")
	T.eq(Spec.Info("WARRIOR", "FURY").sourceCommit, "abc1234", "the spec's own table")
	T.eq(Spec.Info("WARRIOR", "NOPE"), nil, "an unknown spec"); T.eq(Spec.Info("MAGE", "FIRE"), nil, "an unknown class")
end)

T.case("a broken spec is left out, the rest still load", function()
	local d = data()
	d.WARRIOR.specs.FURY.weights.STRENGTH = 2                 -- not a canonical key
	d.DRUID.specs.BALANCE.tab = 4
	d.DRUID.specs.RESTORATION.confidence = "sure"
	d.ROGUE = { order = { "COMBAT" }, specs = { COMBAT = spec(2, { AGI = 0 / 0 }) } }   -- not a number
	d.HUNTER = { order = { "SURVIVAL", "GHOST" }, specs = { SURVIVAL = spec(3, { AGI = 1 }) } }
	d.GNOME = { order = {}, specs = {} }
	d.PRIEST = { order = { "HOLY" }, specs = { HOLY = spec(2, { HEAL = 1 }, { source = "wowsims" }) } }   -- no path
	d.MAGE = { default = "ICE", order = { "FROST" }, specs = { FROST = spec(3, { SPELL_DMG = 1 }) } }
	d.SHAMAN = { order = { "low" }, specs = { low = spec(1) } }
	d.PALADIN = { specs = {} }
	local problems = Spec.Load(d)
	T.eq(table.concat(Spec.List("WARRIOR"), ","), "ARMS,PROTECTION", "the bad spec is gone, its neighbors stay")
	T.eq(table.concat(Spec.List("DRUID"), ","), "BEAR,CAT", "two bad druid specs gone")
	T.check(not Spec.HasClass("ROGUE"), "a class whose only spec is bad has no data")
	T.eq(table.concat(Spec.List("HUNTER"), ","), "SURVIVAL", "a key in order with no spec is skipped")
	T.check(not Spec.HasClass("PRIEST"), "wowsims without a path is refused")
	T.check(not Spec.HasClass("SHAMAN"), "a lower-case spec key is refused")
	T.check(not Spec.HasClass("PALADIN"), "a class with no order")
	T.eq(Spec.Detect("MAGE", nil, nil), "FROST", "a bad default falls back to the first spec")
	T.eq(#problems, 10, "each problem is reported once: " .. table.concat(problems, " | "))
end)

T.case("bad brackets are refused", function()
	local d = data()
	d.WARRIOR.specs.ARMS.brackets = { { upTo = 39, weights = {} }, { upTo = 19, weights = {} } }
	local problems = Spec.Load(d)
	T.eq(#problems, 2, "brackets must rise (the spec is refused, and the class default with it)")
	T.eq(Spec.Detect("WARRIOR", nil, nil), "FURY", "the default falls back to the first spec left")
	d = data()
	d.WARRIOR.specs.ARMS.brackets = { { upTo = 39, weights = { BOGUS = 1 } } }
	T.eq(#Spec.Load(d), 2, "a bracket's keys are checked too")
	T.eq(#Spec.Load(nil), 0, "no data at all is not an error")
	T.check(not Spec.HasClass("WARRIOR"), "and leaves nothing loaded")
end)

T.case("the tree with the most points is the spec", function()
	Spec.Load(data())
	T.eq(Spec.Detect("WARRIOR", trees(31, 20, 0), nil), "ARMS", "arms")
	T.eq(Spec.Detect("WARRIOR", trees(5, 31, 15), nil), "FURY", "fury")
	T.eq(Spec.Detect("WARRIOR", trees(0, 3, 48), nil), "PROTECTION", "protection")
	local key, how = Spec.Detect("WARRIOR", trees(1, 0, 0), nil)
	T.eq(key, "ARMS", "one point is enough"); T.eq(how, "talents", "and says how")
end)

T.case("no points, no trees", function()
	Spec.Load(data())
	local key, how = Spec.Detect("WARRIOR", trees(0, 0, 0), "FURY")
	T.eq(key, "ARMS", "no points spent: the default, whatever was last"); T.eq(how, "default", "how")
	key, how = Spec.Detect("WARRIOR", nil, "FURY")
	T.eq(key, "FURY", "no tree data yet: the last answer"); T.eq(how, "last", "how")
	key, how = Spec.Detect("WARRIOR", nil, nil)
	T.eq(key, "ARMS", "no tree data and no last answer: the default"); T.eq(how, "default", "how")
	T.eq(Spec.Detect("WARRIOR", {}, "GONE"), "ARMS", "a last answer that no longer exists is ignored")
	T.eq(Spec.Detect("MAGE", trees(1, 2, 3), nil), nil, "a class with no data has no spec")
end)

T.case("ties", function()
	Spec.Load(data())
	T.eq(Spec.Detect("WARRIOR", trees(10, 10, 0), nil), "ARMS", "leftmost of the tied trees")
	T.eq(Spec.Detect("WARRIOR", trees(10, 10, 0), "FURY"), "FURY", "the last answer keeps a tie it is part of")
	T.eq(Spec.Detect("WARRIOR", trees(10, 10, 0), "PROTECTION"), "ARMS", "but not one it is not part of")
	T.eq(Spec.Detect("WARRIOR", trees(0, 10, 10), nil), "FURY", "leftmost again")
	T.eq(Spec.Detect("WARRIOR", trees(10, 11, 0), "ARMS"), "FURY", "a lead beats the last answer")
end)

T.case("variants on one tree", function()
	Spec.Load(data())
	T.eq(Spec.Detect("DRUID", trees(0, 30, 0), nil), "CAT", "Auto skips the manual variant though it is listed first")
	T.eq(Spec.Detect("DRUID", trees(0, 0, 0), nil), "CAT", "the default")
	local key, how = Spec.Resolve("DRUID", "BEAR", trees(0, 30, 0), nil)
	T.eq(key, "BEAR", "the player's choice wins"); T.eq(how, "chosen", "how")
	T.eq(Spec.Resolve("DRUID", "BEAR", trees(40, 0, 0), nil), "BEAR", "even against the talents")
	T.eq(Spec.Resolve("DRUID", "auto", trees(40, 0, 0), nil), "BALANCE", "auto follows talents")
	T.eq(Spec.Resolve("DRUID", "FURY", trees(40, 0, 0), nil), "BALANCE", "a choice from another class is ignored")
	T.eq(Spec.Resolve("DRUID", nil, trees(0, 0, 9), nil), "RESTORATION", "no choice is auto")
	T.eq(Spec.Resolve("MAGE", "FIRE", trees(0, 9, 0), nil), nil, "no data, no spec")
end)

T.case("level brackets: exact at their middles, sliding between, the base at 60", function()
	Spec.Load(data())
	-- ARMS: brackets to 19 (STA 0.8, HIT 0) and to 39 (STA 0.5); base STA 0.1, HIT 10, STR 1.
	-- Anchors: level 10, level 29.5, level 60.
	local top = Spec.Weights("WARRIOR", "ARMS", 60)
	T.check(top == Spec.Info("WARRIOR", "ARMS").weights, "level 60 is the base table itself")
	local low = Spec.Weights("WARRIOR", "ARMS", 10)
	T.near(low.STA, 0.8, "the first bracket's middle is the bracket as written")
	T.near(low.HIT, 0, "a key switched off"); T.near(low.STR, 1, "a key only in the base stays")
	T.near(Spec.Weights("WARRIOR", "ARMS", 1).STA, 0.8, "below the first middle: the first bracket, flat")
	T.near(Spec.Weights("WARRIOR", "ARMS", 5).HIT, 0, "flat for every key")
	local function sta(level) return Spec.Weights("WARRIOR", "ARMS", level).STA end
	local function hit(level) return Spec.Weights("WARRIOR", "ARMS", level).HIT end
	T.near(sta(19), 0.8 + (0.5 - 0.8) * (9 / 19.5), "level 19 by the straight line")
	T.near(sta(20), 0.8 + (0.5 - 0.8) * (10 / 19.5), "level 20 by the same line")
	T.near(sta(19) - sta(20), 0.3 / 19.5, "no step from 19 to 20: one level's worth")
	T.near(hit(20), 10 * (10 / 19.5), "hit rises from 0 toward the second bracket's 10")
	T.near(sta(39), 0.5 + (0.1 - 0.5) * (9.5 / 30.5), "level 39")
	T.near(sta(40), 0.5 + (0.1 - 0.5) * (10.5 / 30.5), "level 40")
	T.near(sta(39) - sta(40), 0.4 / 30.5, "no step from 39 to 40")
	T.near(sta(59), 0.5 + (0.1 - 0.5) * (29.5 / 30.5), "level 59 is nearly the base")
	T.check(sta(59) - sta(60) < 0.02, "no step from 59 to 60")
	T.near(hit(45), 10, "a key equal on both sides stays put")
	for level = 2, 60 do
		T.check(sta(level) <= sta(level - 1) + 1e-12, "Stamina only falls with level here (" .. level .. ")")
		T.near(Spec.Weights("WARRIOR", "ARMS", level).STR, 1, "Strength never moves (" .. level .. ")")
	end
	T.check(Spec.Weights("WARRIOR", "ARMS", 12) == Spec.Weights("WARRIOR", "ARMS", 12), "built once per level")
	T.check(Spec.Weights("WARRIOR", "ARMS", 12.7) == Spec.Weights("WARRIOR", "ARMS", 12), "a level is a whole number")
	T.check(Spec.Weights("WARRIOR", "ARMS", 75) == top, "above 60 is 60")
	T.check(Spec.Weights("WARRIOR", "ARMS", nil) == top, "no level is 60")
	T.near(Spec.Weights("WARRIOR", "ARMS", 0).STA, 0.8, "below 1 is 1")
	T.eq(Spec.Info("WARRIOR", "ARMS").weights.STA, 0.1, "the data itself is never changed")
	T.eq(Spec.Info("WARRIOR", "ARMS").brackets[1].weights.STR, nil, "nor its brackets")
	T.eq(Spec.Weights("WARRIOR", "FURY", 5).CRIT, 12, "a spec without brackets uses its base at any level")
	T.eq(Spec.Weights("WARRIOR", "NOPE", 60), nil, "an unknown spec has no weights")
end)

T.case("a key only in a bracket fades out toward the base", function()
	local d = data()
	d.WARRIOR.specs.FURY.brackets = { { upTo = 59, weights = { SPI = 0.6 } } }   -- one anchor at level 30
	Spec.Load(d)
	T.near(Spec.Weights("WARRIOR", "FURY", 30).SPI, 0.6, "at the middle")
	T.near(Spec.Weights("WARRIOR", "FURY", 45).SPI, 0.3, "half way to 60")
	T.eq(Spec.Weights("WARRIOR", "FURY", 60).SPI, nil, "gone at 60")
	T.near(Spec.Weights("WARRIOR", "FURY", 45).CRIT, 12, "the base keys are untouched")
end)

T.case("a manual spec as the class default (the Leveling profile)", function()
	local d = data()
	d.WARRIOR.order = { "ARMS", "FURY", "PROTECTION", "LEVELING" }
	d.WARRIOR.default = "LEVELING"
	d.WARRIOR.specs.LEVELING = spec(1, { STR = 1, STA = 0.6 }, { manual = true })
	T.eq(#Spec.Load(d), 0, "loads")
	local key, how = Spec.Detect("WARRIOR", trees(0, 0, 0), nil)
	T.eq(key, "LEVELING", "no points spent: the manual default"); T.eq(how, "default", "how")
	T.eq(Spec.Detect("WARRIOR", nil, nil), "LEVELING", "no tree data and nothing remembered: the default")
	T.eq(Spec.Detect("WARRIOR", trees(1, 0, 0), nil), "ARMS", "the first point in a tree picks the tree's spec, not the manual one")
	T.eq(Spec.Detect("WARRIOR", trees(5, 5, 0), "LEVELING"), "ARMS", "a remembered manual spec never holds a tie")
	T.eq(Spec.Detect("WARRIOR", nil, "ARMS"), "ARMS", "a remembered spec is used while the talents are not readable")
	T.eq(Spec.Resolve("WARRIOR", "LEVELING", trees(31, 20, 0), nil), "LEVELING", "and the player may pick it at any level")
	T.eq(Spec.Resolve("WARRIOR", "auto", trees(0, 0, 0), "FURY"), "LEVELING", "after a talent reset Auto is the default again")
	local label, ours = Spec.Label("WARRIOR", "LEVELING", trees(0, 0, 0))
	T.eq(label, "Leveling", "its name is our own word"); T.eq(ours, true, "flagged for translation")
	label, ours = Spec.Label("WARRIOR", "FURY", trees(0, 0, 0))
	T.eq(label, "Two", "a tree's spec takes the game's tree name"); T.eq(ours, false, "already in the client's language")
	T.eq(Spec.Label("WARRIOR", "FURY", nil), nil, "no tree data: no name (the caller shows the key)")
	T.eq(Spec.Label("WARRIOR", "NOPE", nil), nil, "an unknown spec")
end)

T.case("the player: Spec.Current", function()
	T.reset()
	Spec.Load(data())
	local saved
	Spec.GetChoice = function() return "auto" end
	Spec.GetLast = function() return saved end
	Spec.SetLast = function(key) saved = key end
	WORLD.class, WORLD.level, WORLD.trees = "WARRIOR", 33, trees(8, 16, 0)
	local who = Spec.Current()
	T.eq(who.class, "WARRIOR", "class"); T.eq(who.spec, "FURY", "spec"); T.eq(who.level, 33, "level")
	T.eq(who.how, "talents", "how"); T.eq(who.weights.CRIT, 12, "weights")
	T.eq(saved, "FURY", "the answer is remembered")
	WORLD.trees = nil
	T.eq(Spec.Current().spec, "FURY", "and used while the talents are not readable")
	Spec.GetChoice = function() return "PROTECTION" end
	WORLD.trees = trees(8, 16, 0)
	who = Spec.Current()
	T.eq(who.spec, "PROTECTION", "a chosen spec"); T.eq(who.how, "chosen", "how"); T.eq(saved, "FURY", "does not overwrite the remembered one")
	WORLD.class = "MAGE"
	local none, why = Spec.Current()
	T.eq(none, nil, "a class with no weights"); T.eq(why, "noweights", "says so, politely")
	WORLD.class = nil
	none, why = Spec.Current()
	T.eq(none, nil, "no spec"); T.eq(why, "noclass", "no class yet")
	WORLD.class, WORLD.level = "WARRIOR", nil
	none, why = Spec.Current()
	T.eq(none, nil, "no spec"); T.eq(why, "nolevel", "no level yet")
	Spec.GetChoice = function() return "auto" end
end)

return T.done()
