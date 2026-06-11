-- Application wiring: coordinates config, context, Git access, and UI session lifecycle.
local Config = require("line-history.config")
local Context = require("line-history.context")
local Git = require("line-history.git")
local Session = require("line-history.ui.session")

local App = {}
App.__index = App

function App.new(opts)
  return setmetatable({
    config = Config.new(opts),
    context = Context.new(),
    namespace = vim.api.nvim_create_namespace("line-history"),
    session = nil,
  }, App)
end

function App:setup()
  self.config:apply_highlights()
  self:register_autocmds()
  self:register_command()
  self:register_keymap()
end

function App:notify(message, level)
  vim.notify(message, level or vim.log.levels.INFO, { title = "line-history" })
end

function App:show(opts)
  opts = opts or {}

  local file, file_err = self.context:current_file()
  if file_err then
    self:notify(file_err, vim.log.levels.WARN)
    return
  end

  local range, range_err = self:resolve_range(opts)
  if range_err then
    self:notify(range_err, vim.log.levels.WARN)
    return
  end

  local root, root_err = self.context:git_root(file)
  if root_err then
    self:notify(root_err, vim.log.levels.ERROR)
    return
  end

  local rel_file = self.context:relative_path(root, file)
  local entries, history_err = Git.new(root, self.config):line_history(rel_file, range)
  if history_err then
    self:notify(history_err, vim.log.levels.ERROR)
    return
  end

  if #entries == 0 then
    self:notify("No Git history was found for the selected line range.", vim.log.levels.INFO)
    return
  end

  self:open_session(entries, range:to_title(rel_file), self.context:filetype())
end

function App:resolve_range(opts)
  if opts.start_line and opts.end_line then
    return self.context:normalize_range(opts.start_line, opts.end_line)
  end

  return self.context:visual_range()
end

function App:open_session(entries, title, filetype)
  self:close_session()
  self.session = Session.new(self.config, self.namespace, entries, title, filetype, function(session)
    if self.session == session then
      self.session = nil
    end
  end)
end

function App:close_session()
  if self.session then
    self.session:close()
    self.session = nil
  end
end

function App:resize_session()
  if self.session then
    self.session:resize()
  end
end

function App:register_autocmds()
  local group = vim.api.nvim_create_augroup("LineHistory", { clear = true })
  vim.api.nvim_create_autocmd("VimResized", {
    group = group,
    callback = function()
      self:resize_session()
    end,
  })
end

function App:register_command()
  vim.api.nvim_create_user_command(self.config:command(), function(command)
    self:show({ start_line = command.line1, end_line = command.line2 })
  end, { range = true, desc = "Show Git history for the selected line range" })
end

function App:register_keymap()
  local keymap = self.config:keymap()
  if not keymap then
    return
  end

  vim.keymap.set("x", keymap, function()
    vim.cmd("'<,'>" .. self.config:command())
  end, { silent = true, desc = "Git line range history" })
end

return App
