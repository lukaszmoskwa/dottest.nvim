local M = {}

local markers = { ".git" }

local function normalize(path)
  return vim.fs.normalize(path)
end

function M.from_path(path)
  local start = path or vim.api.nvim_buf_get_name(0)
  if start == "" then
    start = vim.loop.cwd()
  end

  local base = vim.fn.fnamemodify(start, ":p")
  if vim.fn.isdirectory(base) == 0 then
    base = vim.fs.dirname(base)
  end

  local solution = vim.fs.find(function(name)
    return name:match("%.sln$")
  end, { upward = true, path = base, type = "file", limit = 1 })[1]

  if solution then
    return normalize(vim.fs.dirname(solution)), normalize(solution)
  end

  local root = vim.fs.find(markers, { upward = true, path = base, limit = 1 })[1]
  if root then
    return normalize(vim.fs.dirname(root)), nil
  end

  return normalize(base), nil
end

return M
