local M = {}

M.defaults = {
  suite_dirname = ".dottest",
  suite_filename = "suites.json",
  keymap = false,
  keymap_mode = "n",
  panel = {
    open_mode = "current_buffer",
    split = {
      position = "botright",
      direction = "vsplit",
      size = 70,
    },
  },
}

function M.merge(opts)
  return vim.tbl_deep_extend("force", {}, M.defaults, opts or {})
end

return M
