# Offline checks for Data/Weights.lua. usage: python -I check.py <Weights.lua>
import sys, re
import lupa.lua51 as l51

path = sys.argv[1]
src = open(path, encoding='utf-8').read()
rt = l51.LuaRuntime()
ns = rt.eval('{}')
rt.eval('function(src, ns) local f = assert(loadstring(src, "@Weights.lua")) f("GloweyGear", ns) end')(src, ns)
D = ns.WeightData

KEYS = set('''STR AGI STA INT SPI ARMOR HEALTH MANA AP RAP FERAL_AP SPELL_DMG HEAL SPELL_DMG_ARCANE SPELL_DMG_FIRE
SPELL_DMG_FROST SPELL_DMG_HOLY SPELL_DMG_NATURE SPELL_DMG_SHADOW HIT CRIT SPELL_HIT SPELL_CRIT HASTE EXPERTISE
ARMOR_PEN DODGE PARRY BLOCK BLOCK_VALUE DEFENSE MP5 HP5 SPELL_PEN RES_FIRE RES_NATURE RES_FROST RES_SHADOW
RES_ARCANE MH_DPS OH_DPS RANGED_DPS MH_SPEED OH_SPEED RANGED_SPEED'''.split())
PERCENT = set('HIT CRIT SPELL_HIT SPELL_CRIT HASTE EXPERTISE ARMOR_PEN DODGE PARRY BLOCK'.split())
CLASSES = {
    'WARRIOR': ['ARMS', 'FURY', 'PROTECTION'], 'PALADIN': ['HOLY', 'PROTECTION', 'RETRIBUTION'],
    'HUNTER': ['BEAST_MASTERY', 'MARKSMANSHIP', 'SURVIVAL'], 'ROGUE': ['ASSASSINATION', 'COMBAT', 'SUBTLETY'],
    'PRIEST': ['DISCIPLINE', 'HOLY', 'SHADOW'], 'SHAMAN': ['ELEMENTAL', 'ENHANCEMENT', 'RESTORATION'],
    'MAGE': ['ARCANE', 'FIRE', 'FROST'], 'WARLOCK': ['AFFLICTION', 'DEMONOLOGY', 'DESTRUCTION'],
    'DRUID': ['BALANCE', 'FERAL_CAT', 'RESTORATION'],
}
errors, n_specs, n_tables = [], 0, 0


def err(*a):
    errors.append(' '.join(str(x) for x in a))


def check_weights(where, w, base=False):
    global n_tables
    n_tables += 1
    for k, v in w.items():
        if k not in KEYS:
            err(where, 'unknown key', k)
        if not isinstance(v, (int, float)) or v != v or abs(v) == float('inf'):
            err(where, k, 'not a finite number')
            continue
        if v < 0:
            err(where, k, 'negative', v)
        limit = 40 if k in PERCENT else 10
        if v > limit:
            err(where, k, 'absurd', v)
    if base and max(w.values()) <= 0:
        err(where, 'empty')


assert D.format == 1
for key in D.keys():
    if key not in CLASSES and key != 'format':
        err('unknown top-level key', key)
