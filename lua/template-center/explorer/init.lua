local apply = require("template-center.explorer.apply")
local config = require("template-center.config")
local parse = require("template-center.explorer.parse")
local render = require("template-center.explorer.render")
local store = require("template-center.store")
local util = require("template-center.util")

--- The library sidebar: nerdtree's shape (a collapsible tree) with oil's way of
--- editing it (change the buffer directly; nothing hits disk until `:w`).
---
--- The buffer has to stay editable, so o / O / dd / cc / p / x / u are all left
--- alone: you add a file by typing a line with `o`, delete with `dd`, and move
--- something by indenting its line one level.
local M = {}

local BUF_NAME = "template-center://library"

local state = {
  buf = nil, ---@type integer?
  win = nil, ---@type integer?
  origin_win = nil, ---@type integer?
  rendered = {}, ---@type table<integer, tc.Node>
  line_of = {}, ---@type table<string, integer>
}

-- ---------------------------------------------------------------- rendering --

---@param reveal string? put the cursor on this relative path once drawn
local function draw(reveal)
  local buf = state.buf
  if not buf or not vim.api.nvim_buf_is_valid(buf) then
    return
  end

  local result = render.build({
    expanded = store.expanded(),
    indent = config.options.explorer.indent,
  })
  state.rendered = result.rendered
  state.line_of = result.line_of

  -- Redraws must not enter the undo history: undoing back past a render would
  -- leave ids on screen that point at nodes we no longer know about, and the
  -- next write would then do something surprising.
  vim.api.nvim_buf_call(buf, function()
    local undolevels = vim.bo[buf].undolevels
    vim.bo[buf].undolevels = -1
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, result.lines)
    vim.bo[buf].undolevels = undolevels
  end)
  vim.bo[buf].modified = false

  if reveal and state.win and vim.api.nvim_win_is_valid(state.win) then
    local lnum = result.line_of[reveal]
    if lnum then
      vim.api.nvim_win_set_cursor(state.win, { lnum, 0 })
    end
  end
end

---@return boolean
local function has_pending_edits()
  if state.buf and vim.bo[state.buf].modified then
    util.warn("Sidebar has unsaved edits: :w to apply them, or gr to discard and reload")
    return true
  end
  return false
end

-- ------------------------------------------------------------------ actions --

---@return tc.Node?
local function node_under_cursor()
  if not state.win or not vim.api.nvim_win_is_valid(state.win) then
    return nil
  end
  local lnum = vim.api.nvim_win_get_cursor(state.win)[1]
  local line = vim.api.nvim_buf_get_lines(state.buf, lnum - 1, lnum, false)[1] or ""
  local id = render.id_of(line)
  return id and state.rendered[id] or nil
end

---@param relpath string
local function expand_ancestors(relpath)
  local parts = vim.split(relpath, "/", { plain = true })
  local acc = ""
  for i = 1, #parts - 1 do
    acc = acc == "" and parts[i] or (acc .. "/" .. parts[i])
    store.set_expanded(acc, true)
  end
end

---@param node tc.Node
---@param cmd string? "edit" | "split" | "tabedit"
local function open_file(node, cmd)
  local win = util.pick_target_win(state.origin_win)
  state.origin_win = win
  vim.api.nvim_set_current_win(win)
  vim.cmd(("%s %s"):format(cmd or "edit", vim.fn.fnameescape(node and store.abspath(node.path) or store.root())))
end

local actions = {}

function actions.toggle()
  local node = node_under_cursor()
  if not node or node.type ~= "directory" then
    return
  end
  if has_pending_edits() then
    return
  end
  local expanded = store.expanded()
  store.set_expanded(node.path, not expanded[node.path])
  draw(node.path)
end

function actions.open_or_toggle()
  local node = node_under_cursor()
  if not node then
    return
  end
  if node.type == "directory" then
    actions.toggle()
  else
    open_file(node)
  end
end

function actions.open_split()
  local node = node_under_cursor()
  if node and node.type == "file" then
    open_file(node, "split")
  end
end

function actions.open_tab()
  local node = node_under_cursor()
  if node and node.type == "file" then
    open_file(node, "tabedit")
  end
end

function actions.insert()
  local node = node_under_cursor()
  if not node or node.type ~= "file" then
    return
  end
  require("template-center.insert").insert(store.entry_of(node.path), { win = state.origin_win })
end

