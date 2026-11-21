-- The real Data/Weights.lua through the engine: it loads clean, every class and spec scores a
-- sample item at every level without error, and the rules the format page promises hold.
local Spec, Stats, Score, Compare, Rank = NS.Spec, NS.Stats, NS.Score, NS.Compare, NS.Rank

local handle = assert(io.open(ADDON_ROOT .. "/Data/Weights.lua", "r"))
local source = handle:read("*a")
handle:close()
assert(loadstring(source, "@Data/Weights.lua"))("DaylightGear", NS)

local CLASSES = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }
local function trees(a, b, c) return { { name = "One", spent = a }, { name = "Two", spent = b }, { name = "Three", spent = c } } end

T.case("the file is pure data and loads with no problems", function()
	T.check(not source:find("function", 1, true), "no functions in the data file")
	T.eq(NS.WeightData.format, 1, "format 1")
	local problems = Spec.Load(NS.WeightData)
	T.eq(#problems, 0, "no problems: " .. table.concat(problems, " | "))
	for _, class in ipairs(CLASSES) do T.check(Spec.HasClass(class), class .. " has weights") end
end)

T.case("every tree of every class has a spec Auto can pick, and a default", function()
	Spec.Load(NS.WeightData)
	for _, class in ipairs(CLASSES) do
		local picked = {}
		for tab = 1, 3 do
			local t = trees(tab == 1 and 5 or 0, tab == 2 and 5 or 0, tab == 3 and 5 or 0)
			local key, how = Spec.Detect(class, t, nil)
			local info = Spec.Info(class, key)
			T.check(info ~= nil, class .. " tab " .. tab .. " has a spec")
			T.eq(how, "talents", class .. " tab " .. tab .. " is picked from talents")
			T.eq(info and info.tab, tab, class .. " tab " .. tab .. " picks a spec of that tree")
			T.check(info and not info.manual, class .. " tab " .. tab .. " never picks a manual spec")
			T.check(not picked[key], class .. " tab " .. tab .. " picks a spec of its own")
			picked[key] = true
		end
		local key, how = Spec.Detect(class, trees(0, 0, 0), nil)
		T.check(Spec.Info(class, key) ~= nil, class .. " has a default"); T.eq(how, "default", class .. " default")
		T.eq(Spec.Resolve(class, key, trees(9, 0, 0), nil), key, class .. ": the default can also be chosen by hand")
		for _, k in ipairs(Spec.List(class)) do
			local label = Spec.Label(class, k, trees(0, 0, 0))
			T.check(type(label) == "string" and label ~= "", class .. "." .. k .. " has a name to show")
		end
	end
end)

-- One item carrying a point of everything the stat reader can produce.
local RAW = { ITEM_MOD_STRENGTH_SHORT = 1, ITEM_MOD_AGILITY_SHORT = 1, ITEM_MOD_STAMINA_SHORT = 1, ITEM_MOD_INTELLECT_SHORT = 1,
	ITEM_MOD_SPIRIT_SHORT = 1, RESISTANCE0_NAME = 1, ITEM_MOD_ATTACK_POWER_SHORT = 1, ITEM_MOD_SPELL_POWER_SHORT = 1,
	ITEM_MOD_CRIT_RATING_SHORT = 14, ITEM_MOD_HIT_RATING_SHORT = 10, ITEM_MOD_HASTE_RATING_SHORT = 10,
	ITEM_MOD_DODGE_RATING_SHORT = 12, ITEM_MOD_DEFENSE_SKILL_RATING_SHORT = 1, ITEM_MOD_POWER_REGEN0_SHORT = 1,
	ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 1 }

T.case("every spec scores at every level, finite and without a step", function()
	Spec.Load(NS.WeightData)
	local sample = Stats.Normalize(RAW, "INVTYPE_WEAPON")
	local specs = 0
	for _, class in ipairs(CLASSES) do
		for _, key in ipairs(Spec.List(class)) do
			specs = specs + 1
			local at = class .. "." .. key
			local before
			local biggest, span = 0, 0
			for level = 1, 60 do
				local w = Spec.Weights(class, key, level)
				T.check(type(w) == "table", at .. " has weights at " .. level)
				local score = Score.Value(sample, w)
				T.check(score == score and score > 0 and score < math.huge, at .. " scores the sample at " .. level)
				for k, v in pairs(w) do
					if not Stats.KEYS[k] or v ~= v then T.check(false, at .. " bad weight " .. tostring(k) .. " at " .. level) end
				end
				if before then
					local step = math.abs(score - before)
					if step > biggest then biggest = step end
				end
				span = math.max(span, score)
				before = score
			end
			T.check(Spec.Weights(class, key, 60) == Spec.Info(class, key).weights, at .. ": level 60 is the base table")
			-- (No level-up moves the sample's score by more than a sixth of its largest value:
			-- with plain brackets the step at 60 alone was often more than half.)
			T.check(biggest <= span / 6, at .. ": largest one-level step " .. biggest .. " of " .. span)
		end
	end
	T.check(specs >= 27, "at least the 27 trees (" .. specs .. ")")
end)

T.case("hit and crit are filed on one side per spec, as the stat reader expects", function()
	-- Stats.lua gives a plain hit or crit rating to HIT and SPELL_HIT (CRIT and SPELL_CRIT) alike.
	-- A spec that weighted both would count such an item twice.
	Spec.Load(NS.WeightData)
	for _, class in ipairs(CLASSES) do
		for _, key in ipairs(Spec.List(class)) do
			local info = Spec.Info(class, key)
			for level = 1, 60, 59 do
				local w = Spec.Weights(class, key, level)
				local physical = (w.HIT or 0) ~= 0 or (w.CRIT or 0) ~= 0
				local spell = (w.SPELL_HIT or 0) ~= 0 or (w.SPELL_CRIT or 0) ~= 0
				if info.role == "caster" or info.role == "healer" then
					T.check(level < 60 or not physical, class .. "." .. key .. " (" .. info.role .. ") has no HIT/CRIT weight at 60")
				else
					T.check(level < 60 or not spell, class .. "." .. key .. " (" .. tostring(info.role) .. ") has no SPELL_HIT/SPELL_CRIT weight at 60")
				end
			end
		end
	end
end)

T.case("a whole pass with the real weights: compare and rank for each class", function()
	Spec.Load(NS.WeightData)
	for _, class in ipairs(CLASSES) do
		for _, level in ipairs({ 8, 25, 44, 60 }) do
			T.reset()
			WORLD.class, WORLD.level, WORLD.trees = class, level, trees(0, level >= 10 and level - 9 or 0, 0)
			local who = Spec.Current()
			T.check(who ~= nil and who.weights ~= nil, class .. " " .. level .. " has a spec")
			local worn = T.item({ equipLoc = "INVTYPE_NECK", raw = RAW })
			local ctx = Compare.Context(who, { [2] = worn }, {})
			local better = {}
			for k, v in pairs(RAW) do better[k] = v * 2 end
			local job = Rank.Job(ctx)
			job:Add(T.item({ name = "Better", equipLoc = "INVTYPE_NECK", raw = better }), 12345)
			job:Add(T.item({ name = "Empty", equipLoc = "INVTYPE_NECK", raw = {} }), 12345)
			job:Run()
			local view = Rank.Arrange(job.rows, { level = level, maxPrice = 50000, minPct = 3 })
			local list = view.groups.NECK
			T.eq(list and #list, 1, class .. " " .. level .. ": the better neck is listed, the empty one is not")
			T.check(list and list[1].pct and list[1].pct > 0, class .. " " .. level .. ": with a percent")
		end
	end
end)

return T.done()
