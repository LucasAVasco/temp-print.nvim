NVIM ?= nvim
DEPS_DIR := deps
MINI_DIR := $(DEPS_DIR)/mini.nvim

.PHONY: all test lint format format-check typecheck check deps deps-pickers clean

all: check

## Run every check (formatting, lint, types and tests)
check: format-check lint typecheck test

deps: $(MINI_DIR)

$(MINI_DIR):
	git clone --filter=blob:none --depth 1 https://github.com/echasnovski/mini.nvim $(MINI_DIR)

## Optional picker plugins used by tests/test_pickers.lua (skipped without them)
PICKERS := nvim-lua/plenary.nvim nvim-telescope/telescope.nvim ibhagwan/fzf-lua folke/snacks.nvim
deps-pickers:
	@for repo in $(PICKERS); do \
		dir=$(DEPS_DIR)/$${repo#*/}; \
		[ -d $$dir ] || git clone --filter=blob:none --depth 1 https://github.com/$$repo $$dir; \
	done

## Run the tests. Run a single file with: make test FILE=tests/test_insert.lua
test: deps
ifdef FILE
	$(NVIM) --headless --noplugin -u scripts/minimal_init.lua -c "lua MiniTest.run_file([[$(FILE)]])"
else
	$(NVIM) --headless --noplugin -u scripts/minimal_init.lua -c "lua MiniTest.run()"
endif

lint:
	luacheck lua temp-print tests scripts

format:
	stylua lua temp-print tests scripts

format-check:
	stylua --check lua temp-print tests scripts

typecheck: deps
	VIMRUNTIME=$$($(NVIM) --clean --headless +"lua io.write(vim.env.VIMRUNTIME)" +q) \
		lua-language-server --check=lua --checklevel=Warning --configpath=$(CURDIR)/.luarc.json --logpath=.typecheck

clean:
	rm -rf $(DEPS_DIR) .luacheckcache .typecheck
