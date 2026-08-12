" 側邊欄的行是 `/<id> <縮排><名稱>`，前面的 id 只是給存檔時對照用的，藏起來。
" 需要視窗有 conceallevel=3（explorer 開視窗時會設）。
if exists("b:current_syntax")
  finish
endif

syntax match TemplateCenterId /^\/\d\+ / conceal
syntax match TemplateCenterDir /^\/\d\+ .*\/$/ contains=TemplateCenterId

highlight default link TemplateCenterDir Directory

let b:current_syntax = "templatecenter"
