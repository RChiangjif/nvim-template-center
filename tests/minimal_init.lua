-- Minimal config for the tests and for poking at the plugin by hand:
--   nvim --headless -u tests/minimal_init.lua -c "luafile tests/run.lua" -c 'qa!'
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

-- Pick up telescope if this machine happens to have it, so that backend gets
-- exercised too. Without it everything runs through the vim.ui.select fallback.
for _, plugin in ipairs({ "plenary.nvim", "telescope.nvim" }) do
  local path = vim.fs.joinpath(vim.fn.stdpath("data"), "lazy", plugin)
  if vim.uv.fs_stat(path) then
    vim.opt.runtimepath:append(path)
  end
end

require("template-center").setup({
  -- Never touch the real library while playing around.
  dir = vim.fs.joinpath(vim.fn.stdpath("cache"), "template-center-dev"),
})
