local config = require("template-center.config")
local store = require("template-center.store")

local M = { passed = 0, failures = {} }

---@param name string
---@param fn fun()
function M.test(name, fn)
  local ok, err = pcall(fn)
  if ok then
    M.passed = M.passed + 1
    print("  ok   " .. name)
  else
    M.failures[#M.failures + 1] = name
    print("  FAIL " .. name)
    print("       " .. tostring(err))
  end
end

function M.eq(actual, expected, what)
  if not vim.deep_equal(actual, expected) then
    error(
      ("%s\n  expected: %s\n  actual:   %s"):format(what or "not equal", vim.inspect(expected), vim.inspect(actual)),
      2
    )
  end
end

function M.truthy(value, what)
  if not value then
    error(what or "expected truthy", 2)
  end
end

--- A clean library for each test.
---@param opts table?
---@return string dir
function M.fresh(opts)
  local dir = vim.fn.tempname()
  config.setup(vim.tbl_deep_extend("force", { dir = dir }, opts or {}))
  store.reload_meta()
  store.ensure()
  return dir
end

return M
