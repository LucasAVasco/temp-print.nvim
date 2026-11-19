-- Insertion of temporary prints
local blocks = require("temp-print.blocks")
local context = require("temp-print.context")
local render = require("temp-print.render")
local util = require("temp-print.util")

local M = {}

---@class TempPrint.BlockSpec
---@field type string Print type (marker suffix)
---@field lines string[] Rendered command lines (may contain the `<LINE_NUMBER>` tag)
---@field target_row integer? Printed row (line prints), in buffer coordinates before the insertion
---@field lang_config TempPrint.Config.Lang? Configuration used to render the lines (placeholders)

---Inserts chained blocks after `after_row`, sharing a single end marker. Keeps the cursor on its code line
---@param buffer integer
---@param after_row integer 0 inserts at the top
---@param specs TempPrint.BlockSpec[]
---@return integer? inserted Number of inserted lines, nil on error
function M.insert_blocks(buffer, after_row, specs)
    local commentstring, err = util.get_commentstring(buffer)
    if not commentstring then
        util.notify(err --[[@as string]])
        return nil
    end

    local indent = context.insert_indentation(buffer, after_row)

    local total = 1 -- End marker
    for _, spec in ipairs(specs) do
        total = total + 1 + #spec.lines
    end

    local lines = {}
    local row = after_row
    for _, spec in ipairs(specs) do
        table.insert(lines, indent .. util.comment_line(commentstring, blocks.start_marker(spec.type)))
        row = row + 1

        local target_row = spec.target_row
        if target_row and target_row > after_row then
            target_row = target_row + total
        end

        for _, line in ipairs(render.set_line_numbers(spec.type, spec.lines, row + 1, target_row, spec.lang_config)) do
            table.insert(lines, indent .. line)
        end
        row = row + #spec.lines
    end
    table.insert(lines, indent .. util.comment_line(commentstring, blocks.end_marker()))

    util.keep_cursor(buffer, function()
        vim.api.nvim_buf_set_lines(buffer, after_row, after_row, false, lines)
    end)
    return #lines
end

---@param buffer integer
---@param row integer
---@return integer
local function clamp_row(buffer, row)
    return math.max(0, math.min(row, vim.api.nvim_buf_line_count(buffer)))
end

---Builds the spec of a location print
---@param info TempPrint.ContextInfo
---@return TempPrint.BlockSpec?
---@return string? error
local function location_spec(info)
    local lines, err = render.render("location", info.lang_config, {
        context = context.get_context(info),
        file_path = context.get_file_path(info.buffer),
    })
    if not lines then
        return nil, err
    end
    return { type = "location", lines = lines, lang_config = info.lang_config }
end

---Builds the spec of a variable print
---@param info TempPrint.ContextInfo
---@return TempPrint.BlockSpec?
---@return string? error
local function variable_spec(info)
    local var_name, var = context.get_variable(info)
    if not var_name or not var then
        return nil, "no variable under the cursor"
    end

    local lines, err = render.render("variable", info.lang_config, {
        context = context.get_context(info),
        file_path = context.get_file_path(info.buffer),
        var_name = var_name,
        var = var,
    })
    if not lines then
        return nil, err
    end
    return { type = "variable", lines = lines, lang_config = info.lang_config }
end

---Builds the spec of a line print (previous_line or next_line) that prints `target_row`
---@param type "previous_line"|"next_line"
---@param buffer integer
---@param target_row integer
---@return TempPrint.BlockSpec?
---@return string? error
function M.line_spec(type, buffer, target_row)
    local info, err = context.for_line(buffer, target_row)
    if not info then
        return nil, err
    end

    local lines, render_err = render.render(type, info.lang_config, {
        context = context.get_context(info),
        file_path = context.get_file_path(buffer),
        line = util.get_line(buffer, target_row) or "",
    })
    if not lines then
        return nil, render_err
    end
    return { type = type, lines = lines, target_row = target_row, lang_config = info.lang_config }
end

---Runs `fn` with a context and notifies its error
---@param buffer integer?
---@param row integer?
---@param col integer?
---@param fn fun(info: TempPrint.ContextInfo): boolean?, string?
---@return boolean success
local function with_context(buffer, row, col, fn)
    local info, err = context.new(buffer, row, col)
    if not info then
        util.notify(err --[[@as string]])
        return false
    end

    local ok, fn_err = fn(info)
    if not ok then
        if fn_err then
            util.notify(fn_err)
        end
        return false
    end
    return true
end

---Inserts the print built by `build_spec` after the line `info.row + offset`
---@param buffer integer?
---@param row integer?
---@param col integer?
---@param offset integer?
---@param build_spec fun(info: TempPrint.ContextInfo): TempPrint.BlockSpec?, string?
---@return boolean success
local function insert_at_offset(buffer, row, col, offset, build_spec)
    return with_context(buffer, row, col, function(info)
        local spec, err = build_spec(info)
        if not spec then
            return false, err
        end
        return M.insert_blocks(info.buffer, clamp_row(info.buffer, info.row + (offset or 0)), { spec }) ~= nil
    end)
end

