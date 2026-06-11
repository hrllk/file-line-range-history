# line-history OOP 리팩토링 최종 구현 계획

## 1. 최종 결정

`lua/line-history/init.lua`에 모여 있는 설정, Git 실행, 파싱, patch 변환, UI 상태, floating window 렌더링, keymap 처리를 객체 책임 단위로 분리한다.

최종 구조는 4.1의 두 번째 안으로 진행한다. 파일 수를 줄이되, 핵심 객체 경계는 유지한다.

```text
lua/line-history/
  init.lua
  config.lua
  plugin.lua
  context.lua
  git.lua
  patch.lua
  ui/
    layout.lua
    view.lua
    session.lua
```

유지할 외부 동작:

- `require("line-history").setup(opts)` 유지
- `require("line-history").show(opts)` 유지
- 기본 명령 `:LineHistory` 유지
- visual mode 기본 키맵 `<leader>gflh` 유지
- `git log -L <start>,<end>:<file> --patch --no-ext-diff` 기반 동작 유지
- `SOURCE`, `TARGET`, commit list 3-pane floating UI 유지
- `VimResized` 자동 리사이즈 유지
- `q`, `<Esc>`, `j`, `k`, 방향키, page key, `<C-d>`, `<C-u>` 동작 유지

이번 범위에서 제외:

- 비동기 Git 실행
- 다중 session 동시 지원
- 검색, 필터, commit detail 추가
- UI 디자인 변경
- 외부 테스트 프레임워크 도입
- `plugin/line-history.lua`에서 자동 setup 호출

## 2. 현재 코드 문제

현재 [lua/line-history/init.lua](/Users/alzar/task/sources/opensources/file-line-range-history/lua/line-history/init.lua)는 모든 책임을 한 파일에 가진다.

| 현재 책임 | 문제 |
| --- | --- |
| `defaults`, `config` | 설정 병합과 사용 지점이 전역으로 결합 |
| `state` | UI session 생명주기를 전역 변수로 관리 |
| `current_file()`, `visual_range()`, `git_root()` | Neovim 실행 context 수집이 use case와 섞임 |
| `run_git_log()`, `parse_history()` | Git 실행과 파싱이 UI 파일에 존재 |
| `side_by_side_items()` | 순수 patch 변환 로직이 UI highlight 이름과 결합 |
| `calculate_layout()`, `open_float()` | layout 계산과 window 생성이 결합 |
| `render_list()`, `render_preview()` | 전역 `state`와 buffer API에 직접 의존 |
| `select_entry()`, `scroll_preview()` | session 객체가 가져야 할 동작이 전역 함수로 존재 |

핵심 개선 목표:

- 전역 `state` 제거
- session 상태를 `ui/session.lua` 객체가 소유
- Git 실행과 파싱을 `git.lua`로 격리
- patch 변환을 `patch.lua`로 격리
- UI 렌더링과 keymap 처리를 `ui/view.lua`, `ui/session.lua`로 격리
- `init.lua`는 facade만 담당

## 3. 목표 의존성

```text
init.lua
  -> plugin.lua
    -> config.lua
    -> context.lua
    -> git.lua
    -> ui/session.lua
       -> ui/view.lua
          -> ui/layout.lua
       -> patch.lua
```

금지할 의존성:

- `git.lua`에서 window/buffer API 호출 금지
- `patch.lua`에서 window/buffer API 호출 금지
- `ui/*`에서 `git log` 실행 금지
- `init.lua`에서 세부 UI 함수 직접 호출 금지

## 4. 모듈별 구현 계획

### 4.1 `config.lua`

역할:

- 기본 설정 보유
- 사용자 설정 병합
- 설정 getter 제공
- highlight 등록 helper 제공

```lua
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
```

### 4.2 `context.lua`

역할:

- 현재 buffer 파일 확인
- visual/range line 정규화
- Git root 탐색
- 상대 경로 계산
- 현재 filetype 제공

```lua
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
```

### 4.3 `git.lua`

역할:

- `git log -L` 인자 구성
- Git 실행
- Git 출력 파싱
- commit entry 생성

```lua
local Git = {}
Git.__index = Git

local RECORD_SEPARATOR = string.char(31)
local FIELD_SEPARATOR = string.char(0)

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

function Git.format_list_line(entry)
  return string.format("%-12s %-12s %-18s %s", entry.short_hash, entry.date, entry.author, entry.message)
end

return Git
```

### 4.4 `patch.lua`

