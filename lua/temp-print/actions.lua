-- Functions meant for keymaps. They act on the cursor (Normal mode) or on the selected lines (Visual mode), and can be
-- repeated with `.`
--
-- Example: vim.keymap.set({ "n", "x" }, "<leader>pl", require("temp-print.actions").location)
local edit = require("temp-print.edit")
local insert = require("temp-print.insert")

local M = {}

---@class TempPrint.Actions.State
---@field fn fun(first: integer, last: integer, visual: boolean)
---@field visual boolean

---@type TempPrint.Actions.State?
local state = nil

---Operator function used for the dot repeat. Do not call it directly
---@param _ string Motion type
function M._operatorfunc(_)
    if not state then
        return
    end
    local first = vim.api.nvim_buf_get_mark(0, "[")[1]
    local last = vim.api.nvim_buf_get_mark(0, "]")[1]
    if not state.visual then
        last = first -- `g@l` on an empty line sets a wrong `]` mark
    end
    if last < first then
        first, last = last, first
    end
    state.fn(first, last, state.visual)
end

---Runs `fn` through an operator (`g@l` in Normal mode, `g@` in Visual mode), so `.` repeats it
---@param fn fun(first: integer, last: integer, visual: boolean)
local function run(fn)
    local visual = vim.api.nvim_get_mode().mode:match("^[vV\22]") ~= nil
    state = { fn = fn, visual = visual }
    vim.go.operatorfunc = "v:lua.require'temp-print.actions'._operatorfunc"
    vim.api.nvim_feedkeys(visual and "g@" or "g@l", "nx", false)
end

---@return integer row
---@return integer col
local function cursor()
    local position = vim.api.nvim_win_get_cursor(0)
    return position[1], position[2]
end

---Inserts a location print after the cursor line, or after each non-blank selected line
---@param offset integer? Normal mode: the print goes after the line `cursor + offset` (-1 places it before the cursor line)
function M.location(offset)
    run(function(first, last, visual)
        if visual then
            insert.each_code_line(0, first, last, insert.location_for_line)
        else
            local row, col = cursor()
            insert.location(0, row, col, offset)
        end
    end)
end

---Inserts a print of the variable under the cursor. The offset only changes where the print goes
---@param offset integer? The print goes after the line `cursor + offset` (-1 places it before the cursor line)
function M.variable(offset)
    run(function()
        local row, col = cursor()
        insert.variable(0, row, col, offset)
    end)
end

---Inserts a print of the cursor line followed by a print of the variable under the cursor
---@param offset integer? The prints go after the line `cursor + offset`
function M.variable_with_line(offset)
    run(function()
        local row, col = cursor()
        insert.variable_with_line(0, row, col, offset)
    end)
end

---Inserts a print of the variable under the cursor before and after the cursor line
function M.variable_around()
    run(function()
        local row, col = cursor()
        insert.variable_around(0, row, col)
    end)
end

---Like `variable_around`, but also prints the cursor line after it
function M.variable_around_with_line()
    run(function()
        local row, col = cursor()
        insert.variable_around(0, row, col, true)
    end)
end

---Inserts, after the cursor line (or each non-blank selected line), a print of that line
function M.previous_line_below()
    run(function(first, last, visual)
        if visual then
            insert.each_code_line(0, first, last, insert.previous_line)
        else
            insert.previous_line(0, (cursor()))
        end
    end)
end

---Inserts, before the cursor line (or each non-blank selected line), a print of that line
function M.next_line_above()
    run(function(first, last, visual)
        if visual then
            insert.each_code_line(0, first, last, insert.next_line)
        else
            insert.next_line(0, (cursor()))
        end
    end)
end

---Deletes the temporary print under the cursor, or the ones in the selection
function M.delete()
    run(function(first, last)
        edit.delete_range(0, first, last)
    end)
end

---Comments the temporary print under the cursor, or the ones in the selection
function M.comment()
    run(function(first, last)
        edit.comment_range(0, first, last)
    end)
end

---Uncomments the temporary print under the cursor, or the ones in the selection
function M.uncomment()
    run(function(first, last)
        edit.uncomment_range(0, first, last)
    end)
end

---Toggles the comments of the temporary print under the cursor, or the ones in the selection
function M.toggle_comment()
    run(function(first, last)
        edit.toggle_comment_range(0, first, last)
    end)
end

---Comments all temporary prints of the buffer
function M.comment_all()
    run(function()
        edit.comment_all(0)
    end)
end

---Uncomments all temporary prints of the buffer
function M.uncomment_all()
    run(function()
        edit.uncomment_all(0)
    end)
end

---Deletes all temporary prints of the buffer
function M.clear_all()
    edit.clear_all(0)
end

---Regenerates the location and line prints of the buffer
function M.update()
    require("temp-print.update").update(0)
end

function M.next()
    require("temp-print.navigate").next()
end

function M.prev()
    require("temp-print.navigate").prev()
end

function M.first()
    require("temp-print.navigate").first()
end

function M.last()
    require("temp-print.navigate").last()
end

function M.toggle_auto_update()
    require("temp-print.update").toggle_auto_update()
end

function M.toggle_highlight()
    require("temp-print.highlight").toggle()
end

---Lists the temporary prints of the buffer in the quickfix list
function M.quickfix()
    require("temp-print.list").to_quickfix("buffer")
end

---Lists the temporary prints of the current working directory in the quickfix list
function M.quickfix_directory()
    require("temp-print.list").to_quickfix("directory")
end

---Lists the temporary prints of the buffer in the location list
function M.loclist()
    require("temp-print.list").to_loclist()
end

return M
