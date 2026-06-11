-- Presentation mapper; converts history entries and patches into renderable UI rows.
local Presenter = {}

local highlights = {
  add = "LineHistoryAdd",
  modify = "LineHistoryModify",
  delete = "LineHistoryDelete",
}

local function hunk_lines(patch)
  local lines = vim.split(patch or "", "\n", { plain = true })
  local result = {}

  for _, line in ipairs(lines) do
    if line:match("^@@") or line:match("^[%-%+ ]") then
      if not line:match("^%-%-%- ") and not line:match("^%+%+%+ ") then
        table.insert(result, line)
      end
    end
  end

  return result
end

local function flush_change_group(source, target, removed, added)
  local max_count = math.max(#removed, #added)

  for i = 1, max_count do
    local removed_line = removed[i]
    local added_line = added[i]

    if removed_line and added_line then
      table.insert(source, { text = removed_line, highlight = highlights.modify })
      table.insert(target, { text = added_line, highlight = highlights.modify })
    elseif removed_line then
      table.insert(source, { text = removed_line, highlight = highlights.delete })
      table.insert(target, { text = "" })
    elseif added_line then
      table.insert(source, { text = "" })
      table.insert(target, { text = added_line, highlight = highlights.add })
    end
  end
end

function Presenter.format_list_line(entry)
  return string.format("%-12s %-12s %-18s %s", entry.short_hash, entry.date, entry.author, entry.message)
end

function Presenter.side_by_side_items(patch)
  local source = {}
  local target = {}
  local removed = {}
  local added = {}

  local function flush()
    if #removed > 0 or #added > 0 then
      flush_change_group(source, target, removed, added)
      removed = {}
      added = {}
    end
  end

  for _, line in ipairs(hunk_lines(patch)) do
    if line:match("^@@") then
      flush()
      table.insert(source, { text = line })
      table.insert(target, { text = line })
    elseif line:sub(1, 1) == "-" then
      table.insert(removed, line:sub(2))
    elseif line:sub(1, 1) == "+" then
      table.insert(added, line:sub(2))
    elseif line:sub(1, 1) == " " then
      flush()
      table.insert(source, { text = line:sub(2) })
      table.insert(target, { text = line:sub(2) })
    end
  end

  flush()

  if #source == 0 and #target == 0 then
    source = { { text = "No patch content." } }
    target = { { text = "No patch content." } }
  end

  return source, target
end

return Presenter
