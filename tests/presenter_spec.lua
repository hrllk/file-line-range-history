dofile("tests/minimal_init.lua")

local Presenter = require("line-history.ui.presenter")

local line = Presenter.format_list_line({
  short_hash = "abcdef1",
  date = "2026-06-11",
  author = "Alice",
  message = "Change selected lines",
})
assert(line:match("abcdef1"), "formatted list line should include short hash")
assert(line:match("Alice"), "formatted list line should include author")
assert(line:match("Change selected lines"), "formatted list line should include message")

local source, target = Presenter.side_by_side_items([[
diff --git a/file b/file
--- a/file
+++ b/file
@@ -1,3 +1,3 @@
-old
+new
 context
]])

assert(source[1].text:match("^@@"), "first visible line should be hunk header")
assert(target[1].text:match("^@@"), "target should include hunk header")
assert(source[2].text == "old", "removed line should appear in source")
assert(source[2].highlight == "LineHistoryModify", "paired removed line should be modify")
assert(target[2].text == "new", "added line should appear in target")
assert(target[2].highlight == "LineHistoryModify", "paired added line should be modify")
assert(source[3].text == "context", "context should appear in source")
assert(target[3].text == "context", "context should appear in target")

local delete_source, delete_target = Presenter.side_by_side_items([[
@@ -1 +0,0 @@
-gone
]])
assert(delete_source[2].text == "gone", "deleted line should appear in source")
assert(delete_source[2].highlight == "LineHistoryDelete", "deleted line should use delete highlight")
assert(delete_target[2].text == "", "deleted target line should be blank")

local add_source, add_target = Presenter.side_by_side_items([[
@@ -0,0 +1 @@
+added
]])
assert(add_source[2].text == "", "added source line should be blank")
assert(add_target[2].text == "added", "added line should appear in target")
assert(add_target[2].highlight == "LineHistoryAdd", "added line should use add highlight")

local empty_source, empty_target = Presenter.side_by_side_items("")
assert(empty_source[1].text == "No patch content.", "empty source fallback should render")
assert(empty_target[1].text == "No patch content.", "empty target fallback should render")
