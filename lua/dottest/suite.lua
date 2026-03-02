local root = require("dottest.root")
local state = require("dottest.state")

local M = {}

local function suite_path(path)
  local workspace_root = root.from_path(path)
  return workspace_root .. "/" .. state.config.suite_dirname .. "/" .. state.config.suite_filename
end

local function load_json(path)
  if vim.fn.filereadable(path) == 0 then
    return { suites = {} }
  end

  local ok, lines = pcall(vim.fn.readfile, path)
  if not ok then
    return { suites = {} }
  end

  local ok_decode, decoded = pcall(vim.json.decode, table.concat(lines, "\n"))
  if not ok_decode or type(decoded) ~= "table" then
    return { suites = {} }
  end

  decoded.suites = decoded.suites or {}
  return decoded
end

local function write_json(path, payload)
  vim.fn.mkdir(vim.fs.dirname(path), "p")
  local encoded = vim.json.encode(payload)
  vim.fn.writefile(vim.split(encoded, "\n", { plain = true }), path)
end

local function item_key(item)
  return table.concat({
    item.kind or "",
    item.name or "",
    item.filter or "",
    item.project and item.project.path or "",
  }, "::")
end

function M.list(path)
  local data = load_json(suite_path(path))
  return data.suites
end

function M.save(name, items, path)
  local file = suite_path(path)
  local data = load_json(file)
  local next_suites = {}
  local inserted = false

  for _, suite in ipairs(data.suites) do
    if suite.name == name then
      local merged = {}
      local seen = {}

      for _, item in ipairs(suite.items or {}) do
        local key = item_key(item)
        if not seen[key] then
          seen[key] = true
          table.insert(merged, item)
        end
      end

      for _, item in ipairs(items) do
        local key = item_key(item)
        if not seen[key] then
          seen[key] = true
          table.insert(merged, item)
        end
      end

      table.insert(next_suites, {
        name = name,
        items = merged,
      })
      inserted = true
    else
      table.insert(next_suites, suite)
    end
  end

  if not inserted then
    table.insert(next_suites, {
      name = name,
      items = items,
    })
  end

  table.sort(next_suites, function(a, b)
    return a.name < b.name
  end)

  write_json(file, { suites = next_suites })
end

function M.rename(old_name, new_name, path)
  local file = suite_path(path)
  local data = load_json(file)
  local next_suites = {}

  for _, suite in ipairs(data.suites) do
    if suite.name == old_name then
      table.insert(next_suites, { name = new_name, items = suite.items or {} })
    else
      table.insert(next_suites, suite)
    end
  end

  table.sort(next_suites, function(a, b)
    return a.name < b.name
  end)

  write_json(file, { suites = next_suites })
end

function M.delete(name, path)
  local file = suite_path(path)
  local data = load_json(file)
  local next_suites = {}

  for _, suite in ipairs(data.suites) do
    if suite.name ~= name then
      table.insert(next_suites, suite)
    end
  end

  write_json(file, { suites = next_suites })
end

return M
