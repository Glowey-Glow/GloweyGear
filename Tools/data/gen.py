# Builds Data/Weights.lua from upstream.json (extract.py) plus the authored tables below.
# usage: python -I gen.py <upstream.json> <commit> <out Weights.lua>
import sys, json

up_path, COMMIT, out_path = sys.argv[1], sys.argv[2], sys.argv[3]
UP = json.load(open(up_path, encoding='utf-8'))
DATE = '2026-11-20'

KEYS = ['STR', 'AGI', 'STA', 'INT', 'SPI', 'ARMOR', 'HEALTH', 'MANA', 'AP', 'RAP', 'FERAL_AP',
        'SPELL_DMG', 'HEAL', 'SPELL_DMG_ARCANE', 'SPELL_DMG_FIRE', 'SPELL_DMG_FROST', 'SPELL_DMG_HOLY',
        'SPELL_DMG_NATURE', 'SPELL_DMG_SHADOW', 'HIT', 'CRIT', 'SPELL_HIT', 'SPELL_CRIT', 'HASTE',
        'EXPERTISE', 'ARMOR_PEN', 'DODGE', 'PARRY', 'BLOCK', 'BLOCK_VALUE', 'DEFENSE', 'MP5', 'HP5',
        'SPELL_PEN', 'RES_FIRE', 'RES_NATURE', 'RES_FROST', 'RES_SHADOW', 'RES_ARCANE',
        'MH_DPS', 'OH_DPS', 'RANGED_DPS', 'MH_SPEED', 'OH_SPEED', 'RANGED_SPEED']

# ---- upstream stat name -> (canonical key, units of the game stat per one engine unit) ----------
# Percent keys: the engine divides the item's rating by RATING_PER_PERCENT, so a per-rating weight
# is multiplied by the same number. ARMOR_PEN: the engine divides by 10 (design/data-format.md 3.2).
PLAIN = {
    'StatStrength': ('STR', 1), 'StatAgility': ('AGI', 1), 'StatStamina': ('STA', 1),
    'StatIntellect': ('INT', 1), 'StatSpirit': ('SPI', 1), 'StatHealingPower': ('HEAL', 1),
    'StatSpellDamage': ('SPELL_DMG', 1), 'StatArcaneDamage': ('SPELL_DMG_ARCANE', 1),
    'StatFireDamage': ('SPELL_DMG_FIRE', 1), 'StatFrostDamage': ('SPELL_DMG_FROST', 1),
    'StatHolyDamage': ('SPELL_DMG_HOLY', 1), 'StatNatureDamage': ('SPELL_DMG_NATURE', 1),
    'StatShadowDamage': ('SPELL_DMG_SHADOW', 1), 'StatSpellPiercing': ('SPELL_PEN', 1),
    'StatAttackPower': ('AP', 1), 'StatRangedAttackPower': ('RAP', 1),
    'StatFeralAttackPower': ('FERAL_AP', 1), 'StatHasteRating': ('HASTE', 10),
    'StatArmorPenetration': ('ARMOR_PEN', 10), 'StatExpertiseRating': ('EXPERTISE', 10),
    'StatDefenseRating': ('DEFENSE', 1), 'StatBlockRating': ('BLOCK', 5),
    'StatBlockValue': ('BLOCK_VALUE', 1), 'StatDodgeRating': ('DODGE', 12),
    'StatParryRating': ('PARRY', 15), 'StatArmor': ('ARMOR', 1), 'StatHealth': ('HEALTH', 1),
    'StatMana': ('MANA', 1), 'StatMP5': ('MP5', 1),
    'PseudoStatMainHandDps': ('MH_DPS', 1), 'PseudoStatOffHandDps': ('OH_DPS', 1),
    'PseudoStatRangedDps': ('RANGED_DPS', 1),
}
# Not representable in the format (documented in README): flat weapon damage, armor that ignores
# multipliers (same weight as Armor upstream), bonus armor (the game reports one armor sum), feral
# combat skill, per-school hit.
DROPPED = {'StatPhysicalDamage', 'StatArmorNoMods', 'StatBonusArmor', 'PseudoStatFeralCombatSkill',
           'PseudoStatSchoolHitPercentHoly'}
