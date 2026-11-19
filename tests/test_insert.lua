local H = dofile("tests/helpers.lua")
local eq = H.eq
local P = H.lua_print

local child, T = H.new_set()

local function lua_buffer()
    H.set_buffer(child, H.lua_buffer, "lua")
    H.cursor(child, unpack(H.lua_var_pos))
end

T["location"] = MiniTest.new_set()

T["location"]["inserts after the cursor line with file, line number and context"] = function()
    lua_buffer()
    eq(H.lua(child, "return TempPrint.insert_location()"), true)
    eq(H.get_lines(child), {
        "local M = {}",
        "function M.run()",
        "    local x = foo.bar",
        H.START .. "_LOCATION",
        P.location(5),
        H.END,
        "end",
        "return M",
    })
end

T["location"]["offset places the print before the cursor line and keeps the cursor on its line"] = function()
    lua_buffer()
    eq(H.lua(child, "return TempPrint.insert_location(0, nil, nil, -1)"), true)
    local lines = H.get_lines(child)
    eq({ lines[3], lines[4], lines[5], lines[6] }, { H.START .. "_LOCATION", P.location(4), H.END, "    local x = foo.bar" })
    eq(child.api.nvim_win_get_cursor(0), { 6, 18 })
end

T["location"]["indents every line of a multi-line command"] = function()
    H.lua(child, [[TempPrint.setup({ languages = { lua = { print_location = { command = "do\n  print(1)\nend" } } } })]])
    lua_buffer()
    H.lua(child, "TempPrint.insert_location()")
    local lines = H.get_lines(child)
    eq({ lines[5], lines[6], lines[7] }, { "    do", "      print(1)", "    end" })
end

T["location"]["works without a tree-sitter parser"] = function()
    H.lua(
        child,
        [[TempPrint.setup({ languages = { text = {
        commentstring = "# %s", print_location = { command = "[<CONTEXT>] <LINE_NUMBER>" } } } })]]
    )
    H.set_buffer(child, { "hello" }, "text")
    eq(H.lua(child, "return TempPrint.insert_location()"), true)
    eq(H.get_lines(child), { "hello", "# TEMP_PRINT_NVIM_MARKER_START_LOCATION", "[] 3", "# TEMP_PRINT_NVIM_MARKER_END" })
end

