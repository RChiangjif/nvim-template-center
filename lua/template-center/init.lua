--- nvim-template-center: a competitive programming template library.
---
---   * select in visual mode, name it, and it's in the library
---   * a picker (telescope, or vim.ui.select when it isn't installed) finds a
---     template by name and inserts it
---   * a collapsible sidebar for the library that you can edit like a buffer
local M = {}

---@param opts tc.Config?
function M.setup(opts)
  require("template-center.config").setup(opts)
  require("template-center.commands").setup()
end

--- Save the range (or the whole buffer, without one) as a template.
---@param opts { line1: integer?, line2: integer?, bufnr: integer?, name: string? }?
function M.save(opts)
  require("template-center.capture").save(opts)
end

--- For visual mode mappings: leave visual mode first so '< and '> settle, then
--- read the range.
function M.save_selection()
  vim.cmd('execute "normal! \\<Esc>"')
  local line1 = vim.fn.line("'<")
  local line2 = vim.fn.line("'>")
  require("template-center.capture").save({ line1 = line1, line2 = line2 })
end

--- Open the picker; the choice is inserted into the current buffer.
---@param opts table?
function M.find(opts)
  require("template-center.picker").find(opts)
end

--- Open the picker; the choice is opened for editing.
---@param opts table?
function M.edit(opts)
  require("template-center.picker").open(opts)
end

--- Insert by name.
---@param name string
---@param opts table?
function M.insert(name, opts)
  require("template-center.insert").insert(name, opts)
end

---@param opts { focus: boolean?, reveal: string? }?
function M.toggle_tree(opts)
  require("template-center.explorer").toggle(opts)
end

---@param opts { focus: boolean?, reveal: string? }?
function M.open_tree(opts)
  require("template-center.explorer").open(opts)
end

--- Root of the template library.
---@return string
function M.root()
  return require("template-center.store").root()
end

return M
