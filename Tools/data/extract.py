# Reads EP weight presets out of a wowsims/forever checkout (text only, nothing is executed).
# usage: python -I extract.py <repo dir> <out.json>
import sys, re, json, os

repo, out = sys.argv[1], sys.argv[2]

FILES = [
    'ui/specs/druid/balance/presets.ts',
    'ui/specs/druid/feral_ep.ts',
    'ui/specs/hunter/dps/presets.ts',
    'ui/specs/paladin/retribution/presets.ts',
    'ui/specs/priest/dps/presets.ts',
    'ui/specs/priest/healer/presets.ts',
    'ui/specs/rogue/dps/presets.ts',
    'ui/specs/shaman/elemental/presets.ts',
    'ui/specs/shaman/enhancement/presets.ts',
    'ui/specs/warrior/dps/presets.ts',
    'ui/specs/warrior/protection/presets.ts',
]

CONST = {'Mechanics.HIT_RATING_PER_HIT_PERCENT': 10.0}
NUM = r'[0-9]+(?:\.[0-9]+)?'


def block_end(text, start):
    depth = 0
    for i in range(start, len(text)):
        c = text[i]
        if c == '(':
            depth += 1
        elif c == ')':
            depth -= 1
            if depth == 0:
                return i
    raise ValueError('unbalanced')


def value(expr):
    expr = expr.strip()
    m = re.fullmatch(r'(%s)\s*\*\s*([A-Za-z_.]+)' % NUM, expr)
    if m:
        return float(m.group(1)) * CONST[m.group(2)]
    return float(expr)


result = {}
for rel in FILES:
    text = open(os.path.join(repo, rel), encoding='utf-8').read()
    for m in re.finditer(r"export const (\w+) = (?:PresetUtils\.makePresetEpWeights\(\s*'([^']*)',\s*)?Stats\.fromMap\(", text):
        start = text.index('Stats.fromMap(', m.start()) + len('Stats.fromMap')
        body = text[start:block_end(text, start) + 1]
        stats = {}
        for k, v in re.findall(r'\[(?:Stat|PseudoStat)\.(\w+)\]:\s*([^,\n]+),', body):
            stats[k] = value(v)
        result[rel + '#' + m.group(1)] = {'label': m.group(2), 'stats': stats}

json.dump(result, open(out, 'w', encoding='utf-8'), indent=1, sort_keys=True)
for k, v in sorted(result.items()):
    print(k, len(v['stats']))