for cls, want in CLASSES.items():
    c = D[cls]
    if c is None:
        err('missing class', cls)
        continue
    order = list(c.order.values())
    if c.default not in order:
        err(cls, 'default not in order')
    if len(set(order)) != len(order):
        err(cls, 'duplicate in order')
    for k in want:
        if k not in order:
            err(cls, 'missing spec', k)
    auto = {}
    for k in order:
        s = c.specs[k]
        where = cls + '.' + k
        if s is None:
            err(where, 'in order but not in specs')
            continue
        n_specs += 1
        if not re.fullmatch(r'[A-Z_]+', k):
            err(where, 'bad key')
        if s.tab not in (1, 2, 3):
            err(where, 'bad tab')
        if s.role not in ('melee', 'ranged', 'caster', 'healer', 'tank'):
            err(where, 'bad role')
        if s.confidence not in ('low', 'medium', 'high'):
            err(where, 'bad confidence')
        if s.source == 'wowsims':
            if not s.sourcePath or not s.sourceCommit or not re.fullmatch(r'[0-9a-f]{40}', s.sourceCommit):
                err(where, 'wowsims without path/commit')
        elif s.source == 'authored':
            if s.sourcePath or s.sourceCommit:
                err(where, 'authored with path/commit')
        else:
            err(where, 'bad source')
        if not s.manual:
            auto.setdefault(s.tab, k)
        w = dict(s.weights.items())
        check_weights(where, w, base=True)
        # double-count rule (data-format 3.2/3.3)
        if s.role in ('caster', 'healer') and (w.get('HIT') or w.get('CRIT')):
            err(where, 'caster with HIT/CRIT')
        if s.role in ('melee', 'ranged', 'tank') and (w.get('SPELL_HIT') or w.get('SPELL_CRIT')):
            err(where, 'physical with SPELL_HIT/SPELL_CRIT')
        last = 0
        for b in (s.brackets.values() if s.brackets else []):
            if b.upTo <= last or b.upTo > 59:
                err(where, 'brackets not ascending / past 59')
            last = b.upTo
            check_weights(where + '<=%d' % b.upTo, dict(b.weights.items()))
    if sorted(auto) != [1, 2, 3]:
        err(cls, 'a tab has no auto spec', auto)
    for tab, k in auto.items():
        if k != want[tab - 1]:
            err(cls, 'tab', tab, 'auto-picks', k, 'expected', want[tab - 1])
print('structure: %d classes, %d spec entries, %d weight tables, %d errors' % (len(CLASSES), n_specs, n_tables, len(errors)))
for e in errors:
    print('  ERROR', e)


# ---- item pairs --------------------------------------------------------------------------------
def table(cls, spec, level):
    s = D[cls].specs[spec]
    w = dict(s.weights.items())
    if level < 60 and s.brackets:
        for b in s.brackets.values():
            if b.upTo >= level:
                w.update(dict(b.weights.items()))
                break
    return w


def score(w, item):
    return sum(w.get(k, 0) * v for k, v in item.items())


