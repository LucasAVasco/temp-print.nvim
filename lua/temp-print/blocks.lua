-- Parser of the temporary print blocks:
--
--   <comment> TEMP_PRINT_NVIM_MARKER_START[_TYPE]
--   print command(s)
--   <comment> TEMP_PRINT_NVIM_MARKER_END
--
-- A start marker also closes the block that is still open, so blocks can be chained and share a single end marker.
local config = require("temp-print.config")
local util = require("temp-print.util")

local M = {}

---@class TempPrint.Marker
---@field kind "start"|"end"
---@field type string? Lowercase type suffix of a start marker (`location`, `variable`, `previous_line`, `next_line`...)
---@field commented boolean Whether a start marker has the commented prefix

---@class TempPrint.Block
---@field index integer Position of the block in the buffer (1 for the first block)
---@field start_row integer Row of the start marker (all rows are 1-indexed)
---@field content_first integer First row of the print command
---@field content_last integer Last row of the print command (`content_last < content_first` if the block is empty)
---@field end_row integer? Row of the end marker. Nil if the block was closed by the next start marker or never closed
---@field last_row integer Last row of the block (end marker or last content row)
---@field type string?
---@field commented boolean
---@field chained_prev boolean Whether the start marker of this block closed the previous block
---@field chained_next boolean Whether this block was closed by the start marker of the next block
---@field unclosed boolean? The block has no end (parse error)

---@class TempPrint.ParseError
---@field row integer
---@field message string

---@class TempPrint.Parsed
---@field blocks TempPrint.Block[]
---@field errors TempPrint.ParseError[]

---The types of the prints created by this plugin
M.TYPES = { "location", "variable", "previous_line", "next_line" }

---Builds the text of a start marker
---@param type string?
---@param commented boolean?
---@return string
function M.start_marker(type, commented)
    local markers = config.options.markers
    return (commented and markers.commented_prefix or "") .. markers.start .. (type and ("_" .. type:upper()) or "")
end

---@return string
function M.end_marker()
    return config.options.markers["end"]
end

---Parses the marker of a line
---@param line string
---@return TempPrint.Marker?
function M.parse_marker(line)
    local markers = config.options.markers

    local start = line:find(markers.start, 1, true)
    if start then
        local prefix = markers.commented_prefix
        local commented = start > #prefix and line:sub(start - #prefix, start - 1) == prefix
        local type = line:sub(start + #markers.start):match("^_([%w_]+)")
        return { kind = "start", type = type and type:lower() or nil, commented = commented }
    end

    if line:find(markers["end"], 1, true) then
        return { kind = "end", commented = false }
    end
end

---@param lines string[]
---@return TempPrint.Parsed
function M.parse_lines(lines)
    local blocks, errors = {}, {}
    ---@type TempPrint.Block?
    local open = nil

    local function close(content_last, end_row, chained_next)
        assert(open)
        open.content_last = content_last
        open.end_row = end_row
        open.last_row = end_row or content_last
        open.chained_next = chained_next
        table.insert(blocks, open)
        open = nil
    end

    for row, line in ipairs(lines) do
        local marker = M.parse_marker(line)
        if marker and marker.kind == "start" then
            local chained = open ~= nil
            if open then
                close(row - 1, nil, true)
            end
            open = {
                index = #blocks + 1,
                start_row = row,
                content_first = row + 1,
                content_last = row,
                last_row = row,
                type = marker.type,
                commented = marker.commented,
                chained_prev = chained,
                chained_next = false,
            }
        elseif marker then
            if open then
                close(row - 1, row, false)
            else
                table.insert(errors, { row = row, message = "end marker without a start marker" })
            end
        end
    end

    if open then
        table.insert(errors, { row = open.start_row, message = "start marker without an end marker" })
        open.unclosed = true
        close(#lines, nil, false)
    end

    return { blocks = blocks, errors = errors }
end

---@param buffer integer
---@return TempPrint.Parsed
function M.parse(buffer)
    return M.parse_lines(vim.api.nvim_buf_get_lines(buffer, 0, -1, false))
end

---Parses the buffer and notifies the errors, if any
---@param buffer integer
---@param action string Description of the action used in the error message
---@return TempPrint.Parsed?
function M.parse_checked(buffer, action)
    local parsed = M.parse(buffer)
    if #parsed.errors > 0 then
        local messages = vim.tbl_map(function(err)
            return ("line %d: %s"):format(err.row, err.message)
        end, parsed.errors)
        util.notify(("can not %s, invalid temporary prints: %s"):format(action, table.concat(messages, "; ")))
        return nil
    end
    return parsed
end

---@param parsed TempPrint.Parsed
---@param row integer
---@return TempPrint.Block?
function M.block_at(parsed, row)
    for _, block in ipairs(parsed.blocks) do
        if block.start_row <= row and row <= block.last_row then
            return block
        end
    end
end

---Blocks that have at least one row inside the range
---@param parsed TempPrint.Parsed
---@param first integer
---@param last integer
---@return TempPrint.Block[]
function M.blocks_in_range(parsed, first, last)
    return vim.tbl_filter(function(block)
        return block.start_row <= last and block.last_row >= first
    end, parsed.blocks)
end

---Finds the nearest row, starting at `row` and moving in `direction`, that is not blank and not part of a temporary
---print
---@param buffer integer
---@param parsed TempPrint.Parsed
---@param row integer
---@param direction 1|-1
---@return integer?
function M.find_code_row(buffer, parsed, row, direction)
    local line_count = vim.api.nvim_buf_line_count(buffer)
    while row >= 1 and row <= line_count do
        local block = M.block_at(parsed, row)
        if block then
            row = direction > 0 and block.last_row + 1 or block.start_row - 1
        elseif util.is_blank(util.get_line(buffer, row)) then
            row = row + direction
        else
            return row
        end
    end
end

return M
