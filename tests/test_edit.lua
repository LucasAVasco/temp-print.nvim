local H = dofile("tests/helpers.lua")
local eq = H.eq

local child, T = H.new_set()

local S = "-- TEMP_PRINT_NVIM_MARKER_START"
local E = "-- TEMP_PRINT_NVIM_MARKER_END"
local C = "-- COMMENTED_TEMP_PRINT_NVIM_MARKER_START"

local chain = { "code", S .. "_PREVIOUS_LINE", "print(1)", S .. "_VARIABLE", "print(2)", E, "end" }

local function errors()
    return H.lua(child, "return #require('temp-print.blocks').parse(0).errors")
end

T["delete"] = MiniTest.new_set()

T["delete"]["the last block of a chain keeps the end marker"] = function()
    H.set_buffer(child, chain, "lua")
    eq(H.lua(child, "return TempPrint.delete_at(0, 5)"), 1)
    eq(H.get_lines(child), { "code", S .. "_PREVIOUS_LINE", "print(1)", E, "end" })
    eq(errors(), 0)
end

T["delete"]["the first block of a chain"] = function()
    H.set_buffer(child, chain, "lua")
    eq(H.lua(child, "return TempPrint.delete_at(0, 2)"), 1)
    eq(H.get_lines(child), { "code", S .. "_VARIABLE", "print(2)", E, "end" })
end

T["delete"]["a whole chain through a range"] = function()
    H.set_buffer(child, chain, "lua")
    eq(H.lua(child, "return TempPrint.delete_range(0, 3, 4)"), 2)
    eq(H.get_lines(child), { "code", "end" })
end

T["delete"]["warns when there is no print"] = function()
    H.set_buffer(child, chain, "lua")
    eq(H.lua(child, "return TempPrint.delete_at(0, 1)"), 0)
    eq(H.messages(child)[1].level, child.lua_get("vim.log.levels.WARN"))
end

T["clear_all"] = MiniTest.new_set()

T["clear_all"]["removes every print"] = function()
    H.set_buffer(child, vim.list_extend(vim.deepcopy(chain), { S, "x", E }), "lua")
    eq(H.lua(child, "return TempPrint.clear_all()"), 3)
    eq(H.get_lines(child), { "code", "end" })
end

T["clear_all"]["fails without changes when a print is invalid"] = function()
    local lines = { "a", S, "print(1)", E, "b", S, "print(2)" }
    H.set_buffer(child, lines, "lua")
    eq(H.lua(child, "return TempPrint.clear_all()"), vim.NIL)
    eq(H.get_lines(child), lines)
    eq(H.messages(child)[1].msg:find("line 6", 1, true) ~= nil, true)
end

T["comment"] = MiniTest.new_set()

T["comment"]["comments and uncomments a print"] = function()
    local lines = { "code", "    " .. S .. "_LOCATION", "    print(1)", "", "    " .. E }
    H.set_buffer(child, lines, "lua")

    eq(H.lua(child, "return TempPrint.comment_at(0, 3)"), 1)
    eq(H.get_lines(child), { "code", "    " .. C .. "_LOCATION", "    -- print(1)", "", "    " .. E })

    eq(H.lua(child, "return TempPrint.uncomment_at(0, 3)"), 1)
    eq(H.get_lines(child), lines)
end

T["comment"]["a commented print still closes the previous one"] = function()
    H.set_buffer(child, chain, "lua")
    eq(H.lua(child, "return TempPrint.comment_at(0, 4)"), 1)
    eq(H.get_lines(child)[4], C .. "_VARIABLE")
    eq(errors(), 0)
    eq(H.lua(child, "return require('temp-print.blocks').parse(0).blocks[1].content_last"), 3)
end

T["comment"]["toggle comments everything if any print is not commented"] = function()
    H.set_buffer(child, { C, "-- a", E, S, "b", E }, "lua")
    eq(H.lua(child, "return TempPrint.toggle_comment_range(0, 1, 6)"), 1)
    eq(H.get_lines(child), { C, "-- a", E, C, "-- b", E })
    eq(H.lua(child, "return TempPrint.toggle_comment_range(0, 1, 6)"), 2)
    eq(H.get_lines(child), { S, "a", E, S, "b", E })
end

T["comment"]["comment_all and uncomment_all"] = function()
    H.set_buffer(child, chain, "lua")
    eq(H.lua(child, "return TempPrint.comment_all()"), 2)
    eq(H.lua(child, "return TempPrint.uncomment_all()"), 2)
    eq(H.get_lines(child), chain)
end

T["cursor defaults"] = MiniTest.new_set()

T["cursor defaults"]["use a window showing the buffer, and fail cleanly if there is none"] = function()
    H.set_buffer(child, { "local a = 1", "local b = 2" }, "lua")
    local buffer = child.api.nvim_get_current_buf()
    H.lua(child, ("TempPrint.insert_location(%d, 1, 0)"):format(buffer))
    H.cursor(child, 2, 0) -- Start marker of the print

    -- Another buffer in another window: the cursor of the window showing `buffer` is used
    child.cmd("vsplit | enew")
    eq(H.lua(child, ("return TempPrint.comment_at(%d)"):format(buffer)), 1)
    eq(H.lua(child, ("return TempPrint.insert_previous_line(%d)"):format(buffer)), true)

    -- No window shows the buffer
    child.cmd("only")
    eq(H.lua(child, ("return TempPrint.delete_at(%d)"):format(buffer)), vim.NIL)
    eq(H.lua(child, ("return TempPrint.insert_next_line(%d)"):format(buffer)), false)
    eq(H.messages(child)[1].msg:find("not displayed in any window", 1, true) ~= nil, true)
end

return T