PERCENT = {'HIT', 'CRIT', 'SPELL_HIT', 'SPELL_CRIT', 'HASTE', 'EXPERTISE', 'ARMOR_PEN', 'DODGE', 'PARRY', 'BLOCK'}


def convert(name, kind):
    """kind 'phys': hit/crit rating -> HIT/CRIT; 'spell': -> SPELL_HIT/SPELL_CRIT."""
    src = UP[name]['stats']
    t = {}
    for k, v in src.items():
        if k in DROPPED:
            continue
        if k == 'StatHitRating':
            key, mul = ('HIT' if kind == 'phys' else 'SPELL_HIT'), 10
        elif k == 'StatCritRating':
            key, mul = ('CRIT' if kind == 'phys' else 'SPELL_CRIT'), 14
        else:
            key, mul = PLAIN[k]
        if v != 0:
            t[key] = v * mul
    return t


def scaled(t, f):
    return {k: v * f for k, v in t.items()}


def normalize(t, ref):
    return scaled(t, 1.0 / t[ref])


# ---- leveling archetypes (authored). Values are for levels 40-59; see README "Leveling" -------
ARCH = {
    'WARRIOR_melee': dict(STR=1, AGI=0.55, STA=0.6, SPI=0.15, AP=0.45, CRIT=6, HIT=4, HASTE=4, EXPERTISE=2,
                          ARMOR_PEN=0.5, MH_DPS=7.5, OH_DPS=1.2, ARMOR=0.02, DEFENSE=0.1, DODGE=2, PARRY=2,
                          BLOCK=0.5, BLOCK_VALUE=0.1, HEALTH=0.06, HP5=0.5),
    'PALADIN_melee': dict(STR=1, AGI=0.45, STA=0.6, INT=0.4, SPI=0.25, AP=0.45, SPELL_DMG=0.3, SPELL_DMG_HOLY=0.25,
                          HEAL=0.05, CRIT=5, HIT=4, HASTE=4, EXPERTISE=2, MH_DPS=6.5, MP5=0.8, ARMOR=0.02,
                          DEFENSE=0.1, DODGE=2, PARRY=2, BLOCK=0.5, BLOCK_VALUE=0.1, HEALTH=0.06, MANA=0.025, HP5=0.4),
    'HUNTER_ranged': dict(AGI=1, STR=0.05, STA=0.5, INT=0.3, SPI=0.2, AP=0.1, RAP=0.4, CRIT=5, HIT=3, HASTE=3.2,
                          RANGED_DPS=3.0, MH_DPS=0.3, OH_DPS=0.1, MP5=0.5, ARMOR=0.015, DODGE=1, HEALTH=0.05,
                          MANA=0.02, HP5=0.3),
    'ROGUE_melee': dict(AGI=1, STR=0.55, STA=0.5, SPI=0.05, AP=0.5, CRIT=5, HIT=3.5, HASTE=3.5, EXPERTISE=2,
                        ARMOR_PEN=0.8, MH_DPS=5.4, OH_DPS=1.5, ARMOR=0.015, DODGE=1.5, HEALTH=0.05, HP5=0.4),
    'SHAMAN_melee': dict(STR=1, AGI=0.6, STA=0.6, INT=0.5, SPI=0.25, AP=0.45, SPELL_DMG=0.35, SPELL_DMG_NATURE=0.2,
                         SPELL_DMG_FIRE=0.05, CRIT=6, HIT=4, HASTE=5, EXPERTISE=2, MH_DPS=6.5, MP5=0.8, ARMOR=0.02,
                         DODGE=1.5, BLOCK=0.3, HEALTH=0.06, MANA=0.03, HP5=0.4),
    'SHAMAN_caster': dict(SPELL_DMG=1, SPELL_DMG_NATURE=0.7, SPELL_DMG_FIRE=0.15, SPELL_DMG_FROST=0.15, HEAL=0.15,
                          INT=0.5, SPI=0.3, STA=0.4, SPELL_CRIT=3.5, SPELL_HIT=2.8, HASTE=4, MP5=1.0, ARMOR=0.01,
                          HEALTH=0.04, MANA=0.03),
    'DRUID_melee': dict(AGI=1, STR=0.95, STA=0.55, INT=0.2, SPI=0.2, AP=0.4, FERAL_AP=0.4, CRIT=4.3, HIT=2,
                        HASTE=2.4, EXPERTISE=1.5, MH_DPS=3.2, ARMOR=0.02, DODGE=1, HEALTH=0.05, MP5=0.3, HP5=0.3),
    'DRUID_caster': dict(SPELL_DMG=1, SPELL_DMG_ARCANE=0.4, SPELL_DMG_NATURE=0.6, HEAL=0.15, INT=0.5, SPI=0.4,
                         STA=0.4, SPELL_CRIT=4, SPELL_HIT=3.4, HASTE=3.9, MP5=1.0, ARMOR=0.01, HEALTH=0.04,
                         MANA=0.03),
    'PRIEST_caster': dict(SPELL_DMG=1, SPELL_DMG_SHADOW=0.75, SPELL_DMG_HOLY=0.25, HEAL=0.15, INT=0.5, SPI=0.6,
                          STA=0.4, SPELL_CRIT=3.5, SPELL_HIT=2.8, HASTE=3, MP5=1.0, RANGED_DPS=0.8, HEALTH=0.04,
                          MANA=0.03),
    'MAGE_caster': dict(SPELL_DMG=1, SPELL_DMG_FROST=0.55, SPELL_DMG_FIRE=0.35, SPELL_DMG_ARCANE=0.1, INT=0.5,
                        SPI=0.35, STA=0.4, SPELL_CRIT=4, SPELL_HIT=3.2, HASTE=3.6, MP5=1.0, RANGED_DPS=0.4,
                        HEALTH=0.04, MANA=0.03),
    'WARLOCK_caster': dict(SPELL_DMG=1, SPELL_DMG_SHADOW=0.75, SPELL_DMG_FIRE=0.25, INT=0.35, SPI=0.25, STA=0.55,
                           SPELL_CRIT=3, SPELL_HIT=3, HASTE=3, MP5=0.6, RANGED_DPS=0.6, HEALTH=0.055, MANA=0.025),
}
# Wand DPS by bracket (19, 39, 59): casters wand a large share of every fight early on.
WAND = {'PRIEST_caster': (3.0, 1.8, 0.8), 'MAGE_caster': (2.0, 1.0, 0.4), 'WARLOCK_caster': (2.5, 1.5, 0.6)}

