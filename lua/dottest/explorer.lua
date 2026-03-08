local discovery = require("dottest.discovery")
local model = require("dottest.model")
local root = require("dottest.root")
local runner = require("dottest.runner")
local state = require("dottest.state")

local M = {}

local STATUS_LABELS = {
  ["not-run"] = "     -",
  loading = "  load",
  running = "   run",
  passed = "  pass",
  failed = "  fail",
  partial = " mixed",
}

local STATUS_HL = {
  ["not-run"] = "DottestStatusNeutral",
  loading = "DottestStatusNeutral",
  running = "DottestStatusRunning",
  passed = "DottestStatusPassed",
  failed = "DottestStatusFailed",
  partial = "DottestStatusPartial",
}

local OUTPUT_HEIGHT = 12

local function explorer_state()
  return state.explorer
end

local function set_highlights()
  vim.api.nvim_set_hl(0, "DottestStatusNeutral", { link = "Comment", default = true })
  vim.api.nvim_set_hl(0, "DottestStatusRunning", { link = "DiagnosticWarn", default = true })
  vim.api.nvim_set_hl(0, "DottestStatusPassed", { link = "DiagnosticOk", default = true })
  vim.api.nvim_set_hl(0, "DottestStatusFailed", { link = "DiagnosticError", default = true })
  vim.api.nvim_set_hl(0, "DottestStatusPartial", { link = "DiagnosticInfo", default = true })
  vim.api.nvim_set_hl(0, "DottestDirectory", { link = "Directory", default = true })
  vim.api.nvim_set_hl(0, "DottestOutputHeader", { link = "Title", default = true })
  vim.api.nvim_set_hl(0, "DottestOutputError", { link = "DiagnosticError", default = true })
end

local function is_valid_buf(bufnr)
  return bufnr and bufnr > 0 and vim.api.nvim_buf_is_valid(bufnr)
end

local function is_valid_win(winid)
  return winid and winid > 0 and vim.api.nvim_win_is_valid(winid)
end

local function open_target_window()
  local panel_config = state.config.panel or {}
  local open_mode = panel_config.open_mode or "current_buffer"

  if open_mode == "tab" then
    vim.cmd.tabnew()
    return vim.api.nvim_get_current_win()
  end

  if open_mode == "split" then
    local split = panel_config.split or {}
    local position = split.position or "botright"
    local direction = split.direction or "vsplit"
    vim.cmd(position .. " " .. direction)
    local winid = vim.api.nvim_get_current_win()

    if direction == "vsplit" then
      vim.api.nvim_win_set_width(winid, tonumber(split.size) or 70)
    else
      vim.api.nvim_win_set_height(winid, tonumber(split.size) or 15)
    end

    return winid
  end

  return vim.api.nvim_get_current_win()
end

local function current_node()
  local explorer = explorer_state()
  if not is_valid_win(explorer.winid) then
    return nil
  end
  local line = vim.api.nvim_win_get_cursor(explorer.winid)[1]
  return explorer.line_map[line]
end

local function get_node_output(node)
  if not node then
    return nil
  end

  local entry = explorer_state().outputs[node.id]
  if entry then
    return entry
  end

  if node.kind == "test" then
    return nil
  end

  for _, child in ipairs(node.children or {}) do
    local child_entry = get_node_output(child)
    if child_entry then
      return child_entry
    end
  end

  return nil
end

local function status_text(node)
  local explorer = explorer_state()
  if node.loading then
    return "loading", STATUS_LABELS.loading
  end
  if node.load_error then
    return "failed", STATUS_LABELS.failed
  end
  local summary = model.summarize(node, explorer.statuses)
  return summary.status, STATUS_LABELS[summary.status] or STATUS_LABELS["not-run"]
end

local function summary_text(node)
  local summary = model.summarize(node, explorer_state().statuses)
  if node.kind == "test" then
    return ""
  end
  if summary.total == 0 then
    return "  0/0"
  end
  return string.format("%3d/%-3d", summary.completed, summary.total)
end

