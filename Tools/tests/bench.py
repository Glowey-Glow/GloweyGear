"""A benchmark for Glowey's Gear at a real-size Auction House. Not a test: it prints timings.

    python -I Tools/tests/bench.py              this tree
    python -I Tools/tests/bench.py <folder>     another copy of the plugin (to compare before and after)
    python -I Tools/tests/bench.py --detail     also where the time went, by timer and by part

It runs Tools/tests/bench.lua in the stand-in world (this tree's mocks.lua) with the plugin's files
from the folder given. bench.lua's header says what house is simulated and what each game call is
assumed to cost. Needs `pip install lupa`. Takes a minute or two.
"""
import os
import sys
import time

import lupa.lua51 as lua51

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
ENGINE = ["Stats.lua", "Spec.lua", "Score.lua", "Compare.lua", "Rank.lua"]


def text(path):
    with open(path, encoding="utf-8") as handle:
        return handle.read()


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    root = os.path.abspath(args[0]) if args else ROOT
    state = lua51.LuaRuntime()
    compile_ = state.eval(
        "function(source, name) local f, err = loadstring(source, name) if not f then error(err, 0) end return f end")
    state.globals()["ADDON_ROOT"] = root.replace(os.sep, "/")
    state.globals()["BENCH_CLOCK"] = time.perf_counter
    state.globals()["BENCH_DETAIL"] = "--detail" in sys.argv
    compile_(text(os.path.join(HERE, "mocks.lua")), "@mocks.lua")()
    as_addon = state.eval("function(chunk, addon) return chunk(addon, NS) end")
    for name in ENGINE:
        as_addon(compile_(text(os.path.join(root, name)), "@" + name), "GloweyGear")
    started = time.time()
    print("plugin files from: " + root)
    print(compile_(text(os.path.join(HERE, "bench.lua")), "@bench.lua")())
    print("(the benchmark itself ran for %.0f s)" % (time.time() - started))


if __name__ == "__main__":
    main()
