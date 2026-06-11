-- UI session controller; combines presentation data with the concrete Neovim view.
local Presenter = require("line-history.ui.presenter")
local View = require("line-history.ui.view")

local Session = {}
Session.__index = Session

function Session.new(config, namespace, entries, title, filetype, on_close)
  local self = setmetatable({
    config = config,
    namespace = namespace,
    entries = entries,
    selected = 1,
    view = nil,
    closed = false,
    on_close = on_close,
  }, Session)

  self.view = View.new(config, namespace, title, filetype)
  self:install_keymaps()
  self:render()

  return self
end

function Session:install_keymaps()
  for _, buffer_name in ipairs({ "source", "target", "list_header", "list" }) do
    for _, lhs in ipairs({ "q", "<Esc>" }) do
      self.view:map(buffer_name, "n", lhs, function()
        self:close()
      end, { desc = "Close line history" })
    end
  end

  for _, buffer_name in ipairs({ "source", "target" }) do
    for lhs, direction in pairs({ ["<C-d>"] = 1, ["<C-u>"] = -1 }) do
      self.view:map(buffer_name, "n", lhs, function()
        self:scroll_preview(direction)
      end, { desc = "Scroll line-history preview" })
    end
  end

  for lhs, delta in pairs({
    j = 1,
    ["<Down>"] = 1,
    k = -1,
    ["<Up>"] = -1,
  }) do
    self.view:map("list", "n", lhs, function()
      self:select(delta)
    end, { desc = "Select line-history commit" })
  end

  for lhs, direction in pairs({ ["<PageDown>"] = 1, ["<PageUp>"] = -1 }) do
    self.view:map("list", "n", lhs, function()
      self:select(self.view:list_page_delta(direction))
    end, { desc = "Page line-history commits" })
  end

  for lhs, direction in pairs({ ["<C-d>"] = 1, ["<C-u>"] = -1 }) do
    self.view:map("list", "n", lhs, function()
      self:scroll_preview(direction)
    end, { desc = "Scroll line-history preview" })
  end
end

function Session:select(delta)
  if self.closed then
    return
  end

  self.selected = math.max(1, math.min(#self.entries, self.selected + delta))
  self:render()
end

function Session:scroll_preview(direction)
  if self.closed then
    return
  end

  self.view:scroll_preview(self.view:preview_page_delta(direction))
end

function Session:render()
  if self.closed then
    return
  end

  local entry = self.entries[self.selected]
  local source_items, target_items = Presenter.side_by_side_items(entry.patch)

  self.view:render_preview(entry, source_items, target_items)
  self.view:render_list(self.entries, self.selected, Presenter.format_list_line)
end

function Session:resize()
  if self.closed then
    return
  end

  self.view:resize()
  self.view:render_list(self.entries, self.selected, Presenter.format_list_line)
end

function Session:close()
  if self.closed then
    return
  end

  self.closed = true
  self.view:close()

  if self.on_close then
    self.on_close(self)
  end
end

return Session
