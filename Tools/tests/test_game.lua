-- Game.lua, the one file that talks to the game: it must never raise, whatever the client has
-- or lacks, and its talent reader must follow the client's own steps. This test loads the real
-- file over a stand-in for the calls it makes (the other tests never load it).
setmetatable(_G, nil)   -- this file is allowed to see the game's globals: here, the ones set below

local function load()
	local handle = assert(io.open(ADDON_ROOT .. "/Game.lua", "r"))
	local source = handle:read("*a")
	handle:close()
	local ns = {}
	assert(loadstring(source, "@Game.lua"))("DaylightGear", ns)
	return ns.Game
end

T.case("with nothing of the game there, every call answers quietly", function()
	local G = load()
	T.eq(G.ItemStats("item:1"), nil, "ItemStats"); T.eq(G.ItemInstant("item:1"), nil, "ItemInstant")
	T.eq(G.ItemInfo("item:1"), nil, "ItemInfo"); T.eq(G.ItemSpeed("item:1"), nil, "ItemSpeed")
	T.eq(G.ItemUnique("item:1"), false, "ItemUnique"); G.RequestItem(1)
	T.eq(G.Class(), nil, "Class"); T.eq(G.Level(), nil, "Level"); T.eq(G.Trees(), nil, "Trees")
	T.eq(G.KnowsSkill(43), nil, "KnowsSkill cannot say"); T.eq(G.KnowsSpell(674), false, "KnowsSpell")
	T.eq(G.WornLink(1), nil, "WornLink"); T.eq(#G.BagLinks(), 0, "BagLinks"); T.eq(G.InCombat(), false, "InCombat")
	T.eq(G.Clock(), 0, "Clock")
end)

T.case("calls that raise are swallowed", function()
	local boom = function() error("boom") end
	C_Item = { GetItemStats = boom, GetItemInfoInstant = boom, GetItemInfo = boom, GetItemUniquenessByID = boom, RequestLoadItemDataByID = boom }
	C_Traits = { GetConfigInfo = boom, GetGroupDisplayInfoByTreeID = boom, GetGroupCurrencyInfo = boom }
	C_SpecializationInfo = { GetActiveSpecGroup = boom, GetCombatConfigIDForSpecGroup = boom }
	C_SkillInfo = { GetSkillLineInfoByID = boom }
	C_SpellBook = { IsSpellKnown = boom }
	C_Container = { GetContainerNumSlots = boom, GetContainerItemLink = boom }
	GetInventoryItemLink, UnitClass, UnitLevel = boom, boom, boom
	local G = load()
	T.eq(G.ItemStats("item:1"), nil, "ItemStats"); T.eq(G.ItemInstant("item:1"), nil, "ItemInstant")
	T.eq(G.ItemInfo("item:1"), nil, "ItemInfo"); T.eq(G.ItemUnique("item:1"), false, "ItemUnique"); G.RequestItem(1)
	T.eq(G.Class(), nil, "Class"); T.eq(G.Level(), nil, "Level"); T.eq(G.Trees(), nil, "Trees")
	T.eq(G.KnowsSkill(43), nil, "KnowsSkill"); T.eq(G.KnowsSpell(674), false, "KnowsSpell")
	T.eq(G.WornLink(1), nil, "WornLink"); T.eq(#G.BagLinks(), 0, "BagLinks")
end)

T.case("items, as the game answers", function()
	C_Item = {
		GetItemStats = function(link) if link == "item:1" then return { ITEM_MOD_STAMINA_SHORT = 3 } end end,
		GetItemInfoInstant = function() return 1, "Armor", "Cloth", "INVTYPE_HEAD", 133, 4, 1 end,
		GetItemInfo = function(link)
			if link ~= "item:1" then return nil end
			return "Hat", "|Hitem:1|h[Hat]|h", 2, 20, 15, "Armor", "Cloth", 1, "INVTYPE_HEAD", 133, 250, 4, 1
		end,
		GetItemUniquenessByID = function() return true end,
	}
	local G = load()
	T.eq(G.ItemStats("item:1").ITEM_MOD_STAMINA_SHORT, 3, "the stat table"); T.eq(G.ItemStats("item:2"), nil, "nothing yet")
	local loc, class, sub = G.ItemInstant("item:1")
	T.eq(loc, "INVTYPE_HEAD", "equipLoc"); T.eq(class, 4, "classID"); T.eq(sub, 1, "subclassID")
	local name, quality, minLevel, sell = G.ItemInfo("item:1")
	T.eq(name, "Hat", "name"); T.eq(quality, 2, "quality"); T.eq(minLevel, 15, "minLevel"); T.eq(sell, 250, "sellPrice")
	T.eq(G.ItemInfo("item:2"), nil, "not cached"); T.eq(G.ItemUnique("item:1"), true, "unique")
end)

T.case("talent trees: the client's own steps, matched by ID and sorted left to right", function()
	local asked = {}
	C_SpecializationInfo = {
		GetActiveSpecGroup = function() return 2 end,
		GetCombatConfigIDForSpecGroup = function(group) asked.group = group return 777 end,
	}
	C_Traits = {
		GetConfigInfo = function(id) asked.config = id return { treeIDs = { 55 } } end,
		GetGroupDisplayInfoByTreeID = function(tree)
			asked.tree = tree
			-- out of order on purpose
			return { { groupID = 13, orderIndex = 2, displayName = "Protection" }, { groupID = 11, orderIndex = 0, displayName = "Arms" },
				{ groupID = 12, orderIndex = 1, displayName = "Fury" } }
		end,
		GetGroupCurrencyInfo = function(config, ids)
			asked.ids = table.concat(ids, ",")
			-- answered in another order, one group missing
			return { { traitNodeGroupID = 12, currencyInfos = { { spent = 31 } } }, { traitNodeGroupID = 11, currencyInfos = { { spent = 20 } } } }
		end,
	}
	local G = load()
	local t = G.Trees()
	T.eq(asked.group, 2, "the active build's config"); T.eq(asked.config, 777, "its config info"); T.eq(asked.tree, 55, "its first tree")
	T.eq(asked.ids, "13,11,12", "every group asked in one call")
	T.eq(#t, 3, "three trees"); T.eq(t[1].name, "Arms", "leftmost first"); T.eq(t[2].name, "Fury", "then"); T.eq(t[3].name, "Protection", "last")
	T.eq(t[1].spent, 20, "points by group ID"); T.eq(t[2].spent, 31, "points by group ID"); T.eq(t[3].spent, 0, "a group with no answer reads 0")
	C_SpecializationInfo.GetCombatConfigIDForSpecGroup = function() return nil end
	T.eq(load().Trees(), nil, "no config yet: nil, not an error")
	C_SpecializationInfo.GetCombatConfigIDForSpecGroup = function() return 777 end
	C_Traits.GetGroupDisplayInfoByTreeID = function() return {} end
	T.eq(load().Trees(), nil, "no groups: nil")
end)

T.case("class, level, skills, spells, worn and carried", function()
	UnitClass = function() return "Krieger", "WARRIOR", 1 end
	UnitLevel = function() return 42 end
	C_SkillInfo = { GetSkillLineInfoByID = function(id) if id == 43 then return { skillID = 43, rank = 200 } end end }
	C_SpellBook = { IsSpellKnown = function(id) return id == 674 end }
	GetInventoryItemLink = function(unit, slot) if unit == "player" and slot == 16 then return "item:9" end end
	C_Container = {
		GetContainerNumSlots = function(bag) return bag == 0 and 3 or (bag == 2 and 1 or 0) end,
		GetContainerItemLink = function(bag, slot) if slot ~= 2 then return "item:" .. bag .. slot end end,
	}
	NUM_BAG_SLOTS = 4
	InCombatLockdown = function() return true end
	debugprofilestop = function() return 12.5 end
	local G = load()
	T.eq(G.Class(), "WARRIOR", "the class token, not the shown name"); T.eq(G.Level(), 42, "level")
	T.eq(G.KnowsSkill(43), true, "a skill the character has"); T.eq(G.KnowsSkill(54), false, "one it has not")
	T.eq(G.KnowsSpell(674), true, "a known spell"); T.eq(G.KnowsSpell(1), false, "an unknown one")
	T.eq(G.WornLink(16), "item:9", "worn"); T.eq(G.WornLink(1), nil, "an empty slot")
	T.eq(table.concat(G.BagLinks(), " "), "item:01 item:03 item:21", "every bag, empty slots skipped")
	local into = { "kept" }
	T.eq(#G.BagLinks(into), 4, "appends to the table given")
	T.eq(G.InCombat(), true, "in combat"); T.eq(G.Clock(), 12.5, "clock")
	UnitLevel = function() return 0 end
	T.eq(load().Level(), nil, "a level of 0 is 'not known yet'")
end)

T.case("a secret value is never used", function()
	local SECRET = {}
	issecretvalue = function(v) return v == SECRET end
	UnitClass = function() return "x", SECRET, 1 end
	UnitLevel = function() return SECRET end
	GetInventoryItemLink = function() return SECRET end
	C_SpellBook = { IsSpellKnown = function() return SECRET end }
	C_Item = { GetItemInfo = function() return SECRET end, GetItemUniquenessByID = function() return SECRET end }
	local G = load()
	T.eq(G.Class(), nil, "class"); T.eq(G.Level(), nil, "level"); T.eq(G.WornLink(1), nil, "worn link")
	T.eq(G.KnowsSpell(1), false, "spell"); T.eq(G.ItemInfo("item:1"), nil, "item info"); T.eq(G.ItemUnique("item:1"), false, "unique")
end)

T.case("a stat table holding anything unreadable is 'not there yet' (the audit's L1)", function()
	local SECRET = {}
	issecretvalue = function(v) return v == SECRET end
	C_Item = {
		GetItemStats = function(link)
			if link == "item:1" then return { ITEM_MOD_STAMINA_SHORT = 3, ITEM_MOD_STRENGTH_SHORT = SECRET } end
			if link == "item:2" then return { [SECRET] = 3 } end
			return { ITEM_MOD_STAMINA_SHORT = 3 }
		end,
		GetItemInfo = function() return "Hat", "link", SECRET, 20, SECRET, "Armor", "Cloth", 1, "INVTYPE_HEAD", 133, SECRET, 4, 1 end,
	}
	C_Container = { GetContainerNumSlots = function() return SECRET end, GetContainerItemLink = function() return "item:5" end }
	local G = load()
	T.eq(G.ItemStats("item:1"), nil, "a secret value"); T.eq(G.ItemStats("item:2"), nil, "a secret key")
	T.eq(G.ItemStats("item:3").ITEM_MOD_STAMINA_SHORT, 3, "a plain table passes")
	local name, quality, minLevel, sell = G.ItemInfo("item:1")
	T.eq(name, "Hat", "the name"); T.eq(quality, nil, "quality"); T.eq(minLevel, nil, "level"); T.eq(sell, nil, "price: none is used")
	T.eq(#G.BagLinks(), 0, "a bag whose size cannot be read is not walked")
	issecretvalue = nil
end)

T.case("effect lines are counted by their type, never by their text", function()
	Enum = { TooltipDataLineType = { ItemSpellTriggerOnUse = 44, ItemSpellTriggerOnEquip = 45, ItemSpellTriggerOnProc = 46, ItemName = 22 } }
	local asked
	C_TooltipInfo = { GetHyperlink = function(link)
		asked = link
		if link == "item:9" then return nil end
		return { lines = { { type = 22, leftText = "Equip: not this one" }, { type = 45, leftText = "x" }, { type = 45 }, { type = 44 },
			{ type = 46 }, { type = 46 }, { type = 46 }, { leftText = "no type" }, "junk" } }
	end }
	local G = load()
	local equip, use, proc = G.ItemEffects("item:1")
	T.eq(asked, "item:1", "the link is asked for as tooltip data")
	T.eq(table.concat(G.ItemEffectFields("item:1"), ","), "leftText,type", "debug can name the fields an effect line carries")
	T.eq(G.ItemEffectFields("item:9"), nil, "or nothing")
	T.eq(equip, 2, "equip lines"); T.eq(use, 1, "use lines"); T.eq(proc, 3, "proc lines")
	T.eq(G.ItemEffects("item:9"), nil, "no tooltip data: cannot say")
	Enum.TooltipDataLineType.ItemSpellTriggerOnProc = nil
	T.eq(load().ItemEffects("item:1"), nil, "a client without the line types: cannot say")
	Enum = nil
	T.eq(load().ItemEffects("item:1"), nil, "no enum at all")
	C_TooltipInfo = { GetHyperlink = function() error("boom") end }
	Enum = { TooltipDataLineType = { ItemSpellTriggerOnUse = 44, ItemSpellTriggerOnEquip = 45, ItemSpellTriggerOnProc = 46 } }
	T.eq(load().ItemEffects("item:1"), nil, "a call that raises")
end)

T.case("who the character is when the realm has no name", function()
	UnitGUID = function() return "Player-4407-00ABCDEF" end
	UnitName = function() return "Tester" end
	GetRealmName = function() return "" end
	UnitFactionGroup = function() return "Horde", "Horde" end
	GetRealmID = nil
	local G = load()
	T.eq(G.Guid(), "Player-4407-00ABCDEF", "the GUID"); T.eq(G.Name(), "Tester", "the name")
	T.eq(G.Realm(), nil, "an empty realm name is no name"); T.eq(G.Faction(), "Horde", "the faction")
	T.eq(G.RealmID(), 4407, "the realm's number is the GUID's middle part")
	GetRealmID = function() return 0 end
	T.eq(load().RealmID(), 4407, "a realm number of 0 from the game is not one")
	GetRealmID = function() return 77 end
	T.eq(load().RealmID(), 77, "the game's own number when it gives one")
	GetRealmName = function() return "Some Realm" end
	T.eq(load().Realm(), "Some Realm", "a name when there is one")
	UnitGUID = function() return nil end
	GetRealmID = nil
	G = load()
	T.eq(G.Guid(), nil, "no GUID yet"); T.eq(G.RealmID(), nil, "and no number")
	UnitGUID = function() error("boom") end
	T.eq(load().Guid(), nil, "a call that raises")
end)

T.case("the clock is one nobody else can reset", function()
	GetTimePreciseSec = function() return 12.5 end
	debugprofilestop = function() return 3 end
	T.eq(load().Clock(), 12500, "milliseconds from the precise clock (the audit's L20)")
	GetTimePreciseSec = nil
	T.eq(load().Clock(), 3, "the profiling timer only as a stand-by")
end)

T.case("whether the game has an item, asked without making it fetch the item", function()
	local asked
	C_Item = { IsItemDataCachedByID = function(what) asked = what return what == "item:1" end,
		GetItemInfo = function() error("must not be called to learn whether an item is cached") end }
	local G = load()
	T.eq(G.ItemCached("item:1"), true, "cached"); T.eq(asked, "item:1", "asked by the link")
	T.eq(G.ItemCached("item:2"), false, "not cached")
	C_Item.IsItemDataCachedByID = function() error("boom") end
	T.eq(load().ItemCached("item:1"), nil, "a call that raises: cannot say")
	C_Item.IsItemDataCachedByID = function() return "yes" end
	T.eq(load().ItemCached("item:1"), nil, "an answer that is no yes or no: cannot say")
	C_Item = {}
	T.eq(load().ItemCached("item:1"), nil, "a client without the call: cannot say")
	GetTime = function() return 123.5 end
	T.eq(load().Time(), 123.5, "the frame's time"); GetTime = nil
	T.eq(load().Time(), 0, "or 0 without it")
end)

return T.done()
