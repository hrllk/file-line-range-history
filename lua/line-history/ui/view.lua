-- Neovim view adapter; uses layout geometry to manage buffers and floating windows.
local Layout = require("line-history.ui.layout")

local View = {}
View.__index = View

local function set_lines(buf, lines)
  if not vim.api.nvim_buf_is_valid(buf) then
    return
  end

  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
end

local function set_items(buf, namespace, items)
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

local function start_treesitter(buf, enabled)
  local filetype = vim.bo[buf].filetype
  if not enabled or filetype == "" then
    return
  end

  local language = filetype
  if vim.treesitter.language and vim.treesitter.language.get_lang then
    language = vim.treesitter.language.get_lang(filetype) or filetype
  end

  pcall(vim.treesitter.start, buf, language)
end

local function open_float(config, buf, opts)
  opts = opts or {}
  local win_opts = {
    relative = "editor",
    row = opts.row,
    col = opts.col,
    width = opts.width,
    height = opts.height,
    border = config:window().border,
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

local function close_window(win)
  if win and vim.api.nvim_win_is_valid(win) then
    vim.api.nvim_win_close(win, true)
  end
end

local function delete_buffer(buf)
  if buf and vim.api.nvim_buf_is_valid(buf) then
    vim.api.nvim_buf_delete(buf, { force = true })
  end
end

local function scroll_window(win, delta)
  if not win or not vim.api.nvim_win_is_valid(win) then
    return
  end

  local cursor = vim.api.nvim_win_get_cursor(win)
  local line_count = vim.api.nvim_buf_line_count(vim.api.nvim_win_get_buf(win))
  local target = math.max(1, math.min(line_count, cursor[1] + delta))
  vim.api.nvim_win_set_cursor(win, { target, cursor[2] })
end

function View.new(config, namespace, title, filetype)
  local self = setmetatable({
    config = config,
    namespace = namespace,
    title = title,
    filetype = filetype,
    layout = Layout.new(config),
    buffers = {},
    wins = {},
  }, View)

  self:open()
  return self
end

function View:open()
  local layout = self.layout:calculate()

  self.buffers.source = create_buffer(self.filetype)
  self.buffers.target = create_buffer(self.filetype)
  self.buffers.list_header = create_buffer("")
  self.buffers.list = create_buffer("")

  start_treesitter(self.buffers.source, self.config:treesitter_enabled())
  start_treesitter(self.buffers.target, self.config:treesitter_enabled())

  self.wins.source = open_float(self.config, self.buffers.source, vim.tbl_extend("force", self.layout:window_config(layout, "source"), {
    title = " SOURCE ",
  }))
  self.wins.target = open_float(self.config, self.buffers.target, vim.tbl_extend("force", self.layout:window_config(layout, "target"), {
    title = " TARGET ",
  }))
  self.wins.list_header = open_float(self.config, self.buffers.list_header, vim.tbl_extend("force", self.layout:window_config(layout, "list_header"), {
    title = " " .. self.title .. " ",
  }))
  self.wins.list = open_float(self.config, self.buffers.list, vim.tbl_extend("force", self.layout:window_config(layout, "list"), {
    enter = true,
    cursorline = true,
  }))
end

function View:map(buffer_name, mode, lhs, rhs, opts)
  opts = opts or {}
  local silent = true
  if opts.silent ~= nil then
    silent = opts.silent
  end

  local map_opts = vim.tbl_extend("force", opts, {
    buffer = self.buffers[buffer_name],
    silent = silent,
  })
  vim.keymap.set(mode, lhs, rhs, map_opts)
end

function View:render_list(entries, selected, format_line)
  set_lines(self.buffers.list_header, {
    string.format("%-12s %-12s %-18s %s", "Version", "Date", "Author", "Commit Message"),
  })

  local lines = {}
  for _, entry in ipairs(entries) do
    table.insert(lines, format_line(entry))
  end

  set_lines(self.buffers.list, lines)

  if vim.api.nvim_win_is_valid(self.wins.list) then
    vim.api.nvim_win_set_cursor(self.wins.list, { selected, 0 })
  end
end

function View:render_preview(entry, source_items, target_items)
  set_items(self.buffers.source, self.namespace, source_items)
  set_items(self.buffers.target, self.namespace, target_items)

  if vim.api.nvim_win_is_valid(self.wins.source) then
    vim.api.nvim_win_set_config(self.wins.source, { title = " SOURCE " .. entry.parent_short_hash .. " " })
  end

  if vim.api.nvim_win_is_valid(self.wins.target) then
    vim.api.nvim_win_set_config(self.wins.target, { title = " TARGET " .. entry.short_hash .. " " })
  end
end

function View:resize()
  local layout = self.layout:calculate()
  for key, win in pairs(self.wins) do
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_set_config(win, self.layout:window_config(layout, key))
    end
  end
end

function View:preview_page_delta(direction)
  if not vim.api.nvim_win_is_valid(self.wins.source) then
    return direction
  end

  return direction * math.max(1, vim.api.nvim_win_get_height(self.wins.source) - 1)
end

function View:list_page_delta(direction)
  if not vim.api.nvim_win_is_valid(self.wins.list) then
    return direction
  end

  return direction * math.max(1, vim.api.nvim_win_get_height(self.wins.list) - 1)
end

function View:scroll_preview(delta)
  scroll_window(self.wins.source, delta)
  scroll_window(self.wins.target, delta)
end

function View:close()
  for _, win in pairs(self.wins) do
    close_window(win)
  end

  for _, buf in pairs(self.buffers) do
    delete_buffer(buf)
  end

  self.wins = {}
  self.buffers = {}
end

return View
