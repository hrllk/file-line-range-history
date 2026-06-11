#!/bin/sh
set -eu

export NVIM_LOG_FILE="${TMPDIR:-/tmp}/line-history-nvim.log"

nvim --headless -u NONE -i NONE -n -l tests/config_spec.lua
nvim --headless -u NONE -i NONE -n -l tests/context_spec.lua
nvim --headless -u NONE -i NONE -n -l tests/git_spec.lua
nvim --headless -u NONE -i NONE -n -l tests/presenter_spec.lua
nvim --headless -u NONE -i NONE -n -l tests/layout_spec.lua
nvim --headless -u NONE -i NONE -n -l tests/smoke_spec.lua
nvim --headless -u NONE -i NONE -n +"set rtp+=." +"edit README.md" +"lua require('line-history').setup({ keymap = false, treesitter = { enabled = false } })" +"1,1LineHistory" +"qa!"
nvim --headless -u NONE -i NONE -n +"set rtp+=." +"lua local lh=require('line-history'); lh.setup({ keymap = false }); lh.setup({ keymap = false })" +"qa!"

rm -f .nvimlog
