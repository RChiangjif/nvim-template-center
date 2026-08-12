-- 走完整條路：visual 選取 → 存模板 → picker → 插入 → 側邊欄展開／編輯／存檔。
-- vim.ui.input / vim.ui.select 會被換成自動作答的版本（這也順便驗證了
-- fallback picker 真的只用得到這兩個 hook）。
--
-- 這是一串有先後順序的情境，後面的測試吃前面留下的模板庫狀態。

local config = require("template-center.config")
local store = require("template-center.store")

return function(h)
  local test, eq, truthy, fresh = h.test, h.eq, h.truthy, h.fresh

  print("\n[e2e]")

  -- 先把 picker 釘在 fallback，才不會因為這台機器剛好有 telescope 就測不到它。
  local dir = fresh({ picker = "select", explorer = { confirm = false } })

  ---@param list string[]
  local function answer_with(list)
    local i = 0
    vim.ui.input = function(_, on_confirm)
      i = i + 1
      on_confirm(list[i])
    end
  end

  -- ---------------------------------------------------------------- capture --

  answer_with({ "cpp/graph", "最大流" }) -- 名稱由引數給，接著問分類、說明

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

  test("capture 依分類存進 cpp/graph/loop.cpp", function()
    truthy(store.exists("cpp/graph/loop.cpp"))
  end)

  test("capture 去掉共同縮排、保留內部縮排", function()
    eq(store.read("cpp/graph/loop.cpp"), {
      "for (int i = 0; i < n; i++) {",
      "    work(i);",
      "}",
    })
  end)

  test("capture 記下說明", function()
    eq(store.get_desc("cpp/graph/loop.cpp"), "最大流")
  end)

  -- --------------------------------------------------- picker fallback + 插入 --

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

  test("fallback picker 拿到全部模板", function()
    eq(shown.n, 2)
  end)

  test("fallback picker 帶上 kind 給 dressing 之類的實作分派", function()
    eq(shown.kind, "template-center")
  end)

  test("fallback picker 一行顯示名稱、分類、說明", function()
    eq(shown.first, "loop (cpp/graph) — 最大流")
  end)

  test("插入時對齊游標縮排，並吃掉原本的空行", function()
    eq(vim.api.nvim_buf_get_lines(target, 0, -1, false), {
      "int main() {",
      "    for (int i = 0; i < n; i++) {",
      "        work(i);",
      "    }",
      "}",
    })
  end)

  test("含 ${1:n} 的模板會走 snippet 展開", function()
    local buf = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_win_set_buf(0, buf)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "" })
    require("template-center.insert").insert("snip")

    eq(vim.api.nvim_buf_get_lines(buf, 0, -1, false)[1], "int n;")
    truthy(vim.snippet.active(), "應該停在 placeholder 上等你打字")
    -- expand 會把 placeholder 選起來（select mode），收工前要退回 normal mode。
    vim.snippet.stop()
    vim.cmd("stopinsert")
  end)

  -- -------------------------------------------------------------- telescope --

  -- 沒裝 telescope 就跳過；CI 上跑得起來的是上面的 fallback 那條路。
  if pcall(require, "telescope") then
    test("telescope 後端：欄位、ordinal、預覽用的 path 都對", function()
      config.options.picker = "telescope"
      require("template-center.picker").find()

      local prompt_bufnr = vim.api.nvim_get_current_buf()
      local picker = require("telescope.actions.state").get_current_picker(prompt_bufnr)
      truthy(picker, "telescope picker 應該開起來了")
      eq(picker.prompt_title, "插入模板")

      local entry = picker.finder.entry_maker(store.entry_of("cpp/graph/loop.cpp"))
      eq(entry.ordinal, "loop cpp/graph 最大流", "分類與說明也要吃得到模糊搜尋")
      eq(entry.path, store.abspath("cpp/graph/loop.cpp"), "previewer 靠這個欄位上色")
      truthy(entry.display(entry):match("^loop%s+cpp/graph%s+最大流$"), "三欄顯示")

      require("telescope.actions").close(prompt_bufnr)
      config.options.picker = "select"
    end)
  else
    print("  skip telescope 後端（沒裝 telescope.nvim）")
  end

  -- --------------------------------------------------------------- explorer --

  local explorer = require("template-center.explorer")
  explorer.open()
  local ebuf = vim.api.nvim_get_current_buf()
  local ewin = vim.api.nvim_get_current_win()

  local function lines()
    return vim.api.nvim_buf_get_lines(ebuf, 0, -1, false)
  end

  test("側邊欄是可寫回的 acwrite buffer", function()
    eq(vim.bo[ebuf].buftype, "acwrite")
    eq(vim.bo[ebuf].filetype, "templatecenter")
    eq(vim.wo[ewin].conceallevel, 3, "行首的 id 要藏起來")
  end)

  test("一開始全部收合", function()
    eq(lines(), { "/1 cpp/" })
  end)

  test("<CR> 展開目錄", function()
    explorer.actions.open_or_toggle()
    eq(lines(), { "/1 cpp/", "/2   graph/", "/3   snip.cpp" })

    vim.api.nvim_win_set_cursor(ewin, { 2, 0 })
    explorer.actions.open_or_toggle()
    eq(lines(), { "/1 cpp/", "/2   graph/", "/3     loop.cpp", "/4   snip.cpp" })
  end)

  test(":w 一次套用改名、往左縮排搬移、新增目錄", function()
    vim.api.nvim_buf_set_lines(ebuf, 0, -1, false, {
      "/1 cpp/",
      "/2   graph/",
      "  math/",
      "/3   maxflow.cpp", -- 改名 + 從 graph/ 搬到 cpp/
      "/4   snip.cpp",
    })
    truthy(vim.bo[ebuf].modified)
    vim.cmd("silent write")

    truthy(store.exists("cpp/maxflow.cpp"), "改名+搬移應該生效")
    truthy(not store.exists("cpp/graph/loop.cpp"), "舊路徑應該不見了")
    eq(store.read("cpp/maxflow.cpp"), {
      "for (int i = 0; i < n; i++) {",
      "    work(i);",
      "}",
    }, "內容不該被動到")
    eq(store.get_desc("cpp/maxflow.cpp"), "最大流", "說明要跟著搬")
    truthy(vim.uv.fs_stat(vim.fs.joinpath(dir, "cpp/math")), "math/ 應該被建出來")
    truthy(not vim.bo[ebuf].modified, "存完要清掉 modified")
    eq(lines(), {
      "/1 cpp/",
      "/2   graph/",
      "/3   math/",
      "/4   maxflow.cpp",
      "/5   snip.cpp",
    }, "存完要重畫並重新發 id")
  end)

  test("刪掉一行 = 把檔案搬進 .trash", function()
    vim.api.nvim_buf_set_lines(ebuf, 4, 5, false, {})
    vim.cmd("silent write")

    truthy(not store.exists("cpp/snip.cpp"))
    truthy(#vim.fn.readdir(store.trash_dir()) > 0, ".trash 應該接到東西")
  end)

  test("編壞的內容整批擋下，:w 不會爆 traceback", function()
    vim.api.nvim_buf_set_lines(ebuf, 0, -1, false, { "/1 cpp/", "/4       deep.cpp" })
    local ok, err = pcall(vim.cmd, "silent write")

    truthy(ok, "BufWriteCmd 不該把錯誤往上丟：" .. tostring(err))
    truthy(vim.bo[ebuf].modified, "沒套用成功就要維持 modified，:wq 才不會吞掉變更")
    truthy(store.exists("cpp/maxflow.cpp"), "擋下時檔案系統不該被動到")
    truthy(not store.exists("deep.cpp"))
  end)

  explorer.close()

  -- ------------------------------------------------------- visual mode 按鍵 --

  -- 換一個乾淨的模板庫，才不會干擾上面那串情境。
  test("visual mode 按鍵讀到的是這次框選的範圍", function()
    fresh({ picker = "select" })
    answer_with({ "body", "", "" }) -- 名稱、分類（留空 = 放最外層）、說明

    vim.api.nvim_win_set_buf(0, src)
    vim.api.nvim_win_set_cursor(0, { 1, 0 })
    vim.keymap.set("v", "<F9>", function()
      require("template-center").save_selection()
    end, { buffer = src })

    -- 用 :normal（不加 !，才會套用 mapping）而不是 feedkeys：不必跟 typeahead
    -- 和跳脫序列的解析搶時序，測起來才穩。
    vim.cmd("normal Vjj" .. vim.keycode("<F9>"))

    eq(store.read("body.cpp"), {
      "int main() {",
      "    for (int i = 0; i < n; i++) {",
      "        work(i);",
    }, "應該存到 1~3 行，而不是上一次留下的 '< '> 範圍")
  end)

  -- ------------------------------------------------------------ 其他插入位置 --

  fresh({ picker = "select" })
  store.write("cpp/graph/dinic.cpp", { "struct Dinic {};" })
  store.write("hdr.cpp", { "#include <set>" })

  test("position=top 插在最後一個 #include 之後", function()
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

  test("position=above 插在游標行上面", function()
    local buf = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_win_set_buf(0, buf)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "a", "b" })
    vim.api.nvim_win_set_cursor(0, { 2, 0 })
    require("template-center.insert").insert("hdr", { position = "above" })

    eq(vim.api.nvim_buf_get_lines(buf, 0, -1, false), { "a", "#include <set>", "b" })
  end)

  test("store.find 名稱與完整路徑都查得到", function()
    eq(store.find("dinic").id, "cpp/graph/dinic.cpp")
    eq(store.find("cpp/graph/dinic.cpp").name, "dinic")
    eq(store.find("沒這個東西"), nil)
  end)

  test("picker 的 reveal 會展開祖先並把游標停在該模板上", function()
    require("template-center.picker").actions.reveal(store.entry_of("cpp/graph/dinic.cpp"))

    eq(vim.api.nvim_buf_get_lines(0, 0, -1, false), {
      "/1 cpp/",
      "/2   graph/",
      "/3     dinic.cpp",
      "/4 hdr.cpp",
    })
    eq(vim.api.nvim_win_get_cursor(0)[1], 3)
  end)

  test("<C-p> 開得出預覽浮窗", function()
    local before = #vim.api.nvim_list_wins()
    explorer.actions.preview()
    eq(#vim.api.nvim_list_wins(), before + 1)
  end)

  explorer.close()
end