BRACKETS = (19, 39, 59)
ALPHA = {19: 0.15, 39: 0.45, 59: 0.75}        # share of the spec's own table in the blend
PCT = {19: 0.08, 39: 0.22, 59: 0.50}          # percent stats scale with the character's damage
SAME_LEVEL_HIT = 0.6                           # hit and expertise against same-level targets
ARCH_SCALE = {                                 # archetype (written for 40-59) scaled to lower brackets
    59: {},
    39: dict(STA=1.15, SPI=1.25, HP5=1.25, ARMOR=1.5, PCT=0.5),
    19: dict(STA=1.3, SPI=1.5, HP5=1.5, ARMOR=2.0, PCT=0.25),
}


def arch_at(name, upto):
    sc = ARCH_SCALE[upto]
    t = {}
    for k, v in ARCH[name].items():
        if k in PERCENT:
            v *= sc.get('PCT', 1)
        else:
            v *= sc.get(k, 1)
        t[k] = v
    if name in WAND:
        t['RANGED_DPS'] = WAND[name][BRACKETS.index(upto)]
    return t


def spec_at(t, upto):
    r = {}
    for k, v in t.items():
        if k in PERCENT or k == 'DEFENSE':
            v *= PCT[upto]
        if k in ('HIT', 'SPELL_HIT', 'EXPERTISE'):
            v *= SAME_LEVEL_HIT
        if k == 'SPELL_PEN':
            v *= 0.25
        r[k] = v
    return r


