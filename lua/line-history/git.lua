-- Git repository adapter; builds git-log commands and parses line history output.
local Git = {}
Git.__index = Git

local RECORD_SEPARATOR = string.char(31)
local FIELD_SEPARATOR = string.char(0)

Git.RECORD_SEPARATOR = RECORD_SEPARATOR
Git.FIELD_SEPARATOR = FIELD_SEPARATOR

function Git.new(root, config)
  return setmetatable({
    root = root,
    config = config,
  }, Git)
end

function Git:line_history(file, range)
  local result = vim.system(self:build_log_args(file, range), { text = true }):wait()
  if result.code ~= 0 then
    return nil, vim.trim(result.stderr or "Failed to run git log -L.")
  end

  return self:parse_history(result.stdout or ""), nil
end

function Git:build_log_args(file, range)
  local args = {
    "git",
    "-C",
    self.root,
    "log",
    "--date=short",
    "--format=" .. RECORD_SEPARATOR .. "%H%x00%h%x00%P%x00%an%x00%ad%x00%s",
    "-L",
    range:to_git_spec(file),
  }

  for _, arg in ipairs(self.config:git_extra_args()) do
    table.insert(args, arg)
  end

  return args
end

function Git:parse_history(output)
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

return Git
