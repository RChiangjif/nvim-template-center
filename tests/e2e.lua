-- The whole path: select in visual mode → save → pick → insert → expand, edit
-- and write the sidebar. vim.ui.input and vim.ui.select are swapped for versions
-- that answer themselves, which doubles as proof that the fallback picker really
-- does need nothing but those two hooks.
--
-- These are sequential scenarios: later tests build on the library state left by
-- the earlier ones.

local config = require("template-center.config")
local store = require("template-center.store")

return function(h)
  local test, eq, truthy, fresh = h.test, h.eq, h.truthy, h.fresh

  print("\n[e2e]")

  -- Pin the picker to the fallback so it still gets tested on a machine that
  -- happens to have telescope installed.
  local dir = fresh({ picker = "select", explorer = { confirm = false } })

  ---@param list string[]
  local function answer_with(list)
    local i = 0
    vim.ui.input = function(_, on_confirm)
      i = i + 1
      on_confirm(list[i])
    end
  end

  -- ------------------------------------------------------------------ capture --

  answer_with({ "cpp/graph", "max flow" }) -- name comes from the argument, then category and description

  local src = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_buf_set_name(src, dir .. "/scratch.cpp")
  vim.api.nvim_buf_set_lines(src, 0, -1, false, {
    "int main() {",
    "    for (int i = 0; i < n; i++) {",
    "        work(i);",
    "    }",
    "}",
  })
  vim.api.nvim_set_current_buf(src)
  require("template-center.capture").save({ line1 = 2, line2 = 4, name = "loop" })

  test("capture files it under the category as cpp/graph/loop.cpp", function()
    truthy(store.exists("cpp/graph/loop.cpp"))
  end)

  test("capture strips the shared indentation and keeps the inner one", function()
    eq(store.read("cpp/graph/loop.cpp"), {
      "for (int i = 0; i < n; i++) {",
      "    work(i);",
      "}",
    })
  end)

  test("capture records the description", function()
    eq(store.get_desc("cpp/graph/loop.cpp"), "max flow")
  end)

  -- ------------------------------------------------------ fallback picker + insert --

  store.write("cpp/snip.cpp", { "int ${1:n};", "$0" })

  local shown
  vim.ui.select = function(items, opts, on_choice)
    shown = { n = #items, first = opts.format_item(items[1]), kind = opts.kind }
    on_choice(items[1])
  end

  local target = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_set_current_buf(target)
  vim.api.nvim_buf_set_lines(target, 0, -1, false, { "int main() {", "    ", "}" })
  vim.api.nvim_win_set_cursor(0, { 2, 4 })
  require("template-center.picker").find()

  test("the fallback picker receives every template", function()
    eq(shown.n, 2)
  end)

  test("the fallback picker passes a kind for implementations like dressing", function()
    eq(shown.kind, "template-center")
  end)

  test("the fallback picker shows name, category and description on one line", function()
    eq(shown.first, "loop (cpp/graph) — max flow")
  end)

  test("inserting matches the cursor line's indentation and eats the blank line", function()
    eq(vim.api.nvim_buf_get_lines(target, 0, -1, false), {
      "int main() {",
      "    for (int i = 0; i < n; i++) {",
      "        work(i);",
      "    }",
      "}",
    })
  end)

  test("a template containing ${1:n} goes through snippet expansion", function()
    local buf = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_win_set_buf(0, buf)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "" })
    require("template-center.insert").insert("snip")

    eq(vim.api.nvim_buf_get_lines(buf, 0, -1, false)[1], "int n;")
    truthy(vim.snippet.active(), "it should be sitting on the placeholder waiting for input")
    -- expand selects the placeholder (select mode); get back to normal mode
    -- before moving on.
    vim.snippet.stop()
    vim.cmd("stopinsert")
  end)

  -- ---------------------------------------------------------------- telescope --

  -- Skipped when telescope isn't installed; CI exercises the fallback above.
  if pcall(require, "telescope") then
    test("telescope backend: columns, ordinal and the previewer's path", function()
      config.options.picker = "telescope"
      require("template-center.picker").find()

      local prompt_bufnr = vim.api.nvim_get_current_buf()
      local picker = require("telescope.actions.state").get_current_picker(prompt_bufnr)
      truthy(picker, "the telescope picker should be open")
      eq(picker.prompt_title, "Insert template")

      local entry = picker.finder.entry_maker(store.entry_of("cpp/graph/loop.cpp"))
      eq(entry.ordinal, "loop cpp/graph max flow", "category and description feed the fuzzy matcher")
      eq(entry.path, store.abspath("cpp/graph/loop.cpp"), "the previewer highlights based on this field")
      truthy(entry.display(entry):match("^loop%s+cpp/graph%s+max flow$"), "three columns")

      require("telescope.actions").close(prompt_bufnr)
      config.options.picker = "select"
    end)
  else
    print("  skip telescope backend (telescope.nvim not installed)")
  end

  -- ----------------------------------------------------------------- explorer --

  local explorer = require("template-center.explorer")
  explorer.open()
  local ebuf = vim.api.nvim_get_current_buf()
  local ewin = vim.api.nvim_get_current_win()

  local function lines()
    return vim.api.nvim_buf_get_lines(ebuf, 0, -1, false)
  end

  test("the sidebar is a writable acwrite buffer", function()
    eq(vim.bo[ebuf].buftype, "acwrite")
    eq(vim.bo[ebuf].filetype, "templatecenter")
    eq(vim.wo[ewin].conceallevel, 3, "the leading id has to be hidden")
  end)

  test("everything starts collapsed", function()
    eq(lines(), { "/1 cpp/" })
  end)

  test("<CR> expands a directory", function()
    explorer.actions.open_or_toggle()
    eq(lines(), { "/1 cpp/", "/2   graph/", "/3   snip.cpp" })

    vim.api.nvim_win_set_cursor(ewin, { 2, 0 })
    explorer.actions.open_or_toggle()
    eq(lines(), { "/1 cpp/", "/2   graph/", "/3     loop.cpp", "/4   snip.cpp" })
  end)

  test(":w applies a rename, an outdent-move and a new directory at once", function()
    vim.api.nvim_buf_set_lines(ebuf, 0, -1, false, {
      "/1 cpp/",
      "/2   graph/",
      "  math/",
      "/3   maxflow.cpp", -- renamed and moved out of graph/ into cpp/
      "/4   snip.cpp",
    })
    truthy(vim.bo[ebuf].modified)
    vim.cmd("silent write")

    truthy(store.exists("cpp/maxflow.cpp"), "the rename and move should both land")
    truthy(not store.exists("cpp/graph/loop.cpp"), "the old path should be gone")
    eq(store.read("cpp/maxflow.cpp"), {
      "for (int i = 0; i < n; i++) {",
      "    work(i);",
      "}",
    }, "contents must not be touched")
    eq(store.get_desc("cpp/maxflow.cpp"), "max flow", "the description follows along")
    truthy(vim.uv.fs_stat(vim.fs.joinpath(dir, "cpp/math")), "math/ should have been created")
    truthy(not vim.bo[ebuf].modified, "'modified' is cleared once written")
    eq(lines(), {
      "/1 cpp/",
      "/2   graph/",
      "/3   math/",
      "/4   maxflow.cpp",
      "/5   snip.cpp",
    }, "a write redraws and hands out fresh ids")
  end)

  test("deleting a line moves the file into .trash", function()
    vim.api.nvim_buf_set_lines(ebuf, 4, 5, false, {})
    vim.cmd("silent write")

    truthy(not store.exists("cpp/snip.cpp"))
    truthy(#vim.fn.readdir(store.trash_dir()) > 0, ".trash should have received it")
  end)

  test("a broken edit is rejected as a batch and :w doesn't blow up", function()
    vim.api.nvim_buf_set_lines(ebuf, 0, -1, false, { "/1 cpp/", "/4       deep.cpp" })
    local ok, err = pcall(vim.cmd, "silent write")

    truthy(ok, "BufWriteCmd must not rethrow: " .. tostring(err))
    truthy(vim.bo[ebuf].modified, "staying modified is what stops :wq from swallowing the edit")
    truthy(store.exists("cpp/maxflow.cpp"), "nothing on disk should have moved")
    truthy(not store.exists("deep.cpp"))
  end)

  explorer.close()

  -- ------------------------------------------------------ visual mode mapping --

  -- A clean library, so this doesn't disturb the scenario above.
  test("a visual mode mapping reads the selection you just made", function()
    fresh({ picker = "select" })
    answer_with({ "body", "", "" }) -- name, category (empty = top level), description

    vim.api.nvim_win_set_buf(0, src)
    vim.api.nvim_win_set_cursor(0, { 1, 0 })
    vim.keymap.set("v", "<F9>", function()
      require("template-center").save_selection()
    end, { buffer = src })

    -- :normal (without the bang, so mappings apply) rather than feedkeys: no
    -- racing against typeahead or escape sequence parsing, so it stays stable.
    vim.cmd("normal Vjj" .. vim.keycode("<F9>"))

    eq(store.read("body.cpp"), {
      "int main() {",
      "    for (int i = 0; i < n; i++) {",
      "        work(i);",
    }, "should be lines 1-3, not whatever '< and '> pointed at before")
  end)

  -- ---------------------------------------------------------- other positions --

  fresh({ picker = "select" })
  store.write("cpp/graph/dinic.cpp", { "struct Dinic {};" })
  store.write("hdr.cpp", { "#include <set>" })

  test("position=top lands after the last #include", function()
    local buf = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_win_set_buf(0, buf)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
      "#include <bits/stdc++.h>",
      "#include <vector>",
      "",
      "int main() {}",
    })
    vim.api.nvim_win_set_cursor(0, { 4, 0 })
    require("template-center.insert").insert("hdr", { position = "top" })

    eq(vim.api.nvim_buf_get_lines(buf, 0, -1, false)[3], "#include <set>")
  end)

  test("position=above lands on the line before the cursor", function()
    local buf = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_win_set_buf(0, buf)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "a", "b" })
    vim.api.nvim_win_set_cursor(0, { 2, 0 })
    require("template-center.insert").insert("hdr", { position = "above" })

    eq(vim.api.nvim_buf_get_lines(buf, 0, -1, false), { "a", "#include <set>", "b" })
  end)

  test("store.find takes either a name or a full relative path", function()
    eq(store.find("dinic").id, "cpp/graph/dinic.cpp")
    eq(store.find("cpp/graph/dinic.cpp").name, "dinic")
    eq(store.find("no such thing"), nil)
  end)

  test("the picker's reveal expands the ancestors and lands on the template", function()
    require("template-center.picker").actions.reveal(store.entry_of("cpp/graph/dinic.cpp"))

    eq(vim.api.nvim_buf_get_lines(0, 0, -1, false), {
      "/1 cpp/",
      "/2   graph/",
      "/3     dinic.cpp",
      "/4 hdr.cpp",
    })
    eq(vim.api.nvim_win_get_cursor(0)[1], 3)
  end)

  test("<C-p> opens a preview float", function()
    local before = #vim.api.nvim_list_wins()
    explorer.actions.preview()
    eq(#vim.api.nvim_list_wins(), before + 1)
  end)

  explorer.close()
end
