-- Register the command and nothing else; the modules are only required once a
-- command actually runs, so startup stays free even without lazy.nvim.
if vim.g.loaded_template_center then
  return
end
vim.g.loaded_template_center = true

if vim.fn.has("nvim-0.10") == 0 then
  vim.notify("template-center requires Neovim 0.10 or newer", vim.log.levels.ERROR)
  return
end

require("template-center.commands").setup()
