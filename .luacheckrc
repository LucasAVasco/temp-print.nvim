std = "luajit"
cache = true
codes = true

-- Writable because options are set through it (vim.bo[buf].x = ..., vim.go.x = ...)
globals = { "vim" }

-- Line length is handled by stylua (long string templates can not be wrapped)
max_line_length = false

exclude_files = { "deps/" }

files["tests/"] = {
	read_globals = { "MiniTest" },
}
