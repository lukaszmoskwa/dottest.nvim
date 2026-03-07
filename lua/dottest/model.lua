local M = {}

local function sort_children(node)
  table.sort(node.children, function(a, b)
    if a.kind ~= b.kind then
      return a.kind == "scope"
    end
    return a.name:lower() < b.name:lower()
  end)

  for _, child in ipairs(node.children) do
    if child.children then
      sort_children(child)
    end
  end
end

local function tally_totals(node)
  if node.kind == "test" then
    node.total_tests = 1
    return 1
  end

  local total = 0
  for _, child in ipairs(node.children) do
    total = total + tally_totals(child)
  end
  node.total_tests = total
  return total
end

local function visible_match(node, filter)
  if not filter or filter == "" then
    return true
  end

  local haystacks = {
    node.name or "",
    node.full_name or "",
    node.project and node.project.name or "",
  }

  for _, value in ipairs(haystacks) do
    if value:lower():find(filter, 1, true) then
      return true
    end
  end

  return false
end

function M.make_workspace(discovered, expanded)
  local workspace = {
    root = discovered.root,
    solution = discovered.solution,
    projects = {},
    project_lookup = {},
    node_lookup = {},
  }

  for _, project in ipairs(discovered.projects) do
    local node = {
      id = project.path,
      kind = "project",
      name = project.name,
      full_name = project.name,
      project = project,
      children = {},
      expanded = expanded[project.path] ~= false,
      loaded = false,
      loading = false,
      load_error = nil,
      total_tests = 0,
    }
    table.insert(workspace.projects, node)
    workspace.project_lookup[project.path] = node
    workspace.node_lookup[node.id] = node
  end

  return workspace
end

function M.populate_project(workspace, project_path, tests, expanded)
  local project_node = workspace.project_lookup[project_path]
  if not project_node then
    return nil
  end

  local scope_lookup = {}
  project_node.children = {}

  for _, test in ipairs(tests) do
    local segments = vim.split(test.name, ".", { plain = true, trimempty = true })
    local leaf_name = table.remove(segments) or test.name
    local parent = project_node
    local full_scope = ""

    for _, segment in ipairs(segments) do
      full_scope = full_scope == "" and segment or (full_scope .. "." .. segment)
      local scope_id = project_path .. "::scope::" .. full_scope
      local scope = scope_lookup[scope_id]
      if not scope then
        scope = {
          id = scope_id,
          kind = "scope",
          name = segment,
          full_name = full_scope,
          project = project_node.project,
          children = {},
          expanded = expanded[scope_id] == true,
          total_tests = 0,
        }
        scope_lookup[scope_id] = scope
        workspace.node_lookup[scope_id] = scope
        table.insert(parent.children, scope)
      end
      parent = scope
    end

    local test_id = project_path .. "::test::" .. test.name
    local test_node = {
      id = test_id,
      kind = "test",
      name = leaf_name,
      full_name = test.name,
      filter_name = test.filter_name or test.name,
      project = project_node.project,
      children = {},
      expanded = false,
      total_tests = 1,
    }
    workspace.node_lookup[test_id] = test_node
    table.insert(parent.children, test_node)
  end

  sort_children(project_node)
  tally_totals(project_node)
  project_node.loaded = true
  project_node.loading = false
  project_node.load_error = nil
  return project_node
end

function M.iter_tree(node, callback)
  callback(node)
  for _, child in ipairs(node.children or {}) do
    M.iter_tree(child, callback)
  end
end

function M.clear_subtree_status(node, statuses)
  M.iter_tree(node, function(item)
    statuses[item.id] = nil
  end)
end

function M.resolve_test_id(workspace, project_path, test_name)
  local exact = project_path .. "::test::" .. test_name
  if workspace.node_lookup[exact] then
    return exact
  end

  local suffix = "::test::" .. test_name
  local matched
  for id, node in pairs(workspace.node_lookup) do
    if node.kind == "test" and node.project.path == project_path and id:sub(-#suffix) == suffix then
      if matched then
        return nil
      end
      matched = id
    end
  end
  return matched
end

function M.summarize(node, statuses)
  local explicit = statuses[node.id]
  if node.kind == "test" then
    local status = explicit or "not-run"
    return {
      status = status,
      total = 1,
      passed = status == "passed" and 1 or 0,
      failed = status == "failed" and 1 or 0,
      running = status == "running" and 1 or 0,
      completed = (status == "passed" or status == "failed") and 1 or 0,
    }
  end

  if explicit == "running" then
    return {
      status = "running",
      total = node.total_tests,
      passed = 0,
      failed = 0,
      running = node.total_tests > 0 and 1 or 0,
      completed = 0,
    }
  end

  local summary = {
    status = "not-run",
    total = node.total_tests,
    passed = 0,
    failed = 0,
    running = 0,
    completed = 0,
  }

  for _, child in ipairs(node.children) do
    local child_summary = M.summarize(child, statuses)
    summary.passed = summary.passed + child_summary.passed
    summary.failed = summary.failed + child_summary.failed
    summary.running = summary.running + child_summary.running
    summary.completed = summary.completed + child_summary.completed
  end

  if summary.running > 0 then
    summary.status = "running"
  elseif summary.failed > 0 then
    summary.status = "failed"
  elseif summary.total > 0 and summary.passed == summary.total then
    summary.status = "passed"
  elseif summary.completed > 0 then
    summary.status = "partial"
  else
    summary.status = "not-run"
  end

  return summary
end

local function collect_visible_node(node, filter, items)
  local match = visible_match(node, filter)
  local child_items = {}
  local child_matches = false

  if node.expanded or filter then
    for _, child in ipairs(node.children) do
      if collect_visible_node(child, filter, child_items) then
        child_matches = true
      end
    end
  end

  if filter and not match and not child_matches then
    return false
  end

  table.insert(items, node)
  for _, child in ipairs(child_items) do
    table.insert(items, child)
  end
  return true
end

function M.collect_visible(workspace, filter)
  local items = {}
  for _, project in ipairs(workspace.projects) do
    collect_visible_node(project, filter, items)
  end
  return items
end

function M.depth(node)
  if node.kind == "project" then
    return 0
  end
  local count = 1
  for _ in (node.full_name or ""):gmatch("%.") do
    count = count + 1
  end
  return count
end

return M
