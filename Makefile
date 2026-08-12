.PHONY: test dev

test:
	@nvim --headless -u tests/minimal_init.lua -c "luafile tests/run.lua" -c 'qa!'

# 拿一個乾淨的 Neovim 手動試玩（模板庫在 stdpath('cache')/template-center-dev）
dev:
	@nvim -u tests/minimal_init.lua
