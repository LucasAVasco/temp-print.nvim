local H = dofile("tests/helpers.lua")
local eq = H.eq
local P = H.lua_print

local child, T = H.new_set()

local function lua_buffer()
    H.set_buffer(child, H.lua_buffer, "lua")
    H.cursor(child, unpack(H.lua_var_pos))
end

---Inserts two lines at the top of the buffer, so all line numbers become outdated
local function shift_lines()
    child.api.nvim_buf_set_lines(0, 0, 0, false, { "local a = 1", "local b = 2" })
end

T["update()"] = MiniTest.new_set()

T["update()"]["regenerates location and line prints"] = function()
    lua_buffer()
    H.lua(child, "TempPrint.insert_location()")
    H.lua(child, "TempPrint.insert_next_line()")
    shift_lines()

    eq(H.lua(child, "return TempPrint.update()"), 2)
    local lines = H.get_lines(child)
    eq(lines[6], P.line(8, "local x = foo.bar"))
    eq(lines[10], P.location(10))
    eq(H.lua(child, "return TempPrint.update()"), 0)
end

T["update()"]["skips variable, commented and untyped prints"] = function()
    local lines = {
        "local a = 1",
        "-- TEMP_PRINT_NVIM_MARKER_START_VARIABLE",
        "print(1)",
        "-- COMMENTED_TEMP_PRINT_NVIM_MARKER_START_LOCATION",
        "-- print(2)",
        "-- TEMP_PRINT_NVIM_MARKER_START",
        "print(3)",
        "-- TEMP_PRINT_NVIM_MARKER_END",
    }
    H.set_buffer(child, lines, "lua")
    eq(H.lua(child, "return TempPrint.update()"), 0)
    eq(H.get_lines(child), lines)
end

T["update()"]["does nothing when a print is invalid"] = function()
    local lines = { "local a = 1", "-- TEMP_PRINT_NVIM_MARKER_START_LOCATION", "print(1)" }
    H.set_buffer(child, lines, "lua")
    eq(H.lua(child, "return TempPrint.update()"), vim.NIL)
    eq(H.get_lines(child), lines)
end

T["update()"]["a location print at the top has an empty context"] = function()
    H.set_buffer(child, { "-- TEMP_PRINT_NVIM_MARKER_START_LOCATION", "x", "-- TEMP_PRINT_NVIM_MARKER_END" }, "lua")
    eq(H.lua(child, "return TempPrint.update()"), 1)
    eq(H.get_lines(child)[2], 'vim.print("sub/file.lua:2 ")')
end

T["update()"]["keeps prints reformatted by a code formatter"] = function()
    local lines = {
        "local a = 1",
        "-- TEMP_PRINT_NVIM_MARKER_START_LOCATION",
        "vim.print(",
        '        "sub/file.lua:3 ",',
        ")",
        "-- TEMP_PRINT_NVIM_MARKER_END",
    }
    H.set_buffer(child, lines, "lua")
    eq(H.lua(child, "return TempPrint.update()"), 0)
    eq(H.get_lines(child), lines)

    -- Outdated after the code moves
    shift_lines()
    eq(H.lua(child, "return TempPrint.update()"), 1)
    eq(H.get_lines(child)[5], 'vim.print("sub/file.lua:5 ")')
end

T["auto-update"] = MiniTest.new_set()

local function write_file()
    local file = child.fn.tempname() .. ".lua"
    child.cmd("silent write " .. file)
    return file
end

T["auto-update"]["updates before saving"] = function()
    lua_buffer()
    H.lua(child, "TempPrint.insert_location()")
    shift_lines()
    write_file()
    eq(H.get_lines(child)[7]:match(":(%d+) M.run"), "7")
end

T["auto-update"]["can be disabled"] = function()
    lua_buffer()
    H.lua(child, "TempPrint.insert_location()")
    shift_lines()
    H.lua(child, "TempPrint.disable_auto_update()")
    eq(H.lua(child, "return TempPrint.is_auto_update_enabled()"), false)
    write_file()
    eq(H.get_lines(child)[7], P.location(5))

    H.lua(child, "TempPrint.toggle_auto_update()")
    eq(H.lua(child, "return TempPrint.is_auto_update_enabled()"), true)
end

T["auto-update"]["is disabled by the auto_update option"] = function()
    H.lua(child, "TempPrint.setup({ auto_update = false })")
    eq(H.lua(child, "return TempPrint.is_auto_update_enabled()"), false)
end

return T
