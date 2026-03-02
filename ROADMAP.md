# Roadmap

## Phase 1

- [x] Checked runs in the panel
  Make `R` run selected nodes instead of all discovered tests, with clear precedence for project, scope, and test selections.
- [ ] Suite creation and editing
  Add "save selection as suite", "append to suite", and "rename suite" flows from the panel or Neovim commands.
- [ ] Failure integration with quickfix
  Populate quickfix or diagnostics from failed tests so users can navigate failures outside the Ink panel.
- [ ] Configurable runner options
  Support user config for extra `dotnet test` args, env vars, configuration, framework, and settings file.

## Phase 2

- [ ] Batch execution by project
  Run selected tests per project with a combined filter instead of spawning one `dotnet test` per test.
- [ ] Better nearest-test detection
  Replace the current regex-only parser with something more resilient to common C# syntax patterns.
- [ ] Persistent last-run state
  Store last run target in `.dottest` so rerun survives Neovim restarts.
- [ ] Cache invalidation improvements
  Refresh per-project test cache based on file changes or project file timestamps instead of manual refresh only.

## Phase 3

- [ ] Debug current test / selection
  Integrate with `nvim-dap` or a configurable debug command for test methods and failed tests.
- [ ] Watch mode
  Auto-rerun nearest test, current scope, or suite on save.
- [ ] Trait/category filters
  Support xUnit traits, NUnit categories, MSTest categories, and saved filter presets.
- [ ] Inline status in source buffers
  Show pass/fail signs or virtual text for nearest or recently run tests.

## Phase 4

- [ ] Add automated tests
  Cover discovery, suite persistence, and nearest-test resolution.
- [ ] Split the Ink app into smaller modules
  Break up `ink/cli.mjs` so UI state, execution, parsing, and rendering are easier to maintain.
- [ ] Add a shared behavior layer between Lua and Ink
  Reduce duplicated logic between the Neovim plugin side and the panel side.
- [ ] Keep the README aligned with shipped behavior
  Update docs when features change so the documented workflow stays accurate.

## Recommended Order

- [x] Checked runs in the panel
- [ ] Suite creation and editing
- [ ] Failure integration with quickfix
- [ ] Configurable runner options
- [ ] Batch execution by project
- [ ] Better nearest-test detection
