# line-history OOP 리팩토링 최종 구조

## 최종 결정

`lua/line-history/init.lua`에 모여 있던 설정, Git 실행, 파싱, 표시 모델 생성, UI 상태, floating window 렌더링, keymap 처리를 책임 단위로 분리한다.

최종 구조:

```text
lua/line-history/
  init.lua
  app.lua
  config.lua
  context.lua
  git.lua
  ui/
    layout.lua
    presenter.lua
    session.lua
    view.lua
```

삭제한 구조:

- `plugin/line-history.lua`: lazy.nvim 기반 명시적 `setup()` 방식에서는 실질 기능이 없는 자동 로딩 stub.
- `lua/line-history/plugin.lua`: 내부 애플리케이션 객체 이름으로 부적절해 `app.lua`로 변경.
- `lua/line-history/patch.lua`: UI 표시 모델 생성 책임이므로 `ui/presenter.lua`로 이동.

## 의존 방향

```text
init.lua
  -> app.lua
    -> config.lua
    -> context.lua
    -> git.lua
    -> ui/session.lua
       -> ui/presenter.lua
       -> ui/view.lua
          -> ui/layout.lua
```

규칙:

- `git.lua`는 UI를 모른다.
- `git.lua`는 표시 문자열 formatting을 하지 않는다.
- `ui/session.lua`는 Git을 모른다.
- `ui/presenter.lua`는 Git 실행을 모른다.
- `ui/view.lua`는 Git과 patch parsing을 모른다.
- `ui/layout.lua`는 window를 열지 않는다.
- `init.lua`는 내부 구현을 모른다.

## 역할

| 파일 | 책임 |
| --- | --- |
| `init.lua` | public facade. `setup()`, `show()`만 노출 |
| `app.lua` | application orchestration. config/context/git/session 조립, command/autocmd/keymap 등록 |
| `config.lua` | 기본 옵션, 사용자 옵션 merge, highlight 등록 |
| `context.lua` | 현재 buffer, visual/range, Git root, 상대 경로, filetype 수집 |
| `git.lua` | `git log -L` 실행, 인자 구성, Git output parsing |
| `ui/presenter.lua` | commit entry와 patch를 화면 표시용 데이터로 변환 |
| `ui/session.lua` | UI session 상태, selected index, keymap, render/resize/close lifecycle |
| `ui/view.lua` | Neovim buffer/window/extmark/cursor API 처리 |
| `ui/layout.lua` | floating window geometry 계산 |

## 유지할 외부 동작

- `require("line-history").setup(opts)` 유지
- `require("line-history").show(opts)` 유지
- 기본 명령 `:LineHistory` 유지
- visual mode 기본 키맵 `<leader>gflh` 유지
- `git log -L <start>,<end>:<file> --patch --no-ext-diff` 기반 동작 유지
- `SOURCE`, `TARGET`, commit list 3-pane floating UI 유지
- `VimResized` 자동 리사이즈 유지
- `q`, `<Esc>`, `j`, `k`, 방향키, page key, `<C-d>`, `<C-u>` 동작 유지

## 제외 범위

- 비동기 Git 실행
- 다중 session 동시 지원
- 검색, 필터, commit detail 추가
- UI 디자인 변경
- 외부 테스트 프레임워크 도입
- 전통적 runtime 자동 초기화 지원

## 데이터 흐름

```text
User visual selection
  -> :LineHistory
    -> init.lua M.show()
      -> App:show()
        -> Context:current_file()
        -> Context:visual_range() or Context:normalize_range()
        -> Context:git_root()
        -> Context:relative_path()
        -> Git:line_history()
          -> Git:build_log_args()
          -> vim.system("git log -L ...")
          -> Git:parse_history()
        -> Session.new(entries)
          -> View.new()
          -> Session:install_keymaps()
          -> Session:render()
            -> Presenter.side_by_side_items(entry.patch)
            -> Presenter.format_list_line(entry)
            -> View:render_preview()
            -> View:render_list()
```

## 테스트 구조

```text
tests/
  minimal_init.lua
  config_spec.lua
  context_spec.lua
  git_spec.lua
  presenter_spec.lua
  layout_spec.lua
  smoke_spec.lua
scripts/
  test.sh
```

필수 검증:

- `config_spec.lua`: 기본값, deep merge, `keymap = false`
- `context_spec.lua`: range 정규화, 역방향 range, invalid range
- `git_spec.lua`: `git log -L` 인자, 빈 output, 정상 output, root commit, malformed block
- `presenter_spec.lua`: list formatting, modify/delete/add/context/empty patch
- `layout_spec.lua`: 일반/작은 terminal geometry
- `smoke_spec.lua`: setup, command 등록, show 실패 경로

실행:

```sh
./scripts/test.sh
```

## 회귀 위험과 대응

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

## 완료 기준

- [ ] `init.lua`가 facade 역할만 수행한다.
- [ ] 전역 `state`가 제거된다.
- [ ] `git.lua`가 Git 실행과 Git 출력 파싱만 소유한다.
- [ ] `ui/presenter.lua`가 표시 모델 생성을 소유한다.
- [ ] `ui/session.lua`가 Git에 의존하지 않는다.
- [ ] `ui/view.lua`가 buffer/window 생성, 렌더링, close를 소유한다.
- [ ] 기존 README의 lazy.nvim 설정 예시가 수정 없이 동작한다.
- [ ] headless 테스트가 통과한다.
- [ ] 실제 Neovim에서 visual selection 기반 line history UI가 기존과 동일하게 동작한다.

## 참고 문서

- Neovim Lua plugin guide: https://neovim.io/doc/user/lua-plugin.html
- Neovim Lua guide: https://neovim.io/doc/user/lua-guide.html
- Neovim `vim.system()`: https://neovim.io/doc/user/lua.html#vim.system()
- Neovim floating window API: https://neovim.io/doc/user/api.html#nvim_open_win()
