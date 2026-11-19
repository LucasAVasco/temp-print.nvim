local H = dofile("tests/helpers.lua")
local eq = H.eq

local child, T = H.new_set()

---Effective configuration of a filetype, with functions replaced by "function"
local function get_config(filetype)
    return child.lua(
        [[
        local config = require("temp-print.config.language").get_filetype_config(...)
        if not config then return vim.NIL end
        local function sanitize(value)
            if type(value) == "function" then return "function" end
            if type(value) == "table" then
                local result = {}
                for k, v in pairs(value) do result[k] = sanitize(v) end
                return result
            end
            return value
        end
        return sanitize(config)
    ]],
        { filetype }
    )
end

T["filetype configuration"] = MiniTest.new_set()

T["filetype configuration"]["next line prints fall back to the previous line configuration"] = function()
    local config = get_config("go")
    eq(config.print_next_line, config.print_previous_line)
    eq(config.escape, "function")
end

T["filetype configuration"]["returns nil for unknown filetypes"] = function()
    eq(get_config("unknown-filetype"), vim.NIL)
end

T["filetype configuration"]["setup languages are merged over the bundled file"] = function()
    H.lua(child, [[TempPrint.setup({ languages = { go = { print_location = { command = "custom" } } } })]])
    local config = get_config("go")
    eq(config.print_location.command, "custom")
    eq(config.print_variable.command:find("fmt.Printf", 1, true) ~= nil, true)
end

T["filetype configuration"]["supports filetypes defined only in setup()"] = function()
    H.lua(child, [[TempPrint.setup({ languages = { foo = { print_variable = { command = "show(<VAR>)" } } } })]])
    eq(get_config("foo").print_variable.command, "show(<VAR>)")
end

T["filetype configuration"]["re-running setup() clears the cache"] = function()
    H.lua(child, [[TempPrint.setup({ languages = { go = { print_location = { command = "first" } } } })]])
    eq(get_config("go").print_location.command, "first")
    H.lua(child, [[TempPrint.setup({ languages = { go = { print_location = { command = "second" } } } })]])
    eq(get_config("go").print_location.command, "second")
end

T["filetype configuration"]["user files are merged over the plugin ones, and setup() over both"] = function()
    local config_home = vim.fn.tempname()
    vim.fn.mkdir(config_home .. "/nvim/temp-print/config", "p")
    vim.fn.writefile({
        'return { print_location = { command = "USER" }, print_previous_line = { command = "USER LINE" } }',
    }, config_home .. "/nvim/temp-print/config/go.lua")

    local previous = vim.env.XDG_CONFIG_HOME
    vim.env.XDG_CONFIG_HOME = config_home
    H.restart(child)
    vim.env.XDG_CONFIG_HOME = previous

    local config = get_config("go")
    eq(config.print_location.command, "USER")
    eq(config.print_next_line.command, "USER LINE")
    eq(config.print_variable.command:find("fmt.Printf", 1, true) ~= nil, true)

    H.lua(child, [[TempPrint.setup({ languages = { go = { print_location = { command = "SETUP" } } } })]])
    eq(get_config("go").print_location.command, "SETUP")
end

T["filetype configuration"]["every bundled file is valid"] = function()
    for _, file in ipairs(vim.fn.glob("temp-print/config/*.lua", false, true)) do
        local filetype = vim.fn.fnamemodify(file, ":t:r")
        local config = get_config(filetype)
        for _, key in ipairs({ "print_location", "print_variable", "print_previous_line", "print_next_line" }) do
            eq({ filetype, key, type(config[key].command) }, { filetype, key, "string" })
        end
        -- Variable prints are never updated, so a line number would become wrong
        eq({ filetype, config.print_variable.command:find("<LINE_NUMBER>", 1, true) }, { filetype, nil })
    end
end

---Creates `<dir>/temp-print/config/<filetype>.lua` with the given content
---@return string dir
local function config_dir(filetype, content, dir)
    dir = dir or vim.fn.tempname()
    vim.fn.mkdir(dir .. "/temp-print/config", "p")
    vim.fn.writefile(vim.split(content, "\n"), dir .. "/temp-print/config/" .. filetype .. ".lua")
    return dir
end

