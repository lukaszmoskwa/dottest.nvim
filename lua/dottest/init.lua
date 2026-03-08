local config = require("dottest.config")
local state = require("dottest.state")
local ui = require("dottest.ui")

local M = {}

local function create_user_commands()
  pcall(vim.api.nvim_del_user_command, "DottestPanel")
  pcall(vim.api.nvim_del_user_command, "DottestPanelToggle")
  pcall(vim.api.nvim_del_user_command, "DottestPanelFile")

  vim.api.nvim_create_user_command("DottestPanel", function()
    ui.open_discovery()
  end, { desc = "Open the .NET test panel" })

  vim.api.nvim_create_user_command("DottestPanelToggle", function()
    ui.toggle_panel()
  end, { desc = "Toggle the .NET test panel" })

  vim.api.nvim_create_user_command("DottestPanelFile", function()
    ui.open_for_file()
  end, { desc = "Open the .NET test panel filtered to the current file" })
end

local function create_keymap()
  if not state.config.keymap then
    return
  end

  vim.keymap.set(state.config.keymap_mode, state.config.keymap, function()
    ui.toggle_panel()
  end, { desc = "Toggle dottest panel" })
end

function M.setup(opts)
  state.config = config.merge(opts)
  create_user_commands()
  create_keymap()
end

return M