역할:

- unified diff patch를 source/target 표시 item으로 변환
- add/modify/delete highlight group 매핑

```lua
local Patch = {}

local highlights = {
  add = "LineHistoryAdd",
  modify = "LineHistoryModify",
  delete = "LineHistoryDelete",
}

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

local function flush_change_group(source, target, removed, added)
  local max_count = math.max(#removed, #added)

  for i = 1, max_count do
    local removed_line = removed[i]
    local added_line = added[i]

    if removed_line and added_line then
      table.insert(source, { text = removed_line, highlight = highlights.modify })
      table.insert(target, { text = added_line, highlight = highlights.modify })
    elseif removed_line then
      table.insert(source, { text = removed_line, highlight = highlights.delete })
      table.insert(target, { text = "" })
    elseif added_line then
      table.insert(source, { text = "" })
      table.insert(target, { text = added_line, highlight = highlights.add })
    end
  end
end

function Patch.side_by_side_items(patch)
  local source = {}
  local target = {}
  local removed = {}
  local added = {}

  local function flush()
    if #removed > 0 or #added > 0 then
      flush_change_group(source, target, removed, added)
      removed = {}
      added = {}
    end
  end

  for _, line in ipairs(hunk_lines(patch)) do
    if line:match("^@@") then
      flush()
      table.insert(source, { text = line })
      table.insert(target, { text = line })
    elseif line:sub(1, 1) == "-" then
      table.insert(removed, line:sub(2))
    elseif line:sub(1, 1) == "+" then
      table.insert(added, line:sub(2))
    elseif line:sub(1, 1) == " " then
      flush()
      table.insert(source, { text = line:sub(2) })
      table.insert(target, { text = line:sub(2) })
    end
  end

  flush()

  if #source == 0 and #target == 0 then
    source = { { text = "No patch content." } }
    target = { { text = "No patch content." } }
  end

  return source, target
end

return Patch
```

### 4.5 `ui/layout.lua`

역할:

- 화면 크기와 설정 기반 layout 계산
- 각 pane의 floating window config 계산

```lua
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
```

### 4.6 `ui/view.lua`

역할:

- scratch buffer 생성/삭제
- floating window 생성/닫기
- source/target/list 렌더링
- extmark highlight 적용
- preview scroll 지원
- resize 적용

구현 포인트:

- 기존 `asis`/`tobe` 내부 이름은 `source`/`target`으로 바꾼다.
- 화면 title은 기존처럼 `SOURCE`, `TARGET` 유지.
- `close()`에서는 window를 닫고 buffer도 삭제한다.
- `open_float()`는 `opts = opts or {}` 방어를 넣는다.
- `set_items()`는 highlight extmark를 기존과 동일하게 적용한다.

핵심 메서드:

```lua
function View.new(config, namespace, title, filetype)
function View:render_list(entries, selected, format_line)
function View:render_preview(entry, source_items, target_items)
function View:resize()
function View:scroll_preview(delta)
function View:close()
```

필수 내부 상태:

```lua
self.buffers = {
  source = source_buf,
  target = target_buf,
  list_header = list_header_buf,
  list = list_buf,
}

self.wins = {
  source = source_win,
  target = target_win,
  list_header = list_header_win,
  list = list_win,
}
```

필수 private helper:

```lua
local function create_buffer(filetype)
local function set_lines(buf, lines)
local function set_items(buf, namespace, items)
local function start_treesitter(buf, enabled)
local function open_float(config, buf, opts)
local function close_window(win)
local function delete_buffer(buf)
local function scroll_window(win, delta)
```

`View:render_list()`는 header와 list를 모두 갱신해야 한다.

```lua
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
```

`View:render_preview()`는 buffer 내용과 window title을 함께 갱신해야 한다.

```lua
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
```

### 4.7 `ui/session.lua`

역할:

- 하나의 line history UI session 소유
- entries, selected index, closed flag 보유
- keymap 등록
- select, scroll, render, resize, close 처리

필수 구현 조건:

- `closed` 플래그를 둔다.
- `close()`는 idempotent 해야 한다.
- `close()` 후 `select`, `scroll_preview`, `render`, `resize`는 즉시 return 한다.
- close callback을 받아 `Plugin.session`을 nil로 정리한다.

핵심 메서드:

```lua
function Session.new(config, namespace, entries, title, filetype, on_close)
function Session:install_keymaps()
function Session:select(delta)
function Session:scroll_preview(direction)
function Session:render()
function Session:resize()
function Session:close()
```

