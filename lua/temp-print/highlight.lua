-- Highlighting of temporary prints, applied to every buffer while enabled
local blocks = require("temp-print.blocks")
local config = require("temp-print.config")

local M = {}

local GROUP = "TempPrintHighlight"
local ns = vim.api.nvim_create_namespace("temp-print-highlight")
local enabled = false
local pending = {} ---@type table<integer, boolean>

---Highlight group of each element
M.GROUPS = {
    marker = "TempPrintMarker",
    content = "TempPrintContent",
    commented = "TempPrintCommented",
}

---Defines the highlight groups from the options
function M.apply_groups()
    for key, group in pairs(M.GROUPS) do
        vim.api.nvim_set_hl(0, group, config.options.highlight[key])
    end
end

---Redraws the highlights of a buffer
---@param buffer integer
function M.refresh(buffer)
    if not vim.api.nvim_buf_is_valid(buffer) then
        return
    end
    vim.api.nvim_buf_clear_namespace(buffer, ns, 0, -1)
    if not enabled then
        return
    end

    local function mark(row, group)
        vim.api.nvim_buf_set_extmark(buffer, ns, row - 1, 0, { line_hl_group = group })
    end

    for _, block in ipairs(blocks.parse(buffer).blocks) do
        local marker_group = block.commented and M.GROUPS.commented or M.GROUPS.marker
        local content_group = block.commented and M.GROUPS.commented or M.GROUPS.content
        mark(block.start_row, marker_group)
        for row = block.content_first, block.content_last do
            mark(row, content_group)
        end
        if block.end_row then
            mark(block.end_row, marker_group) -- The end marker follows the block it closes
        end
    end
end

---Schedules a refresh, merging the requests done in the same event loop iteration
---@param buffer integer
local function schedule_refresh(buffer)
    if pending[buffer] then
        return
    end
    pending[buffer] = true
    vim.schedule(function()
        pending[buffer] = nil
        M.refresh(buffer)
    end)
end

function M.enable()
    enabled = true
    local group = vim.api.nvim_create_augroup(GROUP, { clear = true })
    vim.api.nvim_create_autocmd({ "BufEnter", "BufWinEnter", "TextChanged", "TextChangedI", "InsertLeave" }, {
        group = group,
        desc = "temp-print: highlight the temporary prints",
        callback = function(args)
            schedule_refresh(args.buf)
        end,
    })
    for _, win in ipairs(vim.api.nvim_list_wins()) do
        M.refresh(vim.api.nvim_win_get_buf(win))
    end
end

function M.disable()
    enabled = false
    pcall(vim.api.nvim_del_augroup_by_name, GROUP)
    for _, buffer in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_is_loaded(buffer) then
            vim.api.nvim_buf_clear_namespace(buffer, ns, 0, -1)
        end
    end
end

function M.toggle()
    if enabled then
        M.disable()
    else
        M.enable()
    end
end

---@return boolean
function M.is_enabled()
    return enabled
end

---Applies the highlight options. Called by `setup()`
function M.setup()
    M.apply_groups()
    if config.options.highlight.enabled then
        M.enable()
    else
        M.disable()
    end
end

-- The groups must exist even without `setup()`, and survive color scheme changes
M.apply_groups()
vim.api.nvim_create_autocmd("ColorScheme", {
    group = vim.api.nvim_create_augroup("TempPrintHighlightGroups", { clear = true }),
    callback = M.apply_groups,
})

return M
