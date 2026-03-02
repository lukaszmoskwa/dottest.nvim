local root = require("dottest.root")
local state = require("dottest.state")

local M = {}

local function plugin_root()
  local source = debug.getinfo(1, "S").source:sub(2)
  local lua_dir = vim.fs.dirname(source)
  return vim.fs.dirname(vim.fs.dirname(lua_dir))
end

local function ensure_server()
  if vim.v.servername ~= "" then
    return vim.v.servername
  end

  local socket = vim.fn.stdpath("run") .. "/dottest.nvim." .. vim.fn.getpid() .. ".sock"
  return vim.fn.serverstart(socket)
end

local function restore_window(winid, term_bufnr, previous_bufnr)
  vim.schedule(function()
    if not vim.api.nvim_win_is_valid(winid) then
      if vim.api.nvim_buf_is_valid(term_bufnr) then
        pcall(vim.api.nvim_buf_delete, term_bufnr, { force = true })
      end
      return
    end

    local replacement_bufnr = previous_bufnr
    if not replacement_bufnr or replacement_bufnr == term_bufnr or not vim.api.nvim_buf_is_valid(replacement_bufnr) then
      vim.cmd.enew()
      replacement_bufnr = vim.api.nvim_get_current_buf()
    end

    if vim.api.nvim_win_is_valid(winid) then
      vim.api.nvim_win_set_buf(winid, replacement_bufnr)
    end

    if vim.api.nvim_buf_is_valid(term_bufnr) then
      pcall(vim.api.nvim_buf_delete, term_bufnr, { force = true })
    end
  end)
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

local function open_terminal(cmd, cwd)
  local source_win = vim.api.nvim_get_current_win()
  local previous_bufnr = vim.api.nvim_get_current_buf()
  state.panel.last_source_win = source_win
  state.panel.last_source_buf = previous_bufnr

  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.bo[bufnr].buflisted = false
  state.panel.panel_buf = bufnr

  local winid = open_target_window()
  state.panel.panel_win = winid
  vim.api.nvim_win_set_buf(winid, bufnr)

  local job_id
  if vim.fn.has("nvim-0.11") == 1 then
    job_id = vim.fn.jobstart(cmd, {
      cwd = cwd,
      term = true,
      on_exit = function()
        restore_window(winid, bufnr, previous_bufnr)
        state.panel.panel_win = nil
        state.panel.panel_buf = nil
      end,
    })
  else
    ---@diagnostic disable-next-line: deprecated
    job_id = vim.fn.termopen(cmd, {
      cwd = cwd,
      on_exit = function()
        restore_window(winid, bufnr, previous_bufnr)
        state.panel.panel_win = nil
        state.panel.panel_buf = nil
      end,
    })
  end

  if not job_id or job_id <= 0 then
    vim.notify("[dottest.nvim] Failed to start Ink panel", vim.log.levels.ERROR)
    return
  end

  vim.schedule(function()
    if vim.api.nvim_buf_is_valid(bufnr) then
      vim.cmd.startinsert()
    end
  end)
end

function M.open()
  local workspace_root = root.from_path()
  local repo_root = plugin_root()
  local cli = repo_root .. "/ink/cli.mjs"
  local server = ensure_server()

  if vim.fn.filereadable(cli) == 0 then
    vim.notify("[dottest.nvim] Ink CLI not found: " .. cli, vim.log.levels.ERROR)
    return
  end

  open_terminal({
    "node",
    cli,
    "--cwd",
    workspace_root,
    "--nvim-server",
    server,
  }, workspace_root)
end

return M