---Inserts a location print
---@param buffer integer? Defaults to the current buffer
---@param row integer? Row used for the context. Defaults to the cursor
---@param col integer? Column used for the context. Defaults to the cursor
---@param offset integer? The print is inserted after the line `row + offset`. Defaults to 0 (after the row)
---@return boolean success
function M.location(buffer, row, col, offset)
    return insert_at_offset(buffer, row, col, offset, location_spec)
end

---Inserts a location print after a line, with the context at its first non-blank character
---@param buffer integer?
---@param row integer
---@return boolean success
function M.location_for_line(buffer, row)
    buffer = util.resolve_buffer(buffer)
    return M.location(buffer, row, #util.indentation(util.get_line(buffer, row)))
end

---Inserts a variable print. The variable is the one at the position, the offset only changes where the print goes
---@param buffer integer?
---@param row integer?
---@param col integer?
---@param offset integer? The print is inserted after the line `row + offset`. Defaults to 0
---@return boolean success
function M.variable(buffer, row, col, offset)
    return insert_at_offset(buffer, row, col, offset, variable_spec)
end

---Calls `fn` for each non-blank row of the range that is not part of a temporary print. Rows are processed from the
---top and shifted by the lines inserted so far, so the line numbers of the inserted prints stay correct
---@param buffer integer?
---@param first integer
---@param last integer
---@param fn fun(buffer: integer, row: integer)
function M.each_code_line(buffer, first, last, fn)
    buffer = util.resolve_buffer(buffer)
    local parsed = blocks.parse(buffer)
    local rows = {}
    for row = first, last do
        if not util.is_blank(util.get_line(buffer, row)) and not blocks.block_at(parsed, row) then
            table.insert(rows, row)
        end
    end

    local initial_count = vim.api.nvim_buf_line_count(buffer)
    for _, row in ipairs(rows) do
        fn(buffer, row + vim.api.nvim_buf_line_count(buffer) - initial_count)
    end
end

---Finds the code row printed by a line print, skipping blank lines and temporary prints
---@param buffer integer
---@param row integer
---@param direction 1|-1
---@return integer?
local function code_row(buffer, row, direction)
    return blocks.find_code_row(buffer, blocks.parse(buffer), row, direction)
end

---Inserts a line print next to the row: a previous line print after it, or a next line print before it
---@param buffer integer?
---@param row integer? Defaults to the cursor row
---@param type "previous_line"|"next_line"
---@return boolean success
local function insert_line_print(buffer, row, type)
    buffer = util.resolve_buffer(buffer)
    if not row then
        local err
        row, err = util.cursor(buffer)
        if not row then
            util.notify(err --[[@as string]])
            return false
        end
    end

    local is_previous = type == "previous_line"
    local target = code_row(buffer, row, is_previous and -1 or 1)
    if not target then
        util.notify(("no line to print %s line %d"):format(is_previous and "above" or "below", row))
        return false
    end

    local spec, err = M.line_spec(type, buffer, target)
    if not spec then
        util.notify(err --[[@as string]])
        return false
    end
    return M.insert_blocks(buffer, is_previous and row or row - 1, { spec }) ~= nil
end

---Inserts, after the row, a print of the row (or of the nearest non-blank line above it)
---@param buffer integer?
---@param row integer? Defaults to the cursor row
---@return boolean success
function M.previous_line(buffer, row)
    return insert_line_print(buffer, row, "previous_line")
end

---Inserts, before the row, a print of the row (or of the nearest non-blank line below it)
---@param buffer integer?
---@param row integer? Defaults to the cursor row
---@return boolean success
function M.next_line(buffer, row)
    return insert_line_print(buffer, row, "next_line")
end

---Inserts, after the line `row + offset`, a print of the line `row` followed by a print of the variable at the position
---@param buffer integer?
---@param row integer?
---@param col integer?
---@param offset integer?
---@return boolean success
function M.variable_with_line(buffer, row, col, offset)
    return with_context(buffer, row, col, function(info)
        local after_row = clamp_row(info.buffer, info.row + (offset or 0))
        local target = code_row(info.buffer, info.row, -1)
        if not target then
            return false, "no line to print"
        end

        local line, line_err = M.line_spec("previous_line", info.buffer, target)
        if not line then
            return false, line_err
        end
        local var, var_err = variable_spec(info)
        if not var then
            return false, var_err
        end
        return M.insert_blocks(info.buffer, after_row, { line, var }) ~= nil
    end)
end

---Inserts a print of the variable at the position before and after its line. Useful to check whether the line changes
---the variable
---@param buffer integer?
---@param row integer?
---@param col integer?
---@param with_line boolean? Also print the line itself after it
---@return boolean success
function M.variable_around(buffer, row, col, with_line)
    return with_context(buffer, row, col, function(info)
        local spec, err = variable_spec(info)
        if not spec then
            return false, err
        end

        -- Above first, then the line moves down by the inserted lines
        local inserted = M.insert_blocks(info.buffer, info.row - 1, { spec })
        if not inserted then
            return false
        end
        local row_now = info.row + inserted

        local after = { spec }
        if with_line then
            local line, line_err = M.line_spec("previous_line", info.buffer, row_now)
            if not line then
                return false, line_err
            end
            after = { line, spec }
        end
        return M.insert_blocks(info.buffer, row_now, after) ~= nil
    end)
end

return M
