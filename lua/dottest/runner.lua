local state = require("dottest.state")
local discovery = require("dottest.discovery")

local M = {}

local function build_test_command(target)
  local path = target.path or (target.project and target.project.path)
  local cmd = {
    "dotnet",
    "test",
    path,
    "--nologo",
    "--logger",
    "console;verbosity=detailed",
  }

  if target.filter and target.filter ~= "" then
    table.insert(cmd, "--filter")
    table.insert(cmd, "FullyQualifiedName~" .. discovery.test_filter_name(target.filter))
  end

  return cmd
end

local function normalize_test_name(name)
  return vim.trim((name or ""):gsub("%s+%[[^%]]+%]%s*$", ""))
end

local function parse_outcomes(output)
  local outcomes = {}
  for line in vim.gsplit(output or "", "\n", { plain = true, trimempty = true }) do
    local passed = line:match("^%s*Passed%s+(.+)%s+%[[^%]]+%]%s*$")
    if passed then
      outcomes[normalize_test_name(passed)] = "passed"
    end

    local failed = line:match("^%s*Failed%s+(.+)%s+%[[^%]]+%]%s*$")
    if failed then
      outcomes[normalize_test_name(failed)] = "failed"
    end
  end
  return outcomes
end

local function populate_quickfix(target, outcomes)
  local items = {}
  for name, status in pairs(outcomes) do
    if status == "failed" then
      table.insert(items, {
        text = string.format("%s :: %s", target.project.name, name),
      })
    end
  end

  vim.fn.setqflist({}, "r", { title = "dottest failures", items = items })
  if #items > 0 then
    vim.cmd.copen()
  end
end

local function summarize_run(target, result)
  local output = table.concat({
    result.stdout or "",
    result.stderr or "",
  }, "\n")
  local outcomes = parse_outcomes(output)
  local failed = 0
  for _, status in pairs(outcomes) do
    if status == "failed" then
      failed = failed + 1
    end
  end

  if next(outcomes) ~= nil then
    populate_quickfix(target, outcomes)
  end

  return {
    ok = result.code == 0,
    output = output,
    outcomes = outcomes,
    failed = failed,
    code = result.code,
  }
end

local function run_one(target, callback)
  local explorer = require("dottest.explorer")
  local cmd = build_test_command(target)
  explorer.mark_running(target)

  vim.system(cmd, { cwd = target.project.root, text = true }, function(result)
    vim.schedule(function()
      local summary = summarize_run(target, result)
      explorer.complete_run(target, summary)
      callback(summary)
    end)
  end)
end

local function run_items(items, done)
  local index = 1

  local function step()
    local item = items[index]
    if not item then
      if done then
        done()
      end
      return
    end

    run_one(item, function()
      index = index + 1
      step()
    end)
  end

  step()
end

function M.run_target(target)
  state.last_run = {
    type = "target",
    target = target,
  }

  run_one(target, function()
  end)
end

function M.run_workspace(workspace)
  local items = {}

  if workspace.projects and #workspace.projects > 0 then
    for _, project in ipairs(workspace.projects) do
      table.insert(items, {
        kind = "project",
        name = project.name,
        project = project,
      })
    end
  elseif workspace.solution then
    table.insert(items, {
      kind = "workspace",
      name = vim.fn.fnamemodify(workspace.solution, ":t:r"),
      path = workspace.solution,
      project = {
        path = workspace.solution,
        root = workspace.root,
      },
    })
  end

  if #items == 0 then
    vim.notify("[dottest.nvim] No test projects found in this workspace", vim.log.levels.WARN)
    return
  end

  state.last_run = {
    type = "workspace",
    workspace = workspace,
  }

  run_items(items, function()
  end)
end

function M.run_suite(name, items)
  state.last_run = {
    type = "suite",
    suite_name = name,
    items = items,
  }
  run_items(items, function()
  end)
end

function M.rerun_last()
  if not state.last_run then
    vim.notify("[dottest.nvim] Nothing to rerun yet", vim.log.levels.WARN)
    return
  end

  if state.last_run.type == "suite" then
    M.run_suite(state.last_run.suite_name, state.last_run.items)
    return
  end

  if state.last_run.type == "workspace" then
    M.run_workspace(state.last_run.workspace)
    return
  end

  M.run_target(state.last_run.target)
end

return M
