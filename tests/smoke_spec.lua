dofile("tests/minimal_init.lua")

local line_history = require("line-history")

line_history.setup({ keymap = false })
assert(vim.fn.exists(":LineHistory") == 2, "LineHistory command should be registered")

line_history.show({ start_line = 1, end_line = 1 })
assert(vim.g.line_history_last_notify.message == "The current buffer is not backed by a file.", "show should fail cleanly without file buffer")
