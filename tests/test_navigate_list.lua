local H = dofile("tests/helpers.lua")
local eq = H.eq

local child, T = H.new_set()

local S = "-- TEMP_PRINT_NVIM_MARKER_START"
local E = "-- TEMP_PRINT_NVIM_MARKER_END"

local lines = {
    "local a = 1", -- 1
    S .. "_LOCATION", -- 2
    "print(1)",
    E,
    "local b = 2", -- 5
    "  " .. S .. "_PREVIOUS_LINE", -- 6
    "  print(2)",
    "  -- COMMENTED_TEMP_PRINT_NVIM_MARKER_START_VARIABLE", -- 8
    "  -- print(3)",
    "  " .. E,
}

local function row()
    return child.api.nvim_win_get_cursor(0)[1]
end

T["navigation"] = function()
    H.set_buffer(child, lines, "lua")
    H.cursor(child, 1, 0)

    eq(H.lua(child, "return TempPrint.goto_next()"), true)
    eq(row(), 2)
    H.lua(child, "TempPrint.goto_next(2)")
    eq(child.api.nvim_win_get_cursor(0), { 8, 2 })
    eq(H.lua(child, "return TempPrint.goto_next()"), false)

    H.lua(child, "TempPrint.goto_prev()")
    eq(row(), 6)
    H.lua(child, "TempPrint.goto_first()")
    eq(row(), 2)
    H.lua(child, "TempPrint.goto_last()")
    eq(row(), 8)
end

T["location list"] = function()
    H.set_buffer(child, lines, "lua")
    eq(H.lua(child, "return TempPrint.to_loclist()"), 3)
    local texts = H.lua(
        child,
        [[
        return vim.tbl_map(function(item) return item.lnum .. " " .. item.text end, vim.fn.getloclist(1))
    ]]
    )
    eq(texts, { "2 location: print(1)", "6 previous_line: print(2)", "8 commented variable: -- print(3)" })
end

T["quickfix of a directory"] = function()
    local directory = child.fn.tempname()
    child.fn.mkdir(directory .. "/sub", "p")
    child.fn.writefile({ "a", S .. "_NEXT_LINE", "x", E }, directory .. "/sub/one.lua")
    child.fn.writefile({ "nothing here" }, directory .. "/two.lua")

    eq(H.lua(child, ("return TempPrint.to_quickfix('directory', %q)"):format(directory)), 1)
    local item = child.fn.getqflist()[1]
    eq({ item.lnum, item.text }, { 2, "next_line: x" })
end

T["highlight"] = function()
    H.set_buffer(child, lines, "lua")
    local function count()
        return H.lua(
            child,
            [[
            local ns = vim.api.nvim_get_namespaces()["temp-print-highlight"]
            return #vim.api.nvim_buf_get_extmarks(0, ns, 0, -1, {})
        ]]
        )
    end

    H.lua(child, "TempPrint.enable_highlight()")
    eq(count(), #lines - 2)
    H.lua(child, "TempPrint.toggle_highlight()")
    eq(count(), 0)
    eq(H.lua(child, "return TempPrint.is_highlight_enabled()"), false)
end

T["highlight groups"] = function()
    local function groups()
        return H.lua(
            child,
            [[
            local ns = vim.api.nvim_get_namespaces()["temp-print-highlight"]
            local result = {}
            for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(0, ns, 0, -1, { details = true })) do
                result[mark[2] + 1] = mark[4].line_hl_group:gsub("^TempPrint", "")
            end
            return result
        ]]
        )
    end
    H.lua(child, "TempPrint.enable_highlight()")

    -- A commented print, including its end marker
    H.set_buffer(child, { "-- COMMENTED_TEMP_PRINT_NVIM_MARKER_START_LOCATION", "-- print(1)", E }, "lua")
    H.lua(child, "require('temp-print.highlight').refresh(0)")
    eq(groups(), { "Commented", "Commented", "Commented" })

    -- A commented print between active prints of a chain
    H.set_buffer(child, {
        S .. "_PREVIOUS_LINE",
        "print(1)",
        "-- COMMENTED_TEMP_PRINT_NVIM_MARKER_START_VARIABLE",
        "-- print(2)",
        S .. "_VARIABLE",
        "print(3)",
        E,
    }, "lua")
    H.lua(child, "require('temp-print.highlight').refresh(0)")
    eq(groups(), { "Marker", "Content", "Commented", "Commented", "Marker", "Content", "Marker" })
end

return T
