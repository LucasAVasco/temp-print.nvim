-- Moves the cursor between temporary prints of the current window
local blocks = require("temp-print.blocks")
local util = require("temp-print.util")

local M = {}

---Moves the cursor to the indentation of the row, adding the previous position to the jump list
---@param row integer?
---@return boolean moved
local function jump(row)
    if not row then
        return false
    end
    vim.cmd("normal! m'")
    vim.api.nvim_win_set_cursor(0, { row, #util.indentation(util.get_line(0, row)) })
    return true
end

---Start rows of the temporary prints, from the top
---@return integer[]
local function start_rows()
    return vim.tbl_map(function(block)
        return block.start_row
    end, blocks.parse(0).blocks)
end

---Finds the `count`th print after (direction 1) or before (direction -1) the cursor. If there are fewer prints, returns
---the farthest one
---@param direction 1|-1
---@param count integer
---@return integer? row
local function find(direction, count)
    local cursor = vim.api.nvim_win_get_cursor(0)[1]
    local rows = start_rows()
    local first, last = 1, #rows
    if direction < 0 then
        first, last = #rows, 1
    end

    local found = nil
    for i = first, last, direction do
        if (rows[i] - cursor) * direction > 0 then
            found = rows[i]
            count = count - 1
            if count == 0 then
                break
            end
        end
    end
    return found
end

---Goes to the next temporary print
---@param count integer? Defaults to `v:count1`
---@return boolean moved
function M.next(count)
    return jump(find(1, count or vim.v.count1))
end

---Goes to the previous temporary print
---@param count integer? Defaults to `v:count1`
---@return boolean moved
function M.prev(count)
    return jump(find(-1, count or vim.v.count1))
end

---Goes to the first temporary print of the buffer
---@return boolean moved
function M.first()
    return jump(start_rows()[1])
end

---Goes to the last temporary print of the buffer
---@return boolean moved
function M.last()
    local rows = start_rows()
    return jump(rows[#rows])
end

return M