T["filetype configuration"]["precedence: user > other plugins > this plugin, and setup() over all"] = function()
    local config_home = vim.fn.tempname()
    config_dir("go", 'return { print_location = { command = "USER" } }', config_home .. "/nvim")
    local plugin = config_dir("go", 'return { print_location = { command = "PLUGIN" }, print_variable = { command = "PLUGIN VAR" } }')

    local previous = vim.env.XDG_CONFIG_HOME
    vim.env.XDG_CONFIG_HOME = config_home
    H.restart(child)
    vim.env.XDG_CONFIG_HOME = previous
    child.lua("vim.opt.runtimepath:prepend(...)", { plugin })
    H.lua(child, "require('temp-print.config.language').clear_cache()")

    local config = get_config("go")
    eq(config.print_location.command, "USER")
    eq(config.print_variable.command, "PLUGIN VAR")
    eq(config.print_previous_line.command:find("fmt.Println", 1, true) ~= nil, true)

    local sources = H.lua(
        child,
        [[
        return vim.tbl_map(function(file) return file.source end, require("temp-print.config.language").find_files("go"))
    ]]
    )
    eq(sources, { "builtin", "plugins", "user" })

    -- A filetype provided only by another plugin
    config_dir("foo", 'return { print_location = { command = "FOO" } }', plugin)
    eq(get_config("foo").print_location.command, "FOO")

    -- Loading a subset of the sources
    eq(H.lua(child, [[return require("temp-print").load_filetype_config("go", { "builtin", "plugins" }).print_location.command]]), "PLUGIN")
end

T["filetype configuration"]["bundled files reuse other bundled configurations"] = function()
    local c, cpp = get_config("c"), get_config("cpp")
    eq(cpp.print_variable, c.print_variable)
    eq(get_config("bash").print_location, get_config("sh").print_location)
    eq(get_config("typescript").print_location, get_config("javascript").print_location)
    eq(get_config("vue").commentstring, "// %s")
    eq(get_config("javascript").commentstring, nil)
end

T["filetype configuration"]["extend() copies the base configuration"] = function()
    eq(
        H.lua(
            child,
            [[
        local language = require("temp-print.config.language")
        local base = language.load("go", { "builtin" })
        local extended = language.extend(base, { print_location = { command = "X" } })
        return { base.print_location.command ~= "X", extended.print_location.command, extended.print_variable ~= nil }
    ]]
        ),
        { true, "X", true }
    )
end

T["filetype configuration"]["a recursive load fails cleanly"] = function()
    local plugin = config_dir("foo", 'return require("temp-print.config.language").load("foo")')
    child.lua("vim.opt.runtimepath:prepend(...)", { plugin })
    eq(get_config("foo"), vim.NIL)
    eq(
        H.lua(child, [[return select(2, require("temp-print.config.language").get_filetype_config("foo"))]]):find("recursive", 1, true)
            ~= nil,
        true
    )
end

T["dynamic configuration"] = MiniTest.new_set()

---Creates a buffer with a name and a filetype in the child
local function make_buffer(name, filetype, lines)
    return H.lua(
        child,
        ([[
        local buffer = vim.api.nvim_create_buf(true, false)
        vim.api.nvim_buf_set_name(buffer, %q)
        vim.api.nvim_buf_set_lines(buffer, 0, -1, false, %s)
        vim.bo[buffer].filetype = %q
        return buffer
    ]]):format(name, vim.inspect(lines or {}), filetype)
    )
end

T["dynamic configuration"]["a file can return a function of the buffer"] = function()
    local plugin = config_dir(
        "foo",
        [[return function(buffer)
        return { print_location = { command = "B" .. tostring(buffer) } }
    end]]
    )
    child.lua("vim.opt.runtimepath:prepend(...)", { plugin })
    local one, two = make_buffer("/tmp/one.foo", "foo"), make_buffer("/tmp/two.foo", "foo")

    local function command(buffer)
        return H.lua(
            child,
            ("return require('temp-print.config.language').get_filetype_config('foo', %s).print_location.command"):format(buffer or "nil")
        )
    end
    eq(command(one), "B" .. one)
    eq(command(two), "B" .. two)
    eq(command(nil), "Bnil")

    -- Defaults are applied to dynamic configurations
    eq(H.lua(child, ("return require('temp-print.config.language').get_filetype_config('foo', %d).escape('x')"):format(one)), "x")

    -- load() resolves the functions too
    eq(H.lua(child, ("return TempPrint.load_filetype_config('foo', nil, %d).print_location.command"):format(two)), "B" .. two)
