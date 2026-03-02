local state = require("dottest.state")

local M = {}

local function shellescape(value)
  return vim.fn.shellescape(value)
end

local function ensure_terminal(config)
  local position = config.terminal.position or "botright"
  local size = tonumber(config.terminal.size) or 15
  vim.cmd(position .. " " .. size .. "split")

  local bufnr = vim.api.nvim_get_current_buf()
  vim.bo[bufnr].buflisted = false

  local job_id
  if vim.fn.has("nvim-0.11") == 1 then
    job_id = vim.fn.jobstart(vim.o.shell, { term = true })
  else
    ---@diagnostic disable-next-line: deprecated
    job_id = vim.fn.termopen(vim.o.shell)
  end

  if not job_id or job_id <= 0 then
    vim.notify("[dottest.nvim] Failed to open terminal", vim.log.levels.ERROR)
    return nil
  end

  vim.schedule(function()
    if vim.api.nvim_buf_is_valid(bufnr) then
      vim.cmd.startinsert()
    end
  end)

  return job_id
end

local function send(job_id, command)
  vim.api.nvim_chan_send(job_id, command .. "\n")
end

local function print_title(job_id, title)
  send(job_id, string.format("printf '%%s\\n' %s", shellescape("[" .. title .. "]")))
end

local function build_test_command(target)
  local path = target.path or (target.project and target.project.path)
  local cmd = { "dotnet", "test", shellescape(path), "--nologo" }

  if target.filter and target.filter ~= "" then
    table.insert(cmd, "--filter")
    table.insert(cmd, shellescape("FullyQualifiedName~" .. target.filter))
  end

  return table.concat(cmd, " ")
end

local function run_items(items, title)
  local job_id = ensure_terminal(state.config)
  if not job_id then
    return
  end

  if title then
    print_title(job_id, title)
  end

  for _, item in ipairs(items) do
    send(job_id, string.format("cd %s", shellescape(item.project.root)))
    send(job_id, build_test_command(item))
  end
end

function M.run_target(target)
  state.last_run = {
    type = "target",
    target = target,
  }
  run_items({ target }, target.name)
end

function M.run_workspace(workspace)
  local items = {}

  if workspace.solution then
    table.insert(items, {
      kind = "workspace",
      name = vim.fn.fnamemodify(workspace.solution, ":t:r"),
      path = workspace.solution,
      project = {
        path = workspace.solution,
        root = workspace.root,
      },
    })
  else
    for _, project in ipairs(workspace.projects) do
      table.insert(items, {
        kind = "project",
        name = project.name,
        project = project,
      })
    end
  end

  if #items == 0 then
    vim.notify("[dottest.nvim] No test projects found in this workspace", vim.log.levels.WARN)
    return
  end

  state.last_run = {
    type = "workspace",
    workspace = workspace,
  }
  run_items(items, "All tests")
end

function M.run_suite(name, items)
  state.last_run = {
    type = "suite",
    suite_name = name,
    items = items,
  }
  run_items(items, "Suite: " .. name)
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
