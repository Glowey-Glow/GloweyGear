-- luacheck config: run `luacheck .` from this folder.
std = "lua51"
max_line_length = false
exclude_files = { "Libs/", ".release/" }
-- Unused arguments and loop variables named _ or _name are placeholders.
ignore = { "212/_.*", "213/_.*" }

-- Globals this addon sets: its saved variables.
globals = {
	"GloweyGearDB",
}

-- The WoW client's API and constants this addon reads. Game.lua, Core.lua and Update.lua name
-- the rest of what they read in a line of their own, so a game call in an engine file stands out.
read_globals = {
	"GetLocale",
}

-- The offline tests: mocks.lua is the test world (it defines NS, WORLD and T and locks the
-- globals); the test files read those, and test_game.lua sets the game's globals on purpose.
files["Tools/tests/mocks.lua"] = { globals = { "NS", "WORLD", "T", "T_ident" }, read_globals = { "ADDON_ROOT" } }
files["Tools/tests/test_*.lua"] = { globals = { "NS", "WORLD", "T", "T_ident" }, read_globals = { "ADDON_ROOT" } }
files["Tools/tests/test_game.lua"] = { globals = { "NS", "WORLD", "T", "T_ident" }, read_globals = { "ADDON_ROOT" }, ignore = { "111", "112", "113", "121", "122", "212" } }
files["Tools/tests/test_core.lua"] = { globals = { "NS", "WORLD", "T", "T_ident" }, read_globals = { "ADDON_ROOT" }, ignore = { "111", "112", "113", "121", "122", "212" } }