# Stat tables written BY HAND FROM MEMORY of classic-era items (percent bonuses as percent). They are
# illustrations of archetypes, not data read from this client; "synthetic" rows are made-up items.
I = {
    'Lionheart Helm': dict(STR=18, CRIT=2, HIT=2, ARMOR=565),
    'Helm of Valor': dict(STR=15, AGI=9, STA=23, SPI=8, ARMOR=526),
    'Arcanite Reaper': dict(MH_DPS=53.8, STA=13, AP=62, RAP=62),
    "Executioner's Cleaver": dict(MH_DPS=40.0, STR=10),
    'Devilsaur Gauntlets': dict(AP=28, RAP=28, CRIT=1, STA=9, ARMOR=103),
    'Shadowcraft Gloves': dict(AGI=14, STR=9, STA=9, SPI=10, ARMOR=105),
    'Robe of the Archmage': dict(SPELL_DMG=40, HEAL=40, INT=12, SPELL_CRIT=1, CRIT=1, ARMOR=96),
    "Magister's Robes": dict(INT=31, STA=9, SPI=8, ARMOR=89),
    'Robes of the Exalted': dict(HEAL=68, INT=18, SPI=9, ARMOR=96),
    'Devout Robe': dict(INT=24, SPI=15, STA=13, ARMOR=89),
    'Stockade Pauldrons': dict(STA=20, DEFENSE=5, DODGE=1, ARMOR=478),
    'Truestrike Shoulders': dict(AP=24, RAP=24, HIT=2, SPELL_HIT=2, ARMOR=129),
    'Carapace Spine Crossbow': dict(RANGED_DPS=39.8, AGI=9, STA=4),
    'synthetic level-42 bow': dict(RANGED_DPS=22.0, AGI=4),
    'synthetic +30 Fire ring': dict(SPELL_DMG_FIRE=30),
    'synthetic +30 Frost ring': dict(SPELL_DMG_FROST=30),
    'synthetic +21 Shadow ring': dict(SPELL_DMG_SHADOW=21),
    'synthetic 2H, 30 DPS': dict(MH_DPS=30),
    'synthetic 2H, 26 DPS, +8 STR': dict(MH_DPS=26, STR=8),
    'synthetic cloak of the Eagle': dict(INT=5, STA=5, ARMOR=20),
    'synthetic cloak of the Bear': dict(STR=5, STA=5, ARMOR=20),
    'synthetic cloak of the Monkey': dict(AGI=5, STA=5, ARMOR=20),
    'synthetic cloak of the Whale': dict(INT=5, SPI=5, ARMOR=20),
    'synthetic cloak of the Tiger': dict(STR=5, AGI=5, ARMOR=20),
    'synthetic wand, 20 DPS': dict(RANGED_DPS=20),
    'synthetic wand, 14 DPS, +3 INT': dict(RANGED_DPS=14, INT=3),
    'synthetic ring +12 STA': dict(STA=12),
    'synthetic ring +1% hit': dict(HIT=1, SPELL_HIT=1),
    'synthetic ring +10 AGI': dict(AGI=10),
    'synthetic ring +10 INT': dict(INT=10),
    'synthetic ring +22 healing': dict(HEAL=22),
    'synthetic ring +12 damage and healing': dict(SPELL_DMG=12, HEAL=12),
    'synthetic shield 2000 armor, 38 block': dict(ARMOR=2000, BLOCK_VALUE=38),
    'synthetic shield 1500 armor, 28 block, +9 INT': dict(ARMOR=1500, BLOCK_VALUE=28, INT=9),
}
# (class, spec, level, better, worse)
PAIRS = [
    ('WARRIOR', 'FURY', 60, 'Lionheart Helm', 'Helm of Valor'),
    ('WARRIOR', 'ARMS', 60, 'Lionheart Helm', 'Helm of Valor'),
    ('WARRIOR', 'PROTECTION', 60, 'Helm of Valor', 'Lionheart Helm'),
    ('WARRIOR', 'ARMS', 60, 'Arcanite Reaper', "Executioner's Cleaver"),
    ('WARRIOR', 'PROTECTION', 60, 'Stockade Pauldrons', 'Truestrike Shoulders'),
    ('WARRIOR', 'FURY', 60, 'Truestrike Shoulders', 'Stockade Pauldrons'),
    ('WARRIOR', 'PROTECTION', 60, 'synthetic shield 2000 armor, 38 block', 'synthetic shield 1500 armor, 28 block, +9 INT'),
    ('WARRIOR', 'LEVELING', 25, 'synthetic 2H, 30 DPS', 'synthetic 2H, 26 DPS, +8 STR'),
    ('WARRIOR', 'ARMS', 35, 'synthetic 2H, 30 DPS', 'synthetic 2H, 26 DPS, +8 STR'),
    ('WARRIOR', 'LEVELING', 15, 'synthetic cloak of the Bear', 'synthetic cloak of the Eagle'),
    ('WARRIOR', 'ARMS', 30, 'synthetic ring +12 STA', 'synthetic ring +1% hit'),
    ('WARRIOR', 'ARMS', 60, 'synthetic ring +1% hit', 'synthetic ring +12 STA'),
    ('PALADIN', 'RETRIBUTION', 60, 'Lionheart Helm', 'Helm of Valor'),
    ('PALADIN', 'PROTECTION', 60, 'Stockade Pauldrons', 'Truestrike Shoulders'),
    ('PALADIN', 'HOLY', 60, 'Robes of the Exalted', 'Devout Robe'),
    ('PALADIN', 'HOLY', 60, 'synthetic ring +22 healing', 'synthetic ring +12 damage and healing'),
    ('PALADIN', 'LEVELING', 20, 'synthetic cloak of the Bear', 'synthetic cloak of the Whale'),
    ('HUNTER', 'MARKSMANSHIP', 60, 'Carapace Spine Crossbow', 'synthetic level-42 bow'),
    ('HUNTER', 'MARKSMANSHIP', 60, 'synthetic ring +10 AGI', 'synthetic ring +10 INT'),
    ('HUNTER', 'LEVELING', 22, 'synthetic cloak of the Monkey', 'synthetic cloak of the Bear'),
    ('HUNTER', 'BEAST_MASTERY', 30, 'synthetic cloak of the Monkey', 'synthetic cloak of the Whale'),
    ('ROGUE', 'COMBAT', 60, 'Devilsaur Gauntlets', 'Shadowcraft Gloves'),
    ('ROGUE', 'COMBAT', 60, 'Truestrike Shoulders', 'Stockade Pauldrons'),
    ('ROGUE', 'LEVELING', 18, 'synthetic cloak of the Monkey', 'synthetic cloak of the Bear'),
    ('ROGUE', 'SUBTLETY', 45, 'synthetic cloak of the Monkey', 'synthetic cloak of the Eagle'),
    ('PRIEST', 'HOLY', 60, 'Robes of the Exalted', 'Devout Robe'),
    ('PRIEST', 'DISCIPLINE', 60, 'synthetic ring +22 healing', 'synthetic ring +12 damage and healing'),
    ('PRIEST', 'SHADOW', 60, 'synthetic +21 Shadow ring', 'synthetic ring +12 damage and healing'),
    ('PRIEST', 'SHADOW', 60, 'synthetic ring +12 damage and healing', 'synthetic ring +22 healing'),
    ('PRIEST', 'LEVELING', 12, 'synthetic wand, 20 DPS', 'synthetic wand, 14 DPS, +3 INT'),
    ('PRIEST', 'LEVELING', 12, 'synthetic cloak of the Whale', 'synthetic cloak of the Bear'),
    ('SHAMAN', 'ELEMENTAL', 60, 'Robe of the Archmage', "Magister's Robes"),
    ('SHAMAN', 'RESTORATION', 60, 'Robes of the Exalted', 'Devout Robe'),
    ('SHAMAN', 'ENHANCEMENT', 60, 'Arcanite Reaper', "Executioner's Cleaver"),
    ('SHAMAN', 'ENHANCEMENT', 30, 'synthetic cloak of the Tiger', 'synthetic cloak of the Whale'),
    ('SHAMAN', 'ELEMENTAL', 30, 'synthetic cloak of the Eagle', 'synthetic cloak of the Tiger'),
    ('MAGE', 'FROST', 60, 'Robe of the Archmage', "Magister's Robes"),
    ('MAGE', 'FIRE', 60, 'synthetic +30 Fire ring', 'synthetic +30 Frost ring'),
    ('MAGE', 'FROST', 60, 'synthetic +30 Frost ring', 'synthetic +30 Fire ring'),
    ('MAGE', 'ARCANE', 60, 'synthetic ring +12 damage and healing', 'synthetic ring +10 INT'),
    ('MAGE', 'LEVELING', 15, 'synthetic cloak of the Eagle', 'synthetic cloak of the Bear'),
    ('MAGE', 'FROST', 25, 'synthetic wand, 20 DPS', 'synthetic wand, 14 DPS, +3 INT'),
    ('WARLOCK', 'AFFLICTION', 60, 'synthetic +21 Shadow ring', 'synthetic ring +12 damage and healing'),
    ('WARLOCK', 'DESTRUCTION', 60, 'Robe of the Archmage', "Magister's Robes"),
    ('WARLOCK', 'LEVELING', 20, 'synthetic cloak of the Eagle', 'synthetic cloak of the Tiger'),
    ('DRUID', 'BALANCE', 60, 'Robe of the Archmage', "Magister's Robes"),
    ('DRUID', 'FERAL_CAT', 60, 'synthetic ring +10 AGI', 'synthetic ring +10 INT'),
    ('DRUID', 'FERAL_BEAR', 60, 'synthetic ring +12 STA', 'synthetic ring +10 AGI'),
    ('DRUID', 'FERAL_CAT', 60, 'synthetic ring +10 AGI', 'synthetic ring +12 STA'),
    ('DRUID', 'RESTORATION', 60, 'synthetic ring +22 healing', 'synthetic ring +10 INT'),
    ('DRUID', 'LEVELING', 25, 'synthetic cloak of the Monkey', 'synthetic cloak of the Eagle'),
    ('DRUID', 'BALANCE', 35, 'synthetic cloak of the Eagle', 'synthetic cloak of the Monkey'),
]
bad = 0
for cls, spec, lvl, a, b in PAIRS:
    w = table(cls, spec, lvl)
    sa, sb = score(w, I[a]), score(w, I[b])
    ok = sa > sb
    bad += not ok
    print('%-4s %-8s %-13s L%-2d %7.1f > %7.1f  %s  >  %s' % ('ok' if ok else 'FAIL', cls, spec, lvl, sa, sb, a, b))
print('pairs: %d checked, %d failed' % (len(PAIRS), bad))
sys.exit(1 if (errors or bad) else 0)
