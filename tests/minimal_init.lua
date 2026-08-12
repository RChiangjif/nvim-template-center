-- 測試與手動試玩用的最小設定：
--   nvim --headless -u tests/minimal_init.lua -c "lua require('tests.run')()" -c qa
--   nvim -u tests/minimal_init.lua some.cpp
local this = debug.getinfo(1, "S").source:sub(2)
local root = vim.fs.dirname(vim.fs.dirname(vim.fs.normalize(this)))

vim.opt.runtimepath:prepend(root)
package.path = table.concat({
  root .. "/lua/?.lua",
  root .. "/lua/?/init.lua",
  root .. "/?.lua",
  package.path,
}, ";")

vim.opt.swapfile = false
vim.opt.shada = ""

-- 這台機器上有裝 telescope 的話就順便掛上，好連 telescope 那條路一起測；
-- 沒有的話一切照走 vim.ui.select fallback。
for _, plugin in ipairs({ "plenary.nvim", "telescope.nvim" }) do
  local path = vim.fs.joinpath(vim.fn.stdpath("data"), "lazy", plugin)
  if vim.uv.fs_stat(path) then
    vim.opt.runtimepath:append(path)
  end
end

require("template-center").setup({
  -- 手動試玩時不要碰到真的模板庫。
  dir = vim.fs.joinpath(vim.fn.stdpath("cache"), "template-center-dev"),
})
