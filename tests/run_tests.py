"""Run OpenXP's Lua unit tests outside the game.

Needs `pip install lupa`. Uses LuaJIT (Lua 5.1, like WoW) when available.
"""
import os
import sys

try:
    from lupa import luajit21 as lupa_mod
except ImportError:
    import lupa as lupa_mod

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
rt = lupa_mod.LuaRuntime()
print(rt.eval("_VERSION"))
failures = 0
for name in sorted(os.listdir(os.path.join(ROOT, "tests"))):
    if not name.endswith("_test.lua"):
        continue
    print(f"== {name}")
    rt = lupa_mod.LuaRuntime()  # fresh globals for each test file
    with open(os.path.join(ROOT, "tests", name), encoding="utf-8") as f:
        fn = rt.execute("return function(src, root) return assert(loadstring(src))(root) end")
        failures += int(fn(f.read(), ROOT) or 0)
print("== route_frozen.py")
import subprocess
failures += subprocess.call([sys.executable, os.path.join(ROOT, "tests", "route_frozen.py")])
print("== convert_roundtrip.py")
failures += subprocess.call([sys.executable, os.path.join(ROOT, "tests", "convert_roundtrip.py")])
print("== guide_places.py")
failures += subprocess.call([sys.executable, os.path.join(ROOT, "tests", "guide_places.py")])
sys.exit(1 if failures else 0)
