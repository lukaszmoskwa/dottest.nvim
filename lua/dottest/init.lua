local config = require("dottest.config")
local discovery = require("dottest.discovery")
local runner = require("dottest.runner")
local state = require("dottest.state")
local ui = require("dottest.ui")

local M = {}

local function create_user_commands()
  pcall(vim.api.nvim_del_user_command, "DottestDiscover")
  pcall(vim.api.nvim_del_user_command, "DottestPanel")
  pcall(vim.api.nvim_del_user_command, "DottestSuites")
  pcall(vim.api.nvim_del_user_command, "DottestRunAll")
  pcall(vim.api.nvim_del_user_command, "DottestRunNearest")
  pcall(vim.api.nvim_del_user_command, "DottestRerunLast")

  vim.api.nvim_create_user_command("DottestDiscover", function()
    ui.open_discovery()
  end, { desc = "Open the .NET test panel" })

  vim.api.nvim_create_user_command("DottestPanel", function()
    ui.open_discovery()
  end, { desc = "Open the .NET test panel" })

  vim.api.nvim_create_user_command("DottestSuites", function()
    ui.manage_suites()
  end, { desc = "Manage saved .NET test suites" })

  vim.api.nvim_create_user_command("DottestRunAll", function()
    ui.run_all()
  end, { desc = "Run all .NET tests in the workspace" })

  vim.api.nvim_create_user_command("DottestRunNearest", function()
    local target, err = discovery.nearest_test()
    if not target then
      vim.notify("[dottest.nvim] " .. err, vim.log.levels.WARN)
      return
    end
    runner.run_target(target)
  end, { desc = "Run the nearest .NET test" })

  vim.api.nvim_create_user_command("DottestRerunLast", function()
    runner.rerun_last()
  end, { desc = "Rerun the last .NET test target" })
end

function M.setup(opts)
  state.config = config.merge(opts)
  create_user_commands()
end

return M