local function display_name(node)
  if node.kind == "project" then
    local icon = node.expanded and "v " or "> "
    return icon .. node.name
  end

  local depth = model.depth(node)
  local indent = string.rep("  ", depth)
  if node.kind == "scope" then
    local icon = node.expanded and "v " or "> "
    return indent .. icon .. node.name
  end
  return indent .. "- " .. node.name
end

local function ensure_buffer()
  local explorer = explorer_state()
  if is_valid_buf(explorer.bufnr) then
    return explorer.bufnr
  end

  local bufnr = vim.api.nvim_create_buf(false, true)
  explorer.bufnr = bufnr

  vim.bo[bufnr].buftype = "nofile"
  vim.bo[bufnr].bufhidden = "hide"
  vim.bo[bufnr].swapfile = false
  vim.bo[bufnr].modifiable = false
  vim.bo[bufnr].filetype = "dottest"
  vim.api.nvim_create_autocmd("CursorMoved", {
    buffer = bufnr,
    callback = function()
      if is_valid_win(explorer_state().output_winid) then
        M.render_output()
      end
    end,
  })

  local opts = { buffer = bufnr, nowait = true, silent = true }
  vim.keymap.set("n", "<CR>", function()
    M.activate()
  end, opts)
  vim.keymap.set("n", "l", function()
    M.activate()
  end, opts)
  vim.keymap.set("n", "h", function()
    M.collapse()
  end, opts)
  vim.keymap.set("n", "r", function()
    M.run_target()
  end, opts)
  vim.keymap.set("n", "R", function()
    runner.run_workspace(explorer.workspace_source)
  end, opts)
  vim.keymap.set("n", "gr", function()
    M.refresh(true)
  end, opts)
  vim.keymap.set("n", "/", function()
    M.prompt_filter()
  end, opts)
  vim.keymap.set("n", "c", function()
    M.clear_filter()
  end, opts)
  vim.keymap.set("n", "o", function()
    M.toggle_output()
  end, opts)
  vim.keymap.set("n", "q", function()
    M.close()
  end, opts)

  return bufnr
end

