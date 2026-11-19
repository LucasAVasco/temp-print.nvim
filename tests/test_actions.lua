-- Keymap functions (actions module) and the :TempPrint command
local H = dofile("tests/helpers.lua")
local eq = H.eq
local P = H.lua_print

local child, T = H.new_set()

local function map(lhs, action, arg)
    H.lua(child, ([[vim.keymap.set({ "n", "x" }, %q, function() require("temp-print.actions").%s(%s) end)]]):format(lhs, action, arg or ""))
end

local function count_blocks()
    return H.lua(child, "return #require('temp-print.blocks').parse(0).blocks")
end

T["actions"] = MiniTest.new_set()

T["actions"]["location can be repeated with dot"] = function()
    H.set_buffer(child, { "local a = 1", "local b = 2" }, "lua")
    map("gl", "location")
    H.cursor(child, 1, 0)
    child.type_keys("gl")
    eq(count_blocks(), 1)

    H.cursor(child, 5, 0) -- local b = 2
    child.type_keys(".")
    eq(count_blocks(), 2)
    eq(H.get_lines(child)[7], 'vim.print("sub/file.lua:7 ")')
end

T["actions"]["visual mode inserts a print after each non-blank line"] = function()
    H.set_buffer(child, { "local a = 1", "", "local b = 2" }, "lua")
    map("gp", "previous_line_below")
    H.cursor(child, 1, 0)
    child.type_keys("V", "G", "gp")
    eq(H.get_lines(child), {
        "local a = 1",
        "-- TEMP_PRINT_NVIM_MARKER_START_PREVIOUS_LINE",
        P.line(1, "local a = 1", ""),
        "-- TEMP_PRINT_NVIM_MARKER_END",
        "",
        "local b = 2",
        "-- TEMP_PRINT_NVIM_MARKER_START_PREVIOUS_LINE",
        P.line(6, "local b = 2", ""),
        "-- TEMP_PRINT_NVIM_MARKER_END",
    })
end

T["actions"]["variable offset keeps the variable under the cursor"] = function()
    H.set_buffer(child, H.lua_buffer, "lua")
    map("gv", "variable", "-1")
    H.cursor(child, unpack(H.lua_var_pos))
    child.type_keys("gv")
    eq(vim.list_slice(H.get_lines(child), 3, 6), {
        H.START .. "_VARIABLE",
        P.variable(),
        H.END,
        "    local x = foo.bar",
    })
end

T["actions"]["delete and toggle comment are repeatable"] = function()
    H.set_buffer(child, { "local a = 1", "local b = 2", "local c = 3" }, "lua")
    for row = 3, 1, -1 do
        H.lua(child, ("TempPrint.insert_location(0, %d, 0)"):format(row))
    end
    map("gc", "toggle_comment")
    map("gd", "delete")

    H.cursor(child, 2, 0)
    child.type_keys("gc")
    H.cursor(child, 7, 0)
    child.type_keys(".")
    eq(H.lua(child, "return vim.tbl_map(function(b) return b.commented end, require('temp-print.blocks').parse(0).blocks)"), {
        true,
        true,
        false,
    })

    H.cursor(child, 2, 0)
    child.type_keys("gd")
    H.cursor(child, 3, 0)
    child.type_keys(".")
    eq(count_blocks(), 1)
end

T["command"] = MiniTest.new_set()

T["command"]["inserts, comments and deletes prints"] = function()
    H.set_buffer(child, H.lua_buffer, "lua")
    H.cursor(child, unpack(H.lua_var_pos))
    child.cmd("TempPrint variable")
    child.cmd("2,3TempPrint previous_line")
    eq(count_blocks(), 3)

    child.cmd("TempPrint comment_all")
    eq(H.lua(child, "return require('temp-print.blocks').parse(0).blocks[1].commented"), true)

    child.cmd("TempPrint clear")
    eq(H.get_lines(child), H.lua_buffer)
end

T["command"]["completes subcommands and their arguments"] = function()
    local subcommands = child.fn.getcompletion("TempPrint lo", "cmdline")
    eq(subcommands, { "location", "loclist" })
    eq(child.fn.getcompletion("TempPrint highlight t", "cmdline"), { "toggle" })
end

T["command"]["debug shows the effective configuration"] = function()
    H.set_buffer(child, H.lua_buffer, "lua")
    child.cmd("TempPrint debug")
    eq(child.bo.filetype, "lua")
    local text = table.concat(H.get_lines(child), "\n")
    eq(text:find("filetype_config = {", 1, true) ~= nil, true)
    eq(text:find("print_location", 1, true) ~= nil, true)
end

T["command"]["can be disabled"] = function()
    H.lua(child, "TempPrint.setup({ command = false })")
    eq(child.fn.exists(":TempPrint"), 0)
end

T["command"]["can have another name"] = function()
    H.lua(child, "TempPrint.setup({ command = 'Tp' })")
    eq(child.fn.exists(":Tp"), 2)
    eq(child.fn.exists(":TempPrint"), 0)
    eq(child.fn.getcompletion("Tp highlight t", "cmdline"), { "toggle" })

    H.lua(child, "TempPrint.setup({ command = 'bad name' })")
    eq(child.fn.exists(":Tp"), 0)
    eq(child.fn.exists(":TempPrint"), 2)
end

T["command"]["toggles notify the resulting state"] = function()
    child.cmd("TempPrint highlight enable")
    child.cmd("TempPrint auto_update disable")
    child.cmd("TempPrint highlight wrong")
    eq(
        vim.tbl_map(function(m)
            return m.msg
        end, H.messages(child)),
        {
            "[temp-print] highlight enabled",
            "[temp-print] auto-update disabled",
            "[temp-print] invalid argument: wrong",
        }
    )
end

return T
