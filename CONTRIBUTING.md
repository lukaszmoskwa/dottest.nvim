# Contributing

## Setup

1. Clone the repository.
2. Start Neovim with the plugin on `runtimepath`:

```bash
NVIM_APPNAME=dottest-dev nvim -u NONE -i NONE \
  --cmd "set runtimepath^=$(pwd)" \
  --cmd 'lua require("dottest").setup()'
```

## Development notes

- The Neovim plugin code lives under `lua/dottest/`.
- Workspace-local cache and suites are stored under `.dottest/` and should not be committed accidentally.

## Before opening a pull request

1. Confirm the plugin loads in headless mode:

```bash
NVIM_APPNAME=dottest-dev nvim --headless -u NONE -i NONE \
  --cmd "set runtimepath^=$(pwd)" \
  --cmd 'lua require("dottest").setup()' \
  +q
```

2. Check that no machine-specific paths, credentials, logs, or local cache files were added to the diff.

## Reporting security issues

Please do not open a public issue for a suspected security problem. Report it privately to the maintainer instead.