def blend(spec_t, arch_name, upto, conv):
    a = ALPHA[upto]
    s = scaled(spec_at(spec_t, upto), conv)
    ar = arch_at(arch_name, upto)
    return {k: (1 - a) * ar.get(k, 0) + a * s.get(k, 0) for k in set(s) | set(ar)}


def rnd(v):
    av = abs(v)
    if av >= 10:
        return round(v, 1)
    if av >= 0.1:
        return round(v, 2)
    return round(v, 3)


def clean(t):
    r = {}
    for k, v in t.items():
        v = rnd(v)
        if v != 0:
            r[k] = v
    return r


# ---- spec definitions ---------------------------------------------------------------------------
W = 'ui/specs/'
STA_FLOOR = {'melee': 0.15, 'ranged': 0.15, 'caster': 0.10, 'healer': 0.05}


def ws(tab, role, arch, preset, ref, kind, conf, note, conv=1.0, edit=None, manual=False):
    path, name = preset.split('#')
    t = normalize(convert(preset, kind), ref)
    t = {k: v for k, v in t.items() if abs(v) >= 0.005}   # upstream 0.01-per-AP placeholders vanish
    if edit:
        edit(t)
    return dict(tab=tab, role=role, arch=arch, source='wowsims', sourcePath=path, sourcePreset=name, ref=ref,
                confidence=conf, note=note, weights=t, conv=conv, manual=manual)


def au(tab, role, arch, ref, conf, rationale, weights, conv=1.0, manual=False):
    return dict(tab=tab, role=role, arch=arch, source='authored', ref=ref, confidence=conf, note=rationale,
                weights=dict(weights), conv=conv, manual=manual)


def ret_edit(t):
    # Upstream 22.87 per haste rating (about 3.3 x its hit weight) on the Unsealed Wrath preset; the sibling
    # Holy Shock preset has 4.06 per rating at the same AP = 1 scale. Use the sibling value.
    t['HASTE'] = 4.06 * 10 / 2.4


def tank_health(t):
    t.setdefault('HEALTH', 0.08)


LEVEL_NOTE = ' Level 60 raid-style sim (pre-raid gear, consumables and raid buffs); brackets below 60 are authored.'

