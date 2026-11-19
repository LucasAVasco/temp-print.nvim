-- Deletion and (un)commenting of temporary prints. All functions refuse to change the buffer if it has invalid prints
local blocks = require("temp-print.blocks")
local config = require("temp-print.config")
local util = require("temp-print.util")

local M = {}

---Resolves the buffer and the row (default: the cursor of a window showing the buffer). Notifies the error
---@param buffer integer?
---@param row integer?
---@return integer buffer
---@return integer? row Nil if there is no row and no window shows the buffer
local function resolve(buffer, row)
    buffer = util.resolve_buffer(buffer)
    if row then
        return buffer, row
    end
    local cursor_row, err = util.cursor(buffer)
    if not cursor_row then
        util.notify(err --[[@as string]])
    end
    return buffer, cursor_row
end

---Deletes blocks, from the bottom so the rows of the others remain valid. The end marker of the last block of a chain
---is kept when an earlier block of the chain is not deleted, so that block stays closed
---@param buffer integer
---@param parsed TempPrint.Parsed
---@param to_delete TempPrint.Block[]
local function delete_blocks(buffer, parsed, to_delete)
    local deleted = {}
    for _, block in ipairs(to_delete) do
        deleted[block.index] = true
    end

    table.sort(to_delete, function(a, b)
        return a.start_row > b.start_row
    end)

    for _, block in ipairs(to_delete) do
        local last = block.last_row
        if block.end_row then
            local index = block.index
            while parsed.blocks[index].chained_prev do
                index = index - 1
                if not deleted[index] then
                    last = block.end_row - 1
                    break
                end
            end
        end
        vim.api.nvim_buf_set_lines(buffer, block.start_row - 1, last, false, {})
    end
end

---Deletes the temporary print at the row
---@param buffer integer?
---@param row integer? Defaults to the cursor row
---@return integer? deleted Number of deleted prints (nil on error)
function M.delete_at(buffer, row)
    buffer, row = resolve(buffer, row)
    if not row then
        return nil
    end
    return M.delete_range(buffer, row, row)
end

---Deletes the temporary prints that have at least one line in the range
---@param buffer integer?
---@param first integer
---@param last integer
---@return integer? deleted
function M.delete_range(buffer, first, last)
    buffer = util.resolve_buffer(buffer)
    local parsed = blocks.parse_checked(buffer, "delete")
    if not parsed then
        return nil
    end

    local found = blocks.blocks_in_range(parsed, first, last)
    if #found == 0 then
        util.notify("no temporary print found", vim.log.levels.WARN)
        return 0
    end
    delete_blocks(buffer, parsed, found)
    return #found
end

---Deletes all temporary prints. Fails without changing anything if the buffer has invalid prints
---@param buffer integer?
---@return integer? deleted
function M.clear_all(buffer)
    buffer = util.resolve_buffer(buffer)
    local parsed = blocks.parse_checked(buffer, "clear")
    if not parsed then
        return nil
    end
    delete_blocks(buffer, parsed, vim.list_extend({}, parsed.blocks))
    return #parsed.blocks
end

---Comments or uncomments a block. The number of lines does not change
---@param buffer integer
---@param block TempPrint.Block
---@param commented boolean
---@param commentstring string
---@return boolean changed
local function set_commented(buffer, block, commented, commentstring)
    if block.commented == commented then
        return false
    end

    local markers = config.options.markers
    local lines = vim.api.nvim_buf_get_lines(buffer, block.start_row - 1, block.content_last, false)

    local marker_line = lines[1]
    local commented_start = markers.commented_prefix .. markers.start
    if commented then
        local position = assert(marker_line:find(markers.start, 1, true))
        lines[1] = marker_line:sub(1, position - 1) .. commented_start .. marker_line:sub(position + #markers.start)
    else
        local position = assert(marker_line:find(commented_start, 1, true))
        lines[1] = marker_line:sub(1, position - 1) .. markers.start .. marker_line:sub(position + #commented_start)
    end

    for i = 2, #lines do
        lines[i] = commented and util.comment_line(commentstring, lines[i]) or util.uncomment_line(commentstring, lines[i])
    end

    vim.api.nvim_buf_set_lines(buffer, block.start_row - 1, block.content_last, false, lines)
    return true
end

---@param buffer integer
---@param first integer
---@param last integer
---@param mode "comment"|"uncomment"|"toggle"
---@return integer? changed Number of changed prints
local function comment_range(buffer, first, last, mode)
    local parsed = blocks.parse_checked(buffer, mode .. " temporary prints")
    if not parsed then
        return nil
    end
    local commentstring, err = util.get_commentstring(buffer)
    if not commentstring then
        util.notify(err --[[@as string]])
        return nil
    end

    local found = blocks.blocks_in_range(parsed, first, last)
    if #found == 0 then
        util.notify("no temporary print found", vim.log.levels.WARN)
        return 0
    end

    local commented = mode == "comment"
    if mode == "toggle" then
        -- Comment everything if any print is not commented, otherwise uncomment everything
        commented = vim.iter(found):any(function(block)
            return not block.commented
        end)
    end

    local changed = 0
    for _, block in ipairs(found) do
        if set_commented(buffer, block, commented, commentstring) then
            changed = changed + 1
        end
    end
    return changed
end

---Comments the temporary prints in the range
---@param buffer integer?
---@param first integer
---@param last integer
---@return integer? changed
function M.comment_range(buffer, first, last)
    return comment_range(util.resolve_buffer(buffer), first, last, "comment")
end

---Uncomments the temporary prints in the range
---@param buffer integer?
---@param first integer
---@param last integer
---@return integer? changed
function M.uncomment_range(buffer, first, last)
    return comment_range(util.resolve_buffer(buffer), first, last, "uncomment")
end

---Toggles the comments of the temporary prints in the range. If any print is not commented, comments all of them
---@param buffer integer?
---@param first integer
---@param last integer
---@return integer? changed
function M.toggle_comment_range(buffer, first, last)
    return comment_range(util.resolve_buffer(buffer), first, last, "toggle")
end

---@param buffer integer?
---@param row integer? Defaults to the cursor row
---@return integer? changed
function M.comment_at(buffer, row)
    buffer, row = resolve(buffer, row)
    if not row then
        return nil
    end
    return comment_range(buffer, row, row, "comment")
end

---@param buffer integer?
---@param row integer? Defaults to the cursor row
---@return integer? changed
function M.uncomment_at(buffer, row)
    buffer, row = resolve(buffer, row)
    if not row then
        return nil
    end
    return comment_range(buffer, row, row, "uncomment")
end

---@param buffer integer?
---@param row integer? Defaults to the cursor row
---@return integer? changed
function M.toggle_comment_at(buffer, row)
    buffer, row = resolve(buffer, row)
    if not row then
        return nil
    end
    return comment_range(buffer, row, row, "toggle")
end

---@param buffer integer?
---@return integer? changed
function M.comment_all(buffer)
    buffer = util.resolve_buffer(buffer)
    return comment_range(buffer, 1, vim.api.nvim_buf_line_count(buffer), "comment")
end

---@param buffer integer?
---@return integer? changed
function M.uncomment_all(buffer)
    buffer = util.resolve_buffer(buffer)
    return comment_range(buffer, 1, vim.api.nvim_buf_line_count(buffer), "uncomment")
end

return M
