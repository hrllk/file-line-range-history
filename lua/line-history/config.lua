-- Configuration object; owns defaults, user option merging, and highlight setup.
local Config = {}
Config.__index = Config

local defaults = {
  keymap = "<leader>gflh",
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

function Config.new(opts)
  return setmetatable({
    values = vim.tbl_deep_extend("force", vim.deepcopy(defaults), opts or {}),
  }, Config)
end

function Config:command()
  return self.values.command
end

function Config:keymap()
  return self.values.keymap
end

function Config:git_extra_args()
  return self.values.git.extra_args or {}
end

function Config:window()
  return self.values.window
end

function Config:treesitter_enabled()
  return self.values.treesitter.enabled
end

function Config:apply_highlights()
  vim.api.nvim_set_hl(0, "LineHistoryAdd", self.values.highlight.add)
  vim.api.nvim_set_hl(0, "LineHistoryModify", self.values.highlight.modify)
  vim.api.nvim_set_hl(0, "LineHistoryDelete", self.values.highlight.delete)
end

return Config
