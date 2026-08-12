-- nvim --headless -u tests/minimal_init.lua -c "luafile tests/run.lua" -c 'qa!'
-- 或 make test
--
-- 這裡刻意用 dofile 而不是 require：telescope 自己也有 lua/tests/helpers.lua，
-- 一旦它進了 runtimepath，require("tests.helpers") 就會拿到它的版本。
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
