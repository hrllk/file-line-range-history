# nvim-line-history

Small Neovim plugin for showing Git history for a selected line range.

The plugin reads the current visual selection and runs:

```sh
git log -L <start>,<end>:<file> --patch --no-ext-diff
```

The result is shown in a three-pane floating view:

- `SOURCE`: the selected commit's parent line content
- `TARGET`: the selected commit's resulting line content
- `Commit list`: commits that touched the selected line range

Use `j`/`k` or arrow keys in the commit list to move through commits.
Use `<C-d>`/`<C-u>` to scroll the `SOURCE` and `TARGET` preview panes together.
Use page keys to move through the commit list by page.
Press `q` or `<Esc>` to close the view.

Preview highlighting:

- Added lines use `LineHistoryAdd`, green by default.
- Modified lines use `LineHistoryModify`, blue by default.
- Deleted lines use `LineHistoryDelete`, gray by default.

## lazy.nvim

```lua
{
  dir = "~/task/sources/opensources/nvim-line-history",
  name = "nvim-line-history",
  dependencies = {
    "nvim-treesitter/nvim-treesitter",
  },
  keys = {
    {
      "<leader>gH",
      function()
        require("line-history").show()
      end,
      mode = "x",
      desc = "Git line range history",
    },
  },
  opts = {
    keymap = false,
    treesitter = {
      enabled = true,
    },
  },
  config = function(_, opts)
    require("line-history").setup(opts)
  end,
}
```

## Usage

1. Open a file inside a Git repository.
2. Select lines in visual mode.
3. Press `<leader>gH`.

## Limitations

`git log -L` traces a line range that exists in the starting revision. Rename,
move, and copy behavior follows Git's own line-history limitations.
