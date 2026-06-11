dofile("tests/minimal_init.lua")

local Config = require("line-history.config")
local Context = require("line-history.context")
local Git = require("line-history.git")

local config = Config.new({
  git = {
    extra_args = { "--patch", "--no-ext-diff" },
  },
})
local git = Git.new("/repo", config)
local range = assert(Context.new():normalize_range(1, 4))
local args = git:build_log_args("lua/example.lua", range)

assert(args[1] == "git", "first arg should be git")
assert(args[2] == "-C", "second arg should be -C")
assert(args[3] == "/repo", "root should be passed to git -C")
assert(args[4] == "log", "git subcommand should be log")
assert(args[5] == "--date=short", "date format should be preserved")
assert(args[6]:match("^%-%-format="), "format arg should be present")
assert(args[7] == "-L", "-L arg should be present")
assert(args[8] == "1,4:lua/example.lua", "line range should match git -L format")
assert(args[9] == "--patch", "extra git args should be appended")
assert(args[10] == "--no-ext-diff", "all extra git args should be appended")

assert(#git:parse_history("") == 0, "empty output should parse to no entries")

local output = Git.RECORD_SEPARATOR
  .. "abcdef123456"
  .. Git.FIELD_SEPARATOR
  .. "abcdef1"
  .. Git.FIELD_SEPARATOR
  .. "1234567890 parent2"
  .. Git.FIELD_SEPARATOR
  .. "Alice"
  .. Git.FIELD_SEPARATOR
  .. "2026-06-11"
  .. Git.FIELD_SEPARATOR
  .. "Change selected lines"
  .. "\n@@ -1 +1 @@\n-old\n+new\n"

local entries = git:parse_history(output)
assert(#entries == 1, "one valid record should parse")
assert(entries[1].hash == "abcdef123456", "hash should parse")
assert(entries[1].short_hash == "abcdef1", "short hash should parse")
assert(entries[1].parent_hash == "1234567890", "first parent hash should parse")
assert(entries[1].parent_short_hash == "1234567", "parent short hash should be seven chars")
assert(entries[1].author == "Alice", "author should parse")
assert(entries[1].date == "2026-06-11", "date should parse")
assert(entries[1].message == "Change selected lines", "message should parse")
assert(entries[1].patch:match("%+new"), "patch should parse")

local root_output = Git.RECORD_SEPARATOR
  .. "root"
  .. Git.FIELD_SEPARATOR
  .. "root123"
  .. Git.FIELD_SEPARATOR
  .. ""
  .. Git.FIELD_SEPARATOR
  .. "Bob"
  .. Git.FIELD_SEPARATOR
  .. "2026-06-11"
  .. Git.FIELD_SEPARATOR
  .. "Initial"

local root_entries = git:parse_history(root_output)
assert(root_entries[1].parent_short_hash == "empty", "root commit parent should render as empty")

local malformed = Git.RECORD_SEPARATOR .. "too" .. Git.FIELD_SEPARATOR .. "short"
assert(#git:parse_history(malformed) == 0, "malformed record should be skipped")
