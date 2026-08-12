" Sidebar lines read `/<id> <indent><name>`. The id only exists so a write can
" tell which file each line started as, so hide it. Needs conceallevel=3 on the
" window, which the explorer sets when it opens.
if exists("b:current_syntax")
  finish
endif

syntax match TemplateCenterId /^\/\d\+ / conceal
syntax match TemplateCenterDir /^\/\d\+ .*\/$/ contains=TemplateCenterId

highlight default link TemplateCenterDir Directory

let b:current_syntax = "templatecenter"
