local config = require("template-center.config")
local store = require("template-center.store")
local util = require("template-center.util")

--- The picker. telescope when it is installed, `vim.ui.select` otherwise — and
--- since dressing, snacks and fzf-lua all take that hook over themselves, there
--- is no need to write an adapter for each of them.
local M = {}

---@class tc.PickerContext
---@field win integer the window the picker was opened from; inserts and opens go there
---@field prompt string
---@field on_select fun(entry: tc.Entry, ctx: tc.PickerContext)

M.actions = {}

---@param entry tc.Entry
---@param ctx tc.PickerContext
function M.actions.insert(entry, ctx)
  require("template-center.insert").insert(entry, { win = ctx.win })
end

---@param entry tc.Entry
---@param ctx tc.PickerContext
function M.actions.edit(entry, ctx)
  local win = util.pick_target_win(ctx.win)
  vim.api.nvim_set_current_win(win)
  vim.cmd.edit(vim.fn.fnameescape(entry.path))
end

---@param entry tc.Entry
function M.actions.yank(entry)
  local lines = store.read(entry)
  if not lines then
    return
  end
  local text = table.concat(lines, "\n")
  vim.fn.setreg('"', text, "l")
  vim.fn.setreg("0", text, "l")
  util.notify(("Copied %s (%d lines), paste with p"):format(entry.id, #lines))
end

---@param entry tc.Entry
function M.actions.reveal(entry)
  require("template-center.explorer").open({ focus = true, reveal = entry.id })
end

---@return table? backend
local function backend()
  local choice = config.options.picker

  if choice ~= "select" then
    local ok, telescope = pcall(require, "template-center.picker.telescope")
    if ok and telescope.available() then
      return telescope
    end
    if choice == "telescope" then
      util.warn("telescope not found, falling back to vim.ui.select")
    end
  end

  return require("template-center.picker.select")
end

---@param opts { prompt: string?, win: integer?, on_select: fun(entry: tc.Entry, ctx: tc.PickerContext)? }?
function M.pick(opts)
  opts = opts or {}

  local entries = store.list()
  if #entries == 0 then
    util.warn(("The library is empty (%s). Save one with :TemplateCenter save"):format(store.root()))
    return
  end

  ---@type tc.PickerContext
  local ctx = {
    win = opts.win or vim.api.nvim_get_current_win(),
    prompt = opts.prompt or "Templates",
    on_select = opts.on_select or M.actions.insert,
  }

  backend().pick(entries, ctx)
end

--- Pick one and insert it into the current buffer.
---@param opts table?
function M.find(opts)
  opts = vim.tbl_extend("force", { prompt = "Insert template", on_select = M.actions.insert }, opts or {})
  M.pick(opts)
end

--- Pick one and open the template file itself for editing.
---@param opts table?
function M.open(opts)
  opts = vim.tbl_extend("force", { prompt = "Edit template", on_select = M.actions.edit }, opts or {})
  M.pick(opts)
end

return M
