dofile("tests/minimal_init.lua")

local Config = require("line-history.config")
local Layout = require("line-history.ui.layout")

local original_columns = vim.o.columns
local original_lines = vim.o.lines
local original_cmdheight = vim.o.cmdheight

vim.o.columns = 120
vim.o.lines = 40
vim.o.cmdheight = 1

local layout = Layout.new(Config.new({})):calculate()
assert(layout.total_width == 108, "total width should follow configured ratio")
assert(layout.total_height == 33, "total height should follow configured ratio")
assert(layout.left_width >= 1, "left width should be positive")
assert(layout.right_width >= 1, "right width should be positive")
assert(layout.preview_height >= 4, "preview height should respect minimum")
assert(layout.list_height >= 3, "list height should respect minimum")

local layout_obj = Layout.new(Config.new({}))
assert(layout_obj:window_config(layout, "source").width == layout.left_width, "source window should use left width")
assert(layout_obj:window_config(layout, "target").width == layout.right_width, "target window should use right width")
assert(layout_obj:window_config(layout, "list_header").height == 1, "list header should be one line")
assert(layout_obj:window_config(layout, "list").height == layout.list_height, "list window should use list height")

vim.o.columns = 10
vim.o.lines = 5
vim.o.cmdheight = 1

local small = Layout.new(Config.new({})):calculate()
assert(small.total_width >= 20, "small layout should clamp width to minimum")
assert(small.total_height >= 12, "small layout should clamp height to minimum")
assert(small.preview_height >= 4, "small preview should keep minimum height")
assert(small.list_height >= 3, "small list should keep minimum height")

vim.o.columns = original_columns
vim.o.lines = original_lines
vim.o.cmdheight = original_cmdheight