CLASSES = [
    ('WARRIOR', 'WARRIOR_melee', 1, 'melee', [
        ('ARMS', ws(1, 'melee', 'WARRIOR_melee', W + 'warrior/dps/presets.ts#PreBiSArmsEpWeights', 'STR', 'phys', 'high',
                    'Pre-BiS Arms preset, divided by its Strength weight. Hit is its value below the 8% cap.' + LEVEL_NOTE)),
        ('FURY', ws(2, 'melee', 'WARRIOR_melee', W + 'warrior/dps/presets.ts#PreBiSFuryEpWeights', 'STR', 'phys', 'high',
                    'Pre-BiS Fury preset, divided by its Strength weight. Its low hit weight is dual-wield hit past the 8% special cap.' + LEVEL_NOTE)),
        ('PROTECTION', ws(3, 'tank', 'WARRIOR_melee', W + 'warrior/protection/presets.ts#PreBiSBalancedEpWeights', 'STA', 'phys', 'medium',
                          'Pre-BiS Balanced preset (upstream: 0.6 x threat + 1.15 x damage-smoothing weights), divided by its Stamina weight. Hit is its value PAST the cap (near zero): review. HEALTH 0.08 authored.' + LEVEL_NOTE,
                          edit=tank_health)),
    ]),
    ('PALADIN', 'PALADIN_melee', 3, 'melee', [
        ('HOLY', au(1, 'healer', 'PALADIN_melee', 'HEAL', 'low',
                    'Authored: healing = 1; regen stats anchored on upstream priest healer presets; crit raised (crit heals refund mana), Spirit near zero (no Spirit talents).',
                    dict(HEAL=1, INT=0.4, SPI=0.05, MP5=0.6, SPELL_CRIT=8.5, HASTE=3, STA=0.05, MANA=0.02, HEALTH=0.005), conv=0.45)),
        ('PROTECTION', au(2, 'tank', 'PALADIN_melee', 'STA', 'low',
                          'Authored: mitigation stats copied in ratio from the upstream Protection Warrior preset (same enemy attack table); threat part moved from Strength/weapon to spell damage and mana.',
                          dict(STA=1, STR=0.4, AGI=0.5, INT=0.15, AP=0.15, SPELL_DMG=0.3, SPELL_DMG_HOLY=0.25, HIT=1.0, CRIT=3,
                               HASTE=1.5, EXPERTISE=15, DEFENSE=0.46, DODGE=3.0, PARRY=3.4, BLOCK=0.5, BLOCK_VALUE=0.5,
                               ARMOR=0.05, MH_DPS=0.8, MP5=0.2, HEALTH=0.08, MANA=0.008))),
        ('RETRIBUTION', ws(3, 'melee', 'PALADIN_melee', W + 'paladin/retribution/presets.ts#UnsealedWrathEpWeights', 'STR', 'phys', 'medium',
                           'Unsealed Wrath preset (the upstream default), divided by its Strength weight. CHANGED: haste 22.87 per rating upstream replaced by the Holy Shock preset value 4.06. Hit and crit rating weights are filed under HIT/CRIT only (they also move spells).' + LEVEL_NOTE,
                           edit=ret_edit)),
    ]),
    ('HUNTER', 'HUNTER_ranged', 1, 'ranged', [
        ('BEAST_MASTERY', ws(1, 'ranged', 'HUNTER_ranged', W + 'hunter/dps/presets.ts#TurretEpWeights', 'AGI', 'phys', 'medium',
                             'Turret preset, measured upstream on the Marksmanship build; the Beast Mastery build uses the same gear set upstream. Pet scaling may differ.' + LEVEL_NOTE)),
        ('MARKSMANSHIP', ws(2, 'ranged', 'HUNTER_ranged', W + 'hunter/dps/presets.ts#TurretEpWeights', 'AGI', 'phys', 'high',
                            'Turret preset (Agility = 1 upstream), measured on the Marksmanship build. Hit is its value below the 8% cap.' + LEVEL_NOTE)),
        ('SURVIVAL', ws(3, 'ranged', 'HUNTER_ranged', W + 'hunter/dps/presets.ts#TurretEpWeights', 'AGI', 'phys', 'medium',
                        'Turret preset: the ranged Survival build uses the Turret gear upstream. The Weave and Melee presets (melee weapon DPS valued) are NOT used here.' + LEVEL_NOTE)),
    ]),
    ('ROGUE', 'ROGUE_melee', 2, 'melee', [
        ('ASSASSINATION', ws(1, 'melee', 'ROGUE_melee', W + 'rogue/dps/presets.ts#EP_PRESET_ASSASSINATION', 'AGI', 'phys', 'high',
                             'Assassination preset, divided by its Agility weight.' + LEVEL_NOTE)),
        ('COMBAT', ws(2, 'melee', 'ROGUE_melee', W + 'rogue/dps/presets.ts#EP_PRESET_COMBAT_SINISTER', 'AGI', 'phys', 'high',
                      'Combat Sinister preset (the upstream default), divided by its Agility weight.' + LEVEL_NOTE)),
        ('SUBTLETY', ws(3, 'melee', 'ROGUE_melee', W + 'rogue/dps/presets.ts#EP_PRESET_SUBTLETY', 'AGI', 'phys', 'high',
                        'Subtlety preset, divided by its Agility weight.' + LEVEL_NOTE)),
    ]),
    ('PRIEST', 'PRIEST_caster', 3, 'caster', [
        ('DISCIPLINE', ws(1, 'healer', 'PRIEST_caster', W + 'priest/healer/presets.ts#DiscRaidHealingEpWeights', 'HEAL', 'spell', 'medium',
                          'Disc Raid Healing preset (healing = 1 upstream). Upstream gives no measurement note; the round numbers look hand-set.' + LEVEL_NOTE, conv=0.55)),
        ('HOLY', ws(2, 'healer', 'PRIEST_caster', W + 'priest/healer/presets.ts#HolyRaidHealingEpWeights', 'HEAL', 'spell', 'medium',
                    'Holy Raid Healing preset (healing = 1 upstream). Upstream gives no measurement note; the round numbers look hand-set.' + LEVEL_NOTE, conv=0.55)),
        ('SHADOW', ws(3, 'caster', 'PRIEST_caster', W + 'priest/dps/presets.ts#ShadowEpWeights', 'SPELL_DMG', 'spell', 'high',
                      'Shadow preset (spell damage = 1 upstream).' + LEVEL_NOTE)),
    ]),
    ('SHAMAN', 'SHAMAN_melee', 2, 'melee', [
        ('ELEMENTAL', ws(1, 'caster', 'SHAMAN_caster', W + 'shaman/elemental/presets.ts#DefaultEpWeights', 'SPELL_DMG', 'spell', 'high',
                         'Default preset (spell damage = 1 upstream). Hit is its value below the 17% cap. Spell penetration weight is against a resistant raid target.' + LEVEL_NOTE)),
        ('ENHANCEMENT', ws(2, 'melee', 'SHAMAN_melee', W + 'shaman/enhancement/presets.ts#PreBiSEpWeights', 'STR', 'phys', 'high',
                           'Pre-BiS preset, divided by its Strength weight. Hit and crit rating weights are filed under HIT/CRIT only (they also move spells). No off-hand weight upstream.' + LEVEL_NOTE)),
        ('RESTORATION', au(3, 'healer', 'SHAMAN_caster', 'HEAL', 'low',
                           'Authored: healing = 1; regen stats anchored on upstream priest healer presets; MP5 over Spirit (no in-combat Spirit regen talent assumed), haste valued for cast-time heals.',
                           dict(HEAL=1, INT=0.3, SPI=0.1, MP5=0.6, SPELL_CRIT=5, HASTE=4.5, STA=0.05, MANA=0.015, HEALTH=0.005), conv=0.55)),
    ]),
    ('MAGE', 'MAGE_caster', 3, 'caster', [
        ('ARCANE', au(1, 'caster', 'MAGE_caster', 'SPELL_DMG', 'low',
                      'Authored: spell damage = 1; hit/crit/haste set from first principles inside the range of the three upstream caster presets; Intellect raised for mana-hungry Arcane.',
                      dict(SPELL_DMG=1, SPELL_DMG_ARCANE=0.9, SPELL_DMG_FIRE=0.1, INT=0.35, SPI=0.05, SPELL_HIT=13, SPELL_CRIT=10,
                           HASTE=9.5, MP5=0.25, STA=0.1, MANA=0.015, HEALTH=0.01))),
        ('FIRE', au(2, 'caster', 'MAGE_caster', 'SPELL_DMG', 'medium',
                    'Authored: spell damage = 1; hit/crit/haste set from first principles inside the range of the three upstream caster presets; crit raised for Ignite-style crit talents.',
                    dict(SPELL_DMG=1, SPELL_DMG_FIRE=1.0, INT=0.28, SPI=0.02, SPELL_HIT=13, SPELL_CRIT=12, HASTE=9, MP5=0.1,
                         STA=0.1, MANA=0.012, HEALTH=0.01))),
        ('FROST', au(3, 'caster', 'MAGE_caster', 'SPELL_DMG', 'medium',
                     'Authored: spell damage = 1; hit/crit/haste set from first principles inside the range of the three upstream caster presets.',
                     dict(SPELL_DMG=1, SPELL_DMG_FROST=1.0, INT=0.25, SPI=0.02, SPELL_HIT=13, SPELL_CRIT=10, HASTE=9, MP5=0.1,
                          STA=0.1, MANA=0.012, HEALTH=0.01))),
    ]),
    ('WARLOCK', 'WARLOCK_caster', 1, 'caster', [
        ('AFFLICTION', au(1, 'caster', 'WARLOCK_caster', 'SPELL_DMG', 'low',
                          'Authored: spell damage = 1; mostly Shadow periodic damage, so crit and haste sit low; Stamina has value through Life Tap.',
                          dict(SPELL_DMG=1, SPELL_DMG_SHADOW=0.9, SPELL_DMG_FIRE=0.1, INT=0.15, STA=0.15, SPELL_HIT=12.5,
                               SPELL_CRIT=5, HASTE=6, MP5=0.05, MANA=0.008, HEALTH=0.015))),
        ('DEMONOLOGY', au(2, 'caster', 'WARLOCK_caster', 'SPELL_DMG', 'low',
                          'Authored: spell damage = 1; Shadow and Fire split evenly (upstream has a Fire Brand and a Shadow Brand build); Stamina has value through Life Tap.',
                          dict(SPELL_DMG=1, SPELL_DMG_SHADOW=0.5, SPELL_DMG_FIRE=0.5, INT=0.15, STA=0.15, SPELL_HIT=12.5,
                               SPELL_CRIT=8, HASTE=8, MP5=0.05, MANA=0.008, HEALTH=0.015))),
        ('DESTRUCTION', au(3, 'caster', 'WARLOCK_caster', 'SPELL_DMG', 'low',
                           'Authored: spell damage = 1; Fire-leaning split read from the spell mix of the upstream Destruction build; crit raised for crit-damage talents.',
                           dict(SPELL_DMG=1, SPELL_DMG_FIRE=0.6, SPELL_DMG_SHADOW=0.4, INT=0.15, STA=0.15, SPELL_HIT=12.5,
                                SPELL_CRIT=10.5, HASTE=8.5, MP5=0.05, MANA=0.008, HEALTH=0.015))),
    ]),
    ('DRUID', 'DRUID_melee', 2, 'melee', [
        ('BALANCE', ws(1, 'caster', 'DRUID_caster', W + 'druid/balance/presets.ts#PreBiSEpWeights', 'SPELL_DMG', 'spell', 'high',
                       'Pre-BiS preset (spell damage = 1 upstream), Moonkin talents.' + LEVEL_NOTE)),
        ('FERAL_CAT', ws(2, 'melee', 'DRUID_melee', W + 'druid/feral_ep.ts#CatEp', 'AGI', 'phys', 'high',
                         'CatEp, divided by its Agility weight. Weapon DPS counts in forms on this game version (upstream sim/druid/forms.go).' + LEVEL_NOTE)),
        ('FERAL_BEAR', ws(2, 'tank', 'DRUID_melee', W + 'druid/feral_ep.ts#BearEp', 'STA', 'phys', 'medium',
                          'BearEp (damage plus calibrated damage-smoothing value upstream), divided by its Stamina weight.' + LEVEL_NOTE, manual=True)),
        ('RESTORATION', au(3, 'healer', 'DRUID_caster', 'HEAL', 'low',
                           'Authored: healing = 1; regen stats anchored on upstream priest healer presets; crit low (periodic heals do not crit), Spirit equal to Intellect.',
                           dict(HEAL=1, INT=0.3, SPI=0.3, MP5=0.55, SPELL_CRIT=2, HASTE=4, STA=0.05, MANA=0.015, HEALTH=0.005), conv=0.55)),
    ]),
]


