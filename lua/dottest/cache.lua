local M = {}

local function cache_dir()
  return vim.fn.stdpath("data") .. "/dottest.nvim"
end

local function cache_path(project_path)
  return cache_dir() .. "/" .. vim.fn.sha256(project_path) .. ".json"
end

local function project_mtime(project_path)
  local stat = (vim.uv or vim.loop).fs_stat(project_path)
  return stat and stat.mtime.sec or nil
end

-- Returns the cached test list for project_path, or nil if missing/stale.
-- Stale means the .csproj mtime differs from when the cache was written.
function M.read(project_path)
  local path = cache_path(project_path)
  local ok, lines = pcall(vim.fn.readfile, path)
  if not ok then
    return nil
  end

  local ok2, entry = pcall(vim.json.decode, table.concat(lines, "\n"))
  if not ok2 or type(entry) ~= "table" then
    return nil
  end

  local mtime = project_mtime(project_path)
  if entry.mtime ~= mtime then
    return nil
  end

  return entry.tests
end

-- Writes the test list for project_path to the global cache directory.
-- Tests are stored without the project reference (reattached on read).
function M.write(project_path, tests)
  vim.fn.mkdir(cache_dir(), "p")
  local mtime = project_mtime(project_path)
  local to_store = {}
  for _, t in ipairs(tests) do
    table.insert(to_store, { kind = t.kind, name = t.name, filter_name = t.filter_name })
  end
  local ok, json = pcall(vim.json.encode, {
    project_path = project_path,
    mtime = mtime,
    tests = to_store,
  })
  if not ok then
    return
  end
  pcall(vim.fn.writefile, { json }, cache_path(project_path))
end

return M
