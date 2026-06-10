local M = {}

local defaults = {
  keymap = "<leader>gH",
  command = "LineHistory",
  git = {
    extra_args = { "--patch", "--no-ext-diff" },
  },
  window = {
    width = 0.9,
    height = 0.85,
    border = "rounded",
    preview_ratio = 0.68,
  },
  highlight = {
    add = { fg = "#7ee787", bg = "#123d2b" },
    modify = { fg = "#79c0ff", bg = "#14354f" },
    delete = { fg = "#8b949e", bg = "#2d333b" },
  },
  treesitter = {
    enabled = true,
  },
}

local config = vim.deepcopy(defaults)
local state = nil
local namespace = vim.api.nvim_create_namespace("line-history")

local RECORD_SEPARATOR = string.char(31)
local FIELD_SEPARATOR = string.char(0)

local function merge_config(opts)
  config = vim.tbl_deep_extend("force", vim.deepcopy(defaults), opts or {})
end

local function setup_highlights()
  vim.api.nvim_set_hl(0, "LineHistoryAdd", config.highlight.add)
  vim.api.nvim_set_hl(0, "LineHistoryModify", config.highlight.modify)
  vim.api.nvim_set_hl(0, "LineHistoryDelete", config.highlight.delete)
end

local function notify(message, level)
  vim.notify(message, level or vim.log.levels.INFO, { title = "line-history" })
end

local function current_file()
  local file = vim.api.nvim_buf_get_name(0)
  if file == "" then
    return nil, "현재 버퍼가 파일에 연결되어 있지 않습니다."
  end

  if vim.bo.buftype ~= "" then
    return nil, "일반 파일 버퍼에서만 사용할 수 있습니다."
  end

  return file, nil
end

local function git_root(file)
  local result = vim.system({ "git", "-C", vim.fs.dirname(file), "rev-parse", "--show-toplevel" }, { text = true }):wait()
  if result.code ~= 0 then
    return nil, vim.trim(result.stderr or "Git 저장소를 찾을 수 없습니다.")
  end

  return vim.trim(result.stdout), nil
end

local function relative_path(root, file)
  if vim.startswith(file, root .. "/") then
    return file:sub(#root + 2)
  end

  return vim.fn.fnamemodify(file, ":.")
end

local function visual_range()
  local start_pos = vim.fn.getpos("'<")
  local end_pos = vim.fn.getpos("'>")
  local start_line = start_pos[2]
  local end_line = end_pos[2]

  if start_line == 0 or end_line == 0 then
    return nil, nil, "visual mode에서 라인을 선택한 뒤 실행해주세요."
  end

  if start_line > end_line then
    start_line, end_line = end_line, start_line
  end

  return start_line, end_line, nil
end

local function set_lines(buf, lines)
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
end

local function set_items(buf, items)
  local lines = vim.tbl_map(function(item)
    return item.text
  end, items)

  set_lines(buf, lines)
  vim.api.nvim_buf_clear_namespace(buf, namespace, 0, -1)

  for idx, item in ipairs(items) do
    if item.highlight then
      vim.api.nvim_buf_set_extmark(buf, namespace, idx - 1, 0, {
        end_col = #item.text,
        hl_group = item.highlight,
        hl_eol = true,
        hl_mode = "combine",
        priority = 200,
      })
    end
  end
end

local function create_buffer(filetype)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].filetype = filetype or ""
  return buf
end

local function start_treesitter(buf, filetype)
  if not config.treesitter.enabled or filetype == "" then
    return
  end

  local language = filetype
  if vim.treesitter.language and vim.treesitter.language.get_lang then
    language = vim.treesitter.language.get_lang(filetype) or filetype
  end

  pcall(vim.treesitter.start, buf, language)
end

local function open_float(buf, opts)
  local win_opts = {
    relative = "editor",
    row = opts.row,
    col = opts.col,
    width = opts.width,
    height = opts.height,
    border = config.window.border,
    title = opts.title,
    style = "minimal",
  }

  if opts.title then
    win_opts.title_pos = "center"
  end

  local win = vim.api.nvim_open_win(buf, opts.enter or false, win_opts)

  vim.wo[win].wrap = false
  vim.wo[win].number = false
  vim.wo[win].relativenumber = false
  vim.wo[win].signcolumn = "no"
  vim.wo[win].cursorline = opts.cursorline or false

  return win
end

local function close_state()
  if not state then
    return
  end

  for _, win in pairs(state.wins or {}) do
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
  end

  state = nil
end

local function set_close_maps(buf)
  for _, lhs in ipairs({ "q", "<Esc>" }) do
    vim.keymap.set("n", lhs, close_state, { buffer = buf, silent = true, desc = "Close line history" })
  end
end

local function run_git_log(root, file, start_line, end_line)
  local range = string.format("%d,%d:%s", start_line, end_line, file)
  local args = {
    "git",
    "-C",
    root,
    "log",
    "--date=short",
    "--format=" .. RECORD_SEPARATOR .. "%H%x00%h%x00%P%x00%an%x00%ad%x00%s",
    "-L",
    range,
  }

  for _, arg in ipairs(config.git.extra_args or {}) do
    table.insert(args, arg)
  end

  return vim.system(args, { text = true }):wait()
