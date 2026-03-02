local discovery = require("dottest.discovery")
local panel = require("dottest.panel")
local runner = require("dottest.runner")
local suite = require("dottest.suite")

local M = {}

function M.open_discovery()
  panel.open()
end

function M.toggle_panel()
  panel.toggle()
end

function M.run_all()
  runner.run_workspace(discovery.find_test_projects())
end

function M.manage_suites()
  local suites = suite.list()
  if #suites == 0 then
    vim.notify("[dottest.nvim] No saved suites found", vim.log.levels.WARN)
    return
  end

  vim.ui.select(suites, {
    prompt = "Select suite",
    format_item = function(item)
      return item.name
    end,
  }, function(selected_suite)
    if not selected_suite then
      return
    end

    vim.ui.select({
      { action = "run", label = "Run suite" },
      { action = "rename", label = "Rename suite" },
      { action = "delete", label = "Delete suite" },
    }, {
      prompt = selected_suite.name,
      format_item = function(item)
        return item.label
      end,
    }, function(action)
      if not action then
        return
      end

      if action.action == "delete" then
        suite.delete(selected_suite.name)
        vim.notify("[dottest.nvim] Deleted suite " .. selected_suite.name, vim.log.levels.INFO)
        return
      end

      if action.action == "rename" then
        vim.ui.input({ prompt = "New name: ", default = selected_suite.name }, function(new_name)
          if not new_name or new_name == "" or new_name == selected_suite.name then
            return
          end
          suite.rename(selected_suite.name, new_name)
          vim.notify("[dottest.nvim] Renamed suite to " .. new_name, vim.log.levels.INFO)
        end)
        return
      end

      runner.run_suite(selected_suite.name, selected_suite.items)
    end)
  end)
end

return M