local function render()
  local explorer = explorer_state()
  local bufnr = ensure_buffer()
  local current = current_node()
  local visible = {}
  local lines = {}
  explorer.line_map = {}

  if explorer.workspace then
    visible = model.collect_visible(explorer.workspace, explorer.filter)
  end

  if #visible == 0 then
    local label = explorer.filter and explorer.filter ~= "" and "No matches" or "No test projects found"
    table.insert(lines, label)
  else
    for _, node in ipairs(visible) do
      local state_name, status = status_text(node)
      local summary = summary_text(node)
      local text = string.format("%s  %s  %s", status, summary, display_name(node))
      table.insert(lines, text)
      explorer.line_map[#lines] = node
      node._render_status = state_name
    end
  end

  vim.bo[bufnr].modifiable = true
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  vim.api.nvim_buf_clear_namespace(bufnr, explorer.ns, 0, -1)
  for index, node in pairs(explorer.line_map) do
    if node then
      local status = node._render_status or "not-run"
      vim.api.nvim_buf_add_highlight(bufnr, explorer.ns, STATUS_HL[status], index - 1, 0, 7)
      if node.kind ~= "test" then
        vim.api.nvim_buf_add_highlight(bufnr, explorer.ns, "DottestDirectory", index - 1, 16, -1)
      end
    end
  end
  vim.bo[bufnr].modifiable = false

  vim.api.nvim_buf_set_name(bufnr, "dottest://" .. (explorer.workspace and explorer.workspace.root or root.from_path()))
  vim.bo[bufnr].modified = false

  if is_valid_win(explorer.winid) then
    local target_line = 1
    if current then
      for line, node in pairs(explorer.line_map) do
        if node.id == current.id then
          target_line = line
          break
        end
      end
    end
    vim.api.nvim_win_set_cursor(explorer.winid, { target_line, 0 })
  end

  if is_valid_win(explorer.output_winid) then
    M.render_output()
  end
end

local function open_buffer()
  local explorer = explorer_state()
  local source_win = vim.api.nvim_get_current_win()
  local source_buf = vim.api.nvim_get_current_buf()
  if not (is_valid_buf(explorer.bufnr) and source_buf == explorer.bufnr) then
    explorer.last_source_win = source_win
    explorer.last_source_buf = source_buf
  end

  local bufnr = ensure_buffer()
  if is_valid_win(explorer.winid) then
    vim.api.nvim_set_current_win(explorer.winid)
    vim.api.nvim_win_set_buf(explorer.winid, bufnr)
    return
  end

  local winid = open_target_window()
  explorer.winid = winid
  vim.api.nvim_win_set_buf(winid, bufnr)
  vim.wo[winid].number = false
  vim.wo[winid].relativenumber = false
  vim.wo[winid].signcolumn = "no"
  vim.wo[winid].cursorline = true
  vim.wo[winid].wrap = false
end

local function ensure_output_buffer()
  local explorer = explorer_state()
  if is_valid_buf(explorer.output_bufnr) then
    return explorer.output_bufnr
  end

  local bufnr = vim.api.nvim_create_buf(false, true)
  explorer.output_bufnr = bufnr

  vim.bo[bufnr].buftype = "nofile"
  vim.bo[bufnr].bufhidden = "hide"
  vim.bo[bufnr].swapfile = false
  vim.bo[bufnr].modifiable = false
  vim.bo[bufnr].filetype = "dottest-output"

  local opts = { buffer = bufnr, nowait = true, silent = true }
  vim.keymap.set("n", "<CR>", function()
    jump_to_output_location()
  end, opts)
  vim.keymap.set("n", "q", function()
    M.close_output()
  end, opts)
  vim.keymap.set("n", "o", function()
    M.close_output()
  end, opts)

  return bufnr
end

local function open_output_window()
  local explorer = explorer_state()
  local bufnr = ensure_output_buffer()

  if is_valid_win(explorer.output_winid) then
    vim.api.nvim_win_set_buf(explorer.output_winid, bufnr)
    return explorer.output_winid
  end

  local base_win = is_valid_win(explorer.winid) and explorer.winid or vim.api.nvim_get_current_win()
  vim.api.nvim_set_current_win(base_win)
  vim.cmd("belowright " .. OUTPUT_HEIGHT .. "split")
  local winid = vim.api.nvim_get_current_win()
  explorer.output_winid = winid
  vim.api.nvim_win_set_buf(winid, bufnr)
  vim.wo[winid].number = false
  vim.wo[winid].relativenumber = false
  vim.wo[winid].wrap = false
  vim.wo[winid].cursorline = true
  return winid
end

local function output_lines(node, entry)
  local lines = {}
  local header = node and node.full_name or node and node.name or "Output"
  table.insert(lines, "Output: " .. header)
  table.insert(lines, "")

  if not entry then
    table.insert(lines, "No captured output for this node yet.")
    return lines
  end

  if entry.failed_tests and #entry.failed_tests > 0 then
    table.insert(lines, "Failed tests:")
    for _, name in ipairs(entry.failed_tests) do
      table.insert(lines, "  - " .. name)
    end
    table.insert(lines, "")
  end

  local body = vim.split(entry.output ~= "" and entry.output or "No output", "\n", { plain = true })
  vim.list_extend(lines, body)
  return lines
end

local function parse_output_location(line)
  if not line or line == "" then
    return nil
  end

  local file, lnum = line:match("%s+in%s+(.+):line%s+(%d+)%s*$")
  if file and lnum then
    return vim.fs.normalize(file), tonumber(lnum)
  end

  file, lnum = line:match("^(.+):(%d+):%d+")
  if file and lnum then
    return vim.fs.normalize(file), tonumber(lnum)
  end

  return nil
end

local function jump_to_output_location()
  local line = vim.api.nvim_get_current_line()
  local file, lnum = parse_output_location(line)
  if not file or vim.fn.filereadable(file) == 0 then
    vim.notify("[dottest.nvim] No file location on this line", vim.log.levels.WARN)
    return
  end

  vim.cmd("vsplit " .. vim.fn.fnameescape(file))
  vim.api.nvim_win_set_cursor(0, { lnum or 1, 0 })
end

local function load_next_project()
  local explorer = explorer_state()
  if explorer.loading or #explorer.load_queue == 0 or not explorer.workspace then
    return
  end

  local project_node = table.remove(explorer.load_queue, 1)
  if not project_node or project_node.loaded or project_node.loading then
    load_next_project()
    return
  end

  explorer.loading = true
  project_node.loading = true
  render()

  discovery.list_tests_async(project_node.project, function(tests, err)
    project_node.loading = false
    explorer.loading = false

    if err then
      project_node.load_error = err
    else
      project_node.load_error = nil
      model.populate_project(explorer.workspace, project_node.project.path, tests, explorer.expanded)
    end

    render()
    load_next_project()
  end, explorer.force_refresh)
end

local function queue_project_load(project_node)
  local explorer = explorer_state()
  if not project_node or project_node.loaded or project_node.loading then
    return
  end
  table.insert(explorer.load_queue, project_node)
end

local function target_from_node(node)
  if node.kind == "project" then
    return {
      kind = "project",
      name = node.name,
      project = node.project,
    }
  end

  return {
    kind = node.kind,
    name = node.full_name,
    filter = node.filter_name or node.full_name,
    project = node.project,
  }
end

local function collapse_passed_groups(node)
  if not node or node.kind == "test" then
    return
  end

  for _, child in ipairs(node.children or {}) do
    collapse_passed_groups(child)
  end

  local summary = model.summarize(node, explorer_state().statuses)
  if summary.total > 0 and summary.passed == summary.total then
    node.expanded = false
    explorer_state().expanded[node.id] = false
  end
end

function M.open()
  set_highlights()
  open_buffer()
  if not explorer_state().workspace then
    M.refresh()
  else
    render()
  end
end

function M.toggle()
  local explorer = explorer_state()
  local current_buf = vim.api.nvim_get_current_buf()
  if is_valid_buf(explorer.bufnr) and current_buf == explorer.bufnr then
    if is_valid_win(explorer.last_source_win) and is_valid_buf(explorer.last_source_buf) then
      vim.api.nvim_set_current_win(explorer.last_source_win)
      vim.api.nvim_win_set_buf(explorer.last_source_win, explorer.last_source_buf)
      return
    end
  end
  M.open()
end

function M.close()
  local explorer = explorer_state()
  M.close_output()
  if is_valid_win(explorer.winid) then
    vim.api.nvim_win_close(explorer.winid, true)
    explorer.winid = nil
  end
end

-- force: when true, bypasses the test list cache and re-runs dotnet test --list-tests.
-- gr keymap always passes force=true; opening the panel uses the cache.
function M.refresh(force)
  local explorer = explorer_state()
  explorer.force_refresh = force or false
  local discovered = discovery.find_test_projects()
  explorer.workspace_source = discovered
  explorer.workspace = model.make_workspace(discovered, explorer.expanded)
  explorer.statuses = {}
  explorer.outputs = {}
  explorer.line_map = {}
  explorer.load_queue = {}
  explorer.loading = false

  for _, project_node in ipairs(explorer.workspace.projects) do
    queue_project_load(project_node)
  end

  open_buffer()
  render()
  load_next_project()
end

function M.activate()
  local node = current_node()
  if not node then
    return
  end

  if node.kind == "test" then
    if get_node_output(node) then
      if not is_valid_win(explorer_state().output_winid) then
        open_output_window()
      end
      M.render_output()
      vim.api.nvim_set_current_win(explorer_state().output_winid)
    else
      runner.run_target(target_from_node(node))
    end
    return
  end

  node.expanded = not node.expanded
  explorer_state().expanded[node.id] = node.expanded
  if node.kind == "project" and node.expanded then
    queue_project_load(node)
    load_next_project()
  end
  render()
end

function M.collapse()
  local node = current_node()
  if not node then
    return
  end

  if node.kind ~= "test" and node.expanded then
    node.expanded = false
    explorer_state().expanded[node.id] = false
    render()
    return
  end

  local full_name = node.full_name or ""
  local parts = vim.split(full_name, ".", { plain = true, trimempty = true })
  table.remove(parts)
  if #parts == 0 then
    return
  end

  local parent_id = node.project.path .. "::scope::" .. table.concat(parts, ".")
  local parent = explorer_state().workspace.node_lookup[parent_id]
  if parent then
    for line, item in pairs(explorer_state().line_map) do
      if item.id == parent.id then
        vim.api.nvim_win_set_cursor(0, { line, 0 })
        break
      end
    end
  end
end

function M.run_target()
  local node = current_node()
  if not node then
    return
  end
  runner.run_target(target_from_node(node))
end

function M.render_output()
  local explorer = explorer_state()
  if not is_valid_win(explorer.output_winid) then
    return
  end

  local node = current_node()
  local entry = get_node_output(node)
  local bufnr = ensure_output_buffer()
  local lines = output_lines(node, entry)

  vim.bo[bufnr].modifiable = true
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  vim.api.nvim_buf_clear_namespace(bufnr, explorer.output_ns, 0, -1)
  vim.api.nvim_buf_add_highlight(bufnr, explorer.output_ns, "DottestOutputHeader", 0, 0, -1)
  for index, line in ipairs(lines) do
    if line:match("^  %- ") then
      vim.api.nvim_buf_add_highlight(bufnr, explorer.output_ns, "DottestOutputError", index - 1, 0, -1)
    end
  end
  vim.bo[bufnr].modifiable = false
  vim.bo[bufnr].modified = false
end

function M.toggle_output()
  local explorer = explorer_state()
  if is_valid_win(explorer.output_winid) then
    M.close_output()
    return
  end

  open_output_window()
  M.render_output()
  if is_valid_win(explorer.winid) then
    vim.api.nvim_set_current_win(explorer.winid)
  end
end

function M.close_output()
  local explorer = explorer_state()
  if is_valid_win(explorer.output_winid) then
    vim.api.nvim_win_close(explorer.output_winid, true)
    explorer.output_winid = nil
  end
end

function M.prompt_filter()
  vim.ui.input({ prompt = "Filter tests: ", default = explorer_state().filter or "" }, function(value)
    if value == nil then
      return
    end
    explorer_state().filter = vim.trim(value)
    render()
  end)
end

function M.clear_filter()
  explorer_state().filter = ""
  render()
end

function M.mark_running(target)
  local explorer = explorer_state()
  if not explorer.workspace or not target.project then
    return
  end

  local project_node = explorer.workspace.project_lookup[target.project.path]
  if not project_node then
    return
  end

  local node = project_node
  if target.kind ~= "project" and target.filter then
    local scope_id = target.project.path .. "::scope::" .. target.filter
    local test_id = target.project.path .. "::test::" .. target.filter
    node = explorer.workspace.node_lookup[test_id] or explorer.workspace.node_lookup[scope_id] or project_node
  end

  model.clear_subtree_status(node, explorer.statuses)
  explorer.statuses[node.id] = "running"
  render()
end

function M.complete_run(target, result)
  local explorer = explorer_state()
  if not explorer.workspace or not target.project then
    return
  end

  local project_node = explorer.workspace.project_lookup[target.project.path]
  if not project_node then
    return
  end

  local node = project_node
  if target.kind ~= "project" and target.filter then
    local scope_id = target.project.path .. "::scope::" .. target.filter
    local test_id = target.project.path .. "::test::" .. target.filter
    node = explorer.workspace.node_lookup[test_id] or explorer.workspace.node_lookup[scope_id] or project_node
  end

  explorer.statuses[node.id] = nil
  if result.outcomes then
    local applied = false
    for test_name, status in pairs(result.outcomes) do
      local test_id = model.resolve_test_id(explorer.workspace, target.project.path, test_name)
      if test_id then
        explorer.statuses[test_id] = status
        applied = true
      end
    end
    if not applied and node.kind == "test" then
      explorer.statuses[node.id] = result.ok and "passed" or "failed"
    end
  elseif node.kind == "test" then
    explorer.statuses[node.id] = result.ok and "passed" or "failed"
  end

  local failed_tests = {}
  for test_name, status in pairs(result.outcomes or {}) do
    if status == "failed" then
      table.insert(failed_tests, test_name)
    end
  end
  table.sort(failed_tests)

  explorer.outputs[node.id] = {
    output = result.output or "",
    failed_tests = failed_tests,
    ok = result.ok,
  }

  collapse_passed_groups(project_node)
  render()
end

return M
