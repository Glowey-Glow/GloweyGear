"""Offline tests for Glowey's Gear's engine: stats, specs, scores, comparisons and ranking.

    python -I Tools/tests/run.py              every Tools/tests/test_*.lua
    python -I Tools/tests/run.py test_rank    one test (with or without .lua)

Each test file runs in a Lua 5.1 state of its own (lupa): mocks.lua first (a stand-in for the
game that the test fills with items, worn gear, bags and talents), then the engine's files in the
order the .toc lists them, unchanged, then the test. Game.lua is NOT loaded: the mock takes its
place, which is the point of keeping every game call in that one file. Three tests load more on
their own: test_game.lua the real Game.lua over stand-in game calls, test_data.lua the real
Data/Weights.lua, and test_core.lua the locale table, the weights and Core.lua on a stand-in for
Daylight UI. A test passes when it
returns its "ok, N checks" line; a Lua error or a failed check fails it and names the case.
Needs `pip install lupa`. Not part of the zip players download (.pkgmeta ignores Tools).
"""
import glob
import os
import sys

import lupa.lua51 as lua51

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
ADDON = "DaylightGear"
# The engine, pure Lua. The .toc must list every one of these, in an order that works.
ENGINE = ["Stats.lua", "Spec.lua", "Score.lua", "Compare.lua", "Rank.lua"]


def text(path):
    with open(path, encoding="utf-8") as handle:
        return handle.read()


def in_toc_order():
    listed = [line.strip().replace("\\", "/") for line in text(os.path.join(ROOT, ADDON + ".toc")).splitlines()]
    listed = [line for line in listed if line and not line.startswith("#")]
    absent = [name for name in ENGINE if name not in listed]
    if absent:
        raise RuntimeError("missing from the .toc: " + ", ".join(absent))
    if "Game.lua" not in listed or listed.index("Game.lua") > min(listed.index(n) for n in ENGINE):
        raise RuntimeError("the .toc must load Game.lua before the engine")
    return sorted(ENGINE, key=listed.index)


def run_one(path):
    state = lua51.LuaRuntime()
    compile_ = state.eval(
        "function(source, name) local f, err = loadstring(source, name) if not f then error(err, 0) end return f end")
    state.globals()["ADDON_ROOT"] = ROOT.replace(os.sep, "/")
    compile_(text(os.path.join(HERE, "mocks.lua")), "@mocks.lua")()
    as_addon = state.eval("function(chunk, addon) return chunk(addon, NS) end")
    for name in in_toc_order():
        as_addon(compile_(text(os.path.join(ROOT, name)), "@" + name), ADDON)
    return compile_(text(path), "@" + os.path.basename(path))()


def main():
    asked = {a if a.endswith(".lua") else a + ".lua" for a in sys.argv[1:]}
    paths = sorted(glob.glob(os.path.join(HERE, "test_*.lua")))
    if asked:
        paths = [p for p in paths if os.path.basename(p) in asked]
    failed = 0
    for path in paths:
        name = os.path.basename(path)
        try:
            line = run_one(path)
            if not (isinstance(line, str) and line.startswith("ok")):
                raise RuntimeError("no ok line (got %r)" % (line,))
            print("PASS %-22s %s" % (name, line))
        except Exception as problem:  # a Lua error is a failed test, not a crash of the runner
            failed += 1
            print("FAIL %-22s %s" % (name, problem))
    print("%d test files, %d failed" % (len(paths), failed))
    sys.exit(1 if failed or not paths else 0)


if __name__ == "__main__":
    main()