T["location"]["writes to the given buffer and requires a position when it is hidden"] = function()
    lua_buffer()
    local other = child.api.nvim_get_current_buf()
    child.cmd("enew")
    eq(H.lua(child, ("return TempPrint.insert_location(%d)"):format(other)), false)
    eq(H.lua(child, ("return TempPrint.insert_location(%d, 3, 18)"):format(other)), true)
    eq(#H.get_lines(child, other), #H.lua_buffer + 3)
    eq(H.get_lines(child), { "" })
end

T["location"]["fails cleanly without a language configuration"] = function()
    H.set_buffer(child, { "hello" }, "text")
    eq(H.lua(child, "return TempPrint.insert_location()"), false)
    eq(H.messages(child)[1].msg:find("no language configuration", 1, true) ~= nil, true)
end

T["variable"] = MiniTest.new_set()

T["variable"]["inserts the variable print"] = function()
    lua_buffer()
    eq(H.lua(child, "return TempPrint.insert_variable()"), true)
    local lines = H.get_lines(child)
    eq({ lines[4], lines[5], lines[6] }, { H.START .. "_VARIABLE", P.variable(), H.END })
end

T["variable"]["fails when the cursor is not on a variable"] = function()
    lua_buffer()
    H.cursor(child, 2, 0) -- `function`
    eq(H.lua(child, "return TempPrint.insert_variable()"), false)
    eq(H.get_lines(child), H.lua_buffer)
end

T["variable"]["does not interpret '%' in the inserted values"] = function()
    H.lua(
        child,
        [[TempPrint.setup({
        languages = { lua = { commentstring = "--%% %s", print_variable = { command = "print('%d <VAR>')" } } },
    })]]
    )
    lua_buffer()
    H.lua(child, "TempPrint.insert_variable()")
    local lines = H.get_lines(child)
    eq({ lines[4], lines[5] }, { "    --%% TEMP_PRINT_NVIM_MARKER_START_VARIABLE", "    print('%d foo.bar')" })
end

T["variable"]["text tags have raw, escaped and format-escaped variants"] = function()
    H.lua(child, [[TempPrint.setup({
        get_context = function() return [[a%"b\]] .. "]]" .. [[ end,
        languages = { lua = {
            escape = function(text) return (text:gsub('"', "Q")) end,
            escape_format = function(text) return (text:gsub("%%", "P")) end,
            print_location = { command = "<CONTEXT>|<CONTEXT_ESCAPED>|<CONTEXT_FORMATTED_ESCAPED>" },
            print_variable = { command = "<CONTEXT_FORMATTED_ESCAPED>" },
        } },
    })]])
    lua_buffer()
    H.lua(child, "TempPrint.insert_location()")
    eq(H.get_lines(child)[5], [[    a%"b\|a%Qb\|aP"b\]])

    -- escape_format defaults to escape
    H.lua(
        child,
        [[TempPrint.setup({ get_context = function() return '"' end,
        languages = { lua = { print_location = { command = "<CONTEXT_FORMATTED_ESCAPED>" } } } })]]
    )
    lua_buffer()
    H.lua(child, "TempPrint.insert_location()")
    eq(H.get_lines(child)[5], [[    \"]])
end

T["variable"]["bundled printf configurations escape '%' in the format string"] = function()
    H.set_buffer(child, { "int main() {", "    int x = 1;", "}" }, "c", "sub/100%.c")
    H.cursor(child, 2, 8)
    H.lua(child, "TempPrint.insert_variable()")
    eq(H.get_lines(child)[4], '    printf("sub/100%%.c main x: %d\\n", x);')
end

T["line prints"] = MiniTest.new_set()

T["line prints"]["previous line print goes after the line and prints it"] = function()
    lua_buffer()
    eq(H.lua(child, "return TempPrint.insert_previous_line()"), true)
    local lines = H.get_lines(child)
    eq({ lines[4], lines[5], lines[6] }, { H.START .. "_PREVIOUS_LINE", P.line(3, "local x = foo.bar"), H.END })
end

T["line prints"]["next line print goes before the line and prints it"] = function()
    lua_buffer()
    eq(H.lua(child, "return TempPrint.insert_next_line()"), true)
    local lines = H.get_lines(child)
    eq({ lines[3], lines[4], lines[5], lines[6] }, {
        H.START .. "_NEXT_LINE",
        P.line(6, "local x = foo.bar"),
        H.END,
        "    local x = foo.bar",
    })
end

T["line prints"]["skip blank lines"] = function()
    H.set_buffer(child, { "local a = 1", "", "local b = 2" }, "lua")
    H.cursor(child, 2, 0)
    H.lua(child, "TempPrint.insert_previous_line()")
    eq(H.get_lines(child)[4], P.line(1, "local a = 1", ""))
end

T["line prints"]["escape the printed line"] = function()
    H.set_buffer(child, { 'local s = "a\\b"' }, "lua")
    H.cursor(child, 1, 0)
    H.lua(child, "TempPrint.insert_previous_line()")
    eq(H.get_lines(child)[3], P.line(1, 'local s = \\"a\\\\b\\"', ""))
end

T["combined"] = MiniTest.new_set()

T["combined"]["variable with line chains a line print and a variable print"] = function()
    lua_buffer()
    eq(H.lua(child, "return TempPrint.insert_variable_with_line()"), true)
    local lines = H.get_lines(child)
    eq(vim.list_slice(lines, 4, 8), {
        H.START .. "_PREVIOUS_LINE",
        P.line(3, "local x = foo.bar"),
        H.START .. "_VARIABLE",
        P.variable(),
        H.END,
    })
end

T["combined"]["variable around prints before and after the line"] = function()
    lua_buffer()
    eq(H.lua(child, "return TempPrint.insert_variable_around()"), true)
    eq(vim.list_slice(H.get_lines(child), 3, 9), {
        H.START .. "_VARIABLE",
        P.variable(),
        H.END,
        "    local x = foo.bar",
        H.START .. "_VARIABLE",
        P.variable(),
        H.END,
    })
    eq(child.api.nvim_win_get_cursor(0)[1], 6)
end

T["combined"]["variable around with line also prints the line"] = function()
    lua_buffer()
    eq(H.lua(child, "return TempPrint.insert_variable_around(0, nil, nil, true)"), true)
    eq(vim.list_slice(H.get_lines(child), 6, 11), {
        "    local x = foo.bar",
        H.START .. "_PREVIOUS_LINE",
        P.line(6, "local x = foo.bar"),
        H.START .. "_VARIABLE",
        P.variable(),
        H.END,
    })
end

T["options"] = MiniTest.new_set()

T["options"]["filetype get_context wins over the setup one"] = function()
    H.lua(child, [[TempPrint.setup({ get_context = function() return "GLOBAL" end })]])
    lua_buffer()
    H.lua(child, "TempPrint.insert_location()")
    eq(H.get_lines(child)[5], P.location(5, "GLOBAL"))

    H.lua(
        child,
        [[TempPrint.setup({
        get_context = function() return "GLOBAL" end,
        languages = { lua = { get_context = function(info) return "FT" .. info.row end } },
    })]]
    )
    lua_buffer()
    H.lua(child, "TempPrint.insert_location()")
    eq(H.get_lines(child)[5], P.location(5, "FT3"))
end

T["options"]["filetype placeholders override the setup ones"] = function()
    H.lua(
        child,
        [[TempPrint.setup({
        placeholders = { context_escaped = "@SETUP@", line_number = "@LINE@" },
        languages = { lua = {
            placeholders = { context_escaped = "@FT@" },
            print_location = { command = "@SETUP@ @FT@ @LINE@ <FILE_PATH_ESCAPED>" },
        } },
    })]]
    )
    lua_buffer()
    H.lua(child, "TempPrint.insert_location()")
    eq(H.get_lines(child)[5], "    @SETUP@ M.run 5 sub/file.lua")

    -- The update also uses them
    child.api.nvim_buf_set_lines(0, 0, 0, false, { "local a = 1" })
    eq(H.lua(child, "return TempPrint.update()"), 1)
    eq(H.get_lines(child)[6], "    @SETUP@ M.run 6 sub/file.lua")
end

T["options"]["format_file_path receives the full path"] = function()
    H.lua(child, [[TempPrint.setup({ format_file_path = function(path) return vim.fs.basename(path) .. "!" end })]])
    lua_buffer()
    H.lua(child, "TempPrint.insert_location()")
    eq(H.get_lines(child)[5], '    vim.print("file.lua!:5 M.run")')
end

return T
