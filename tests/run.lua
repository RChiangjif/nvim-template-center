-- nvim --headless -u tests/minimal_init.lua -c "luafile tests/run.lua" -c 'qa!'
-- or: make test
--
-- dofile rather than require on purpose: telescope ships its own
-- lua/tests/helpers.lua, and once it is on the runtimepath
-- require("tests.helpers") picks up that one instead.
local dir = vim.fs.dirname(vim.fs.normalize(debug.getinfo(1, "S").source:sub(2)))

local h = dofile(dir .. "/helpers.lua")

print("template-center tests")
dofile(dir .. "/unit.lua")(h)
dofile(dir .. "/e2e.lua")(h)

print(("\n%d passed, %d failed"):format(h.passed, #h.failures))
if #h.failures > 0 then
  for _, name in ipairs(h.failures) do
    print("  - " .. name)
  end
  vim.cmd("cquit 1")
end
