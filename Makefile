.PHONY: test dev

test:
	@nvim --headless -u tests/minimal_init.lua -c "luafile tests/run.lua" -c 'qa!'

# A clean Neovim to play in; library lives in stdpath('cache')/template-center-dev
dev:
	@nvim -u tests/minimal_init.lua
