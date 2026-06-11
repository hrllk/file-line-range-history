-- Execution context adapter; reads the current Neovim buffer, range, Git root, and filetype.
local Context = {}
Context.__index = Context

function Context.new()
  return setmetatable({}, Context)
end

function Context:current_file()
  local file = vim.api.nvim_buf_get_name(0)
  if file == "" then
    return nil, "The current buffer is not backed by a file."
  end

  if vim.bo.buftype ~= "" then
    return nil, "Line history is only available in normal file buffers."
  end

  return file, nil
end

function Context:normalize_range(start_line, end_line)
  if not start_line or not end_line or start_line == 0 or end_line == 0 then
    return nil, "Select one or more lines in visual mode before running line history."
  end

  if start_line > end_line then
    start_line, end_line = end_line, start_line
  end

  return {
    start_line = start_line,
    end_line = end_line,
    to_git_spec = function(range, file)
      return string.format("%d,%d:%s", range.start_line, range.end_line, file)
    end,
    to_title = function(range, file)
      return string.format("%s:%d-%d", file, range.start_line, range.end_line)
    end,
  }, nil
end

function Context:visual_range()
  local start_pos = vim.fn.getpos("'<")
  local end_pos = vim.fn.getpos("'>")
  return self:normalize_range(start_pos[2], end_pos[2])
end

function Context:git_root(file)
  local result = vim.system({ "git", "-C", vim.fs.dirname(file), "rev-parse", "--show-toplevel" }, { text = true }):wait()
  if result.code ~= 0 then
    return nil, vim.trim(result.stderr or "Could not find a Git repository.")
  end

  return vim.trim(result.stdout), nil
end

function Context:relative_path(root, file)
  if vim.startswith(file, root .. "/") then
    return file:sub(#root + 2)
  end

  return vim.fn.fnamemodify(file, ":.")
end

function Context:filetype()
  return vim.bo.filetype
end

return Context
