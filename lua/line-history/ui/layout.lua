-- Layout calculator; converts editor dimensions and window options into pane geometry.
local Layout = {}
Layout.__index = Layout

function Layout.new(config)
  return setmetatable({ config = config }, Layout)
end

function Layout:calculate()
  local window = self.config:window()
  local available_width = math.max(20, vim.o.columns)
  local available_height = math.max(12, vim.o.lines - vim.o.cmdheight)
  local total_width = math.floor(available_width * window.width)
  local total_height = math.floor(available_height * window.height)

  total_width = math.max(20, math.min(available_width, total_width))
  total_height = math.max(12, math.min(available_height, total_height))

  local preview_height = math.max(4, math.floor(total_height * window.preview_ratio))
  local list_header_height = 1
  local list_height = math.max(3, total_height - preview_height - list_header_height - 6)

  if preview_height + list_header_height + list_height + 6 > total_height then
    preview_height = math.max(4, total_height - list_header_height - list_height - 6)
  end

  local left_width = math.max(1, math.floor((total_width - 2) / 2))
  local right_width = math.max(1, total_width - left_width - 2)

  return {
    total_width = total_width,
    total_height = total_height,
    row = math.max(0, math.floor((available_height - total_height) / 2)),
    col = math.max(0, math.floor((available_width - total_width) / 2)),
    preview_height = preview_height,
    list_header_height = list_header_height,
    list_height = list_height,
    left_width = left_width,
    right_width = right_width,
  }
end

function Layout:window_config(layout, key)
  if key == "source" then
    return {
      relative = "editor",
      row = layout.row,
      col = layout.col,
      width = layout.left_width,
      height = layout.preview_height,
    }
  end

  if key == "target" then
    return {
      relative = "editor",
      row = layout.row,
      col = layout.col + layout.left_width + 2,
      width = layout.right_width,
      height = layout.preview_height,
    }
  end

  if key == "list_header" then
    return {
      relative = "editor",
      row = layout.row + layout.preview_height + 2,
      col = layout.col,
      width = layout.total_width,
      height = layout.list_header_height,
    }
  end

  return {
    relative = "editor",
    row = layout.row + layout.preview_height + layout.list_header_height + 4,
    col = layout.col,
    width = layout.total_width,
    height = layout.list_height,
  }
end

return Layout
