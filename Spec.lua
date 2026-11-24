-- Glowey's Gear: who the player is for scoring: class, spec and level, and the weights for them.
--
--   Spec.Load(data)                       -> problems (a list of sentences; empty when all is well)
--   Spec.HasClass(class)                  -> boolean
--   Spec.List(class)                      -> { "ARMS", "FURY", ... } in picker order (may be empty)
--   Spec.Info(class, key)                 -> the spec's table from the data, or nil
--   Spec.Detect(class, trees, last)       -> key, how      how: "talents" | "default" | "last"
--   Spec.Resolve(class, choice, trees, last) -> key, how   how also: "chosen"; nil when no weights
--   Spec.Weights(class, key, level)       -> { STR = 1, ... } | nil   (Glowey's recommendation)
--   Spec.Effective(class, key, level)     -> weights, custom count    (the player's own on top)
--   Spec.Touched()                        -> the player's own weights changed: build again
--   Spec.Current()                        -> who | nil, why
--        who = { class, spec, level, weights, how, custom };  why: "noclass" | "noweights" | "nolevel"
--
-- The data is Data/Weights.lua (ns.WeightData), a pure table whose shape is the contract in
-- design/data-format.md. This file checks it (a broken spec is left out, never an error) and
-- never changes it.
--
-- How a spec is told from talents (design/data-format.md, section 4): the client keeps classic's
-- three trees, read by ns.Game.Trees(); the tree with the most points is the spec.

local _, ns = ...

local Spec = {}
ns.Spec = Spec

local CLASSES = {
	WARRIOR = true, PALADIN = true, HUNTER = true, ROGUE = true, PRIEST = true,
	SHAMAN = true, MAGE = true, WARLOCK = true, DRUID = true,
}
Spec.CLASSES = CLASSES

local ROLES = { melee = true, ranged = true, caster = true, healer = true, tank = true }
local CONFIDENCE = { low = true, medium = true, high = true }
local MAX_LEVEL = 60
Spec.MAX_LEVEL = MAX_LEVEL

local data = {}          -- class -> { default, order = { keys }, specs = { key -> spec } } (checked)
local merged = {}        -- "CLASS:SPEC:level" -> weights for that level
local anchored = {}      -- spec -> its level anchors (see Spec.Weights)

local NONE = {}

local function finite(n)
	return type(n) == "number" and n == n and n ~= math.huge and n ~= -math.huge
end

-- A weights table with only known keys and finite numbers, or nil and what is wrong.
local function checkWeights(w, where)
	if type(w) ~= "table" then return nil, where .. " is not a table" end
	for key, value in pairs(w) do
		if not ns.Stats.KEYS[key] then return nil, where .. " has an unknown stat key: " .. tostring(key) end
		if not finite(value) then return nil, where .. "." .. key .. " is not a number" end
	end
	return w
end

local function checkSpec(class, key, s)
	local at = class .. "." .. tostring(key)
	if type(key) ~= "string" or not key:match("^[A-Z_]+$") then return at .. ": the spec key must be upper-case letters and _" end
	if type(s) ~= "table" then return at .. " is not a table" end
	if s.tab ~= 1 and s.tab ~= 2 and s.tab ~= 3 then return at .. ": tab must be 1, 2 or 3" end
	if s.role ~= nil and not ROLES[s.role] then return at .. ": unknown role" end
	if s.source ~= "wowsims" and s.source ~= "authored" then return at .. ": source must be \"wowsims\" or \"authored\"" end
	if s.source == "wowsims" and (type(s.sourcePath) ~= "string" or type(s.sourceCommit) ~= "string") then
		return at .. ": a wowsims spec needs sourcePath and sourceCommit"
	end
	if not CONFIDENCE[s.confidence] then return at .. ": confidence must be low, medium or high" end
	local _, bad = checkWeights(s.weights, at .. ".weights")
	if bad then return bad end
	if s.brackets ~= nil then
		if type(s.brackets) ~= "table" then return at .. ".brackets is not a list" end
		local before = 0
		for i, b in ipairs(s.brackets) do
			if type(b) ~= "table" or type(b.upTo) ~= "number" or b.upTo <= before then
				return at .. ".brackets[" .. i .. "]: upTo must rise from one bracket to the next"
			end
			before = b.upTo
			local _, wrong = checkWeights(b.weights, at .. ".brackets[" .. i .. "].weights")
			if wrong then return wrong end
		end
	end
	return nil
end

-- Takes the data in. Returns what was left out and why, for the debug command and the tests.
function Spec.Load(raw)
	data, merged, anchored = {}, {}, {}
	Spec.Touched()
	local problems = {}
	if type(raw) ~= "table" then return problems end
	for class, c in pairs(raw) do
		if CLASSES[class] and type(c) == "table" and type(c.specs) == "table" and type(c.order) == "table" then
			local specs, order = {}, {}
			for _, key in ipairs(c.order) do
				local s = c.specs[key]
				local bad = (s == nil and (class .. "." .. tostring(key) .. " is in order but not in specs"))
					or checkSpec(class, key, s)
				if bad then
					problems[#problems + 1] = bad
				elseif not specs[key] then
					specs[key] = s
					order[#order + 1] = key
				end
			end
			if #order > 0 then
				local default = c.default
				if not specs[default] then
					if default ~= nil then problems[#problems + 1] = class .. ": default is not a listed spec" end
					default = order[1]
				end
				data[class] = { default = default, order = order, specs = specs }
			end
		elseif class ~= "format" and not CLASSES[class] then
			problems[#problems + 1] = "unknown class key: " .. tostring(class)
		elseif CLASSES[class] then
			problems[#problems + 1] = class .. " needs order and specs"
		end
	end
	return problems
end

function Spec.HasClass(class) return data[class] ~= nil end

function Spec.List(class)
	return data[class] and data[class].order or NONE
end

function Spec.Info(class, key)
	local c = data[class]
	return c and c.specs[key] or nil
end

-- The spec Auto picks for a talent tree position: the first in order on that tab that is not
-- marked manual.
local function forTab(c, tab)
	for _, key in ipairs(c.order) do
		local s = c.specs[key]
		if s.tab == tab and not s.manual then return key end
	end
	return nil
end

-- The spec from points spent.
--   * The tree with the most points wins.
--   * A tie stays with the tree of the last answer when that tree is one of the tied ones, so
--     the answer does not flip back and forth while points are spent evenly; else the leftmost.
--   * No points anywhere (below level 10, or after a reset): the class's default spec.
--   * No tree data yet (the first moments after login): the last answer, else the default.
function Spec.Detect(class, trees, last)
	local c = data[class]
	if not c then return nil end
	if last ~= nil and not c.specs[last] then last = nil end
	if type(trees) ~= "table" or #trees == 0 then
		if last then return last, "last" end
		return c.default, "default"
	end
	local most = 0
	for i = 1, math.min(#trees, 3) do
		local spent = tonumber(trees[i].spent) or 0
		if spent > most then most = spent end
	end
	if most <= 0 then return c.default, "default" end
	local lastTab = last and c.specs[last].tab
	local pick
	for i = 1, math.min(#trees, 3) do
		if (tonumber(trees[i].spent) or 0) == most then
			if i == lastTab then
				pick = i
				break
			end
			pick = pick or i
		end
	end
	-- (Staying on a tied tree keeps the very spec the player had there, variant included.)
	if pick == lastTab and last and not c.specs[last].manual then return last, "talents" end
	local key = forTab(c, pick)
	if key then return key, "talents" end
	return c.default, "default"
end

-- The spec in use: the player's own choice when it names a spec of the class, else Detect.
function Spec.Resolve(class, choice, trees, last)
	local c = data[class]
	if not c then return nil end
	if type(choice) == "string" and c.specs[choice] then return choice, "chosen" end
	return Spec.Detect(class, trees, last)
end

-- The weights for a level.
--
-- The spec's base table is the level 60 table. Each bracket is a table for a span of levels
-- (from one past the bracket before it, up to its upTo), written as the keys that differ from
-- the base. A bracket's table is taken to describe the MIDDLE of its span, and between two
-- middles the weights slide in a straight line, key by key:
--
--   levels:   1 ......... 19 | 20 ........ 39 | 40 ........ 59 | 60
--   anchors:       10             29.5             49.5          60 (the base)
--
--   at or below the first anchor: the first bracket as written;
--   between two anchors:          w = A + (B - A) x (level - levelA) / (levelB - levelA);
--   at 60:                        the base as written.
--
-- Why not simply "the first bracket whose upTo covers the level": the tables differ a great deal
-- (a stat can be worth four times as much at 60 as at 59), and a character's advice would flip
-- on the level-up that crosses a bracket's edge. Sliding between the middles removes every such
-- step, including the one at 60, and leaves the data's meaning alone: at the middle of a
-- bracket the weights are exactly what the data says.
--
-- Built once per level and kept; callers must not change the table.
local function whole(s, bracket)
	local w = {}
	for k, v in pairs(s.weights) do w[k] = v end
	for k, v in pairs(bracket.weights) do w[k] = v end
	return w
end

-- { { level = 10, weights = {...} }, ..., { level = 60, weights = base } }
local function anchorsOf(s)
	local list, from = {}, 1
	for _, b in ipairs(s.brackets or NONE) do
		local to = math.min(b.upTo, MAX_LEVEL - 1)
		if to >= from then
			list[#list + 1] = { level = (from + to) / 2, weights = whole(s, b) }
			from = to + 1
		end
	end
	list[#list + 1] = { level = MAX_LEVEL, weights = s.weights }
	return list
end

function Spec.Weights(class, key, level)
	local s = Spec.Info(class, key)
	if not s then return nil end
	level = math.floor(tonumber(level) or MAX_LEVEL)
	if level >= MAX_LEVEL or not s.brackets or #s.brackets == 0 then return s.weights end
	if level < 1 then level = 1 end
	local id = class .. ":" .. key .. ":" .. level
	local w = merged[id]
	if w then return w end

	local anchors = anchored[s]
	if not anchors then
		anchors = anchorsOf(s)
		anchored[s] = anchors
	end
	local below, above
	for i = 1, #anchors do
		if anchors[i].level <= level then below = anchors[i] else above = above or anchors[i] end
	end
	if not below then
		w = anchors[1].weights
	elseif not above then
		w = below.weights
	else
		local t = (level - below.level) / (above.level - below.level)
		w = {}
		for k, v in pairs(below.weights) do w[k] = v + ((above.weights[k] or 0) - v) * t end
		for k, v in pairs(above.weights) do
			if below.weights[k] == nil then w[k] = v * t end
		end
	end
	merged[id] = w
	return w
end

-- ---------------------------------------------------------------------------------------------
-- The player's own weights
-- ---------------------------------------------------------------------------------------------
-- Spec.GetCustom(class, key) gives the player's own weights for a spec: a sparse table of only
-- the stats they set ({ STR = 1.2, HIT = 0 }), or nil. Core.lua points it at GloweyGearDB; left
-- alone there are none. Each number the player set replaces Glowey's recommendation for that
-- stat at EVERY level (a weight set by hand does not slide with the brackets); every stat they
-- did not touch keeps following the shipped data, so a weight correction in a later version
-- still reaches it. A 0 is a real choice ("worth nothing"), not the same as unset.
Spec.GetCustom = function(_class, _key) return nil end

local effective = {}   -- the recommendation's table -> { custom = table, rev = n, w = table, n = count }
local rev = 0

-- The player's weights changed somewhere: the next Effective builds its tables again.
function Spec.Touched()
	rev = rev + 1
	effective = {}
end

-- The weights scoring uses: the recommendation for the level with the player's own on top, and
-- how many of the player's own there are. Kept until Spec.Touched (the same table comes back, so
-- "the weights changed" stays a plain table comparison); callers must not change it.
function Spec.Effective(class, key, level)
	local base = Spec.Weights(class, key, level)
	if not base then return nil, 0 end
	local custom = Spec.GetCustom(class, key)
	if type(custom) ~= "table" or next(custom) == nil then return base, 0 end
	local kept = effective[base]
	if kept and kept.custom == custom and kept.rev == rev then return kept.w, kept.n end
	local w, n = {}, 0
	for k, v in pairs(base) do w[k] = v end
	for k, v in pairs(custom) do
		if ns.Stats.KEYS[k] and finite(v) and v >= 0 then
			w[k] = v
			n = n + 1
		end
	end
	if n == 0 then w = base end
	effective[base] = { custom = custom, rev = rev, w = w, n = n }
	return w, n
end

-- Every stat key a spec's recommendation names, at any level (the level 60 table and every
-- bracket): the stats the weights editor lists.
function Spec.Named(class, key)
	local s = Spec.Info(class, key)
	local out = {}
	if not s then return out end
	for k in pairs(s.weights) do out[k] = true end
	for _, b in ipairs(s.brackets or NONE) do
		for k in pairs(b.weights) do out[k] = true end
	end
	return out
end

-- A spec's name for the player, in English (Core.lua passes ours through the locale table):
-- our own word for a variant, else the game's name of the talent tree, else nil (the caller
-- then shows the key). Second return: true when the word is ours and needs translating.
Spec.VARIANTS = { LEVELING = "Leveling", FERAL_BEAR = "Bear" }
function Spec.Label(class, key, trees)
	local s = Spec.Info(class, key)
	if not s then return nil end
	if Spec.VARIANTS[key] then return Spec.VARIANTS[key], true end
	local tree = type(trees) == "table" and trees[s.tab]
	if tree and type(tree.name) == "string" and tree.name ~= "" then return tree.name, false end
	return nil
end

-- ---------------------------------------------------------------------------------------------
-- The player
-- ---------------------------------------------------------------------------------------------
-- Core.lua sets these three to read and write the character's saved choice; left alone (the
-- tests, or before the saved variables load) the choice is "auto" and nothing is remembered.
Spec.GetChoice = function() return "auto" end
Spec.GetLast = function() return nil end
Spec.SetLast = function(_key) end

function Spec.Current()
	local G = ns.Game
	local class = G.Class()
	if not class then return nil, "noclass" end
	if not data[class] then return nil, "noweights" end
	local level = G.Level()
	if not level then return nil, "nolevel" end
	local last = Spec.GetLast()
	local key, how = Spec.Resolve(class, Spec.GetChoice(), G.Trees(), last)
	if not key then return nil, "noweights" end
	if how == "talents" and key ~= last then Spec.SetLast(key) end
	local weights, custom = Spec.Effective(class, key, level)
	return { class = class, spec = key, level = level, how = how, weights = weights, custom = custom }
end