end

T["dynamic configuration"]["static configurations are cached"] = function()
    eq(
        H.lua(
            child,
            [[
        local language = require("temp-print.config.language")
        return language.get_filetype_config("go", 1) == language.get_filetype_config("go", 2)
    ]]
        ),
        true
    )
end

T["dynamic configuration"]["setup languages accept functions, and errors are reported"] = function()
    H.lua(
        child,
        [[TempPrint.setup({ languages = {
        foo = function(buffer) return { print_location = { command = buffer and "WITH" or "WITHOUT" } } end,
        bar = function() error("boom") end,
    } })]]
    )
    eq(get_config("foo").print_location.command, "WITHOUT")
    eq(get_config("bar"), vim.NIL)
    local err = H.lua(child, [[return select(2, require("temp-print.config.language").get_filetype_config("bar", 1))]])
    eq(err:find("setup().languages.bar", 1, true) ~= nil and err:find("boom", 1, true) ~= nil, true)
end

T["dynamic configuration"]["a function that loads its own filetype fails cleanly"] = function()
    local plugin = config_dir(
        "foo",
        [[return function(buffer)
        return require("temp-print.config.language").load("foo", nil, buffer)
    end]]
    )
    child.lua("vim.opt.runtimepath:prepend(...)", { plugin })
    local err = H.lua(child, [[return select(2, require("temp-print.config.language").get_filetype_config("foo", 1))]])
    eq(err:find("recursive", 1, true) ~= nil, true)
end

T["neovim lua"] = MiniTest.new_set()

T["neovim lua"]["is_neovim_lua checks if the file is inside a Neovim directory"] = function()
    local dir = vim.fn.tempname()
    vim.fn.mkdir(dir, "p")
    local function is_neovim(buffer)
        return H.lua(child, ("return TempPrint.is_neovim_lua(%s)"):format(buffer or "nil"))
    end

    eq(is_neovim(nil), false)
    -- The content is not checked
    local outside = make_buffer(dir .. "/api.lua", "lua", { "vim.api.nvim_echo({}, false, {})" })
    eq(is_neovim(outside), false)

    local config = H.lua(child, "return vim.fn.stdpath('config')")
    eq(is_neovim(make_buffer(config .. "/lua/my/file.lua", "lua", { "local x = 1" })), true)

    -- 'runtimepath' entries are Neovim directories
    child.lua("vim.opt.runtimepath:prepend(...)", { dir })
    eq(is_neovim(outside), true)

    eq(H.lua(child, [[return TempPrint.in_neovim_directory(vim.env.VIMRUNTIME .. "/lua/vim/shared.lua")]]), true)
    eq(H.lua(child, [[return TempPrint.in_neovim_directory("/nonexistent-dir/x.lua")]]), false)
    eq(H.lua(child, [[return TempPrint.in_neovim_directory("")]]), false)
end

T["neovim lua"]["the bundled Lua configuration uses vim.print only in Neovim files"] = function()
    local dir = vim.fn.tempname()
    vim.fn.mkdir(dir, "p")
    child.cmd("cd " .. dir)
    child.api.nvim_buf_set_lines(0, 0, -1, false, { "local x = foo" })
    child.api.nvim_buf_set_name(0, dir .. "/plain.lua")
    child.bo.filetype = "lua"
    H.cursor(child, 1, 10)
    H.lua(child, "TempPrint.insert_variable()")
    eq(H.get_lines(child)[3], 'print("plain.lua  foo: " .. tostring(foo))')

    -- Inside a Neovim directory
    child.lua("vim.opt.runtimepath:prepend(...)", { dir })
    H.cursor(child, 1, 10)
    H.lua(child, "TempPrint.insert_variable()")
    eq(H.get_lines(child)[3], 'vim.print("plain.lua  foo:", foo)')
end