def finish(spec):
    t = spec['weights']
    role = spec['role']
    if role in STA_FLOOR and t.get('STA', 0) < STA_FLOOR[role]:
        t['STA'] = STA_FLOOR[role]
        t.setdefault('HEALTH', STA_FLOOR[role] / 10)
        if spec['source'] == 'wowsims':
            spec['note'] += ' ADDED: STA %.2f and HEALTH as an authored survival floor (the sim measures output only).' % STA_FLOOR[role]
    base = clean(t)
    spec['base'] = base
    spec['brackets'] = []
    for upto in BRACKETS:
        b = clean(blend(t, spec['arch'], upto, spec['conv']))
        over = {}
        for k in KEYS:
            bv, sv = b.get(k, 0), base.get(k, 0)
            if bv != sv:
                over[k] = bv
        spec['brackets'].append((upto, over))


def leveling_spec(arch, tab, role):
    t = {k: (v * 2 if k in PERCENT else v) for k, v in ARCH[arch].items()}
    base = clean(t)
    spec = dict(tab=tab, role=role, source='authored', ref=('SPELL_DMG' if 'caster' in arch else ('AGI' if base.get('AGI') == 1 else 'STR')),
                confidence='low', manual=True, base=base, brackets=[],
                note='Authored generic leveling profile: used while no talent point is spent, and blended into every spec below 60.')
    for upto in BRACKETS:
        b = clean(arch_at(arch, upto))
        over = {k: b.get(k, 0) for k in KEYS if b.get(k, 0) != base.get(k, 0)}
        spec['brackets'].append((upto, over))
    return spec


