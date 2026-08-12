local apply = require("template-center.explorer.apply")
local config = require("template-center.config")
local parse = require("template-center.explorer.parse")
local render = require("template-center.explorer.render")
local store = require("template-center.store")
local util = require("template-center.util")

--- 模板庫側邊欄：nerdtree 的形狀（可展開收合的樹）+ oil 的編輯方式
--- （整個 buffer 直接改，`:w` 才套用到檔案系統）。
---
--- 因為 buffer 要保持可編輯，所以 o / O / dd / cc / p / x / u 一律不佔用：
--- 新增檔案就是 `o` 打一行、刪除就是 `dd`、搬移就是把行往右縮排一層。
local M = {}

local BUF_NAME = "template-center://library"

local state = {
  buf = nil, ---@type integer?
  win = nil, ---@type integer?
  origin_win = nil, ---@type integer?
  rendered = {}, ---@type table<integer, tc.Node>
  line_of = {}, ---@type table<string, integer>
}

-- ------------------------------------------------------------------- 繪製 --

---@param reveal string? 畫完後把游標移到這個相對路徑上
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

  -- 重畫不該進 undo 歷史：`u` 一路退回上一次 render 的話，畫面上的 id 會對應
  -- 到已經失效的節點，接著存檔就會做出莫名其妙的事。
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
    util.warn("側邊欄有未儲存的變更：先 :w 套用，或 gr 放棄重讀")
    return true
  end
  return false
end

-- ------------------------------------------------------------------- 動作 --

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
    local choice = vim.fn.confirm("放棄未儲存的變更，重新讀取？", "放棄(&D)\n取消(&C)", 2, "Question")
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

-- ------------------------------------------------------------- 浮動視窗 --

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

  -- 沒有 focus，所以游標一動就收掉。
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
    lines = { "（空檔案）" }
  end
  float(lines, {
    title = node.path,
    filetype = vim.filetype.match({ filename = node.path }) or "",
    height = math.min(#lines, 24),
  })
end

function actions.help()
  local lines = {
    "模板庫側邊欄",
    "",
    "  這個 buffer 可以直接編輯，改完 :w 才會套用到檔案：",
    "    改行內容  → 改名（含副檔名）",
    "    dd        → 刪除（預設搬到 .trash/，不是真的刪掉）",
    "    o 打一行  → 新增檔案；結尾加 / 就是新增目錄",
    "    往右縮排  → 搬進上面那個目錄；往左縮排 → 搬出來",
    "    yyp 改名  → 複製一份",
    "",
    "  按鍵：",
  }
  local order = {}
  for lhs, action in pairs(config.options.explorer.keymaps) do
    order[#order + 1] = ("    %-8s %s"):format(lhs, action)
  end
  table.sort(order)
  vim.list_extend(lines, order)
  lines[#lines + 1] = ""
  lines[#lines + 1] = "  模板庫：" .. store.root()

  float(lines, { title = "說明", width = 68 })
end

-- ------------------------------------------------------------------- 存檔 --

--- 在 BufWriteCmd 裡直接 vim.notify 錯誤會讓 `:w` 帶著 E5113 traceback 爆掉，
--- 所以訊息一律排到 autocmd 外面再送。存檔失敗時 modified 保持著，`:wq` 也就
--- 不會把沒套用的變更吞掉。
---@param fn fun(msg: string)
---@param msg string
local function notify_later(fn, msg)
  vim.schedule(function()
    fn(msg)
  end)
end

--- `:w` 的實作：把 buffer 的內容當成「期望的樹」，算出要做哪些檔案操作。
function M.save()
  local buf = state.buf
  if not buf or not vim.api.nvim_buf_is_valid(buf) then
    return
  end

  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local nodes, perr = parse.parse(lines, { indent = config.options.explorer.indent })
  if not nodes then
    notify_later(util.error, ("第 %d 行：%s"):format(perr.lnum, perr.msg))
    if state.win and vim.api.nvim_win_is_valid(state.win) then
      vim.api.nvim_win_set_cursor(state.win, { perr.lnum, 0 })
    end
    return
  end

  local ops, aerr = apply.plan(nodes, state.rendered)
  if not ops then
    notify_later(util.error, ("第 %d 行：%s"):format(aerr.lnum, aerr.msg))
    return
  end

  if #ops == 0 then
    vim.bo[buf].modified = false
    notify_later(util.notify, "沒有變更")
    return
  end

  if config.options.explorer.confirm then
    local summary = apply.summary(ops)
    local shown = vim.list_slice(summary, 1, math.min(#summary, 15))
    if #summary > #shown then
      shown[#shown + 1] = ("…還有 %d 項"):format(#summary - #shown)
    end
    local msg = table.concat(shown, "\n") .. "\n\n套用這些變更？"
    if vim.fn.confirm(msg, "套用(&A)\n取消(&C)", 2, "Question") ~= 1 then
      notify_later(util.notify, "已取消，buffer 內容保留")
      return
    end
  end

  local errors = apply.execute(ops)
  draw()

  if #errors > 0 then
    notify_later(util.error, ("%d 項失敗：\n%s"):format(#errors, table.concat(errors, "\n")))
  else
    notify_later(util.notify, ("已套用 %d 項變更"):format(#ops))
  end
end

-- ------------------------------------------------------ buffer / window --

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
      util.warn(("未知的側邊欄動作：%s（%s）"):format(tostring(action), lhs))
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
    -- 行首的 `/<id> ` 靠這兩個設定藏起來。
    wo.conceallevel = 3
    wo.concealcursor = "nvic"
    wo.winbar = "%#Directory# 模板庫 %*%=%#Comment#g? 說明 %*"

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
  -- 側邊欄是分頁裡最後一個視窗時就留著，不然關掉它等於關掉 Neovim。
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

--- 外部（例如剛存了新模板）要求重畫；有未儲存的編輯就不動它。
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
