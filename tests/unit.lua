-- store 的檔案操作，以及側邊欄的 parse／diff／套用（都不需要 UI）。
-- 「收合的目錄不會被誤刪」是最容易寫壞的地方，所以單元與整合各測一次。

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

  --- 沒有 id 的行 = 新增；有 id 的行對應到 rendered 裡的節點。
  local function plan_from(lines, rendered, exists)
    local nodes, perr = parse.parse(lines, { indent = 2 })
    truthy(nodes, perr and perr.msg)
    local ops, aerr = apply.plan(nodes, rendered, { exists = exists or function()
      return false
    end })
    return ops, aerr
  end

  print("\n[unit]")

  -- ------------------------------------------------------------------ util --

  test("dedent 去掉共同縮排、保留相對縮排", function()
    eq(util.dedent({ "    if (x) {", "      y();", "    }" }), { "if (x) {", "  y();", "}" })
  end)

  test("dedent 遇到頂格的行就不動", function()
    eq(util.dedent({ "int main() {", "  return 0;", "}" }), { "int main() {", "  return 0;", "}" })
  end)

  test("dedent 忽略空行", function()
    eq(util.dedent({ "  a", "", "  b" }), { "a", "", "b" })
  end)

  test("validate_name 擋掉路徑分隔與 ..", function()
    truthy(util.validate_name("dinic.cpp"))
    truthy(not util.validate_name("a/b.cpp"))
    truthy(not util.validate_name(".."))
    truthy(not util.validate_name(""))
  end)

  -- ----------------------------------------------------------------- store --

  test("store 寫入 / 列出 / 讀取", function()
    fresh()
    truthy(store.write("cpp/graph/dinic.cpp", { "// dinic", "struct Dinic {};" }))
    store.set_desc("cpp/graph/dinic.cpp", "最大流")

    local entries = store.list()
    eq(#entries, 1, "應該只有一個模板")
    eq(entries[1].name, "dinic")
    eq(entries[1].category, "cpp/graph")
    eq(entries[1].desc, "最大流")
    eq(store.read("cpp/graph/dinic.cpp"), { "// dinic", "struct Dinic {};" })
  end)

  test("store.children 目錄排前面", function()
    fresh()
    store.write("zzz.cpp", { "" })
    store.write("cpp/a.cpp", { "" })
    local nodes = store.children("")
    eq(#nodes, 2)
    eq(nodes[1].name, "cpp")
    eq(nodes[1].type, "directory")
    eq(nodes[2].name, "zzz.cpp")
  end)

  test("store 搬移時說明跟著搬（含整個目錄）", function()
    fresh()
    store.write("cpp/dinic.cpp", { "x" })
    store.set_desc("cpp/dinic.cpp", "最大流")

    truthy(store.move("cpp", "cxx"))
    eq(store.get_desc("cxx/dinic.cpp"), "最大流")
    eq(store.get_desc("cpp/dinic.cpp"), "")
    truthy(store.exists("cxx/dinic.cpp"))
  end)

  test("store 複製會帶著說明", function()
    fresh()
    store.write("a.cpp", { "x" })
    store.set_desc("a.cpp", "說明")
    truthy(store.copy("a.cpp", "b.cpp"))
    eq(store.read("b.cpp"), { "x" })
    eq(store.get_desc("b.cpp"), "說明")
    truthy(store.exists("a.cpp"), "來源不該消失")
  end)

  test("store 刪除是搬進 .trash", function()
    fresh()
    store.write("a.cpp", { "x" })
    truthy(store.remove("a.cpp"))
    truthy(not store.exists("a.cpp"))
    truthy(#vim.fn.readdir(store.trash_dir()) > 0, ".trash 應該接到東西")
    eq(#store.list(), 0, ".trash 不該出現在列表裡")
  end)

  -- ----------------------------------------------------------------- parse --

  test("parse 由縮排重建路徑", function()
    local nodes = parse.parse({ "/1 cpp/", "/2   graph/", "/3     dinic.cpp", "/4 py/" }, { indent = 2 })
    eq(#nodes, 4)
    eq(nodes[3].path, "cpp/graph/dinic.cpp")
    eq(nodes[3].type, "file")
    eq(nodes[2].type, "directory")
    eq(nodes[4].path, "py")
  end)

  test("parse 忽略空行、沒有 id 的行視為新增", function()
    local nodes = parse.parse({ "/1 cpp/", "", "  new.cpp" }, { indent = 2 })
    eq(#nodes, 2)
    eq(nodes[2].id, nil)
    eq(nodes[2].path, "cpp/new.cpp")
  end)

  test("parse 擋下：把東西縮排進一個檔案底下", function()
    local nodes, err = parse.parse({ "/1 a.cpp", "/2   b.cpp" }, { indent = 2 })
    eq(nodes, nil)
    eq(err.lnum, 2)
  end)

  test("parse 擋下：縮排一次跳超過一層", function()
    local nodes, err = parse.parse({ "/1 cpp/", "/2     deep.cpp" }, { indent = 2 })
    eq(nodes, nil)
    eq(err.lnum, 2)
  end)

  test("parse 擋下：同一層重複名稱", function()
    local nodes, err = parse.parse({ "/1 a.cpp", "/2 a.cpp" }, { indent = 2 })
    eq(nodes, nil)
    eq(err.lnum, 2)
  end)

  test("parse 擋下：名稱含路徑分隔", function()
    local nodes, err = parse.parse({ "/1 cpp/dinic.cpp" }, { indent = 2 })
    eq(nodes, nil)
    eq(err.lnum, 1)
  end)

  test("parse 不同層可以同名", function()
    local nodes = parse.parse({ "/1 cpp/", "/2   a.cpp", "/3 a.cpp" }, { indent = 2 })
    eq(#nodes, 3)
  end)

  -- ------------------------------------------------------------------ plan --

  test("plan 改行內容 = 改名", function()
    local ops = plan_from({ "/1 cpp/", "/2   maxflow.cpp", "/3 notes.txt" }, rendered_tree())
    eq(#ops, 1)
    eq(ops[1].kind, "move")
    eq(ops[1].src, "cpp/dinic.cpp")
    eq(ops[1].dst, "cpp/maxflow.cpp")
  end)

  test("plan 改縮排 = 搬出目錄", function()
    local ops = plan_from({ "/1 cpp/", "/2 dinic.cpp", "/3 notes.txt" }, rendered_tree())
    eq(#ops, 1)
    eq(ops[1].kind, "move")
    eq(ops[1].dst, "dinic.cpp")
  end)

  test("plan 同一個 id 出現兩次 = 複製", function()
    local ops = plan_from({ "/1 cpp/", "/2   dinic.cpp", "/2   dinic2.cpp", "/3 notes.txt" }, rendered_tree())
    eq(#ops, 1)
    eq(ops[1].kind, "copy")
    eq(ops[1].src, "cpp/dinic.cpp")
    eq(ops[1].dst, "cpp/dinic2.cpp")
  end)

  test("plan 刪掉行 = 刪除", function()
    local ops = plan_from({ "/1 cpp/", "/2   dinic.cpp" }, rendered_tree())
    eq(#ops, 1)
    eq(ops[1].kind, "delete")
    eq(ops[1].src, "notes.txt")
  end)

  test("plan 刪掉整個子樹只產生一筆刪除", function()
    local ops = plan_from({ "/3 notes.txt" }, rendered_tree())
    eq(#ops, 1)
    eq(ops[1].src, "cpp")
  end)

  test("plan 新增檔案與目錄", function()
    local ops = plan_from({ "/1 cpp/", "/2   dinic.cpp", "  math/", "/3 notes.txt" }, rendered_tree())
    eq(#ops, 1)
    eq(ops[1].kind, "mkdir")
    eq(ops[1].dst, "cpp/math")
  end)

  test("plan 沒改就沒有任何操作", function()
    eq(#plan_from(BASE, rendered_tree()), 0)
  end)

  test("plan 收合的目錄不會被當成刪除", function()
    -- 只畫出 cpp/ 一行（收合狀態），底下的檔案從來沒進 rendered。
    local ops = plan_from({ "/1 cpp/" }, { [1] = { name = "cpp", path = "cpp", type = "directory" } })
    eq(#ops, 0)
  end)

  test("plan 父目錄改名時，子項目的搬移排在後面", function()
    local ops = plan_from({ "/1 cxx/", "/2   maxflow.cpp", "/3 notes.txt" }, rendered_tree())
    eq(#ops, 2)
    eq(ops[1].src, "cpp", "淺的先搬")
    eq(ops[2].src, "cpp/dinic.cpp")
  end)

  test("plan 擋下：目標已經存在（可能藏在收合的目錄裡）", function()
    local exists = function(path)
      return path == "cpp/dinic.cpp"
    end
    local _, err = plan_from({ "/1 cpp/", "  dinic.cpp" }, { [1] = { name = "cpp", path = "cpp", type = "directory" } }, exists)
    truthy(err, "應該要報錯")
  end)

  test("plan 擋下：檔案被改成目錄", function()
    local _, err = plan_from({ "/1 cpp/", "/2   dinic.cpp/", "/3 notes.txt" }, rendered_tree())
    truthy(err)
  end)

  test("plan 擋下：目錄被搬進自己底下", function()
    local rendered = {
      [1] = { name = "cpp", path = "cpp", type = "directory" },
      [2] = { name = "graph", path = "cpp/graph", type = "directory" },
    }
    local _, err = plan_from({ "/2 graph/", "/1   cpp/" }, rendered)
    truthy(err)
  end)

  -- --------------------------------------------------------------- execute --

  test("execute 父目錄與子檔案同時改名", function()
    fresh()
    store.write("cpp/dinic.cpp", { "dinic" })
    store.write("notes.txt", { "notes" })

    local ops = plan_from({ "/1 cxx/", "/2   maxflow.cpp", "/3 notes.txt" }, rendered_tree(), store.exists)
    eq(apply.execute(ops), {})

    truthy(store.exists("cxx/maxflow.cpp"), "父子同時改名後應該落在 cxx/maxflow.cpp")
    eq(store.read("cxx/maxflow.cpp"), { "dinic" })
    truthy(not store.exists("cpp"), "舊目錄應該不見了")
  end)

  test("execute 兩個檔案互換名字", function()
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
    truthy(not vim.uv.fs_stat(vim.fs.joinpath(store.root(), ".tmp-swap")), "暫存區要清乾淨")
  end)

  test("execute 收合目錄底下的檔案原封不動", function()
    fresh()
    store.write("cpp/dinic.cpp", { "keep me" })
    store.write("notes.txt", { "x" })

    -- 使用者只是把收合狀態的 cpp/ 那行留著，然後刪掉 notes.txt。
    local rendered = {
      [1] = { name = "cpp", path = "cpp", type = "directory" },
      [2] = { name = "notes.txt", path = "notes.txt", type = "file" },
    }
    local ops = plan_from({ "/1 cpp/" }, rendered, store.exists)
    eq(apply.execute(ops), {})

    eq(store.read("cpp/dinic.cpp"), { "keep me" }, "收合目錄裡的檔案不該被動到")
    truthy(not store.exists("notes.txt"))
  end)

  test("execute 新增、複製、刪除混在一起", function()
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
    truthy(vim.uv.fs_stat(vim.fs.joinpath(store.root(), "cpp/math")), "math/ 應該被建出來")
    truthy(not store.exists("notes.txt"))
  end)
end