end

local function parse_history(output)
  local entries = {}

  for block in output:gmatch(RECORD_SEPARATOR .. "([^" .. RECORD_SEPARATOR .. "]*)") do
    local first_newline = block:find("\n", 1, true)
    local metadata = first_newline and block:sub(1, first_newline - 1) or block
    local patch = first_newline and block:sub(first_newline + 1) or ""
    local fields = vim.split(metadata, FIELD_SEPARATOR, { plain = true })

    if #fields >= 6 then
      local parent_hash = vim.split(fields[3], " ", { plain = true })[1] or ""

      table.insert(entries, {
        hash = fields[1],
        short_hash = fields[2],
        parent_hash = parent_hash,
        parent_short_hash = parent_hash == "" and "empty" or parent_hash:sub(1, 7),
        author = fields[4],
        date = fields[5],
        message = fields[6],
        patch = patch,
      })
    end
  end

  return entries
end

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

local function flush_change_group(asis, tobe, removed, added)
  local max_count = math.max(#removed, #added)

  for i = 1, max_count do
    local removed_line = removed[i]
    local added_line = added[i]

    if removed_line and added_line then
      table.insert(asis, { text = removed_line, highlight = "LineHistoryModify" })
      table.insert(tobe, { text = added_line, highlight = "LineHistoryModify" })
    elseif removed_line then
      table.insert(asis, { text = removed_line, highlight = "LineHistoryDelete" })
      table.insert(tobe, { text = "", highlight = nil })
    elseif added_line then
      table.insert(asis, { text = "", highlight = nil })
      table.insert(tobe, { text = added_line, highlight = "LineHistoryAdd" })
    end
  end
end

local function side_by_side_items(patch)
  local asis = {}
  local tobe = {}
  local removed = {}
  local added = {}

  local function flush()
    if #removed > 0 or #added > 0 then
      flush_change_group(asis, tobe, removed, added)
      removed = {}
      added = {}
    end
  end

  for _, line in ipairs(hunk_lines(patch)) do
    if line:match("^@@") then
      flush()
      table.insert(asis, { text = line, highlight = nil })
      table.insert(tobe, { text = line, highlight = nil })
    elseif line:sub(1, 1) == "-" then
      table.insert(removed, line:sub(2))
    elseif line:sub(1, 1) == "+" then
      table.insert(added, line:sub(2))
    elseif line:sub(1, 1) == " " then
      flush()
      table.insert(asis, { text = line:sub(2), highlight = nil })
      table.insert(tobe, { text = line:sub(2), highlight = nil })
    end
  end

  flush()

  if #asis == 0 and #tobe == 0 then
    asis = { { text = "No patch content.", highlight = nil } }
    tobe = { { text = "No patch content.", highlight = nil } }
  end

  return asis, tobe
end

local function format_list_line(entry)
  return string.format("%-12s %-12s %-18s %s", entry.short_hash, entry.date, entry.author, entry.message)
end

local function render_list()
  set_lines(state.bufs.list_header, {
    string.format("%-12s %-12s %-18s %s", "Version", "Date", "Author", "Commit Message"),
  })

  local lines = {}

  for _, entry in ipairs(state.entries) do
    table.insert(lines, format_list_line(entry))
  end

  set_lines(state.bufs.list, lines)

  if vim.api.nvim_win_is_valid(state.wins.list) then
    vim.api.nvim_win_set_cursor(state.wins.list, { state.selected, 0 })
  end
end

local function render_preview()
  local entry = state.entries[state.selected]
  local asis, tobe = side_by_side_items(entry.patch)

  set_items(state.bufs.asis, asis)
  set_items(state.bufs.tobe, tobe)

  if vim.api.nvim_win_is_valid(state.wins.asis) then
    vim.api.nvim_win_set_config(state.wins.asis, { title = " SOURCE " .. entry.parent_short_hash .. " " })
  end
  if vim.api.nvim_win_is_valid(state.wins.tobe) then
    vim.api.nvim_win_set_config(state.wins.tobe, { title = " TARGET " .. entry.short_hash .. " " })
  end
end

local function select_entry(delta)
  state.selected = math.max(1, math.min(#state.entries, state.selected + delta))
  render_preview()
  render_list()
end

local function scroll_window(win, delta)
  if not vim.api.nvim_win_is_valid(win) then
    return
  end

  local cursor = vim.api.nvim_win_get_cursor(win)
  local line_count = vim.api.nvim_buf_line_count(vim.api.nvim_win_get_buf(win))
  local target = math.max(1, math.min(line_count, cursor[1] + delta))
  vim.api.nvim_win_set_cursor(win, { target, cursor[2] })
end

local function scroll_preview(direction)
  local delta = direction * math.max(1, vim.api.nvim_win_get_height(state.wins.asis) - 1)

  scroll_window(state.wins.asis, delta)
  scroll_window(state.wins.tobe, delta)
end

local function set_preview_maps()
  for _, buf in ipairs({ state.bufs.asis, state.bufs.tobe }) do
    for lhs, direction in pairs({ ["<C-d>"] = 1, ["<C-u>"] = -1 }) do
      vim.keymap.set("n", lhs, function()
        scroll_preview(direction)
      end, { buffer = buf, silent = true, desc = "Scroll line-history preview" })
    end
  end
end

local function set_list_maps()
  local maps = {
    j = 1,
    ["<Down>"] = 1,
    k = -1,
    ["<Up>"] = -1,
  }

  for lhs, delta in pairs(maps) do
    vim.keymap.set("n", lhs, function()
      select_entry(delta)
    end, { buffer = state.bufs.list, silent = true, desc = "Select line-history commit" })
  end

  local function page_delta(direction)
    return direction * math.max(1, vim.api.nvim_win_get_height(state.wins.list) - 1)
  end

  for lhs, direction in pairs({ ["<PageDown>"] = 1, ["<PageUp>"] = -1 }) do
    vim.keymap.set("n", lhs, function()
      select_entry(page_delta(direction))
    end, { buffer = state.bufs.list, silent = true, desc = "Page line-history commits" })
  end

  for lhs, direction in pairs({ ["<C-d>"] = 1, ["<C-u>"] = -1 }) do
    vim.keymap.set("n", lhs, function()
      scroll_preview(direction)
    end, { buffer = state.bufs.list, silent = true, desc = "Scroll line-history preview" })
  end

  set_close_maps(state.bufs.list)
end

local function open_layout(entries, title, filetype)
  close_state()

  local total_width = math.max(80, math.floor(vim.o.columns * config.window.width))
  local total_height = math.max(20, math.floor((vim.o.lines - vim.o.cmdheight) * config.window.height))
  local row = math.max(0, math.floor((vim.o.lines - total_height) / 2))
  local col = math.max(0, math.floor((vim.o.columns - total_width) / 2))
  local preview_height = math.max(8, math.floor(total_height * config.window.preview_ratio))
  local list_header_height = 1
  local list_height = math.max(5, total_height - preview_height - list_header_height - 6)
  local left_width = math.floor((total_width - 2) / 2)
  local right_width = total_width - left_width - 2

  state = {
    entries = entries,
    selected = 1,
    bufs = {
      asis = create_buffer(filetype),
      tobe = create_buffer(filetype),
      list_header = create_buffer(""),
      list = create_buffer(""),
    },
    wins = {},
  }
  start_treesitter(state.bufs.asis, filetype)
  start_treesitter(state.bufs.tobe, filetype)

  state.wins.asis = open_float(state.bufs.asis, {
    row = row,
    col = col,
    width = left_width,
    height = preview_height,
    title = " SOURCE ",
  })
  state.wins.tobe = open_float(state.bufs.tobe, {
    row = row,
    col = col + left_width + 2,
    width = right_width,
    height = preview_height,
    title = " TARGET ",
  })
  state.wins.list_header = open_float(state.bufs.list_header, {
    row = row + preview_height + 2,
    col = col,
    width = total_width,
    height = list_header_height,
    title = " " .. title .. " ",
  })
  state.wins.list = open_float(state.bufs.list, {
    row = row + preview_height + list_header_height + 4,
    col = col,
    width = total_width,
    height = list_height,
    enter = true,
    cursorline = true,
  })

  set_close_maps(state.bufs.asis)
  set_close_maps(state.bufs.tobe)
  set_close_maps(state.bufs.list_header)
  set_preview_maps()
  set_list_maps()

  render_preview()
  render_list()
end

function M.show()
  local file, file_err = current_file()
  if file_err then
    notify(file_err, vim.log.levels.WARN)
    return
  end

  local start_line, end_line, range_err = visual_range()
  if range_err then
    notify(range_err, vim.log.levels.WARN)
    return
  end

  local root, root_err = git_root(file)
  if root_err then
    notify(root_err, vim.log.levels.ERROR)
    return
  end

  local rel_file = relative_path(root, file)
  local filetype = vim.bo.filetype
  local result = run_git_log(root, rel_file, start_line, end_line)
  if result.code ~= 0 then
    notify(vim.trim(result.stderr or "git log -L 실행에 실패했습니다."), vim.log.levels.ERROR)
    return
  end

  local entries = parse_history(result.stdout or "")
  if #entries == 0 then
    notify("선택한 라인 범위의 Git 이력을 찾지 못했습니다.", vim.log.levels.INFO)
    return
  end

  open_layout(entries, string.format("%s:%d-%d", rel_file, start_line, end_line), filetype)
end

function M.setup(opts)
  merge_config(opts)
  setup_highlights()

  vim.api.nvim_create_user_command(config.command, function()
    M.show()
  end, { range = true, desc = "Show Git history for the selected line range" })

  if config.keymap then
    vim.keymap.set("x", config.keymap, function()
      vim.cmd("normal! gv")
      M.show()
    end, { silent = true, desc = "Git line range history" })
  end
end

return M
