local M = {}

---@return boolean
function M.available()
  return pcall(require, "telescope")
end

---@param entries tc.Entry[]
---@param ctx tc.PickerContext
function M.pick(entries, ctx)
  local pickers = require("telescope.pickers")
  local finders = require("telescope.finders")
  local conf = require("telescope.config").values
  local actions = require("telescope.actions")
  local action_state = require("telescope.actions.state")
  local entry_display = require("telescope.pickers.entry_display")

  local tc_actions = require("template-center.picker").actions

  local name_width = 12
  for _, entry in ipairs(entries) do
    name_width = math.max(name_width, #entry.name)
  end
  name_width = math.min(name_width, 32)

  local displayer = entry_display.create({
    separator = "  ",
    items = {
      { width = name_width },
      { width = 16 },
      { remaining = true },
    },
  })

  local function make_display(entry)
    return displayer({
      { entry.value.name, "TelescopeResultsIdentifier" },
      { entry.value.category, "TelescopeResultsComment" },
      { entry.value.desc, "TelescopeResultsComment" },
    })
  end

  ---@param selected table?
  ---@param fn fun(entry: tc.Entry, ctx: tc.PickerContext)
  local function run(prompt_bufnr, selected, fn)
    if not selected then
      return
    end
    actions.close(prompt_bufnr)
    fn(selected.value, ctx)
  end

  pickers
    .new({}, {
      prompt_title = ctx.prompt,
      finder = finders.new_table({
        results = entries,
        entry_maker = function(entry)
          return {
            value = entry,
            -- 分類與說明也吃得到模糊搜尋，打 "graph" 或 "最大流" 都找得到。
            ordinal = table.concat({ entry.name, entry.category, entry.desc }, " "),
            display = make_display,
            path = entry.path,
          }
        end,
      }),
      sorter = conf.generic_sorter({}),
      previewer = conf.file_previewer({}),
      attach_mappings = function(prompt_bufnr, map)
        actions.select_default:replace(function()
          run(prompt_bufnr, action_state.get_selected_entry(), ctx.on_select)
        end)
        map({ "i", "n" }, "<C-e>", function()
          run(prompt_bufnr, action_state.get_selected_entry(), tc_actions.edit)
        end)
        map({ "i", "n" }, "<C-y>", function()
          run(prompt_bufnr, action_state.get_selected_entry(), tc_actions.yank)
        end)
        map({ "i", "n" }, "<C-o>", function()
          run(prompt_bufnr, action_state.get_selected_entry(), tc_actions.reveal)
        end)
        return true
      end,
    })
    :find()
end

return M
