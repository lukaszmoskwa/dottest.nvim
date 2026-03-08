# dottest.nvim

A Neovim plugin for running and managing .NET tests with a Rider-like workflow.

## What it does

Provides a persistent native explorer buffer displaying a hierarchical tree of test projects → namespace/class scopes → individual tests. Integrates with `dotnet test` for discovery and execution.

## Requirements

- Neovim >= 0.9
- .NET SDK on PATH

## Project structure

```
lua/dottest/
├── init.lua        # Plugin entry point and setup()
├── config.lua      # Default configuration and merging
├── state.lua       # Global mutable state container
├── model.lua       # Tree structure, filtering, status aggregation
├── discovery.lua   # .NET project detection and test listing
├── explorer.lua    # UI buffer, rendering, keybindings (main UI file)
├── runner.lua      # Test execution, command building, output parsing
├── ui.lua          # High-level UI commands (open, toggle, run all)
├── suite.lua       # Suite persistence in .dottest/suites.json
└── root.lua        # Workspace root detection (.git, .sln)
```

## Architecture

- **Modular**: each file has a single responsibility
- **State**: centralized in `state.lua`, explorer substate managed in `explorer.lua`
- **Async**: `vim.system()` for subprocess execution, `vim.schedule()` to return to main thread
- **Tree model**: project → scope → test nodes with recursive status aggregation
- **Module pattern**: each file returns a `M` table with exported functions

## Development setup

Run Neovim with the plugin loaded from the local repo:

```bash
NVIM_APPNAME=dottest-dev nvim -u NONE -i NONE \
  --cmd "set runtimepath^=$(pwd)" \
  --cmd 'lua require("dottest").setup()'
```

Verify headless load (use before PRs):

```bash
NVIM_APPNAME=dottest-dev nvim --headless -u NONE -i NONE \
  --cmd "set runtimepath^=$(pwd)" \
  --cmd 'lua require("dottest").setup()' \
  +q
```

## Code conventions

- Pure Lua, no external Lua dependencies
- `local M = {} ... return M` module pattern throughout
- Functions named descriptively (`is_test_project_path`, `populate_project`)
- Async callbacks always re-enter via `vim.schedule()`
- No automated test suite yet (planned for Phase 4)

## Pre-PR checklist

- Run headless verification above (no errors)
- No local paths, credentials, or cache files committed
- `ink/` directory is intentionally empty (legacy UI removed)
