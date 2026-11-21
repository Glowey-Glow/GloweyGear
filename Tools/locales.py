"""Checks Glowey's Gear's language files against the code.

    python -I Tools/locales.py

For each of the six languages: every L["..."] key the code uses has a line, no line is left over
(a key the code no longer uses), and each translation has the same string.format holes as its
English key, in the same order. Keys ending in "#few" (Russian's third plural form) may exist in
ruRU.lua only. Exits 1 on any finding. Not part of the zip players download.
"""
import glob
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LANGS = ["deDE", "esES", "frFR", "koKR", "ruRU", "zhCN"]
USE = re.compile(r'L\["((?:[^"\\]|\\.)*)"\]')
LINE = re.compile(r'^L\["((?:[^"\\]|\\.)*)"\]\s*=\s*"((?:[^"\\]|\\.)*)"\s*$')
HOLE = re.compile(r"%[-+ #0]*\d*(?:\.\d+)?[a-zA-Z%]")


def used_keys():
    keys = {}
    for path in glob.glob(os.path.join(ROOT, "*.lua")):
        with open(path, encoding="utf-8") as handle:
            for number, line in enumerate(handle, 1):
                if line.lstrip().startswith("--"):
                    continue
                for key in USE.findall(line):
                    keys.setdefault(key, "%s:%d" % (os.path.basename(path), number))
    return keys


def main():
    used = used_keys()
    findings = 0
    for lang in LANGS:
        have = {}
        with open(os.path.join(ROOT, "Locales", lang + ".lua"), encoding="utf-8") as handle:
            for line in handle:
                match = LINE.match(line.rstrip("\n"))
                if match:
                    if match.group(1) in have:
                        findings += 1
                        print("%s: twice: %s" % (lang, match.group(1)))
                    have[match.group(1)] = match.group(2)
        for key, where in sorted(used.items()):
            if key.endswith("#few") and lang != "ruRU":
                continue
            if key not in have:
                findings += 1
                print("%s: missing (%s): %s" % (lang, where, key))
        for key, value in sorted(have.items()):
            if key not in used:
                findings += 1
                print("%s: not used by the code: %s" % (lang, key))
            base = key[:-4] if key.endswith("#few") else key
            if HOLE.findall(base) != HOLE.findall(value):
                findings += 1
                print("%s: format holes differ: %s" % (lang, key))
            if not value.strip():
                findings += 1
                print("%s: empty: %s" % (lang, key))
    print("%d keys in the code, %d languages, %d findings" % (len(used), len(LANGS), findings))
    sys.exit(1 if findings else 0)


if __name__ == "__main__":
    main()
