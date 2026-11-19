-- Regeneration of the location and line prints (their file path, line numbers, context and printed line change when
-- the code changes). Variable and commented prints, and prints without a type, are never changed
local blocks = require("temp-print.blocks")
local config = require("temp-print.config")
local context = require("temp-print.context")
local render = require("temp-print.render")
local util = require("temp-print.util")

local M = {}

local GROUP = "TempPrintAutoUpdate"
local enabled = false

---Normalized content of a print, so the changes made by code formatters (indentation, line breaks, spaces and
---trailing commas) are not seen as outdated content
---@param lines string[]
---@return string
local function normalize(lines)
    local text = table.concat(lines, ""):gsub("%s+", "")
    text = text:gsub(",([%)%]}])", "%1")
    return text
end

---@class TempPrint.RenderedBlock
---@field lines string[] Content without indentation and with the `<LINE_NUMBER>` tags
---@field target_row integer? Printed row of line prints (before the update)
---@field lang_config TempPrint.Config.Lang

---Renders the new content of a block
---@param buffer integer
---@param parsed TempPrint.Parsed
---@param block TempPrint.Block
---@return TempPrint.RenderedBlock? rendered Nil if the block must be kept as is (or on error)
---@return string? error
local function render_block(buffer, parsed, block)
    if block.type == "location" then
        local anchor = blocks.find_code_row(buffer, parsed, block.start_row - 1, -1)
        local info, err = context.for_line(buffer, anchor or block.start_row)
        if not info then
            return nil, err
        end
        local lines, render_err = render.render("location", info.lang_config, {
            context = anchor and context.get_context(info) or "",
            file_path = context.get_file_path(buffer),
        })
        if not lines then
            return nil, render_err
        end
        return { lines = lines, lang_config = info.lang_config }
    end

    local direction = block.type == "previous_line" and -1 or 1
    local from = direction < 0 and block.start_row - 1 or block.last_row + 1
    local target = blocks.find_code_row(buffer, parsed, from, direction)
    if not target then
        return nil -- Nothing to print: keep the block as is
    end

    local info, err = context.for_line(buffer, target)
    if not info then
        return nil, err
    end
    local lines, render_err = render.render(block.type, info.lang_config, {
        context = context.get_context(info),
        file_path = context.get_file_path(buffer),
        line = util.get_line(buffer, target) or "",
    })
    if not lines then
        return nil, render_err
    end
    return { lines = lines, target_row = target, lang_config = info.lang_config }
end

---Replaces the content of a block by the rendered one, unless only its formatting differs
---@param buffer integer
---@param block TempPrint.Block
---@param rendered TempPrint.RenderedBlock
---@return boolean changed
local function write_block(buffer, block, rendered)
    -- The printed row moves when the block above it changes size
    local target = rendered.target_row
    local old_count = block.content_last - block.content_first + 1
    if target and target > block.start_row then
        target = target + #rendered.lines - old_count
    end

    local indent = util.indentation(util.get_line(buffer, block.start_row))
    local lines = render.set_line_numbers(block.type, rendered.lines, block.content_first, target, rendered.lang_config)
    local new_lines = vim.tbl_map(function(line)
        return indent .. line
    end, lines)

    local old_lines = vim.api.nvim_buf_get_lines(buffer, block.content_first - 1, block.content_last, false)
    if normalize(old_lines) == normalize(new_lines) then
        return false
    end
    vim.api.nvim_buf_set_lines(buffer, block.content_first - 1, block.content_last, false, new_lines)
    return true
end

---Regenerates the location and line prints of the buffer. Does nothing if the buffer has invalid prints
---@param buffer integer?
---@return integer? updated Number of changed prints (nil on error)
function M.update(buffer)
    buffer = util.resolve_buffer(buffer)
    local updated = 0

    -- Blocks are processed from the top, parsing again after each change because the rows move
    local index = 1
    while true do
        local parsed = blocks.parse_checked(buffer, "update temporary prints")
        if not parsed then
            return nil
        end
        local block = parsed.blocks[index]
        if not block then
            return updated
        end

        if not block.commented and render.UPDATABLE[block.type] then
            local rendered, err = render_block(buffer, parsed, block)
            if err then
                util.notify(("can not update the temporary print at line %d: %s"):format(block.start_row, err))
                return nil
            end
            if rendered and write_block(buffer, block, rendered) then
                updated = updated + 1
            end
        end

        index = index + 1
    end
end

---Whether the buffer has a start marker. Cheap check done before saving
---@param buffer integer
---@return boolean
local function has_markers(buffer)
    local start = config.options.markers.start
    for _, line in ipairs(vim.api.nvim_buf_get_lines(buffer, 0, -1, false)) do
        if line:find(start, 1, true) then
            return true
        end
    end
    return false
end

---Regenerates the prints before saving any buffer
function M.enable_auto_update()
    enabled = true
    local group = vim.api.nvim_create_augroup(GROUP, { clear = true })
    vim.api.nvim_create_autocmd("BufWritePre", {
        group = group,
        desc = "temp-print: update the temporary prints",
        callback = function(args)
            if vim.bo[args.buf].modifiable and has_markers(args.buf) then
                M.update(args.buf)
            end
        end,
    })
end

function M.disable_auto_update()
    enabled = false
    pcall(vim.api.nvim_del_augroup_by_name, GROUP)
end

function M.toggle_auto_update()
    if enabled then
        M.disable_auto_update()
    else
        M.enable_auto_update()
    end
end

---@return boolean
function M.is_auto_update_enabled()
    return enabled
end

---Applies the `auto_update` option. Called by `setup()`
function M.setup()
    if config.options.auto_update then
        M.enable_auto_update()
    else
        M.disable_auto_update()
    end
end

return M
