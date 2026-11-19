-- Shared helpers for the tests. Each test case runs in a fresh child Neovim instance
local H = {}

H.eq = MiniTest.expect.equality

---Creates a child Neovim and a test set that restarts it (and calls `setup()`) before each case
---@return table child
---@return table set
function H.new_set()
    local child = MiniTest.new_child_neovim()

    local set = MiniTest.new_set({
        hooks = {
            pre_case = function()
                H.restart(child)
            end,
            post_once = child.stop,
        },
    })

    return child, set
end

---@param child table
function H.restart(child)
    child.restart({ "-u", "scripts/minimal_init.lua" })
    child.lua([[
        TempPrint = require("temp-print")
        TempPrint.setup()
        _G.messages = {}
        vim.notify = function(msg, level)
            table.insert(_G.messages, { msg = msg, level = level })
        end
    ]])
end

---Sets the content, name and filetype of the current buffer in the child. The file path shown by the prints is
---`sub/file.<ext>` (relative to the current directory)
---@param child table
---@param lines string[]
---@param filetype string
---@param name string? Defaults to "sub/file.lua"
function H.set_buffer(child, lines, filetype, name)
    child.api.nvim_buf_set_lines(0, 0, -1, false, lines)
    child.api.nvim_buf_set_name(0, vim.fn.getcwd() .. "/" .. (name or "sub/file.lua"))
    child.bo.filetype = filetype
end

---@param child table
---@param buffer integer?
---@return string[]
function H.get_lines(child, buffer)
    return child.api.nvim_buf_get_lines(buffer or 0, 0, -1, false)
end

---Messages sent with `vim.notify` in the child
---@param child table
---@return { msg: string, level: integer }[]
function H.messages(child)
    return child.lua_get("_G.messages")
end

---Runs Lua code in the child, with `TempPrint` (the main module) available. Returns the result of the code
---@param child table
---@param code string
---@return any
function H.lua(child, code)
    return child.lua(code)
end

---@param child table
---@param row integer
---@param col integer
function H.cursor(child, row, col)
    child.api.nvim_win_set_cursor(0, { row, col })
end

---Lua buffer used by most tests
H.lua_buffer = {
    "local M = {}",
    "function M.run()",
    "    local x = foo.bar",
    "end",
    "return M",
}

-- Cursor position on `bar` of `foo.bar` (1-indexed line, 0-indexed column)
H.lua_var_pos = { 3, 18 }

H.START = "    -- TEMP_PRINT_NVIM_MARKER_START"
H.END = "    -- TEMP_PRINT_NVIM_MARKER_END"

---Expected lines of the bundled Lua prints (4 spaces of indentation). The test buffers are inside this repository, a
---Neovim plugin, so they use `vim.print`
H.lua_print = {
    location = function(row, context)
        return ('    vim.print("sub/file.lua:%d %s")'):format(row, context or "M.run")
    end,
    variable = function(var)
        var = var or "foo.bar"
        return ('    vim.print("sub/file.lua M.run %s:", %s)'):format(var, var)
    end,
    line = function(row, line, indent)
        return ('%svim.print("sub/file.lua:%d\\t%s")'):format(indent or "    ", row, line)
    end,
}

return H