T["neovim lua"]["the is_neovim_lua option replaces the check"] = function()
    local dir = vim.fn.tempname()
    vim.fn.mkdir(dir, "p")
    local plain = make_buffer(dir .. "/plain.lua", "lua", { "local x = 1" })
    local in_repo = make_buffer(vim.fn.getcwd() .. "/sub/other.lua", "lua", { "local x = 1" })
    local function command(buffer)
        return H.lua(child, ("return TempPrint.get_filetype_config('lua', %d).print_location.command"):format(buffer))
    end
    eq(vim.startswith(command(plain), "print("), true)
    eq(vim.startswith(command(in_repo), "vim.print("), true)

    H.lua(child, "TempPrint.setup({ is_neovim_lua = function(buffer) _G.checked = buffer; return true end })")
    eq(vim.startswith(command(plain), "vim.print("), true)
    eq(H.lua(child, "return _G.checked"), plain)

    H.lua(child, "TempPrint.setup({ is_neovim_lua = function() return false end })")
    eq(vim.startswith(command(in_repo), "print("), true)

    -- The option is not called without a buffer
    H.lua(child, "TempPrint.setup({ is_neovim_lua = function() error('called') end })")
    eq(H.lua(child, "return TempPrint.is_neovim_lua(nil)"), false)
end

T["neovim lua"]["symbolic links are resolved"] = function()
    local root = vim.fn.tempname()
    vim.fn.mkdir(root .. "/real", "p")
    vim.fn.mkdir(root .. "/elsewhere", "p")
    vim.fn.writefile({ "local x = 1" }, root .. "/real/a.lua")
    vim.fn.writefile({ "local x = 1" }, root .. "/elsewhere/b.lua")
    assert(vim.uv.fs_symlink(root .. "/real", root .. "/link"))
    assert(vim.uv.fs_symlink(root .. "/elsewhere", root .. "/other"))

    local function in_neovim(path)
        return H.lua(child, ("return TempPrint.in_neovim_directory(%q)"):format(path))
    end

    -- The 'runtimepath' entry is a link, the file is opened through its real path
    child.lua("vim.opt.runtimepath:prepend(...)", { root .. "/link" })
    eq(H.lua(child, ("return TempPrint.is_neovim_lua(%d)"):format(make_buffer(root .. "/real/a.lua", "lua"))), true)

    -- The 'runtimepath' entry is real, the file is opened through a link
    H.restart(child)
    child.lua("vim.opt.runtimepath:prepend(...)", { root .. "/real" })
    eq(in_neovim(root .. "/link/a.lua"), true)

    -- A link to a directory outside the Neovim directories
    eq(in_neovim(root .. "/other/b.lua"), false)
end

T["file path"] = MiniTest.new_set()

T["file path"]["is relative to the deepest of the project root and the working directory"] = function()
    local root = vim.fn.getcwd()
    local function format(path)
        return H.lua(
            child,
            ([[
            local buffer = vim.api.nvim_create_buf(true, false)
            vim.api.nvim_buf_set_name(buffer, %q)
            return require("temp-print.context").get_file_path(buffer)
        ]]):format(path)
        )
    end

    eq(format(root .. "/tests/a.lua"), "tests/a.lua")
    child.cmd("cd lua")
    eq(format(root .. "/lua/temp-print/x.lua"), "temp-print/x.lua")
    eq(format(root .. "/tests/b.lua"), "tests/b.lua") -- Outside the working directory: relative to the project root
end

T["file path"]["the project root function can be replaced"] = function()
    local root = vim.fn.getcwd()
    local buffer = H.lua(
        child,
        ("local b = vim.api.nvim_create_buf(true, false); vim.api.nvim_buf_set_name(b, %q); return b"):format(
            root .. "/lua/temp-print/x.lua"
        )
    )
    local function format()
        return H.lua(child, ("return require('temp-print.context').get_file_path(%d)"):format(buffer))
    end

    child.cmd("cd /")
    H.lua(child, ("TempPrint.setup({ get_project_root = function(_, path) return %q end })"):format(root .. "/lua"))
    eq(format(), "temp-print/x.lua")

    -- An error is ignored: outside the working directory, the path is relative to the home directory
    H.lua(child, "TempPrint.setup({ get_project_root = function() error('boom') end })")
    eq(format(), vim.fn.fnamemodify(root .. "/lua/temp-print/x.lua", ":~"))
end

return T
