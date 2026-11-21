-- Glowey's Gear: stat weights. GENERATED FILE (pure data; see Data/README.md for sources, method and how to regenerate).
-- Shape: design/data-format.md, format 1. Units: percent keys are per 1%, everything else per point.
-- Entries with source = "wowsims" are derived from EP presets of the wowsims/forever simulator,
-- Copyright (c) 2022 wowsims team, MIT License (full text in CREDITS.md), https://github.com/wowsims/forever
-- commit 21377c070b5ea111a9bb5e36eb766193270b0cc7. Entries with source = "authored" and ALL "brackets" tables
-- (levels below 60) are this project's own reasoning, not simulation output.
-- Generated 2026-11-20 by scratch scripts gen.py / extract.py (see Data/README.md).
local _, ns = ...

ns.WeightData = {
	format = 1,

	WARRIOR = {
		default = "LEVELING",
		order = { "ARMS", "FURY", "PROTECTION", "LEVELING" },
		specs = {
			ARMS = {
				tab = 1, role = "melee",
				source = "wowsims", sourcePath = "ui/specs/warrior/dps/presets.ts", sourcePreset = "PreBiSArmsEpWeights",
				sourceCommit = "21377c070b5ea111a9bb5e36eb766193270b0cc7",
				confidence = "high", ref = "STR",
				note = "Pre-BiS Arms preset, divided by its Strength weight. Hit is its value below the 8% cap. Level 60 raid-style sim (pre-raid gear, consumables and raid buffs); brackets below 60 are authored. ADDED: STA 0.15 and HEALTH as an authored survival floor (the sim measures output only).",
				weights = {
					STR = 1, AGI = 0.78, STA = 0.15, HEALTH = 0.015, AP = 0.45, HIT = 21.4, CRIT = 14.2,
					HASTE = 5.41, EXPERTISE = 6.64, ARMOR_PEN = 2.05, MH_DPS = 7.56,
				},
				brackets = {   -- authored, confidence low
					{ upTo = 19, weights = {
						AGI = 0.58, STA = 0.69, SPI = 0.19, ARMOR = 0.034, HEALTH = 0.053, HIT = 1, CRIT = 1.45,
						HASTE = 0.91, EXPERTISE = 0.47, ARMOR_PEN = 0.13, DODGE = 0.42, PARRY = 0.42, BLOCK = 0.11,
						BLOCK_VALUE = 0.085, DEFENSE = 0.085, HP5 = 0.64, MH_DPS = 7.51, OH_DPS = 1.02,
					} },
					{ upTo = 39, weights = {
						AGI = 0.65, STA = 0.45, SPI = 0.1, ARMOR = 0.017, HEALTH = 0.04, HIT = 2.37, CRIT = 3.05,
						HASTE = 1.64, EXPERTISE = 0.94, ARMOR_PEN = 0.34, DODGE = 0.55, PARRY = 0.55, BLOCK = 0.14,
						BLOCK_VALUE = 0.055, DEFENSE = 0.055, HP5 = 0.34, MH_DPS = 7.53, OH_DPS = 0.66,
					} },
					{ upTo = 59, weights = {
						AGI = 0.72, STA = 0.26, SPI = 0.037, ARMOR = 0.005, HEALTH = 0.026, HIT = 5.81, CRIT = 6.82,
						HASTE = 3.03, EXPERTISE = 1.99, ARMOR_PEN = 0.89, DODGE = 0.5, PARRY = 0.5, BLOCK = 0.12,
						BLOCK_VALUE = 0.025, DEFENSE = 0.025, HP5 = 0.12, MH_DPS = 7.54, OH_DPS = 0.3,
					} },
				},
			},
			FURY = {
				tab = 2, role = "melee",
				source = "wowsims", sourcePath = "ui/specs/warrior/dps/presets.ts", sourcePreset = "PreBiSFuryEpWeights",
				sourceCommit = "21377c070b5ea111a9bb5e36eb766193270b0cc7",
				confidence = "high", ref = "STR",
				note = "Pre-BiS Fury preset, divided by its Strength weight. Its low hit weight is dual-wield hit past the 8% special cap. Level 60 raid-style sim (pre-raid gear, consumables and raid buffs); brackets below 60 are authored. ADDED: STA 0.15 and HEALTH as an authored survival floor (the sim measures output only).",
				weights = {
					STR = 1, AGI = 0.77, STA = 0.15, HEALTH = 0.015, AP = 0.45, HIT = 7.68, CRIT = 14.4,
					HASTE = 8, EXPERTISE = 10.7, ARMOR_PEN = 1.77, MH_DPS = 5.72, OH_DPS = 1.21,
				},
				brackets = {   -- authored, confidence low
					{ upTo = 19, weights = {
						AGI = 0.58, STA = 0.69, SPI = 0.19, ARMOR = 0.034, HEALTH = 0.053, HIT = 0.91, CRIT = 1.45,
						HASTE = 0.95, EXPERTISE = 0.5, ARMOR_PEN = 0.13, DODGE = 0.42, PARRY = 0.42, BLOCK = 0.11,
						BLOCK_VALUE = 0.085, DEFENSE = 0.085, HP5 = 0.64, MH_DPS = 7.23, OH_DPS = 1.2,
					} },
					{ upTo = 39, weights = {
						AGI = 0.65, STA = 0.45, SPI = 0.1, ARMOR = 0.017, HEALTH = 0.04, HIT = 1.56, CRIT = 3.07,
						HASTE = 1.89, EXPERTISE = 1.18, ARMOR_PEN = 0.31, DODGE = 0.55, PARRY = 0.55, BLOCK = 0.14,
						BLOCK_VALUE = 0.055, DEFENSE = 0.055, HP5 = 0.34, MH_DPS = 6.7, OH_DPS = 1.2,
					} },
					{ upTo = 59, weights = {
						AGI = 0.72, STA = 0.26, SPI = 0.037, ARMOR = 0.005, HEALTH = 0.026, HIT = 2.73, CRIT = 6.89,
						HASTE = 4, EXPERTISE = 2.9, ARMOR_PEN = 0.79, DODGE = 0.5, PARRY = 0.5, BLOCK = 0.12,
						BLOCK_VALUE = 0.025, DEFENSE = 0.025, HP5 = 0.12, MH_DPS = 6.17,
					} },
				},
			},
			PROTECTION = {
				tab = 3, role = "tank",
				source = "wowsims", sourcePath = "ui/specs/warrior/protection/presets.ts", sourcePreset = "PreBiSBalancedEpWeights",
				sourceCommit = "21377c070b5ea111a9bb5e36eb766193270b0cc7",
				confidence = "medium", ref = "STA",
				note = "Pre-BiS Balanced preset (upstream: 0.6 x threat + 1.15 x damage-smoothing weights), divided by its Stamina weight. Hit is its value PAST the cap (near zero): review. HEALTH 0.08 authored. Level 60 raid-style sim (pre-raid gear, consumables and raid buffs); brackets below 60 are authored.",
				weights = {
					STR = 0.54, AGI = 0.57, STA = 1, ARMOR = 0.052, HEALTH = 0.08, AP = 0.23, HIT = 0.35,
					CRIT = 5.23, HASTE = 1.48, EXPERTISE = 20.4, ARMOR_PEN = 0.96, DODGE = 3.03, PARRY = 3.39,
					BLOCK_VALUE = 0.66, DEFENSE = 0.46, MH_DPS = 1.23,
				},
				brackets = {   -- authored, confidence low
					{ upTo = 19, weights = {
						STR = 0.93, AGI = 0.55, STA = 0.81, SPI = 0.19, ARMOR = 0.042, HEALTH = 0.063, AP = 0.42,
						HIT = 0.85, CRIT = 1.34, HASTE = 0.87, EXPERTISE = 0.57, ARMOR_PEN = 0.12, DODGE = 0.46,
						PARRY = 0.47, BLOCK = 0.11, BLOCK_VALUE = 0.18, DEFENSE = 0.091, HP5 = 0.64, MH_DPS = 6.56,
						OH_DPS = 1.02,
					} },
					{ upTo = 39, weights = {
						STR = 0.79, AGI = 0.56, STA = 0.83, SPI = 0.1, ARMOR = 0.04, HEALTH = 0.069, AP = 0.35,
						HIT = 1.12, CRIT = 2.17, HASTE = 1.25, EXPERTISE = 1.76, ARMOR_PEN = 0.23, DODGE = 0.85,
						PARRY = 0.89, BLOCK = 0.14, BLOCK_VALUE = 0.35, DEFENSE = 0.1, HP5 = 0.34, MH_DPS = 4.68,
						OH_DPS = 0.66,
					} },
					{ upTo = 59, weights = {
						STR = 0.65, STA = 0.9, SPI = 0.037, ARMOR = 0.044, HEALTH = 0.075, AP = 0.29, HIT = 1.08,
						CRIT = 3.46, HASTE = 1.55, EXPERTISE = 5.1, ARMOR_PEN = 0.48, DODGE = 1.63, PARRY = 1.77,
						BLOCK = 0.12, BLOCK_VALUE = 0.52, DEFENSE = 0.2, HP5 = 0.12, MH_DPS = 2.8, OH_DPS = 0.3,
					} },
				},
			},
			-- Authored generic leveling profile: used while no talent point is spent, and blended into every spec below 60.
			LEVELING = {
				tab = 1, role = "melee", manual = true,
				source = "authored",
				confidence = "low", ref = "STR",
				note = "Authored generic leveling profile: used while no talent point is spent, and blended into every spec below 60.",
				weights = {
					STR = 1, AGI = 0.55, STA = 0.6, SPI = 0.15, ARMOR = 0.02, HEALTH = 0.06, AP = 0.45, HIT = 8,
					CRIT = 12, HASTE = 8, EXPERTISE = 4, ARMOR_PEN = 1, DODGE = 4, PARRY = 4, BLOCK = 1,
					BLOCK_VALUE = 0.1, DEFENSE = 0.1, HP5 = 0.5, MH_DPS = 7.5, OH_DPS = 1.2,
				},
				brackets = {   -- authored, confidence low
					{ upTo = 19, weights = {
						STA = 0.78, SPI = 0.22, ARMOR = 0.04, HIT = 1, CRIT = 1.5, HASTE = 1, EXPERTISE = 0.5,
						ARMOR_PEN = 0.12, DODGE = 0.5, PARRY = 0.5, BLOCK = 0.12, HP5 = 0.75,
					} },
					{ upTo = 39, weights = {
						STA = 0.69, SPI = 0.19, ARMOR = 0.03, HIT = 2, CRIT = 3, HASTE = 2, EXPERTISE = 1,
						ARMOR_PEN = 0.25, DODGE = 1, PARRY = 1, BLOCK = 0.25, HP5 = 0.62,
					} },
					{ upTo = 59, weights = {
						HIT = 4, CRIT = 6, HASTE = 4, EXPERTISE = 2, ARMOR_PEN = 0.5, DODGE = 2, PARRY = 2,
						BLOCK = 0.5,
					} },
				},
			},
		},
	},

	PALADIN = {
		default = "LEVELING",
		order = { "HOLY", "PROTECTION", "RETRIBUTION", "LEVELING" },
		specs = {
			-- Authored: healing = 1; regen stats anchored on upstream priest healer presets; crit raised (crit heals refund mana), Spirit near zero (no Spirit talents).
			HOLY = {
				tab = 1, role = "healer",
				source = "authored",
				confidence = "low", ref = "HEAL",
				note = "Authored: healing = 1; regen stats anchored on upstream priest healer presets; crit raised (crit heals refund mana), Spirit near zero (no Spirit talents).",
				weights = {
					STA = 0.05, INT = 0.4, SPI = 0.05, HEALTH = 0.005, MANA = 0.02, HEAL = 1, SPELL_CRIT = 8.5,
					HASTE = 3, MP5 = 0.6,
				},
				brackets = {   -- authored, confidence low
					{ upTo = 19, weights = {
						STR = 0.85, AGI = 0.38, STA = 0.67, INT = 0.37, SPI = 0.32, ARMOR = 0.034, HEALTH = 0.051,
						MANA = 0.023, AP = 0.38, SPELL_DMG = 0.26, HEAL = 0.11, SPELL_DMG_HOLY = 0.21, HIT = 0.85,
						CRIT = 1.06, SPELL_CRIT = 0.046, HASTE = 0.87, EXPERTISE = 0.42, DODGE = 0.42, PARRY = 0.42,
						BLOCK = 0.11, BLOCK_VALUE = 0.085, DEFENSE = 0.085, MP5 = 0.72, HP5 = 0.51, MH_DPS = 5.52,
					} },
					{ upTo = 39, weights = {
						STR = 0.55, AGI = 0.25, STA = 0.39, INT = 0.3, SPI = 0.18, ARMOR = 0.017, HEALTH = 0.034,
						MANA = 0.018, AP = 0.25, SPELL_DMG = 0.17, HEAL = 0.23, SPELL_DMG_HOLY = 0.14, HIT = 1.1,
						CRIT = 1.38, SPELL_CRIT = 0.38, HASTE = 1.23, EXPERTISE = 0.55, DODGE = 0.55, PARRY = 0.55,
						BLOCK = 0.14, BLOCK_VALUE = 0.055, DEFENSE = 0.055, MP5 = 0.56, HP5 = 0.28, MH_DPS = 3.58,
					} },
					{ upTo = 59, weights = {
						STR = 0.25, AGI = 0.11, STA = 0.17, INT = 0.24, SPI = 0.079, ARMOR = 0.005, HEALTH = 0.017,
						MANA = 0.013, AP = 0.11, SPELL_DMG = 0.075, HEAL = 0.35, SPELL_DMG_HOLY = 0.062, HIT = 1,
						CRIT = 1.25, SPELL_CRIT = 1.43, HASTE = 1.51, EXPERTISE = 0.5, DODGE = 0.5, PARRY = 0.5,
						BLOCK = 0.12, BLOCK_VALUE = 0.025, DEFENSE = 0.025, MP5 = 0.4, HP5 = 0.1, MH_DPS = 1.62,
					} },
				},
			},
			-- Authored: mitigation stats copied in ratio from the upstream Protection Warrior preset (same enemy attack table); threat part moved from Strength/weapon to spell damage and mana.
			PROTECTION = {
				tab = 2, role = "tank",
				source = "authored",
				confidence = "low", ref = "STA",
				note = "Authored: mitigation stats copied in ratio from the upstream Protection Warrior preset (same enemy attack table); threat part moved from Strength/weapon to spell damage and mana.",
				weights = {
					STR = 0.4, AGI = 0.5, STA = 1, INT = 0.15, ARMOR = 0.05, HEALTH = 0.08, MANA = 0.008,
					AP = 0.15, SPELL_DMG = 0.3, SPELL_DMG_HOLY = 0.25, HIT = 1, CRIT = 3, HASTE = 1.5,
					EXPERTISE = 15, DODGE = 3, PARRY = 3.4, BLOCK = 0.5, BLOCK_VALUE = 0.5, DEFENSE = 0.46,
					MP5 = 0.2, MH_DPS = 0.8,
				},
				brackets = {   -- authored, confidence low
					{ upTo = 19, weights = {
						STR = 0.91, AGI = 0.46, STA = 0.81, INT = 0.36, SPI = 0.32, ARMOR = 0.042, HEALTH = 0.063,
						MANA = 0.022, AP = 0.41, HEAL = 0.043, HIT = 0.86, CRIT = 1.1, HASTE = 0.87,
						EXPERTISE = 0.53, DODGE = 0.46, PARRY = 0.47, BLOCK = 0.11, BLOCK_VALUE = 0.16,
						DEFENSE = 0.091, MP5 = 0.71, HP5 = 0.51, MH_DPS = 5.64,
					} },
					{ upTo = 39, weights = {
						STR = 0.73, AGI = 0.47, STA = 0.83, INT = 0.29, SPI = 0.17, ARMOR = 0.039, HEALTH = 0.069,
						MANA = 0.017, AP = 0.32, HEAL = 0.028, HIT = 1.16, CRIT = 1.67, HASTE = 1.25,
						EXPERTISE = 1.44, DODGE = 0.85, PARRY = 0.89, BLOCK = 0.19, BLOCK_VALUE = 0.28,
						DEFENSE = 0.1, MP5 = 0.53, HP5 = 0.28, MH_DPS = 3.94,
					} },
					{ upTo = 59, weights = {
						STR = 0.55, AGI = 0.49, STA = 0.9, INT = 0.21, SPI = 0.062, ARMOR = 0.043, HEALTH = 0.075,
						MANA = 0.012, AP = 0.22, HEAL = 0.013, HIT = 1.23, CRIT = 2.38, HASTE = 1.56,
						EXPERTISE = 3.88, DODGE = 1.62, PARRY = 1.77, BLOCK = 0.31, BLOCK_VALUE = 0.4, DEFENSE = 0.2,
						MP5 = 0.35, HP5 = 0.1, MH_DPS = 2.23,
					} },
				},
			},
			RETRIBUTION = {
				tab = 3, role = "melee",
				source = "wowsims", sourcePath = "ui/specs/paladin/retribution/presets.ts", sourcePreset = "UnsealedWrathEpWeights",
				sourceCommit = "21377c070b5ea111a9bb5e36eb766193270b0cc7",
				confidence = "medium", ref = "STR",
				note = "Unsealed Wrath preset (the upstream default), divided by its Strength weight. CHANGED: haste 22.87 per rating upstream replaced by the Holy Shock preset value 4.06. Hit and crit rating weights are filed under HIT/CRIT only (they also move spells). Level 60 raid-style sim (pre-raid gear, consumables and raid buffs); brackets below 60 are authored. ADDED: STA 0.15 and HEALTH as an authored survival floor (the sim measures output only).",
				weights = {
					STR = 1, AGI = 0.93, STA = 0.15, INT = 0.86, HEALTH = 0.015, AP = 0.42, SPELL_DMG = 0.98,
					SPELL_DMG_HOLY = 0.81, HIT = 28.5, CRIT = 18, HASTE = 16.9, EXPERTISE = 21.2, ARMOR_PEN = 1,
					MP5 = 0.096, MH_DPS = 5.77,
				},
				brackets = {   -- authored, confidence low
					{ upTo = 19, weights = {
						AGI = 0.52, STA = 0.69, INT = 0.47, SPI = 0.32, ARMOR = 0.034, HEALTH = 0.053, MANA = 0.021,
						AP = 0.45, SPELL_DMG = 0.4, HEAL = 0.043, SPELL_DMG_HOLY = 0.33, HIT = 1.05, CRIT = 1.28,
						HASTE = 1.05, EXPERTISE = 0.58, ARMOR_PEN = 0.012, DODGE = 0.42, PARRY = 0.42, BLOCK = 0.11,
						BLOCK_VALUE = 0.085, DEFENSE = 0.085, MP5 = 0.69, HP5 = 0.51, MH_DPS = 6.39,
					} },
					{ upTo = 39, weights = {
						AGI = 0.67, STA = 0.45, INT = 0.61, SPI = 0.17, ARMOR = 0.017, HEALTH = 0.04, MANA = 0.014,
						AP = 0.44, SPELL_DMG = 0.61, HEAL = 0.028, SPELL_DMG_HOLY = 0.5, HIT = 2.79, CRIT = 3.15,
						HASTE = 2.77, EXPERTISE = 1.81, ARMOR_PEN = 0.099, DODGE = 0.55, PARRY = 0.55, BLOCK = 0.14,
						BLOCK_VALUE = 0.055, DEFENSE = 0.055, MP5 = 0.48, HP5 = 0.28, MH_DPS = 6.17,
					} },
					{ upTo = 59, weights = {
						AGI = 0.81, STA = 0.26, INT = 0.74, SPI = 0.062, ARMOR = 0.005, HEALTH = 0.026, MANA = 0.006,
						SPELL_DMG = 0.81, HEAL = 0.013, SPELL_DMG_HOLY = 0.67, HIT = 7.4, CRIT = 7.99, HASTE = 7.34,
						EXPERTISE = 5.28, ARMOR_PEN = 0.38, DODGE = 0.5, PARRY = 0.5, BLOCK = 0.12,
						BLOCK_VALUE = 0.025, DEFENSE = 0.025, MP5 = 0.27, HP5 = 0.1, MH_DPS = 5.95,
					} },
				},
			},
			-- Authored generic leveling profile: used while no talent point is spent, and blended into every spec below 60.
			LEVELING = {
				tab = 3, role = "melee", manual = true,
				source = "authored",
				confidence = "low", ref = "STR",
				note = "Authored generic leveling profile: used while no talent point is spent, and blended into every spec below 60.",
				weights = {
					STR = 1, AGI = 0.45, STA = 0.6, INT = 0.4, SPI = 0.25, ARMOR = 0.02, HEALTH = 0.06,
					MANA = 0.025, AP = 0.45, SPELL_DMG = 0.3, HEAL = 0.05, SPELL_DMG_HOLY = 0.25, HIT = 8,
					CRIT = 10, HASTE = 8, EXPERTISE = 4, DODGE = 4, PARRY = 4, BLOCK = 1, BLOCK_VALUE = 0.1,
					DEFENSE = 0.1, MP5 = 0.8, HP5 = 0.4, MH_DPS = 6.5,
				},
				brackets = {   -- authored, confidence low
					{ upTo = 19, weights = {
						STA = 0.78, SPI = 0.38, ARMOR = 0.04, HIT = 1, CRIT = 1.25, HASTE = 1, EXPERTISE = 0.5,
						DODGE = 0.5, PARRY = 0.5, BLOCK = 0.12, HP5 = 0.6,
					} },
					{ upTo = 39, weights = {
						STA = 0.69, SPI = 0.31, ARMOR = 0.03, HIT = 2, CRIT = 2.5, HASTE = 2, EXPERTISE = 1,
						DODGE = 1, PARRY = 1, BLOCK = 0.25, HP5 = 0.5,
					} },
					{ upTo = 59, weights = {
						HIT = 4, CRIT = 5, HASTE = 4, EXPERTISE = 2, DODGE = 2, PARRY = 2, BLOCK = 0.5,
					} },
				},
			},
		},
	},

	HUNTER = {
		default = "LEVELING",
		order = { "BEAST_MASTERY", "MARKSMANSHIP", "SURVIVAL", "LEVELING" },
		specs = {
			BEAST_MASTERY = {
				tab = 1, role = "ranged",
				source = "wowsims", sourcePath = "ui/specs/hunter/dps/presets.ts", sourcePreset = "TurretEpWeights",
				sourceCommit = "21377c070b5ea111a9bb5e36eb766193270b0cc7",
				confidence = "medium", ref = "AGI",
				note = "Turret preset, measured upstream on the Marksmanship build; the Beast Mastery build uses the same gear set upstream. Pet scaling may differ. Level 60 raid-style sim (pre-raid gear, consumables and raid buffs); brackets below 60 are authored. ADDED: STA 0.15 and HEALTH as an authored survival floor (the sim measures output only).",
				weights = {
					AGI = 1, STA = 0.15, INT = 0.38, HEALTH = 0.015, RAP = 0.34, HIT = 11.4, CRIT = 11.8,
					HASTE = 8, MP5 = 0.04, RANGED_DPS = 2.87,
				},
				brackets = {   -- authored, confidence low
					{ upTo = 19, weights = {
						STR = 0.043, STA = 0.57, INT = 0.31, SPI = 0.26, ARMOR = 0.025, HEALTH = 0.045, MANA = 0.017,
						AP = 0.085, RAP = 0.39, HIT = 0.72, CRIT = 1.2, HASTE = 0.78, DODGE = 0.21, MP5 = 0.43,
						HP5 = 0.38, MH_DPS = 0.26, OH_DPS = 0.085, RANGED_DPS = 2.98,
					} },
					{ upTo = 39, weights = {
						STR = 0.028, STA = 0.38, INT = 0.34, SPI = 0.14, ARMOR = 0.012, HEALTH = 0.034, MANA = 0.011,
						AP = 0.055, RAP = 0.37, HIT = 1.5, CRIT = 2.54, HASTE = 1.67, DODGE = 0.28, MP5 = 0.29,
						HP5 = 0.21, MH_DPS = 0.17, OH_DPS = 0.055, RANGED_DPS = 2.94,
					} },
					{ upTo = 59, weights = {
						STR = 0.013, STA = 0.24, INT = 0.36, SPI = 0.05, ARMOR = 0.004, HEALTH = 0.024, MANA = 0.005,
						AP = 0.025, RAP = 0.35, HIT = 3.31, CRIT = 5.66, HASTE = 3.8, DODGE = 0.25, MP5 = 0.15,
						HP5 = 0.075, MH_DPS = 0.075, OH_DPS = 0.025, RANGED_DPS = 2.9,
					} },
				},
			},
			MARKSMANSHIP = {
				tab = 2, role = "ranged",
				source = "wowsims", sourcePath = "ui/specs/hunter/dps/presets.ts", sourcePreset = "TurretEpWeights",
				sourceCommit = "21377c070b5ea111a9bb5e36eb766193270b0cc7",
				confidence = "high", ref = "AGI",
				note = "Turret preset (Agility = 1 upstream), measured on the Marksmanship build. Hit is its value below the 8% cap. Level 60 raid-style sim (pre-raid gear, consumables and raid buffs); brackets below 60 are authored. ADDED: STA 0.15 and HEALTH as an authored survival floor (the sim measures output only).",
				weights = {
					AGI = 1, STA = 0.15, INT = 0.38, HEALTH = 0.015, RAP = 0.34, HIT = 11.4, CRIT = 11.8,
					HASTE = 8, MP5 = 0.04, RANGED_DPS = 2.87,
				},
				brackets = {   -- authored, confidence low
					{ upTo = 19, weights = {
						STR = 0.043, STA = 0.57, INT = 0.31, SPI = 0.26, ARMOR = 0.025, HEALTH = 0.045, MANA = 0.017,
						AP = 0.085, RAP = 0.39, HIT = 0.72, CRIT = 1.2, HASTE = 0.78, DODGE = 0.21, MP5 = 0.43,
						HP5 = 0.38, MH_DPS = 0.26, OH_DPS = 0.085, RANGED_DPS = 2.98,
					} },
					{ upTo = 39, weights = {
						STR = 0.028, STA = 0.38, INT = 0.34, SPI = 0.14, ARMOR = 0.012, HEALTH = 0.034, MANA = 0.011,
						AP = 0.055, RAP = 0.37, HIT = 1.5, CRIT = 2.54, HASTE = 1.67, DODGE = 0.28, MP5 = 0.29,
						HP5 = 0.21, MH_DPS = 0.17, OH_DPS = 0.055, RANGED_DPS = 2.94,
					} },
					{ upTo = 59, weights = {
						STR = 0.013, STA = 0.24, INT = 0.36, SPI = 0.05, ARMOR = 0.004, HEALTH = 0.024, MANA = 0.005,
						AP = 0.025, RAP = 0.35, HIT = 3.31, CRIT = 5.66, HASTE = 3.8, DODGE = 0.25, MP5 = 0.15,
						HP5 = 0.075, MH_DPS = 0.075, OH_DPS = 0.025, RANGED_DPS = 2.9,
					} },
				},
			},
			SURVIVAL = {
				tab = 3, role = "ranged",
				source = "wowsims", sourcePath = "ui/specs/hunter/dps/presets.ts", sourcePreset = "TurretEpWeights",
				sourceCommit = "21377c070b5ea111a9bb5e36eb766193270b0cc7",
				confidence = "medium", ref = "AGI",
				note = "Turret preset: the ranged Survival build uses the Turret gear upstream. The Weave and Melee presets (melee weapon DPS valued) are NOT used here. Level 60 raid-style sim (pre-raid gear, consumables and raid buffs); brackets below 60 are authored. ADDED: STA 0.15 and HEALTH as an authored survival floor (the sim measures output only).",
				weights = {
					AGI = 1, STA = 0.15, INT = 0.38, HEALTH = 0.015, RAP = 0.34, HIT = 11.4, CRIT = 11.8,
					HASTE = 8, MP5 = 0.04, RANGED_DPS = 2.87,
				},
				brackets = {   -- authored, confidence low
					{ upTo = 19, weights = {
						STR = 0.043, STA = 0.57, INT = 0.31, SPI = 0.26, ARMOR = 0.025, HEALTH = 0.045, MANA = 0.017,
						AP = 0.085, RAP = 0.39, HIT = 0.72, CRIT = 1.2, HASTE = 0.78, DODGE = 0.21, MP5 = 0.43,
						HP5 = 0.38, MH_DPS = 0.26, OH_DPS = 0.085, RANGED_DPS = 2.98,
					} },
					{ upTo = 39, weights = {
						STR = 0.028, STA = 0.38, INT = 0.34, SPI = 0.14, ARMOR = 0.012, HEALTH = 0.034, MANA = 0.011,
						AP = 0.055, RAP = 0.37, HIT = 1.5, CRIT = 2.54, HASTE = 1.67, DODGE = 0.28, MP5 = 0.29,
						HP5 = 0.21, MH_DPS = 0.17, OH_DPS = 0.055, RANGED_DPS = 2.94,
					} },
					{ upTo = 59, weights = {
						STR = 0.013, STA = 0.24, INT = 0.36, SPI = 0.05, ARMOR = 0.004, HEALTH = 0.024, MANA = 0.005,
						AP = 0.025, RAP = 0.35, HIT = 3.31, CRIT = 5.66, HASTE = 3.8, DODGE = 0.25, MP5 = 0.15,
						HP5 = 0.075, MH_DPS = 0.075, OH_DPS = 0.025, RANGED_DPS = 2.9,
					} },
				},
			},
			-- Authored generic leveling profile: used while no talent point is spent, and blended into every spec below 60.
			LEVELING = {
				tab = 1, role = "ranged", manual = true,
				source = "authored",
				confidence = "low", ref = "AGI",
				note = "Authored generic leveling profile: used while no talent point is spent, and blended into every spec below 60.",
				weights = {
					STR = 0.05, AGI = 1, STA = 0.5, INT = 0.3, SPI = 0.2, ARMOR = 0.015, HEALTH = 0.05,
					MANA = 0.02, AP = 0.1, RAP = 0.4, HIT = 6, CRIT = 10, HASTE = 6.4, DODGE = 2, MP5 = 0.5,
					HP5 = 0.3, MH_DPS = 0.3, OH_DPS = 0.1, RANGED_DPS = 3,
				},
				brackets = {   -- authored, confidence low
					{ upTo = 19, weights = {
						STA = 0.65, SPI = 0.3, ARMOR = 0.03, HIT = 0.75, CRIT = 1.25, HASTE = 0.8, DODGE = 0.25,
						HP5 = 0.45,
					} },
					{ upTo = 39, weights = {
						STA = 0.57, SPI = 0.25, ARMOR = 0.022, HIT = 1.5, CRIT = 2.5, HASTE = 1.6, DODGE = 0.5,
						HP5 = 0.38,
					} },
					{ upTo = 59, weights = {
						HIT = 3, CRIT = 5, HASTE = 3.2, DODGE = 1,
					} },
				},
			},
		},
	},

	ROGUE = {
		default = "LEVELING",
		order = { "ASSASSINATION", "COMBAT", "SUBTLETY", "LEVELING" },
		specs = {
			ASSASSINATION = {
				tab = 1, role = "melee",
				source = "wowsims", sourcePath = "ui/specs/rogue/dps/presets.ts", sourcePreset = "EP_PRESET_ASSASSINATION",
				sourceCommit = "21377c070b5ea111a9bb5e36eb766193270b0cc7",
				confidence = "high", ref = "AGI",
				note = "Assassination preset, divided by its Agility weight. Level 60 raid-style sim (pre-raid gear, consumables and raid buffs); brackets below 60 are authored. ADDED: STA 0.15 and HEALTH as an authored survival floor (the sim measures output only).",
				weights = {
					STR = 0.53, AGI = 1, STA = 0.15, HEALTH = 0.015, AP = 0.49, HIT = 13.6, CRIT = 13.7,
					HASTE = 9.37, EXPERTISE = 13.4, ARMOR_PEN = 1.94, SPELL_PEN = 0.32, MH_DPS = 4.1,
					OH_DPS = 2.02,
				},
				brackets = {   -- authored, confidence low
					{ upTo = 19, weights = {
						STR = 0.55, STA = 0.57, SPI = 0.064, ARMOR = 0.025, HEALTH = 0.045, AP = 0.5, HIT = 0.84,
						CRIT = 1.23, HASTE = 0.86, EXPERTISE = 0.52, ARMOR_PEN = 0.19, DODGE = 0.32, HP5 = 0.51,
						SPELL_PEN = 0.012, MH_DPS = 5.2, OH_DPS = 1.58,
					} },
					{ upTo = 39, weights = {
						STR = 0.54, STA = 0.38, SPI = 0.034, ARMOR = 0.012, HEALTH = 0.034, HIT = 1.77, CRIT = 2.73,
						HASTE = 1.89, EXPERTISE = 1.35, ARMOR_PEN = 0.41, DODGE = 0.41, HP5 = 0.28,
						SPELL_PEN = 0.035, MH_DPS = 4.81, OH_DPS = 1.73,
					} },
					{ upTo = 59, weights = {
						STR = 0.54, STA = 0.24, SPI = 0.013, ARMOR = 0.004, HEALTH = 0.024, HIT = 3.93, CRIT = 6.4,
						HASTE = 4.39, EXPERTISE = 3.53, ARMOR_PEN = 0.93, DODGE = 0.38, HP5 = 0.1, SPELL_PEN = 0.059,
						MH_DPS = 4.42, OH_DPS = 1.89,
					} },
				},
			},
			COMBAT = {
				tab = 2, role = "melee",
				source = "wowsims", sourcePath = "ui/specs/rogue/dps/presets.ts", sourcePreset = "EP_PRESET_COMBAT_SINISTER",
				sourceCommit = "21377c070b5ea111a9bb5e36eb766193270b0cc7",
				confidence = "high", ref = "AGI",
				note = "Combat Sinister preset (the upstream default), divided by its Agility weight. Level 60 raid-style sim (pre-raid gear, consumables and raid buffs); brackets below 60 are authored. ADDED: STA 0.15 and HEALTH as an authored survival floor (the sim measures output only).",
				weights = {
					STR = 0.56, AGI = 1, STA = 0.15, HEALTH = 0.015, AP = 0.51, HIT = 12.3, CRIT = 12.1,
					HASTE = 8.78, EXPERTISE = 13, ARMOR_PEN = 2.09, SPELL_PEN = 0.097, MH_DPS = 5.39,
					OH_DPS = 1.49,
				},
				brackets = {   -- authored, confidence low
					{ upTo = 19, weights = {
						STR = 0.55, STA = 0.57, SPI = 0.064, ARMOR = 0.025, HEALTH = 0.045, AP = 0.5, HIT = 0.83,
						CRIT = 1.21, HASTE = 0.85, EXPERTISE = 0.52, ARMOR_PEN = 0.2, DODGE = 0.32, HP5 = 0.51,
						SPELL_PEN = 0.004, MH_DPS = 5.4, OH_DPS = 1.5,
					} },
					{ upTo = 39, weights = {
						STA = 0.38, SPI = 0.034, ARMOR = 0.012, HEALTH = 0.034, AP = 0.5, HIT = 1.7, CRIT = 2.58,
						HASTE = 1.83, EXPERTISE = 1.32, ARMOR_PEN = 0.43, DODGE = 0.41, HP5 = 0.28,
						SPELL_PEN = 0.011, MH_DPS = 5.4, OH_DPS = 1.5,
					} },
					{ upTo = 59, weights = {
						STA = 0.24, SPI = 0.013, ARMOR = 0.004, HEALTH = 0.024, HIT = 3.65, CRIT = 5.8, HASTE = 4.17,
						EXPERTISE = 3.43, ARMOR_PEN = 0.98, DODGE = 0.38, HP5 = 0.1, SPELL_PEN = 0.018, OH_DPS = 1.5,
					} },
				},
			},
			SUBTLETY = {
				tab = 3, role = "melee",
				source = "wowsims", sourcePath = "ui/specs/rogue/dps/presets.ts", sourcePreset = "EP_PRESET_SUBTLETY",
				sourceCommit = "21377c070b5ea111a9bb5e36eb766193270b0cc7",
				confidence = "high", ref = "AGI",
				note = "Subtlety preset, divided by its Agility weight. Level 60 raid-style sim (pre-raid gear, consumables and raid buffs); brackets below 60 are authored. ADDED: STA 0.15 and HEALTH as an authored survival floor (the sim measures output only).",
				weights = {
					STR = 0.57, AGI = 1, STA = 0.15, HEALTH = 0.015, AP = 0.52, HIT = 11, CRIT = 11.8,
					HASTE = 7.41, EXPERTISE = 12.5, ARMOR_PEN = 1.71, SPELL_PEN = 0.083, MH_DPS = 5.42,
					OH_DPS = 1.18,
				},
				brackets = {   -- authored, confidence low
					{ upTo = 19, weights = {
						STR = 0.55, STA = 0.57, SPI = 0.064, ARMOR = 0.025, HEALTH = 0.045, AP = 0.5, HIT = 0.82,
						CRIT = 1.2, HASTE = 0.83, EXPERTISE = 0.52, ARMOR_PEN = 0.19, DODGE = 0.32, HP5 = 0.51,
						SPELL_PEN = 0.003, MH_DPS = 5.4, OH_DPS = 1.45,
					} },
					{ upTo = 39, weights = {
						STR = 0.56, STA = 0.38, SPI = 0.034, ARMOR = 0.012, HEALTH = 0.034, AP = 0.51, HIT = 1.61,
						CRIT = 2.55, HASTE = 1.7, EXPERTISE = 1.29, ARMOR_PEN = 0.39, DODGE = 0.41, HP5 = 0.28,
						SPELL_PEN = 0.009, MH_DPS = 5.41, OH_DPS = 1.35,
					} },
					{ upTo = 59, weights = {
						STR = 0.56, STA = 0.24, SPI = 0.013, ARMOR = 0.004, HEALTH = 0.024, AP = 0.51, HIT = 3.35,
						CRIT = 5.68, HASTE = 3.65, EXPERTISE = 3.32, ARMOR_PEN = 0.84, DODGE = 0.38, HP5 = 0.1,
						SPELL_PEN = 0.016, OH_DPS = 1.26,
					} },
				},
			},
			-- Authored generic leveling profile: used while no talent point is spent, and blended into every spec below 60.
			LEVELING = {
				tab = 2, role = "melee", manual = true,
				source = "authored",
				confidence = "low", ref = "AGI",
				note = "Authored generic leveling profile: used while no talent point is spent, and blended into every spec below 60.",
				weights = {
					STR = 0.55, AGI = 1, STA = 0.5, SPI = 0.05, ARMOR = 0.015, HEALTH = 0.05, AP = 0.5, HIT = 7,
					CRIT = 10, HASTE = 7, EXPERTISE = 4, ARMOR_PEN = 1.6, DODGE = 3, HP5 = 0.4, MH_DPS = 5.4,
					OH_DPS = 1.5,
				},
				brackets = {   -- authored, confidence low
					{ upTo = 19, weights = {
						STA = 0.65, SPI = 0.075, ARMOR = 0.03, HIT = 0.88, CRIT = 1.25, HASTE = 0.88,
						EXPERTISE = 0.5, ARMOR_PEN = 0.2, DODGE = 0.38, HP5 = 0.6,
					} },
					{ upTo = 39, weights = {
						STA = 0.57, SPI = 0.062, ARMOR = 0.022, HIT = 1.75, CRIT = 2.5, HASTE = 1.75, EXPERTISE = 1,
						ARMOR_PEN = 0.4, DODGE = 0.75, HP5 = 0.5,
					} },
					{ upTo = 59, weights = {
						HIT = 3.5, CRIT = 5, HASTE = 3.5, EXPERTISE = 2, ARMOR_PEN = 0.8, DODGE = 1.5,
					} },
				},
			},
		},
	},

	PRIEST = {
		default = "LEVELING",
		order = { "DISCIPLINE", "HOLY", "SHADOW", "LEVELING" },
		specs = {
			DISCIPLINE = {
				tab = 1, role = "healer",
				source = "wowsims", sourcePath = "ui/specs/priest/healer/presets.ts", sourcePreset = "DiscRaidHealingEpWeights",
				sourceCommit = "21377c070b5ea111a9bb5e36eb766193270b0cc7",
				confidence = "medium", ref = "HEAL",
				note = "Disc Raid Healing preset (healing = 1 upstream). Upstream gives no measurement note; the round numbers look hand-set. Level 60 raid-style sim (pre-raid gear, consumables and raid buffs); brackets below 60 are authored. ADDED: STA 0.05 and HEALTH as an authored survival floor (the sim measures output only).",
				weights = {
					STA = 0.05, INT = 0.2, SPI = 0.1, HEALTH = 0.005, HEAL = 1, SPELL_CRIT = 6.72, HASTE = 1,
					MP5 = 0.19,
				},
				brackets = {   -- authored, confidence low
					{ upTo = 19, weights = {
						STA = 0.45, INT = 0.44, SPI = 0.77, HEALTH = 0.034, MANA = 0.025, SPELL_DMG = 0.85,
						HEAL = 0.21, SPELL_DMG_HOLY = 0.21, SPELL_DMG_SHADOW = 0.64, SPELL_HIT = 0.59,
						SPELL_CRIT = 0.79, HASTE = 0.64, MP5 = 0.87, RANGED_DPS = 2.55,
					} },
					{ upTo = 39, weights = {
						STA = 0.27, INT = 0.32, SPI = 0.44, HEALTH = 0.023, MANA = 0.017, SPELL_DMG = 0.55,
						HEAL = 0.33, SPELL_DMG_HOLY = 0.14, SPELL_DMG_SHADOW = 0.41, SPELL_HIT = 0.77,
						SPELL_CRIT = 1.33, HASTE = 0.88, MP5 = 0.6, RANGED_DPS = 0.99,
					} },
					{ upTo = 59, weights = {
						STA = 0.12, INT = 0.21, SPI = 0.19, HEALTH = 0.012, MANA = 0.007, SPELL_DMG = 0.25,
						HEAL = 0.45, SPELL_DMG_HOLY = 0.062, SPELL_DMG_SHADOW = 0.19, SPELL_HIT = 0.7,
						SPELL_CRIT = 2.26, HASTE = 0.96, MP5 = 0.33, RANGED_DPS = 0.2,
					} },
				},
			},
			HOLY = {
				tab = 2, role = "healer",
				source = "wowsims", sourcePath = "ui/specs/priest/healer/presets.ts", sourcePreset = "HolyRaidHealingEpWeights",
				sourceCommit = "21377c070b5ea111a9bb5e36eb766193270b0cc7",
				confidence = "medium", ref = "HEAL",
				note = "Holy Raid Healing preset (healing = 1 upstream). Upstream gives no measurement note; the round numbers look hand-set. Level 60 raid-style sim (pre-raid gear, consumables and raid buffs); brackets below 60 are authored. ADDED: STA 0.05 and HEALTH as an authored survival floor (the sim measures output only).",
				weights = {
					STA = 0.05, INT = 0.3, SPI = 0.25, HEALTH = 0.005, HEAL = 1, SPELL_CRIT = 3.22, HASTE = 4.8,
					MP5 = 0.6,
				},
				brackets = {   -- authored, confidence low
					{ upTo = 19, weights = {
						STA = 0.45, INT = 0.45, SPI = 0.79, HEALTH = 0.034, MANA = 0.025, SPELL_DMG = 0.85,
						HEAL = 0.21, SPELL_DMG_HOLY = 0.21, SPELL_DMG_SHADOW = 0.64, SPELL_HIT = 0.59,
						SPELL_CRIT = 0.77, HASTE = 0.67, MP5 = 0.9, RANGED_DPS = 2.55,
					} },
					{ upTo = 39, weights = {
						STA = 0.27, INT = 0.35, SPI = 0.47, HEALTH = 0.023, MANA = 0.017, SPELL_DMG = 0.55,
						HEAL = 0.33, SPELL_DMG_HOLY = 0.14, SPELL_DMG_SHADOW = 0.41, SPELL_HIT = 0.77,
						SPELL_CRIT = 1.14, HASTE = 1.09, MP5 = 0.7, RANGED_DPS = 0.99,
					} },
					{ upTo = 59, weights = {
						STA = 0.12, INT = 0.25, HEALTH = 0.012, MANA = 0.007, SPELL_DMG = 0.25, HEAL = 0.45,
						SPELL_DMG_HOLY = 0.062, SPELL_DMG_SHADOW = 0.19, SPELL_HIT = 0.7, SPELL_CRIT = 1.54,
						HASTE = 1.74, MP5 = 0.5, RANGED_DPS = 0.2,
					} },
				},
			},
			SHADOW = {
				tab = 3, role = "caster",
				source = "wowsims", sourcePath = "ui/specs/priest/dps/presets.ts", sourcePreset = "ShadowEpWeights",
				sourceCommit = "21377c070b5ea111a9bb5e36eb766193270b0cc7",
				confidence = "high", ref = "SPELL_DMG",
				note = "Shadow preset (spell damage = 1 upstream). Level 60 raid-style sim (pre-raid gear, consumables and raid buffs); brackets below 60 are authored. ADDED: STA 0.10 and HEALTH as an authored survival floor (the sim measures output only).",
				weights = {
					STA = 0.1, INT = 0.24, SPI = 0.01, HEALTH = 0.01, SPELL_DMG = 1, SPELL_DMG_SHADOW = 1,
					SPELL_HIT = 11.4, SPELL_CRIT = 11.8, HASTE = 7.3,
				},
				brackets = {   -- authored, confidence low
					{ upTo = 19, weights = {
						STA = 0.46, INT = 0.46, SPI = 0.77, HEALTH = 0.036, MANA = 0.025, HEAL = 0.13,
						SPELL_DMG_HOLY = 0.21, SPELL_DMG_SHADOW = 0.79, SPELL_HIT = 0.68, SPELL_CRIT = 0.88,
						HASTE = 0.73, MP5 = 0.85, RANGED_DPS = 2.55,
					} },
					{ upTo = 39, weights = {
						STA = 0.3, INT = 0.38, SPI = 0.42, HEALTH = 0.027, MANA = 0.017, HEAL = 0.083,
						SPELL_DMG_HOLY = 0.14, SPELL_DMG_SHADOW = 0.86, SPELL_HIT = 1.45, SPELL_CRIT = 2.13,
						HASTE = 1.55, MP5 = 0.55, RANGED_DPS = 0.99,
					} },
					{ upTo = 59, weights = {
						STA = 0.18, INT = 0.3, SPI = 0.16, HEALTH = 0.018, MANA = 0.007, HEAL = 0.037,
						SPELL_DMG_HOLY = 0.062, SPELL_DMG_SHADOW = 0.94, SPELL_HIT = 3.26, SPELL_CRIT = 5.29,
						HASTE = 3.49, MP5 = 0.25, RANGED_DPS = 0.2,
					} },
				},
			},
			-- Authored generic leveling profile: used while no talent point is spent, and blended into every spec below 60.
			LEVELING = {
				tab = 3, role = "caster", manual = true,
				source = "authored",
				confidence = "low", ref = "SPELL_DMG",
				note = "Authored generic leveling profile: used while no talent point is spent, and blended into every spec below 60.",
				weights = {
					STA = 0.4, INT = 0.5, SPI = 0.6, HEALTH = 0.04, MANA = 0.03, SPELL_DMG = 1, HEAL = 0.15,
					SPELL_DMG_HOLY = 0.25, SPELL_DMG_SHADOW = 0.75, SPELL_HIT = 5.6, SPELL_CRIT = 7, HASTE = 6,
					MP5 = 1, RANGED_DPS = 0.8,
				},
				brackets = {   -- authored, confidence low
					{ upTo = 19, weights = {
						STA = 0.52, SPI = 0.9, SPELL_HIT = 0.7, SPELL_CRIT = 0.88, HASTE = 0.75, RANGED_DPS = 3,
					} },
					{ upTo = 39, weights = {
						STA = 0.46, SPI = 0.75, SPELL_HIT = 1.4, SPELL_CRIT = 1.75, HASTE = 1.5, RANGED_DPS = 1.8,
					} },
					{ upTo = 59, weights = {
						SPELL_HIT = 2.8, SPELL_CRIT = 3.5, HASTE = 3,
					} },
				},
			},
		},
	},

	SHAMAN = {
		default = "LEVELING",
		order = { "ELEMENTAL", "ENHANCEMENT", "RESTORATION", "LEVELING" },
		specs = {
			ELEMENTAL = {
				tab = 1, role = "caster",
				source = "wowsims", sourcePath = "ui/specs/shaman/elemental/presets.ts", sourcePreset = "DefaultEpWeights",
				sourceCommit = "21377c070b5ea111a9bb5e36eb766193270b0cc7",
				confidence = "high", ref = "SPELL_DMG",
				note = "Default preset (spell damage = 1 upstream). Hit is its value below the 17% cap. Spell penetration weight is against a resistant raid target. Level 60 raid-style sim (pre-raid gear, consumables and raid buffs); brackets below 60 are authored. ADDED: STA 0.10 and HEALTH as an authored survival floor (the sim measures output only).",
				weights = {
					STA = 0.1, INT = 0.19, SPI = 0.02, HEALTH = 0.01, SPELL_DMG = 1, SPELL_DMG_FIRE = 0.31,
					SPELL_DMG_NATURE = 0.69, SPELL_HIT = 11.8, SPELL_CRIT = 8.54, HASTE = 12.3, MP5 = 0.04,
					SPELL_PEN = 1.81,
				},
				brackets = {   -- authored, confidence low
					{ upTo = 19, weights = {
						STA = 0.46, INT = 0.45, SPI = 0.39, ARMOR = 0.017, HEALTH = 0.036, MANA = 0.025, HEAL = 0.13,
						SPELL_DMG_FIRE = 0.17, SPELL_DMG_FROST = 0.13, SPELL_DMG_NATURE = 0.7, SPELL_HIT = 0.68,
						SPELL_CRIT = 0.85, HASTE = 1, MP5 = 0.86, SPELL_PEN = 0.068,
					} },
					{ upTo = 39, weights = {
						STA = 0.3, INT = 0.36, SPI = 0.22, ARMOR = 0.008, HEALTH = 0.027, MANA = 0.017, HEAL = 0.083,
						SPELL_DMG_FIRE = 0.22, SPELL_DMG_FROST = 0.083, SPELL_DMG_NATURE = 0.7, SPELL_HIT = 1.47,
						SPELL_CRIT = 1.81, HASTE = 2.32, MP5 = 0.57, SPELL_PEN = 0.2,
					} },
					{ upTo = 59, weights = {
						STA = 0.18, INT = 0.27, SPI = 0.09, ARMOR = 0.003, HEALTH = 0.018, MANA = 0.007,
						HEAL = 0.037, SPELL_DMG_FIRE = 0.27, SPELL_DMG_FROST = 0.037, SPELL_HIT = 3.35,
						SPELL_CRIT = 4.08, HASTE = 5.61, MP5 = 0.28, SPELL_PEN = 0.34,
					} },
				},
			},
			ENHANCEMENT = {
				tab = 2, role = "melee",
				source = "wowsims", sourcePath = "ui/specs/shaman/enhancement/presets.ts", sourcePreset = "PreBiSEpWeights",
				sourceCommit = "21377c070b5ea111a9bb5e36eb766193270b0cc7",
				confidence = "high", ref = "STR",
				note = "Pre-BiS preset, divided by its Strength weight. Hit and crit rating weights are filed under HIT/CRIT only (they also move spells). No off-hand weight upstream. Level 60 raid-style sim (pre-raid gear, consumables and raid buffs); brackets below 60 are authored. ADDED: STA 0.15 and HEALTH as an authored survival floor (the sim measures output only).",
				weights = {
					STR = 1, AGI = 0.6, STA = 0.15, INT = 0.9, HEALTH = 0.015, AP = 0.45, SPELL_DMG = 0.58,
					SPELL_DMG_NATURE = 0.33, HIT = 23.6, CRIT = 15.4, HASTE = 12.8, EXPERTISE = 15.9,
					ARMOR_PEN = 1.68, SPELL_PEN = 1.15, MH_DPS = 6.45,
				},
				brackets = {   -- authored, confidence low
					{ upTo = 19, weights = {
						STA = 0.69, INT = 0.56, SPI = 0.32, ARMOR = 0.034, HEALTH = 0.053, MANA = 0.025,
						SPELL_DMG = 0.38, SPELL_DMG_FIRE = 0.043, SPELL_DMG_NATURE = 0.22, HIT = 1.02, CRIT = 1.46,
						HASTE = 1.22, EXPERTISE = 0.54, ARMOR_PEN = 0.02, DODGE = 0.32, BLOCK = 0.064, MP5 = 0.68,
						HP5 = 0.51, SPELL_PEN = 0.043, MH_DPS = 6.49,
					} },
					{ upTo = 39, weights = {
						STA = 0.45, INT = 0.68, SPI = 0.17, ARMOR = 0.017, HEALTH = 0.04, MANA = 0.017,
						SPELL_DMG = 0.45, SPELL_DMG_FIRE = 0.028, SPELL_DMG_NATURE = 0.26, HIT = 2.5, CRIT = 3.17,
						HASTE = 2.64, EXPERTISE = 1.5, ARMOR_PEN = 0.17, DODGE = 0.41, BLOCK = 0.083, MP5 = 0.44,
						HP5 = 0.28, SPELL_PEN = 0.13, MH_DPS = 6.48,
					} },
					{ upTo = 59, weights = {
						STA = 0.26, INT = 0.8, SPI = 0.062, ARMOR = 0.005, HEALTH = 0.026, MANA = 0.007,
						SPELL_DMG = 0.52, SPELL_DMG_FIRE = 0.013, SPELL_DMG_NATURE = 0.3, HIT = 6.32, CRIT = 7.27,
						HASTE = 6.04, EXPERTISE = 4.08, ARMOR_PEN = 0.63, DODGE = 0.38, BLOCK = 0.075, MP5 = 0.2,
						HP5 = 0.1, SPELL_PEN = 0.21, MH_DPS = 6.46,
					} },
				},
			},
			-- Authored: healing = 1; regen stats anchored on upstream priest healer presets; MP5 over Spirit (no in-combat Spirit regen talent assumed), haste valued for cast-time heals.
			RESTORATION = {
				tab = 3, role = "healer",
				source = "authored",
				confidence = "low", ref = "HEAL",
				note = "Authored: healing = 1; regen stats anchored on upstream priest healer presets; MP5 over Spirit (no in-combat Spirit regen talent assumed), haste valued for cast-time heals.",
				weights = {
					STA = 0.05, INT = 0.3, SPI = 0.1, HEALTH = 0.005, MANA = 0.015, HEAL = 1, SPELL_CRIT = 5,
					HASTE = 4.5, MP5 = 0.6,
				},
				brackets = {   -- authored, confidence low
					{ upTo = 19, weights = {
						STA = 0.45, INT = 0.45, SPI = 0.39, ARMOR = 0.017, HEALTH = 0.034, MANA = 0.027,
						SPELL_DMG = 0.85, HEAL = 0.21, SPELL_DMG_FIRE = 0.13, SPELL_DMG_FROST = 0.13,
						SPELL_DMG_NATURE = 0.59, SPELL_HIT = 0.59, SPELL_CRIT = 0.78, HASTE = 0.88, MP5 = 0.9,
					} },
					{ upTo = 39, weights = {
						STA = 0.27, INT = 0.35, SPI = 0.23, ARMOR = 0.008, HEALTH = 0.023, MANA = 0.02,
						SPELL_DMG = 0.55, HEAL = 0.33, SPELL_DMG_FIRE = 0.083, SPELL_DMG_FROST = 0.083,
						SPELL_DMG_NATURE = 0.39, SPELL_HIT = 0.77, SPELL_CRIT = 1.23, HASTE = 1.35, MP5 = 0.7,
					} },
					{ upTo = 59, weights = {
						STA = 0.12, INT = 0.25, SPI = 0.12, ARMOR = 0.003, HEALTH = 0.012, MANA = 0.014,
						SPELL_DMG = 0.25, HEAL = 0.45, SPELL_DMG_FIRE = 0.037, SPELL_DMG_FROST = 0.037,
						SPELL_DMG_NATURE = 0.17, SPELL_HIT = 0.7, SPELL_CRIT = 1.91, HASTE = 1.93, MP5 = 0.5,
					} },
				},
			},
			-- Authored generic leveling profile: used while no talent point is spent, and blended into every spec below 60.
			LEVELING = {
				tab = 2, role = "melee", manual = true,
				source = "authored",
				confidence = "low", ref = "STR",
				note = "Authored generic leveling profile: used while no talent point is spent, and blended into every spec below 60.",
				weights = {
					STR = 1, AGI = 0.6, STA = 0.6, INT = 0.5, SPI = 0.25, ARMOR = 0.02, HEALTH = 0.06,
					MANA = 0.03, AP = 0.45, SPELL_DMG = 0.35, SPELL_DMG_FIRE = 0.05, SPELL_DMG_NATURE = 0.2,
					HIT = 8, CRIT = 12, HASTE = 10, EXPERTISE = 4, DODGE = 3, BLOCK = 0.6, MP5 = 0.8, HP5 = 0.4,
					MH_DPS = 6.5,
				},
				brackets = {   -- authored, confidence low
					{ upTo = 19, weights = {
						STA = 0.78, SPI = 0.38, ARMOR = 0.04, HIT = 1, CRIT = 1.5, HASTE = 1.25, EXPERTISE = 0.5,
						DODGE = 0.38, BLOCK = 0.075, HP5 = 0.6,
					} },
					{ upTo = 39, weights = {
						STA = 0.69, SPI = 0.31, ARMOR = 0.03, HIT = 2, CRIT = 3, HASTE = 2.5, EXPERTISE = 1,
						DODGE = 0.75, BLOCK = 0.15, HP5 = 0.5,
					} },
					{ upTo = 59, weights = {
						HIT = 4, CRIT = 6, HASTE = 5, EXPERTISE = 2, DODGE = 1.5, BLOCK = 0.3,
					} },
				},
			},
		},
	},

	MAGE = {
		default = "LEVELING",
		order = { "ARCANE", "FIRE", "FROST", "LEVELING" },
		specs = {
			-- Authored: spell damage = 1; hit/crit/haste set from first principles inside the range of the three upstream caster presets; Intellect raised for mana-hungry Arcane.
			ARCANE = {
				tab = 1, role = "caster",
				source = "authored",
				confidence = "low", ref = "SPELL_DMG",
				note = "Authored: spell damage = 1; hit/crit/haste set from first principles inside the range of the three upstream caster presets; Intellect raised for mana-hungry Arcane.",
				weights = {
					STA = 0.1, INT = 0.35, SPI = 0.05, HEALTH = 0.01, MANA = 0.015, SPELL_DMG = 1,
					SPELL_DMG_ARCANE = 0.9, SPELL_DMG_FIRE = 0.1, SPELL_HIT = 13, SPELL_CRIT = 10, HASTE = 9.5,
					MP5 = 0.25,
				},
				brackets = {   -- authored, confidence low
					{ upTo = 19, weights = {
						STA = 0.46, INT = 0.48, SPI = 0.45, HEALTH = 0.036, MANA = 0.028, SPELL_DMG_ARCANE = 0.22,
						SPELL_DMG_FIRE = 0.31, SPELL_DMG_FROST = 0.47, SPELL_HIT = 0.77, SPELL_CRIT = 0.97,
						HASTE = 0.88, MP5 = 0.89, RANGED_DPS = 1.7,
					} },
					{ upTo = 39, weights = {
						STA = 0.3, INT = 0.43, SPI = 0.26, HEALTH = 0.027, MANA = 0.023, SPELL_DMG_ARCANE = 0.46,
						SPELL_DMG_FIRE = 0.24, SPELL_DMG_FROST = 0.3, SPELL_HIT = 1.65, SPELL_CRIT = 2.09,
						HASTE = 1.93, MP5 = 0.66, RANGED_DPS = 0.55,
					} },
					{ upTo = 59, weights = {
						STA = 0.18, INT = 0.39, SPI = 0.12, HEALTH = 0.018, MANA = 0.019, SPELL_DMG_ARCANE = 0.7,
						SPELL_DMG_FIRE = 0.16, SPELL_DMG_FROST = 0.14, SPELL_HIT = 3.72, SPELL_CRIT = 4.75,
						HASTE = 4.46, MP5 = 0.44, RANGED_DPS = 0.1,
					} },
				},
			},
			-- Authored: spell damage = 1; hit/crit/haste set from first principles inside the range of the three upstream caster presets; crit raised for Ignite-style crit talents.
			FIRE = {
				tab = 2, role = "caster",
				source = "authored",
				confidence = "medium", ref = "SPELL_DMG",
				note = "Authored: spell damage = 1; hit/crit/haste set from first principles inside the range of the three upstream caster presets; crit raised for Ignite-style crit talents.",
				weights = {
					STA = 0.1, INT = 0.28, SPI = 0.02, HEALTH = 0.01, MANA = 0.012, SPELL_DMG = 1,
					SPELL_DMG_FIRE = 1, SPELL_HIT = 13, SPELL_CRIT = 12, HASTE = 9, MP5 = 0.1,
				},
				brackets = {   -- authored, confidence low
					{ upTo = 19, weights = {
						STA = 0.46, INT = 0.47, SPI = 0.45, HEALTH = 0.036, MANA = 0.027, SPELL_DMG_ARCANE = 0.085,
						SPELL_DMG_FIRE = 0.45, SPELL_DMG_FROST = 0.47, SPELL_HIT = 0.77, SPELL_CRIT = 0.99,
						HASTE = 0.87, MP5 = 0.86, RANGED_DPS = 1.7,
					} },
					{ upTo = 39, weights = {
						STA = 0.3, INT = 0.4, SPI = 0.25, HEALTH = 0.027, MANA = 0.022, SPELL_DMG_ARCANE = 0.055,
						SPELL_DMG_FIRE = 0.64, SPELL_DMG_FROST = 0.3, SPELL_HIT = 1.65, SPELL_CRIT = 2.29,
						HASTE = 1.88, MP5 = 0.6, RANGED_DPS = 0.55,
					} },
					{ upTo = 59, weights = {
						STA = 0.18, INT = 0.34, SPI = 0.1, HEALTH = 0.018, MANA = 0.017, SPELL_DMG_ARCANE = 0.025,
						SPELL_DMG_FIRE = 0.84, SPELL_DMG_FROST = 0.14, SPELL_HIT = 3.72, SPELL_CRIT = 5.5,
						HASTE = 4.28, MP5 = 0.33, RANGED_DPS = 0.1,
					} },
				},
			},
			-- Authored: spell damage = 1; hit/crit/haste set from first principles inside the range of the three upstream caster presets.
			FROST = {
				tab = 3, role = "caster",
				source = "authored",
				confidence = "medium", ref = "SPELL_DMG",
				note = "Authored: spell damage = 1; hit/crit/haste set from first principles inside the range of the three upstream caster presets.",
				weights = {
					STA = 0.1, INT = 0.25, SPI = 0.02, HEALTH = 0.01, MANA = 0.012, SPELL_DMG = 1,
					SPELL_DMG_FROST = 1, SPELL_HIT = 13, SPELL_CRIT = 10, HASTE = 9, MP5 = 0.1,
				},
				brackets = {   -- authored, confidence low
					{ upTo = 19, weights = {
						STA = 0.46, INT = 0.46, SPI = 0.45, HEALTH = 0.036, MANA = 0.027, SPELL_DMG_ARCANE = 0.085,
						SPELL_DMG_FIRE = 0.3, SPELL_DMG_FROST = 0.62, SPELL_HIT = 0.77, SPELL_CRIT = 0.97,
						HASTE = 0.87, MP5 = 0.86, RANGED_DPS = 1.7,
					} },
					{ upTo = 39, weights = {
						STA = 0.3, INT = 0.39, SPI = 0.25, HEALTH = 0.027, MANA = 0.022, SPELL_DMG_ARCANE = 0.055,
						SPELL_DMG_FIRE = 0.19, SPELL_DMG_FROST = 0.75, SPELL_HIT = 1.65, SPELL_CRIT = 2.09,
						HASTE = 1.88, MP5 = 0.6, RANGED_DPS = 0.55,
					} },
					{ upTo = 59, weights = {
						STA = 0.18, INT = 0.31, SPI = 0.1, HEALTH = 0.018, MANA = 0.017, SPELL_DMG_ARCANE = 0.025,
						SPELL_DMG_FIRE = 0.087, SPELL_DMG_FROST = 0.89, SPELL_HIT = 3.72, SPELL_CRIT = 4.75,
						HASTE = 4.28, MP5 = 0.33, RANGED_DPS = 0.1,
					} },
				},
			},
			-- Authored generic leveling profile: used while no talent point is spent, and blended into every spec below 60.
			LEVELING = {
				tab = 3, role = "caster", manual = true,
				source = "authored",
				confidence = "low", ref = "SPELL_DMG",
				note = "Authored generic leveling profile: used while no talent point is spent, and blended into every spec below 60.",
				weights = {
					STA = 0.4, INT = 0.5, SPI = 0.35, HEALTH = 0.04, MANA = 0.03, SPELL_DMG = 1,
					SPELL_DMG_ARCANE = 0.1, SPELL_DMG_FIRE = 0.35, SPELL_DMG_FROST = 0.55, SPELL_HIT = 6.4,
					SPELL_CRIT = 8, HASTE = 7.2, MP5 = 1, RANGED_DPS = 0.4,
				},
				brackets = {   -- authored, confidence low
					{ upTo = 19, weights = {
						STA = 0.52, SPI = 0.52, SPELL_HIT = 0.8, SPELL_CRIT = 1, HASTE = 0.9, RANGED_DPS = 2,
					} },
					{ upTo = 39, weights = {
						STA = 0.46, SPI = 0.44, SPELL_HIT = 1.6, SPELL_CRIT = 2, HASTE = 1.8, RANGED_DPS = 1,
					} },
					{ upTo = 59, weights = {
						SPELL_HIT = 3.2, SPELL_CRIT = 4, HASTE = 3.6,
					} },
				},
			},
		},
	},

	WARLOCK = {
		default = "LEVELING",
		order = { "AFFLICTION", "DEMONOLOGY", "DESTRUCTION", "LEVELING" },
		specs = {
			-- Authored: spell damage = 1; mostly Shadow periodic damage, so crit and haste sit low; Stamina has value through Life Tap.
			AFFLICTION = {
				tab = 1, role = "caster",
				source = "authored",
				confidence = "low", ref = "SPELL_DMG",
				note = "Authored: spell damage = 1; mostly Shadow periodic damage, so crit and haste sit low; Stamina has value through Life Tap.",
				weights = {
					STA = 0.15, INT = 0.15, HEALTH = 0.015, MANA = 0.008, SPELL_DMG = 1, SPELL_DMG_FIRE = 0.1,
					SPELL_DMG_SHADOW = 0.9, SPELL_HIT = 12.5, SPELL_CRIT = 5, HASTE = 6, MP5 = 0.05,
				},
				brackets = {   -- authored, confidence low
					{ upTo = 19, weights = {
						STA = 0.63, INT = 0.32, SPI = 0.32, HEALTH = 0.049, MANA = 0.022, SPELL_DMG_FIRE = 0.23,
						SPELL_DMG_SHADOW = 0.77, SPELL_HIT = 0.73, SPELL_CRIT = 0.7, HASTE = 0.71, MP5 = 0.52,
						RANGED_DPS = 2.12,
					} },
					{ upTo = 39, weights = {
						STA = 0.42, INT = 0.26, SPI = 0.17, HEALTH = 0.037, MANA = 0.017, SPELL_DMG_FIRE = 0.18,
						SPELL_DMG_SHADOW = 0.82, SPELL_HIT = 1.57, SPELL_CRIT = 1.32, HASTE = 1.42, MP5 = 0.35,
						RANGED_DPS = 0.83,
					} },
					{ upTo = 59, weights = {
						STA = 0.25, INT = 0.2, SPI = 0.062, HEALTH = 0.025, MANA = 0.012, SPELL_DMG_FIRE = 0.14,
						SPELL_DMG_SHADOW = 0.86, SPELL_HIT = 3.56, SPELL_CRIT = 2.62, HASTE = 3, MP5 = 0.19,
						RANGED_DPS = 0.15,
					} },
				},
			},
			-- Authored: spell damage = 1; Shadow and Fire split evenly (upstream has a Fire Brand and a Shadow Brand build); Stamina has value through Life Tap.
			DEMONOLOGY = {
				tab = 2, role = "caster",
				source = "authored",
				confidence = "low", ref = "SPELL_DMG",
				note = "Authored: spell damage = 1; Shadow and Fire split evenly (upstream has a Fire Brand and a Shadow Brand build); Stamina has value through Life Tap.",
				weights = {
					STA = 0.15, INT = 0.15, HEALTH = 0.015, MANA = 0.008, SPELL_DMG = 1, SPELL_DMG_FIRE = 0.5,
					SPELL_DMG_SHADOW = 0.5, SPELL_HIT = 12.5, SPELL_CRIT = 8, HASTE = 8, MP5 = 0.05,
				},
				brackets = {   -- authored, confidence low
					{ upTo = 19, weights = {
						STA = 0.63, INT = 0.32, SPI = 0.32, HEALTH = 0.049, MANA = 0.022, SPELL_DMG_FIRE = 0.29,
						SPELL_DMG_SHADOW = 0.71, SPELL_HIT = 0.73, SPELL_CRIT = 0.73, HASTE = 0.73, MP5 = 0.52,
						RANGED_DPS = 2.12,
					} },
					{ upTo = 39, weights = {
						STA = 0.42, INT = 0.26, SPI = 0.17, HEALTH = 0.037, MANA = 0.017, SPELL_DMG_FIRE = 0.36,
						SPELL_DMG_SHADOW = 0.64, SPELL_HIT = 1.57, SPELL_CRIT = 1.62, HASTE = 1.62, MP5 = 0.35,
						RANGED_DPS = 0.83,
					} },
					{ upTo = 59, weights = {
						STA = 0.25, INT = 0.2, SPI = 0.062, HEALTH = 0.025, MANA = 0.012, SPELL_DMG_FIRE = 0.44,
						SPELL_DMG_SHADOW = 0.56, SPELL_HIT = 3.56, SPELL_CRIT = 3.75, HASTE = 3.75, MP5 = 0.19,
						RANGED_DPS = 0.15,
					} },
				},
			},
			-- Authored: spell damage = 1; Fire-leaning split read from the spell mix of the upstream Destruction build; crit raised for crit-damage talents.
			DESTRUCTION = {
				tab = 3, role = "caster",
				source = "authored",
				confidence = "low", ref = "SPELL_DMG",
				note = "Authored: spell damage = 1; Fire-leaning split read from the spell mix of the upstream Destruction build; crit raised for crit-damage talents.",
				weights = {
					STA = 0.15, INT = 0.15, HEALTH = 0.015, MANA = 0.008, SPELL_DMG = 1, SPELL_DMG_FIRE = 0.6,
					SPELL_DMG_SHADOW = 0.4, SPELL_HIT = 12.5, SPELL_CRIT = 10.5, HASTE = 8.5, MP5 = 0.05,
				},
				brackets = {   -- authored, confidence low
					{ upTo = 19, weights = {
						STA = 0.63, INT = 0.32, SPI = 0.32, HEALTH = 0.049, MANA = 0.022, SPELL_DMG_FIRE = 0.3,
						SPELL_DMG_SHADOW = 0.7, SPELL_HIT = 0.73, SPELL_CRIT = 0.76, HASTE = 0.74, MP5 = 0.52,
						RANGED_DPS = 2.12,
					} },
					{ upTo = 39, weights = {
						STA = 0.42, INT = 0.26, SPI = 0.17, HEALTH = 0.037, MANA = 0.017, SPELL_DMG_FIRE = 0.41,
						SPELL_DMG_SHADOW = 0.59, SPELL_HIT = 1.57, SPELL_CRIT = 1.86, HASTE = 1.67, MP5 = 0.35,
						RANGED_DPS = 0.83,
					} },
					{ upTo = 59, weights = {
						STA = 0.25, INT = 0.2, SPI = 0.062, HEALTH = 0.025, MANA = 0.012, SPELL_DMG_FIRE = 0.51,
						SPELL_DMG_SHADOW = 0.49, SPELL_HIT = 3.56, SPELL_CRIT = 4.69, HASTE = 3.94, MP5 = 0.19,
						RANGED_DPS = 0.15,
					} },
				},
			},
			-- Authored generic leveling profile: used while no talent point is spent, and blended into every spec below 60.
			LEVELING = {
				tab = 1, role = "caster", manual = true,
				source = "authored",
				confidence = "low", ref = "SPELL_DMG",
				note = "Authored generic leveling profile: used while no talent point is spent, and blended into every spec below 60.",
				weights = {
					STA = 0.55, INT = 0.35, SPI = 0.25, HEALTH = 0.055, MANA = 0.025, SPELL_DMG = 1,
					SPELL_DMG_FIRE = 0.25, SPELL_DMG_SHADOW = 0.75, SPELL_HIT = 6, SPELL_CRIT = 6, HASTE = 6,
					MP5 = 0.6, RANGED_DPS = 0.6,
				},
				brackets = {   -- authored, confidence low
					{ upTo = 19, weights = {
						STA = 0.72, SPI = 0.38, SPELL_HIT = 0.75, SPELL_CRIT = 0.75, HASTE = 0.75, RANGED_DPS = 2.5,
					} },
					{ upTo = 39, weights = {
						STA = 0.63, SPI = 0.31, SPELL_HIT = 1.5, SPELL_CRIT = 1.5, HASTE = 1.5, RANGED_DPS = 1.5,
					} },
					{ upTo = 59, weights = {
						SPELL_HIT = 3, SPELL_CRIT = 3, HASTE = 3,
					} },
				},
			},
		},
	},

	DRUID = {
		default = "LEVELING",
		order = { "BALANCE", "FERAL_CAT", "FERAL_BEAR", "RESTORATION", "LEVELING" },
		specs = {
			BALANCE = {
				tab = 1, role = "caster",
				source = "wowsims", sourcePath = "ui/specs/druid/balance/presets.ts", sourcePreset = "PreBiSEpWeights",
				sourceCommit = "21377c070b5ea111a9bb5e36eb766193270b0cc7",
				confidence = "high", ref = "SPELL_DMG",
				note = "Pre-BiS preset (spell damage = 1 upstream), Moonkin talents. Level 60 raid-style sim (pre-raid gear, consumables and raid buffs); brackets below 60 are authored. ADDED: STA 0.10 and HEALTH as an authored survival floor (the sim measures output only).",
				weights = {
					STA = 0.1, INT = 0.2, HEALTH = 0.01, SPELL_DMG = 1, SPELL_DMG_ARCANE = 0.68,
					SPELL_DMG_NATURE = 0.32, SPELL_HIT = 14.5, SPELL_CRIT = 10.6, HASTE = 9.5,
				},
				brackets = {   -- authored, confidence low
					{ upTo = 19, weights = {
						STA = 0.46, INT = 0.45, SPI = 0.51, ARMOR = 0.017, HEALTH = 0.036, MANA = 0.025, HEAL = 0.13,
						SPELL_DMG_ARCANE = 0.44, SPELL_DMG_NATURE = 0.56, SPELL_HIT = 0.83, SPELL_CRIT = 0.98,
						HASTE = 0.94, MP5 = 0.85,
					} },
					{ upTo = 39, weights = {
						STA = 0.3, INT = 0.37, SPI = 0.28, ARMOR = 0.008, HEALTH = 0.027, MANA = 0.017, HEAL = 0.083,
						SPELL_DMG_ARCANE = 0.53, SPELL_DMG_NATURE = 0.47, SPELL_HIT = 1.8, SPELL_CRIT = 2.15,
						HASTE = 2.01, MP5 = 0.55,
					} },
					{ upTo = 59, weights = {
						STA = 0.18, INT = 0.28, SPI = 0.1, ARMOR = 0.003, HEALTH = 0.018, MANA = 0.007, HEAL = 0.037,
						SPELL_DMG_ARCANE = 0.61, SPELL_DMG_NATURE = 0.39, SPELL_HIT = 4.11, SPELL_CRIT = 4.99,
						HASTE = 4.54, MP5 = 0.25,
					} },
				},
			},
			FERAL_CAT = {
				tab = 2, role = "melee",
				source = "wowsims", sourcePath = "ui/specs/druid/feral_ep.ts", sourcePreset = "CatEp",
				sourceCommit = "21377c070b5ea111a9bb5e36eb766193270b0cc7",
				confidence = "high", ref = "AGI",
				note = "CatEp, divided by its Agility weight. Weapon DPS counts in forms on this game version (upstream sim/druid/forms.go). Level 60 raid-style sim (pre-raid gear, consumables and raid buffs); brackets below 60 are authored. ADDED: STA 0.15 and HEALTH as an authored survival floor (the sim measures output only).",
				weights = {
					STR = 0.91, AGI = 1, STA = 0.15, HEALTH = 0.015, AP = 0.37, FERAL_AP = 0.37, HIT = 7.96,
					CRIT = 10.8, HASTE = 6, EXPERTISE = 7.49, ARMOR_PEN = 1.13, MH_DPS = 3.27,
				},
				brackets = {   -- authored, confidence low
					{ upTo = 19, weights = {
						STR = 0.94, STA = 0.63, INT = 0.17, SPI = 0.26, ARMOR = 0.034, HEALTH = 0.045, AP = 0.4,
						FERAL_AP = 0.4, HIT = 0.48, CRIT = 1.04, HASTE = 0.58, EXPERTISE = 0.37, ARMOR_PEN = 0.014,
						DODGE = 0.21, MP5 = 0.26, HP5 = 0.38, MH_DPS = 3.21,
					} },
					{ upTo = 39, weights = {
						STR = 0.93, STA = 0.42, INT = 0.11, SPI = 0.14, ARMOR = 0.017, HEALTH = 0.034, AP = 0.39,
						FERAL_AP = 0.39, HIT = 1.02, CRIT = 2.25, HASTE = 1.25, EXPERTISE = 0.86, ARMOR_PEN = 0.11,
						DODGE = 0.28, MP5 = 0.17, HP5 = 0.21, MH_DPS = 3.23,
					} },
					{ upTo = 59, weights = {
						STR = 0.92, STA = 0.25, INT = 0.05, SPI = 0.05, ARMOR = 0.005, HEALTH = 0.024, AP = 0.38,
						FERAL_AP = 0.38, HIT = 2.29, CRIT = 5.13, HASTE = 2.85, EXPERTISE = 2.06, ARMOR_PEN = 0.43,
						DODGE = 0.25, MP5 = 0.075, HP5 = 0.075, MH_DPS = 3.25,
					} },
				},
			},
			FERAL_BEAR = {
				tab = 2, role = "tank", manual = true,
				source = "wowsims", sourcePath = "ui/specs/druid/feral_ep.ts", sourcePreset = "BearEp",
				sourceCommit = "21377c070b5ea111a9bb5e36eb766193270b0cc7",
				confidence = "medium", ref = "STA",
				note = "BearEp (damage plus calibrated damage-smoothing value upstream), divided by its Stamina weight. Level 60 raid-style sim (pre-raid gear, consumables and raid buffs); brackets below 60 are authored.",
				weights = {
					STR = 0.48, AGI = 0.43, STA = 1, ARMOR = 0.17, HEALTH = 0.077, AP = 0.22, FERAL_AP = 0.22,
					HIT = 6.86, CRIT = 5.07, HASTE = 3.57, EXPERTISE = 17.7, ARMOR_PEN = 0.82, DODGE = 1.29,
					DEFENSE = 0.87, MH_DPS = 3.08,
				},
				brackets = {   -- authored, confidence low
					{ upTo = 19, weights = {
						STR = 0.88, AGI = 0.91, STA = 0.76, INT = 0.17, SPI = 0.26, ARMOR = 0.06, HEALTH = 0.054,
						AP = 0.37, FERAL_AP = 0.37, HIT = 0.47, CRIT = 0.97, HASTE = 0.55, EXPERTISE = 0.45,
						ARMOR_PEN = 0.01, DODGE = 0.23, DEFENSE = 0.01, MP5 = 0.26, HP5 = 0.38, MH_DPS = 3.18,
					} },
					{ upTo = 39, weights = {
						STR = 0.74, AGI = 0.74, STA = 0.8, INT = 0.11, SPI = 0.14, ARMOR = 0.095, HEALTH = 0.062,
						AP = 0.32, FERAL_AP = 0.32, HIT = 0.96, CRIT = 1.68, HASTE = 1.01, EXPERTISE = 1.46,
						ARMOR_PEN = 0.082, DODGE = 0.4, DEFENSE = 0.086, MP5 = 0.17, HP5 = 0.21, MH_DPS = 3.15,
					} },
					{ upTo = 59, weights = {
						STR = 0.6, AGI = 0.57, STA = 0.89, INT = 0.05, SPI = 0.05, ARMOR = 0.14, HEALTH = 0.07,
						AP = 0.27, FERAL_AP = 0.27, HIT = 2.04, CRIT = 2.98, HASTE = 1.94, EXPERTISE = 4.36,
						ARMOR_PEN = 0.31, DODGE = 0.73, DEFENSE = 0.33, MP5 = 0.075, HP5 = 0.075, MH_DPS = 3.11,
					} },
				},
			},
			-- Authored: healing = 1; regen stats anchored on upstream priest healer presets; crit low (periodic heals do not crit), Spirit equal to Intellect.
			RESTORATION = {
				tab = 3, role = "healer",
				source = "authored",
				confidence = "low", ref = "HEAL",
				note = "Authored: healing = 1; regen stats anchored on upstream priest healer presets; crit low (periodic heals do not crit), Spirit equal to Intellect.",
				weights = {
					STA = 0.05, INT = 0.3, SPI = 0.3, HEALTH = 0.005, MANA = 0.015, HEAL = 1, SPELL_CRIT = 2,
					HASTE = 4, MP5 = 0.55,
				},
				brackets = {   -- authored, confidence low
					{ upTo = 19, weights = {
						STA = 0.45, INT = 0.45, SPI = 0.53, ARMOR = 0.017, HEALTH = 0.034, MANA = 0.027,
						SPELL_DMG = 0.85, HEAL = 0.21, SPELL_DMG_ARCANE = 0.34, SPELL_DMG_NATURE = 0.51,
						SPELL_HIT = 0.72, SPELL_CRIT = 0.86, HASTE = 0.86, MP5 = 0.9,
					} },
					{ upTo = 39, weights = {
						STA = 0.27, INT = 0.35, SPI = 0.35, ARMOR = 0.008, HEALTH = 0.023, MANA = 0.02,
						SPELL_DMG = 0.55, HEAL = 0.33, SPELL_DMG_ARCANE = 0.22, SPELL_DMG_NATURE = 0.33,
						SPELL_HIT = 0.94, SPELL_CRIT = 1.21, HASTE = 1.29, MP5 = 0.69,
					} },
					{ upTo = 59, weights = {
						STA = 0.12, INT = 0.25, SPI = 0.22, ARMOR = 0.003, HEALTH = 0.012, MANA = 0.014,
						SPELL_DMG = 0.25, HEAL = 0.45, SPELL_DMG_ARCANE = 0.1, SPELL_DMG_NATURE = 0.15,
						SPELL_HIT = 0.85, SPELL_CRIT = 1.41, HASTE = 1.8, MP5 = 0.48,
					} },
				},
			},
			-- Authored generic leveling profile: used while no talent point is spent, and blended into every spec below 60.
			LEVELING = {
				tab = 2, role = "melee", manual = true,
				source = "authored",
				confidence = "low", ref = "AGI",
				note = "Authored generic leveling profile: used while no talent point is spent, and blended into every spec below 60.",
				weights = {
					STR = 0.95, AGI = 1, STA = 0.55, INT = 0.2, SPI = 0.2, ARMOR = 0.02, HEALTH = 0.05, AP = 0.4,
					FERAL_AP = 0.4, HIT = 4, CRIT = 8.6, HASTE = 4.8, EXPERTISE = 3, DODGE = 2, MP5 = 0.3,
					HP5 = 0.3, MH_DPS = 3.2,
				},
				brackets = {   -- authored, confidence low
					{ upTo = 19, weights = {
						STA = 0.72, SPI = 0.3, ARMOR = 0.04, HIT = 0.5, CRIT = 1.07, HASTE = 0.6, EXPERTISE = 0.38,
						DODGE = 0.25, HP5 = 0.45,
					} },
					{ upTo = 39, weights = {
						STA = 0.63, SPI = 0.25, ARMOR = 0.03, HIT = 1, CRIT = 2.15, HASTE = 1.2, EXPERTISE = 0.75,
						DODGE = 0.5, HP5 = 0.38,
					} },
					{ upTo = 59, weights = {
						HIT = 2, CRIT = 4.3, HASTE = 2.4, EXPERTISE = 1.5, DODGE = 1,
					} },
				},
			},
		},
	},
}