function actions.refresh()
  if state.buf and vim.bo[state.buf].modified then
    local choice = vim.fn.confirm("Discard unsaved edits and reload?", "&Discard\n&Cancel", 2, "Question")
    if choice ~= 1 then
      return
    end
    vim.bo[state.buf].modified = false
  end
  draw()
end

function actions.close()
  M.close()
end

-- ------------------------------------------------------------ floating wins --

---@param lines string[]
---@param opts { title: string, filetype: string?, width: integer?, height: integer? }
---@return integer win
local function float(lines, opts)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  vim.bo[buf].bufhidden = "wipe"
  if opts.filetype then
    vim.bo[buf].filetype = opts.filetype
  end

  local width = math.min(opts.width or 84, vim.o.columns - 8)
  local height = math.min(opts.height or #lines, vim.o.lines - 8)

  local win = vim.api.nvim_open_win(buf, false, {
    relative = "editor",
    width = math.max(width, 20),
    height = math.max(height, 1),
    row = math.max((vim.o.lines - height) / 2 - 1, 0),
    col = math.max((vim.o.columns - width) / 2, 0),
    style = "minimal",
    border = "rounded",
    title = " " .. opts.title .. " ",
    noautocmd = true,
  })
  vim.wo[win].wrap = false

  -- It never takes focus, so dismiss it as soon as the cursor moves.
  vim.api.nvim_create_autocmd({ "CursorMoved", "BufLeave", "WinScrolled" }, {
    buffer = state.buf,
    once = true,
    callback = function()
      if vim.api.nvim_win_is_valid(win) then
        vim.api.nvim_win_close(win, true)
      end
    end,
  })
  return win
end

function actions.preview()
  local node = node_under_cursor()
  if not node or node.type ~= "file" then
    return
  end
  local lines = store.read(node.path)
  if not lines then
    return
  end
  if #lines == 0 then
    lines = { "(empty file)" }
  end
  float(lines, {
    title = node.path,
    filetype = vim.filetype.match({ filename = node.path }) or "",
    height = math.min(#lines, 24),
  })
end

function actions.help()
  local lines = {
    "Template library sidebar",
    "",
    "  This buffer is editable; changes are applied on :w",
    "    edit a line     rename (extension included)",
    "    dd              delete (into .trash/, not actually removed)",
    "    o + type        new template; end with / to create a directory",
    "    indent          move into the directory above; outdent to move out",
    "    yyp + rename    make a copy",
    "",
    "  Mappings:",
  }
  local order = {}
  for lhs, action in pairs(config.options.explorer.keymaps) do
    order[#order + 1] = ("    %-8s %s"):format(lhs, action)
  end
  table.sort(order)
  vim.list_extend(lines, order)
  lines[#lines + 1] = ""
  lines[#lines + 1] = "  Library: " .. store.root()

  float(lines, { title = "Help", width = 68 })
end

-- ------------------------------------------------------------------ writing --

--- Calling vim.notify with an error straight from BufWriteCmd makes `:w` blow up
--- with an E5113 traceback, so messages are always deferred out of the autocmd.
--- A failed write leaves 'modified' set, which is what stops `:wq` from
--- swallowing changes that were never applied.
---@param fn fun(msg: string)
---@param msg string
local function notify_later(fn, msg)
  vim.schedule(function()
    fn(msg)
  end)
end

--- The `:w` implementation: read the buffer as the tree you want, then work out
--- which file operations get you there.
function M.save()
  local buf = state.buf
  if not buf or not vim.api.nvim_buf_is_valid(buf) then
    return
  end

  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local nodes, perr = parse.parse(lines, { indent = config.options.explorer.indent })
  if not nodes then
    notify_later(util.error, ("line %d: %s"):format(perr.lnum, perr.msg))
    if state.win and vim.api.nvim_win_is_valid(state.win) then
      vim.api.nvim_win_set_cursor(state.win, { perr.lnum, 0 })
    end
    return
  end

  local ops, aerr = apply.plan(nodes, state.rendered)
  if not ops then
    notify_later(util.error, ("line %d: %s"):format(aerr.lnum, aerr.msg))
    return
  end

  if #ops == 0 then
    vim.bo[buf].modified = false
    notify_later(util.notify, "No changes")
    return
  end

  if config.options.explorer.confirm then
    local summary = apply.summary(ops)
    local shown = vim.list_slice(summary, 1, math.min(#summary, 15))
    if #summary > #shown then
      shown[#shown + 1] = ("… and %d more"):format(#summary - #shown)
    end
    local msg = table.concat(shown, "\n") .. "\n\nApply these changes?"
    if vim.fn.confirm(msg, "&Apply\n&Cancel", 2, "Question") ~= 1 then
      notify_later(util.notify, "Cancelled; the buffer is left as you had it")
      return
    end
  end

  local errors = apply.execute(ops)
  draw()

  if #errors > 0 then
    notify_later(util.error, ("%d operation(s) failed:\n%s"):format(#errors, table.concat(errors, "\n")))
  else
    notify_later(util.notify, ("Applied %d change(s)"):format(#ops))
  end
end

-- ----------------------------------------------------------- buffer /  window --

---@return integer buf
local function ensure_buf()
  if state.buf and vim.api.nvim_buf_is_valid(state.buf) then
    return state.buf
  end

  local buf = vim.api.nvim_create_buf(false, false)
  if not pcall(vim.api.nvim_buf_set_name, buf, BUF_NAME) then
    pcall(vim.api.nvim_buf_set_name, buf, ("%s.%d"):format(BUF_NAME, buf))
  end

  vim.bo[buf].buftype = "acwrite"
  vim.bo[buf].swapfile = false
  vim.bo[buf].bufhidden = "hide"
  vim.bo[buf].buflisted = false
  vim.bo[buf].filetype = "templatecenter"

  for lhs, action in pairs(config.options.explorer.keymaps) do
    local fn = actions[action]
    if fn then
      vim.keymap.set("n", lhs, fn, { buffer = buf, nowait = true, desc = "template-center: " .. action })
    else
      util.warn(("Unknown sidebar action %q (mapped to %s)"):format(tostring(action), lhs))
    end
  end

  vim.api.nvim_create_autocmd("BufWriteCmd", {
    buffer = buf,
    callback = function()
      M.save()
    end,
  })

  state.buf = buf
  return buf
end

---@return boolean
function M.is_open()
  return state.win ~= nil and vim.api.nvim_win_is_valid(state.win)
end

---@param opts { focus: boolean?, reveal: string? }?
function M.open(opts)
  opts = opts or {}
  store.ensure()

  local cur = vim.api.nvim_get_current_win()
  if not M.is_open() or cur ~= state.win then
    if util.is_usable_win(cur) then
      state.origin_win = cur
    end
  end

  if opts.reveal then
    expand_ancestors(opts.reveal)
  end

  local buf = ensure_buf()

  if not M.is_open() then
    local cfg = config.options.explorer
    vim.cmd(cfg.side == "right" and "botright vsplit" or "topleft vsplit")
    local win = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(win, buf)
    vim.api.nvim_win_set_width(win, cfg.width)

    local wo = vim.wo[win]
    wo.number = false
    wo.relativenumber = false
    wo.signcolumn = "no"
    wo.foldcolumn = "0"
    wo.wrap = false
    wo.winfixwidth = true
    wo.cursorline = true
    -- These two are what hide the `/<id> ` prefix at the start of every line.
    wo.conceallevel = 3
    wo.concealcursor = "nvic"
    wo.winbar = "%#Directory# Templates %*%=%#Comment#g? help %*"

    state.win = win
  end

  draw(opts.reveal)

  if opts.focus == false then
    if state.origin_win and vim.api.nvim_win_is_valid(state.origin_win) then
      vim.api.nvim_set_current_win(state.origin_win)
    end
  else
    vim.api.nvim_set_current_win(state.win)
  end
end

function M.close()
  -- Leave it alone when it is the last window in the tabpage; closing it there
  -- would mean quitting Neovim.
  if M.is_open() and #vim.api.nvim_tabpage_list_wins(0) > 1 then
    vim.api.nvim_win_close(state.win, false)
    state.win = nil
  end
end

---@param opts table?
function M.toggle(opts)
  if M.is_open() then
    M.close()
  else
    M.open(opts)
  end
end

--- Redraw on request from elsewhere (a template was just saved, say). Unsaved
--- edits are left untouched.
---@param reveal string?
function M.refresh(reveal)
  if not state.buf or not vim.api.nvim_buf_is_valid(state.buf) then
    return
  end
  if vim.bo[state.buf].modified then
    return
  end
  if reveal then
    expand_ancestors(reveal)
  end
  draw(reveal)
end

M.actions = actions

return M
