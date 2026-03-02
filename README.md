# dottest.nvim

Neovim plugin for running and managing .NET tests with a Rider-like workflow.

## Features

- Discover solutions and test projects in the current workspace
- Open a persistent Ink panel with an expandable test tree and checkboxes
- Keep the test tree inside a scrollable viewport sized to the terminal
- Show per-node run state and overall run progress in the panel
- Show failed tests in a dedicated pane and jump back into Neovim files
- Populate quickfix with failed test locations
- List tests from a selected project using `dotnet test --list-tests`
- Preload tests for the workspace so filtering can search the whole tree
- Cache discovered test lists in `.dottest/test-cache.json` until you refresh the workspace
- Run a whole project, a class/namespace scope, or an individual test
- Run all tests in the current solution or all discovered test projects
- Save named test suites per project in `.dottest/suites.json`
- Re-run the last executed target
- Run the test nearest to the cursor in a C# buffer

## Requirements

- Neovim >= 0.9
- `.NET SDK` available on `PATH`
- Node.js >= 20

## Installation

### lazy.nvim

```lua
{
  "lukaszmoskwa/dottest.nvim",
  build = "npm install",
  config = function()
    require("dottest").setup()
  end,
}
```

`dottest.nvim` embeds an Ink-based panel, so the Node dependencies need to be installed once during setup.

## Development

Install the Ink runtime first:

```bash
cd /path/to/dottest.nvim
npm install
```

For local plugin development, start Neovim with an isolated app name so it does not pick up your normal config:

```bash
NVIM_APPNAME=dottest-dev nvim -u NONE -i NONE \
  --cmd "set runtimepath^=$(pwd)" \
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

To run the Ink panel directly during development:

```bash
cd /path/to/dottest.nvim
npm run panel -- --cwd /path/to/your/dotnet/workspace
```

## Configuration

Default configuration:

```lua
require("dottest").setup({
  suite_dirname = ".dottest",
  suite_filename = "suites.json",
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

- `"current_buffer"` replace the current buffer with the panel
- `"split"` open the panel in a configured split
- `"tab"` open the panel in its own tab

## Commands

- `:DottestDiscover` open the test panel
- `:DottestPanel` open the test panel
- `:DottestPanelToggle` toggle between the test panel and the last source buffer
- `:DottestSuites` manage saved suites
- `:DottestRunAll` run all tests in the current workspace
- `:DottestRunNearest` run the nearest test under the cursor
- `:DottestRerunLast` rerun the last project, scope, test, or suite

## Ink Panel

Inside the panel:

- `j` / `k` / `PageUp` / `PageDown` moves the cursor
- `/` starts filtering tests by name
- `<CR>` or `l` expands a node, or opens a test file in a new Neovim split
- `h` collapses a node
- `<Space>` toggles the checkbox on the current node
- `r` runs the current node
- `R` expands the tree and runs all discovered tests
- `Tab` switches between the main tree and the failed-tests pane
- `Esc` cancels the active test run
- `a` toggles all visible nodes
- `o` toggles the output panel
- `g` refreshes the workspace tree
- `q` closes the panel

When the failed-tests pane is focused, press `<CR>` to open the selected failure in a new Neovim split.

## Suite storage

Suites are stored in a project-local file:

- `.dottest/suites.json`

This keeps named suites close to the repository, so they can be shared if you want to commit them.

Saving a target into an existing suite appends it instead of replacing the suite.

## Contributing

See [CONTRIBUTING.md](./CONTRIBUTING.md).

## License

[MIT](./LICENSE)
