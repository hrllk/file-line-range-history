dofile("tests/minimal_init.lua")

local Config = require("line-history.config")

local defaults = Config.new({})
assert(defaults:keymap() == "<leader>gflh", "default keymap should be preserved")
assert(defaults:command() == "LineHistory", "default command should be preserved")
assert(defaults:window().border == "rounded", "default window border should be preserved")
assert(defaults:treesitter_enabled() == true, "treesitter should be enabled by default")

local custom = Config.new({
  keymap = false,
  window = {
    width = 0.5,
  },
  git = {
    extra_args = { "--patch" },
  },
})

assert(custom:keymap() == false, "false keymap should be preserved")
assert(custom:window().width == 0.5, "custom nested window option should override default")
assert(custom:window().height == 0.85, "deep merge should preserve unspecified nested defaults")
assert(#custom:git_extra_args() == 1, "custom git extra args should override default")
