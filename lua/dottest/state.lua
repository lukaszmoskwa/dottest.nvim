local M = {
  config = {},
  last_run = nil,
  explorer = {
    last_source_win = nil,
    last_source_buf = nil,
    winid = nil,
    bufnr = nil,
    output_winid = nil,
    output_bufnr = nil,
    ns = vim.api.nvim_create_namespace("dottest-explorer"),
    output_ns = vim.api.nvim_create_namespace("dottest-output"),
    workspace = nil,
    workspace_source = nil,
    statuses = {},
    outputs = {},
    line_map = {},
    expanded = {},
    filter = "",
    load_queue = {},
    loading = false,
  },
}

return M
