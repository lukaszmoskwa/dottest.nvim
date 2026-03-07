# dottest.nvim

Neovim plugin for running and managing .NET tests with a Rider-like workflow.

## Features

- Discover solutions and test projects in the current workspace
- Open a persistent native explorer buffer with a project -> namespace/class -> test tree
- Show per-node run state directly in explorer columns
- Aggregate pass/fail state from tests up to scopes and projects
- Populate quickfix with failed test names from the latest run
- List tests from a selected project using `dotnet test --list-tests`
- Preload tests for the workspace so filtering can search the whole tree
- Run a whole project, a class/namespace scope, or an individual test
- Run all tests in the current solution or all discovered test projects
- Save named test suites per project in `.dottest/suites.json`
- Re-run the last executed target
- Run the test nearest to the cursor in a C# buffer

## Requirements

- Neovim >= 0.9
- `.NET SDK` available on `PATH`

## Installation

### lazy.nvim

```lua
{
  "lukaszmoskwa/dottest.nvim",
  config = function()
    require("dottest").setup()
  end,
}
```

## Development

For local plugin development, start Neovim with an isolated app name so it does not pick up your normal config:

```bash
NVIM_APPNAME=dottest-dev nvim -u NONE -i NONE \
  --cmd "set runtimepath^=/path/to/repo/dottest.nvim" \
  --cmd 'lua require("dottest").setup()'
```

If you want to confirm the plugin loads cleanly in headless mode:

```bash
NVIM_APPNAME=dottest-dev nvim --headless -u NONE -i NONE \
  --cmd "set runtimepath^=$(pwd)" \
  --cmd 'lua require("dottest").setup()' \
  +q
```

`NVIM_APPNAME=dottest-dev` tells Neovim to use a separate config/data namespace for this plugin session.

## Configuration

Default configuration:

```lua
require("dottest").setup({
  suite_dirname = ".dottest",
  suite_filename = "suites.json",
  keymap = false,
  keymap_mode = "n",
  panel = {
    open_mode = "current_buffer",
    split = {
      position = "botright",
      direction = "vsplit",
      size = 70,
    },
  },
})
```

`panel.open_mode` supports:

- `"current_buffer"` replace the current buffer with the explorer
- `"split"` open the explorer in a configured split
- `"tab"` open the explorer in its own tab

Set `keymap = false` to disable the built-in mapping, or assign your own shortcut such as `<leader>dt`.

Example:

```lua
require("dottest").setup({
  keymap = "<leader>dt",
})
```

## Commands

- `:DottestPanel` open the test explorer
- `:DottestPanelToggle` toggle between the test explorer and the last source buffer

## Explorer

Inside the explorer:

- `j` / `k` / `PageUp` / `PageDown` moves the cursor
- `/` prompts for a test-name filter
- `c` clears the active filter
- `<CR>` or `l` expands a project or scope, or runs the selected test
- `h` collapses a node
- `r` runs the current node
- `R` runs all discovered test projects
- `o` toggles a split with the latest captured output for the current node
- `gr` refreshes the workspace tree
- `q` closes the explorer window

## Suite storage

Suites are stored in a project-local file:

- `.dottest/suites.json`

This keeps named suites close to the repository, so they can be shared if you want to commit them.

Saving a target into an existing suite appends it instead of replacing the suite.

## Contributing

See [CONTRIBUTING.md](./CONTRIBUTING.md).

## License

[MIT](./LICENSE)