필수 keymap:

| buffer | key | 동작 |
| --- | --- | --- |
| source, target, list_header, list | `q`, `<Esc>` | `Session:close()` |
| list | `j`, `<Down>` | 다음 commit 선택 |
| list | `k`, `<Up>` | 이전 commit 선택 |
| list | `<PageDown>` | list window 높이 기준 다음 page |
| list | `<PageUp>` | list window 높이 기준 이전 page |
| source, target, list | `<C-d>` | source/target preview 동시 아래 스크롤 |
| source, target, list | `<C-u>` | source/target preview 동시 위 스크롤 |

`Session:render()`는 항상 preview를 먼저 갱신한 뒤 list cursor를 갱신한다. 기존 동작과 동일하게 선택 변경 시 preview title hash와 list cursor가 함께 바뀌어야 한다.

```lua
function Session:render()
  if self.closed then
    return
  end

  local entry = self.entries[self.selected]
  local source_items, target_items = Patch.side_by_side_items(entry.patch)

  self.view:render_preview(entry, source_items, target_items)
  self.view:render_list(self.entries, self.selected, Git.format_list_line)
end
```

### 4.8 `plugin.lua`

역할:

- 객체 조립
- `setup()`, `show()` 실제 구현
- autocmd, command, keymap 등록
- active session 관리

흐름:

```lua
function Plugin:show(opts)
  local file = context:current_file()
  local range = resolve range from opts or visual selection
  local root = context:git_root(file)
  local rel_file = context:relative_path(root, file)
  local entries = Git.new(root, config):line_history(rel_file, range)
  open Session when entries exist
end
```

필수 구현 조건:

- `open_session()`은 기존 session을 먼저 닫는다.
- `resize_session()`은 session이 있을 때만 호출한다.
- `register_command()`는 `{ range = true }` 유지.
- `register_keymap()`은 `config:keymap()`이 false/nil이면 등록하지 않는다.
- notify는 별도 파일로 만들지 않고 `Plugin:notify(message, level)` private method로 둔다.
- `show()`의 모든 실패 경로는 session을 열지 않고 알림 후 return 한다.

실패 경로별 알림 레벨:

| 실패 | 레벨 |
| --- | --- |
| 현재 buffer가 파일이 아님 | `vim.log.levels.WARN` |
| range가 없음 또는 0 | `vim.log.levels.WARN` |
| Git root 탐색 실패 | `vim.log.levels.ERROR` |
| `git log -L` 실패 | `vim.log.levels.ERROR` |
| history entry 없음 | `vim.log.levels.INFO` |

### 4.9 `init.lua`

역할:

- public facade
- 내부 `Plugin` 인스턴스 보유

```lua
local Plugin = require("line-history.plugin")

local M = {}
local plugin = nil

function M.setup(opts)
  if plugin then
    plugin:close_session()
  end

  plugin = Plugin.new(opts)
  plugin:setup()
end

function M.show(opts)
  if not plugin then
    plugin = Plugin.new({})
    plugin:setup()
  end

  plugin:show(opts)
end

return M
```

## 5. 구현 순서

1. `config.lua` 작성
2. `context.lua` 작성
3. `git.lua` 작성
4. `patch.lua` 작성
5. `ui/layout.lua` 작성
6. `ui/view.lua` 작성
7. `ui/session.lua` 작성
8. `plugin.lua` 작성
9. `init.lua` facade로 축소
10. headless 테스트 추가
11. 실제 Neovim 수동 QA

이 순서를 지킨다. 특히 `session`과 `plugin`은 마지막에 연결한다. 전역 `state` 제거와 UI 연결을 초반에 섞으면 회귀 원인 추적이 어려워진다.

## 6. 테스트 계획

테스트는 외부 프레임워크 없이 `nvim --headless`와 Lua `assert`로 시작한다.

권장 구조:

```text
tests/
  minimal_init.lua
  config_spec.lua
  context_spec.lua
  git_spec.lua
  patch_spec.lua
  layout_spec.lua
scripts/
  test.sh
```

`tests/minimal_init.lua`:

```lua
vim.opt.runtimepath:append(vim.fn.getcwd())
```

필수 테스트:

- `config_spec.lua`
  - 기본값 유지
  - 사용자 옵션 deep merge
  - `keymap = false` 보존

- `context_spec.lua`
  - line range 정규화
  - 역방향 range 정렬
  - 0/nil range 거부

