--- `:TemplateCenter <子命令>`。這個檔案在啟動時就會被 require，所以裡面
--- 一律延後 require，不要在載入時就把整個 plugin 拉進來。
local M = {}

---@type table<string, fun(args: string[], opts: table)>
local subcommands = {}

function subcommands.save(args, opts)
  require("template-center.capture").save({
    line1 = opts.range > 0 and opts.line1 or nil,
    line2 = opts.range > 0 and opts.line2 or nil,
    name = args[1],
  })
end

function subcommands.find()
  require("template-center.picker").find()
end

function subcommands.edit()
  require("template-center.picker").open()
end

function subcommands.insert(args)
  if args[1] then
    require("template-center.insert").insert(args[1])
  else
    require("template-center.picker").find()
  end
end

function subcommands.tree()
  require("template-center.explorer").toggle()
end

function subcommands.root()
  local store = require("template-center.store")
  store.ensure()
  vim.cmd.edit(vim.fn.fnameescape(store.root()))
end

local order = { "find", "save", "insert", "edit", "tree", "root" }

---@param arglead string
---@param candidates string[]
---@return string[]
local function filter(arglead, candidates)
  return vim.tbl_filter(function(item)
    return vim.startswith(item, arglead)
  end, candidates)
end

function M.setup()
  vim.api.nvim_create_user_command("TemplateCenter", function(opts)
    local args = vim.list_slice(opts.fargs, 2)
    local name = opts.fargs[1] or "find"
    local fn = subcommands[name]
    if not fn then
      vim.notify(
        ("未知的子命令 %q，可用：%s"):format(name, table.concat(order, " ")),
        vim.log.levels.ERROR,
        { title = "template-center" }
      )
      return
    end
    fn(args, opts)
  end, {
    nargs = "*",
    range = true,
    desc = "模板庫：" .. table.concat(order, " / "),
    complete = function(arglead, cmdline)
      local parts = vim.split(cmdline, "%s+")
      if #parts <= 2 then
        return filter(arglead, order)
      end
      if parts[2] == "insert" or parts[2] == "edit" then
        local names = {}
        for _, entry in ipairs(require("template-center.store").list()) do
          names[#names + 1] = entry.name
        end
        return filter(arglead, names)
      end
      return {}
    end,
  })
end

return M
