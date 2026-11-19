-- Parser tests. They run in the test process itself because the parser is pure
local blocks = require("temp-print.blocks")
local eq = MiniTest.expect.equality

local T = MiniTest.new_set()

local S = "-- TEMP_PRINT_NVIM_MARKER_START"
local E = "-- TEMP_PRINT_NVIM_MARKER_END"
local C = "-- COMMENTED_TEMP_PRINT_NVIM_MARKER_START"

T["parse_marker()"] = function()
    eq(blocks.parse_marker(S .. "_PREVIOUS_LINE"), { kind = "start", type = "previous_line", commented = false })
    eq(blocks.parse_marker(C .. "_VARIABLE"), { kind = "start", type = "variable", commented = true })
    eq(blocks.parse_marker("/* " .. S .. " */"), { kind = "start", commented = false })
    eq(blocks.parse_marker(E), { kind = "end", commented = false })
    eq(blocks.parse_marker("print(1)"), nil)
end

T["parses a simple block"] = function()
    local parsed = blocks.parse_lines({ "code", S .. "_LOCATION", "print(1)", E, "code" })
    eq(parsed.errors, {})
    eq(#parsed.blocks, 1)
    local block = parsed.blocks[1]
    eq({ block.start_row, block.content_first, block.content_last, block.end_row, block.last_row }, { 2, 3, 3, 4, 4 })
    eq(block.type, "location")
    eq(block.commented, false)
end

T["a start marker closes the open block"] = function()
    local parsed = blocks.parse_lines({ S .. "_PREVIOUS_LINE", "a", C .. "_VARIABLE", "-- b", E })
    eq(parsed.errors, {})
    eq(#parsed.blocks, 2)

    local first, second = parsed.blocks[1], parsed.blocks[2]
    eq({ first.content_last, first.last_row, first.end_row, first.chained_next }, { 2, 2, nil, true })
    eq({ second.start_row, second.end_row, second.chained_prev, second.commented }, { 3, 5, true, true })
end

T["reports an end marker without a start marker"] = function()
    local parsed = blocks.parse_lines({ "a", E })
    eq(parsed.errors, { { row = 2, message = "end marker without a start marker" } })
end

T["reports a block that is never closed"] = function()
    local parsed = blocks.parse_lines({ S, "a", "b" })
    eq(parsed.errors, { { row = 1, message = "start marker without an end marker" } })
    eq(parsed.blocks[1].unclosed, true)
end

T["block_at() and blocks_in_range()"] = function()
    local parsed = blocks.parse_lines({ "x", S, "a", E, "y", S, "b", S, "c", E })
    eq(blocks.block_at(parsed, 1), nil)
    eq(blocks.block_at(parsed, 3).index, 1)
    eq(blocks.block_at(parsed, 7).index, 2)
    eq(blocks.block_at(parsed, 10).index, 3)
    eq(#blocks.blocks_in_range(parsed, 4, 8), 3)
    eq(#blocks.blocks_in_range(parsed, 5, 5), 0)
end

return T
