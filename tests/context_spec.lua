dofile("tests/minimal_init.lua")

local Context = require("line-history.context")

local context = Context.new()

local range = assert(context:normalize_range(3, 7))
assert(range.start_line == 3, "start line should be preserved")
assert(range.end_line == 7, "end line should be preserved")
assert(range:to_git_spec("lua/example.lua") == "3,7:lua/example.lua", "git range spec should match git -L format")
assert(range:to_title("lua/example.lua") == "lua/example.lua:3-7", "title should include file and range")

local reversed = assert(context:normalize_range(9, 2))
assert(reversed.start_line == 2, "reversed range should normalize start")
assert(reversed.end_line == 9, "reversed range should normalize end")

local missing, err = context:normalize_range(nil, 1)
assert(missing == nil, "nil range should fail")
assert(type(err) == "string" and err ~= "", "nil range should return an error")

local zero, zero_err = context:normalize_range(0, 1)
assert(zero == nil, "zero range should fail")
assert(type(zero_err) == "string" and zero_err ~= "", "zero range should return an error")