- `git_spec.lua`
  - `build_log_args()`가 기존 `git log -L` 인자와 동일한지 확인
  - 빈 output 파싱
  - 정상 metadata + patch 파싱
  - parent 없는 commit의 `parent_short_hash = "empty"`
  - malformed block skip

- `patch_spec.lua`
  - modify pair
  - delete only
  - add only
  - context line
  - `---`, `+++` file header 제외
  - empty patch fallback

- `layout_spec.lua`
  - 일반 terminal size
  - 작은 terminal size
  - preview/list height 최소값 보장

- smoke test
  - `require("line-history").setup({ keymap = false })`가 에러 없이 실행
  - `:LineHistory` command가 등록됨
  - `require("line-history").show({ start_line = 1, end_line = 1 })` 직접 호출이 에러 없이 실패 경로를 통과

수동 QA:

- 일반 파일 buffer에서 visual selection 후 기본 키맵 실행
- `:LineHistory` range 명령 실행
- Git repository가 아닌 파일에서 warning 확인
- 저장되지 않은 buffer에서 warning 확인
- commit이 없는 line range에서 info 알림 확인
- `git log -L` 실패 시 error 알림 확인
- commit list에서 `j/k`, 방향키 이동 확인
- `<PageDown>/<PageUp>` 확인
- list와 preview에서 `<C-d>/<C-u>` 확인
- source/target preview title hash 변경 확인
- `q`, `<Esc>` close 확인
- close 후 terminal resize 시 오류 없음 확인
- terminal resize 후 floating window 재배치 확인
- treesitter가 없는 filetype에서도 오류 없음 확인

## 7. 회귀 위험과 대응

| 위험 | 대응 |
| --- | --- |
| command range 처리 깨짐 | `nvim_create_user_command(..., { range = true })`와 `command.line1/line2` 유지 |
| close 후 resize autocmd가 닫힌 window 접근 | `Session.closed`와 close callback으로 session nil 처리 |
| buffer-local keymap closure가 session 참조 유지 | `View:close()`에서 window close 후 scratch buffer delete |
| `keymap = false`가 무시됨 | `Config:keymap()` 값이 false/nil이면 keymap 등록 생략 |
| `opts.silent = false`가 true로 바뀜 | `and/or` 축약식 사용 금지, 명시적으로 nil 체크 |
| 작은 terminal에서 window 크기 0/음수 | `Layout:calculate()`에서 기존 clamp 유지 |
| Git stderr nil | fallback 메시지 유지 |
| parser가 malformed output에서 에러 | fields 수 부족 block skip |

## 8. 완료 기준

- [ ] `init.lua`가 facade 역할만 수행한다.
- [ ] 전역 `state`가 제거된다.
- [ ] `ui/session.lua`가 selection, render, scroll, close, resize를 소유한다.
- [ ] `git.lua`가 Git 실행과 Git 출력 파싱을 소유한다.
- [ ] `patch.lua`가 side-by-side patch 변환을 소유한다.
- [ ] `ui/view.lua`가 buffer/window 생성, 렌더링, close를 소유한다.
- [ ] 기존 README의 lazy.nvim 설정 예시가 수정 없이 동작한다.
- [ ] headless 테스트가 통과한다.
- [ ] 실제 Neovim에서 visual selection 기반 line history UI가 기존과 동일하게 동작한다.

## 9. 최종 데이터 흐름

```text
User visual selection
  -> :LineHistory
    -> init.lua M.show()
      -> Plugin:show()
        -> Context:current_file()
        -> Context:visual_range() or Context:normalize_range()
        -> Context:git_root()
        -> Git:line_history()
          -> Git:build_log_args()
          -> Git:parse_history()
        -> Session.new()
          -> View.new()
          -> Session:install_keymaps()
          -> Session:render()
            -> Patch.side_by_side_items()
            -> View:render_preview()
            -> View:render_list()
```

최종 상태 소유:

| 객체 | 소유 상태 |
| --- | --- |
| `Plugin` | config, context, namespace, active session |
| `Config` | merged options |
| `Git` | root, config |
| `Session` | entries, selected, view, closed, on_close |
| `View` | buffers, windows, layout |
| `Layout` | config |

## 10. 참고 문서

- Neovim Lua modules: https://neovim.io/doc/user/lua-guide.html
- Neovim `vim.system()`: https://neovim.io/doc/user/lua.html#vim.system()
- Neovim floating window API: https://neovim.io/doc/user/api.html#nvim_open_win()
