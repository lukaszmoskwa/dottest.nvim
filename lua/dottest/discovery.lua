local root = require("dottest.root")

local M = {}

local test_package_patterns = {
  "Microsoft%.NET%.Test%.Sdk",
  "xunit",
  "NUnit",
  "MSTest",
}

local function read_file(path)
  local ok, lines = pcall(vim.fn.readfile, path)
  if not ok then
    return nil
  end
  return table.concat(lines, "\n")
end

local function is_test_project(contents)
  if not contents or contents == "" then
    return false
  end

  if contents:match("<IsTestProject>%s*true%s*</IsTestProject>") then
    return true
  end

  for _, pattern in ipairs(test_package_patterns) do
    if contents:match(pattern) then
      return true
    end
  end

  return false
end

local function is_test_project_path(project_path, contents)
  local filename = vim.fn.fnamemodify(project_path, ":t")
  if filename:match("%.Tests?%.csproj$") then
    return true
  end

  if contents:match("TestProject%.props") then
    return true
  end

  if contents:match("<RootNamespace>.*%.Tests?</RootNamespace>") then
    return true
  end

  return is_test_project(contents)
end

local function project_name(path)
  return vim.fn.fnamemodify(path, ":t:r")
end

function M.find_test_projects(path)
  local workspace_root, solution_path = root.from_path(path)
  local csproj_paths = vim.fn.globpath(workspace_root, "**/*.csproj", false, true)
  local projects = {}

  for _, csproj in ipairs(csproj_paths) do
    local normalized = vim.fs.normalize(csproj)
    local contents = read_file(normalized)
    if is_test_project_path(normalized, contents or "") then
      table.insert(projects, {
        kind = "project",
        name = project_name(normalized),
        path = normalized,
        root = workspace_root,
        solution = solution_path,
      })
    end
  end

  table.sort(projects, function(a, b)
    return a.name < b.name
  end)

  return {
    root = workspace_root,
    solution = solution_path,
    projects = projects,
  }
end

local function trim_indent(line)
  return (line:gsub("^%s+", ""))
end

function M.list_tests(project)
  local cmd = {
    "dotnet",
    "test",
    project.path,
    "--list-tests",
    "--nologo",
    "--verbosity",
    "quiet",
  }

  local result = vim.system(cmd, { cwd = project.root, text = true }):wait()
  if result.code ~= 0 then
    return nil, result.stderr ~= "" and result.stderr or result.stdout
  end

  local tests = {}
  local seen = {}
  for line in vim.gsplit(result.stdout or "", "\n", { plain = true, trimempty = true }) do
    if line:match("^%s") and not line:match("^The following Tests") then
      local name = trim_indent(line)
      if name ~= "" and not seen[name] then
        seen[name] = true
        table.insert(tests, {
          kind = "test",
          name = name,
          project = project,
        })
      end
    end
  end

  return tests
end

local function nearest_match(patterns)
  local cursor = vim.api.nvim_win_get_cursor(0)[1]
  local lines = vim.api.nvim_buf_get_lines(0, 0, cursor, false)

  for i = #lines, 1, -1 do
    local line = lines[i]
    for _, pattern in ipairs(patterns) do
      local match = line:match(pattern)
      if match then
        return match
      end
    end
  end
end

function M.nearest_test(path)
  local file = path or vim.api.nvim_buf_get_name(0)
  if file == "" or not file:match("%.cs$") then
    return nil, "Current buffer is not a C# file"
  end

  local class_name = nearest_match({
    "class%s+([%w_]+)",
    "record%s+([%w_]+)",
    "struct%s+([%w_]+)",
  })

  local method_name = nearest_match({
    "public%s+[%w_<>,%[%]%?]+%s+([%w_]+)%s*%(",
    "async%s+[%w_<>,%[%]%?]+%s+([%w_]+)%s*%(",
  })

  local namespace_name = nearest_match({
    "namespace%s+([%w_%.]+)",
  })

  if not class_name then
    return nil, "Could not detect the nearest test class"
  end

  local fq_name = class_name
  if namespace_name then
    fq_name = namespace_name .. "." .. fq_name
  end
  if method_name then
    fq_name = fq_name .. "." .. method_name
  end

  local workspace = M.find_test_projects(file)
  local project_path
  for _, project in ipairs(workspace.projects) do
    local project_dir = vim.fs.dirname(project.path)
    if vim.startswith(vim.fs.normalize(file), project_dir) then
      project_path = project
      break
    end
  end

  if not project_path and #workspace.projects == 1 then
    project_path = workspace.projects[1]
  end

  if not project_path then
    return nil, "Could not determine the matching test project"
  end

  return {
    kind = method_name and "test" or "scope",
    name = fq_name,
    project = project_path,
    filter = fq_name,
  }
end

return M
