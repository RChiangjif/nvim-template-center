-- 只註冊命令，實際的模組等到命令真的被叫到才 require，
-- 這樣沒有用 lazy.nvim 的人也是零啟動成本。
if vim.g.loaded_template_center then
  return
end
vim.g.loaded_template_center = true

if vim.fn.has("nvim-0.10") == 0 then
  vim.notify("template-center 需要 Neovim 0.10 以上", vim.log.levels.ERROR)
  return
end

require("template-center.commands").setup()