def fmt_weights(t, indent):
    items = ['%s = %s' % (k, repr(t[k]) if not float(t[k]).is_integer() else str(int(t[k]))) for k in KEYS if k in t]
    lines, cur = [], ''
    for it in items:
        if cur and len(cur) + len(it) + 2 > 92:
            lines.append(cur)
            cur = ''
        cur = (cur + ', ' if cur else '') + it
    if cur:
        lines.append(cur)
    return (',\n' + indent).join(lines) + ','


def lua_str(s):
    return '"' + s.replace('\\', '\\\\').replace('"', '\\"') + '"'


out = []
A = out.append
A('-- Glowey\'s Gear: stat weights. GENERATED FILE (pure data; see Data/README.md for sources, method and how to regenerate).')
A('-- Shape: design/data-format.md, format 1. Units: percent keys are per 1%, everything else per point.')
A('-- Entries with source = "wowsims" are derived from EP presets of the wowsims/forever simulator,')
A('-- Copyright (c) 2022 wowsims team, MIT License (full text in CREDITS.md), https://github.com/wowsims/forever')
A('-- commit ' + COMMIT + '. Entries with source = "authored" and ALL "brackets" tables')
A('-- (levels below 60) are this project\'s own reasoning, not simulation output.')
A('-- Generated ' + DATE + ' by scratch scripts gen.py / extract.py (see Data/README.md).')
A('local _, ns = ...')
A('')
A('ns.WeightData = {')
A('\tformat = 1,')
for cls, arch, lvtab, lvrole, specs in CLASSES:
    specs = list(specs)
    for _, s in specs:
        finish(s)
    specs.append(('LEVELING', leveling_spec(arch, lvtab, lvrole)))
    A('')
    A('\t' + cls + ' = {')
    A('\t\tdefault = "LEVELING",')
    A('\t\torder = { ' + ', '.join('"%s"' % k for k, _ in specs) + ' },')
    A('\t\tspecs = {')
    for key, s in specs:
        if s['source'] == 'authored':
            A('\t\t\t-- ' + s['note'])
        A('\t\t\t' + key + ' = {')
        A('\t\t\t\ttab = %d, role = "%s",%s' % (s['tab'], s['role'], ' manual = true,' if s.get('manual') else ''))
        if s['source'] == 'wowsims':
            A('\t\t\t\tsource = "wowsims", sourcePath = "%s", sourcePreset = "%s",' % (s['sourcePath'], s['sourcePreset']))
            A('\t\t\t\tsourceCommit = "%s",' % COMMIT)
        else:
            A('\t\t\t\tsource = "authored",')
        A('\t\t\t\tconfidence = "%s", ref = "%s",' % (s['confidence'], s['ref']))
        A('\t\t\t\tnote = ' + lua_str(s['note']) + ',')
        A('\t\t\t\tweights = {')
        A('\t\t\t\t\t' + fmt_weights(s['base'], '\t\t\t\t\t'))
        A('\t\t\t\t},')
        A('\t\t\t\tbrackets = {   -- authored, confidence low')
        for upto, over in s['brackets']:
            A('\t\t\t\t\t{ upTo = %d, weights = {' % upto)
            A('\t\t\t\t\t\t' + fmt_weights(over, '\t\t\t\t\t\t'))
            A('\t\t\t\t\t} },')
        A('\t\t\t\t},')
        A('\t\t\t},')
    A('\t\t},')
    A('\t},')
A('}')
A('')
open(out_path, 'w', encoding='utf-8', newline='\n').write('\n'.join(out))
print('wrote', out_path, sum(len(c[4]) + 1 for c in CLASSES), 'spec entries')
