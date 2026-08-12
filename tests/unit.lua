-- The store's file operations plus the sidebar's parse/diff/apply pipeline —
-- everything that needs no UI.
--
-- "a collapsed directory never gets deleted" is the easiest thing here to get
-- wrong, so it is pinned twice: once as a unit test, once end to end.

local store = require("template-center.store")
local util = require("template-center.util")
local parse = require("template-center.explorer.parse")
local apply = require("template-center.explorer.apply")

---@return table<integer, tc.Node>
local function rendered_tree()
  return {
    [1] = { name = "cpp", path = "cpp", type = "directory" },
    [2] = { name = "dinic.cpp", path = "cpp/dinic.cpp", type = "file" },
    [3] = { name = "notes.txt", path = "notes.txt", type = "file" },
  }
end

local BASE = { "/1 cpp/", "/2   dinic.cpp", "/3 notes.txt" }

return function(h)
  local test, eq, truthy, fresh = h.test, h.eq, h.truthy, h.fresh

  --- A line without an id is new; a line with one maps back into `rendered`.
  local function plan_from(lines, rendered, exists)
    local nodes, perr = parse.parse(lines, { indent = 2 })
    truthy(nodes, perr and perr.msg)
    local ops, aerr = apply.plan(nodes, rendered, { exists = exists or function()
      return false
    end })
    return ops, aerr
  end

  print("\n[unit]")

  -- --------------------------------------------------------------------- util --

  test("dedent strips the shared indentation and keeps the relative one", function()
    eq(util.dedent({ "    if (x) {", "      y();", "    }" }), { "if (x) {", "  y();", "}" })
  end)

  test("dedent leaves lines alone when one starts at column 0", function()
    eq(util.dedent({ "int main() {", "  return 0;", "}" }), { "int main() {", "  return 0;", "}" })
  end)

  test("dedent ignores blank lines", function()
    eq(util.dedent({ "  a", "", "  b" }), { "a", "", "b" })
  end)

  test("validate_name rejects path separators and ..", function()
    truthy(util.validate_name("dinic.cpp"))
    truthy(not util.validate_name("a/b.cpp"))
    truthy(not util.validate_name(".."))
    truthy(not util.validate_name(""))
  end)

  -- -------------------------------------------------------------------- store --

  test("store writes, lists and reads", function()
    fresh()
    truthy(store.write("cpp/graph/dinic.cpp", { "// dinic", "struct Dinic {};" }))
    store.set_desc("cpp/graph/dinic.cpp", "max flow")

    local entries = store.list()
    eq(#entries, 1, "there should be exactly one template")
    eq(entries[1].name, "dinic")
    eq(entries[1].category, "cpp/graph")
    eq(entries[1].desc, "max flow")
    eq(store.read("cpp/graph/dinic.cpp"), { "// dinic", "struct Dinic {};" })
  end)

  test("store.children puts directories first", function()
    fresh()
    store.write("zzz.cpp", { "" })
    store.write("cpp/a.cpp", { "" })
    local nodes = store.children("")
    eq(#nodes, 2)
    eq(nodes[1].name, "cpp")
    eq(nodes[1].type, "directory")
    eq(nodes[2].name, "zzz.cpp")
  end)

  test("descriptions follow a move, including a whole directory", function()
    fresh()
    store.write("cpp/dinic.cpp", { "x" })
    store.set_desc("cpp/dinic.cpp", "max flow")

    truthy(store.move("cpp", "cxx"))
    eq(store.get_desc("cxx/dinic.cpp"), "max flow")
    eq(store.get_desc("cpp/dinic.cpp"), "")
    truthy(store.exists("cxx/dinic.cpp"))
  end)

  test("a copy carries the description too", function()
    fresh()
    store.write("a.cpp", { "x" })
    store.set_desc("a.cpp", "a description")
    truthy(store.copy("a.cpp", "b.cpp"))
    eq(store.read("b.cpp"), { "x" })
    eq(store.get_desc("b.cpp"), "a description")
    truthy(store.exists("a.cpp"), "the source should still be there")
  end)

  test("delete moves into .trash instead of unlinking", function()
    fresh()
    store.write("a.cpp", { "x" })
    truthy(store.remove("a.cpp"))
    truthy(not store.exists("a.cpp"))
    truthy(#vim.fn.readdir(store.trash_dir()) > 0, ".trash should have received it")
    eq(#store.list(), 0, ".trash must not show up in listings")
  end)

  -- -------------------------------------------------------------------- parse --

  test("parse rebuilds paths from indentation", function()
    local nodes = parse.parse({ "/1 cpp/", "/2   graph/", "/3     dinic.cpp", "/4 py/" }, { indent = 2 })
    eq(#nodes, 4)
    eq(nodes[3].path, "cpp/graph/dinic.cpp")
    eq(nodes[3].type, "file")
    eq(nodes[2].type, "directory")
    eq(nodes[4].path, "py")
  end)

  test("parse skips blank lines and treats id-less lines as new", function()
    local nodes = parse.parse({ "/1 cpp/", "", "  new.cpp" }, { indent = 2 })
    eq(#nodes, 2)
    eq(nodes[2].id, nil)
    eq(nodes[2].path, "cpp/new.cpp")
  end)

  test("parse rejects something indented underneath a file", function()
    local nodes, err = parse.parse({ "/1 a.cpp", "/2   b.cpp" }, { indent = 2 })
    eq(nodes, nil)
    eq(err.lnum, 2)
  end)

  test("parse rejects indentation jumping more than one level", function()
    local nodes, err = parse.parse({ "/1 cpp/", "/2     deep.cpp" }, { indent = 2 })
    eq(nodes, nil)
    eq(err.lnum, 2)
  end)

  test("parse rejects a duplicate name at the same level", function()
    local nodes, err = parse.parse({ "/1 a.cpp", "/2 a.cpp" }, { indent = 2 })
    eq(nodes, nil)
    eq(err.lnum, 2)
  end)

  test("parse rejects a name containing a path separator", function()
    local nodes, err = parse.parse({ "/1 cpp/dinic.cpp" }, { indent = 2 })
    eq(nodes, nil)
    eq(err.lnum, 1)
  end)

  test("parse allows the same name at different levels", function()
    local nodes = parse.parse({ "/1 cpp/", "/2   a.cpp", "/3 a.cpp" }, { indent = 2 })
    eq(#nodes, 3)
  end)

  -- --------------------------------------------------------------------- plan --

  test("editing a line is a rename", function()
    local ops = plan_from({ "/1 cpp/", "/2   maxflow.cpp", "/3 notes.txt" }, rendered_tree())
    eq(#ops, 1)
    eq(ops[1].kind, "move")
    eq(ops[1].src, "cpp/dinic.cpp")
    eq(ops[1].dst, "cpp/maxflow.cpp")
  end)

  test("outdenting a line moves it out of the directory", function()
    local ops = plan_from({ "/1 cpp/", "/2 dinic.cpp", "/3 notes.txt" }, rendered_tree())
    eq(#ops, 1)
    eq(ops[1].kind, "move")
    eq(ops[1].dst, "dinic.cpp")
  end)

  test("the same id twice is a copy", function()
    local ops = plan_from({ "/1 cpp/", "/2   dinic.cpp", "/2   dinic2.cpp", "/3 notes.txt" }, rendered_tree())
    eq(#ops, 1)
    eq(ops[1].kind, "copy")
    eq(ops[1].src, "cpp/dinic.cpp")
    eq(ops[1].dst, "cpp/dinic2.cpp")
  end)

  test("removing a line is a delete", function()
    local ops = plan_from({ "/1 cpp/", "/2   dinic.cpp" }, rendered_tree())
    eq(#ops, 1)
    eq(ops[1].kind, "delete")
    eq(ops[1].src, "notes.txt")
  end)

  test("deleting a whole subtree produces a single delete", function()
    local ops = plan_from({ "/3 notes.txt" }, rendered_tree())
    eq(#ops, 1)
    eq(ops[1].src, "cpp")
  end)

  test("new files and directories", function()
    local ops = plan_from({ "/1 cpp/", "/2   dinic.cpp", "  math/", "/3 notes.txt" }, rendered_tree())
    eq(#ops, 1)
    eq(ops[1].kind, "mkdir")
    eq(ops[1].dst, "cpp/math")
  end)

  test("no edits means no operations", function()
    eq(#plan_from(BASE, rendered_tree()), 0)
  end)

  test("a collapsed directory is never read as a delete", function()
    -- Only the `cpp/` line was drawn (collapsed), so the files under it never
    -- made it into `rendered`.
    local ops = plan_from({ "/1 cpp/" }, { [1] = { name = "cpp", path = "cpp", type = "directory" } })
    eq(#ops, 0)
  end)

  test("renaming a parent orders its children's moves after it", function()
    local ops = plan_from({ "/1 cxx/", "/2   maxflow.cpp", "/3 notes.txt" }, rendered_tree())
    eq(#ops, 2)
    eq(ops[1].src, "cpp", "the shallower one goes first")
    eq(ops[2].src, "cpp/dinic.cpp")
  end)

  test("rejects a target that already exists (possibly inside a collapsed dir)", function()
    local exists = function(path)
      return path == "cpp/dinic.cpp"
    end
    local _, err = plan_from({ "/1 cpp/", "  dinic.cpp" }, { [1] = { name = "cpp", path = "cpp", type = "directory" } }, exists)
    truthy(err, "this should have been rejected")
  end)

  test("rejects turning a file into a directory", function()
    local _, err = plan_from({ "/1 cpp/", "/2   dinic.cpp/", "/3 notes.txt" }, rendered_tree())
    truthy(err)
  end)

  test("rejects moving a directory inside itself", function()
    local rendered = {
      [1] = { name = "cpp", path = "cpp", type = "directory" },
      [2] = { name = "graph", path = "cpp/graph", type = "directory" },
    }
    local _, err = plan_from({ "/2 graph/", "/1   cpp/" }, rendered)
    truthy(err)
  end)

  -- ------------------------------------------------------------------ execute --

  test("renaming a parent and its child in one write", function()
    fresh()
    store.write("cpp/dinic.cpp", { "dinic" })
    store.write("notes.txt", { "notes" })

    local ops = plan_from({ "/1 cxx/", "/2   maxflow.cpp", "/3 notes.txt" }, rendered_tree(), store.exists)
    eq(apply.execute(ops), {})

    truthy(store.exists("cxx/maxflow.cpp"), "both renames should land on cxx/maxflow.cpp")
    eq(store.read("cxx/maxflow.cpp"), { "dinic" })
    truthy(not store.exists("cpp"), "the old directory should be gone")
  end)

  test("two files swapping names", function()
    fresh()
    store.write("a.cpp", { "AAA" })
    store.write("b.cpp", { "BBB" })

    local rendered = {
      [1] = { name = "a.cpp", path = "a.cpp", type = "file" },
      [2] = { name = "b.cpp", path = "b.cpp", type = "file" },
    }
    local ops = plan_from({ "/1 b.cpp", "/2 a.cpp" }, rendered, store.exists)
    eq(apply.execute(ops), {})

    eq(store.read("b.cpp"), { "AAA" })
    eq(store.read("a.cpp"), { "BBB" })
    truthy(not vim.uv.fs_stat(vim.fs.joinpath(store.root(), ".tmp-swap")), "the stash should be cleaned up")
  end)

  test("files inside a collapsed directory are left untouched", function()
    fresh()
    store.write("cpp/dinic.cpp", { "keep me" })
    store.write("notes.txt", { "x" })

    -- The user kept the collapsed `cpp/` line and deleted notes.txt.
    local rendered = {
      [1] = { name = "cpp", path = "cpp", type = "directory" },
      [2] = { name = "notes.txt", path = "notes.txt", type = "file" },
    }
    local ops = plan_from({ "/1 cpp/" }, rendered, store.exists)
    eq(apply.execute(ops), {})

    eq(store.read("cpp/dinic.cpp"), { "keep me" }, "nothing inside the collapsed directory should move")
    truthy(not store.exists("notes.txt"))
  end)

  test("create, copy and delete in one batch", function()
    fresh()
    store.write("cpp/dinic.cpp", { "dinic" })
    store.write("notes.txt", { "notes" })

    local ops = plan_from({
      "/1 cpp/",
      "/2   dinic.cpp",
      "/2   dinic_copy.cpp",
      "  math/",
    }, rendered_tree(), store.exists)
    eq(apply.execute(ops), {})

    eq(store.read("cpp/dinic_copy.cpp"), { "dinic" })
    truthy(vim.uv.fs_stat(vim.fs.joinpath(store.root(), "cpp/math")), "math/ should have been created")
    truthy(not store.exists("notes.txt"))
  end)
end
