-- Lists temporary prints in the quickfix and location lists
local blocks = require("temp-print.blocks")
local config = require("temp-print.config")
local util = require("temp-print.util")

local M = {}

---@class TempPrint.ListItem
---@field filename string? Absolute path (nil for buffers without a name)
---@field bufnr integer? Buffer of the print (buffer scope, or files that are loaded)
---@field lnum integer Row of the start marker
---@field col integer
---@field text string Text shown in the quickfix list: `[commented ]type: content`
---@field type string? Type of the print (nil if the marker has no type)
---@field commented boolean
---@field content string First line of the print command, trimmed

---@param block { type: string?, commented: boolean } A block
---@param content string
---@return string
local function item_text(block, content)
    local label = (block.commented and "commented " or "") .. (block.type or "untyped")
    return label .. ": " .. content
end

---Items of the temporary prints of some lines
---@param lines string[]
---@param filename string?
---@param bufnr integer?
---@return TempPrint.ListItem[]
local function lines_items(lines, filename, bufnr)
    local items = {}
    for _, block in ipairs(blocks.parse_lines(lines).blocks) do
        local content = block.content_first <= block.content_last and vim.trim(lines[block.content_first] or "") or ""
        table.insert(items, {
            filename = filename,
            bufnr = bufnr,
            lnum = block.start_row,
            col = 1,
            text = item_text(block, content),
            type = block.type,
            commented = block.commented,
            content = content,
        })
    end
    return items
end

---Temporary prints of a buffer
---@param buffer integer?
---@return TempPrint.ListItem[]
function M.buffer_items(buffer)
    buffer = util.resolve_buffer(buffer)
    local name = vim.api.nvim_buf_get_name(buffer)
    return lines_items(vim.api.nvim_buf_get_lines(buffer, 0, -1, false), name ~= "" and name or nil, buffer)
end

---Files inside a directory that have a start marker, found with ripgrep (or grep)
---@param directory string
---@return string[]? files
---@return string? error
local function files_with_markers(directory)
    local marker = config.options.markers.start

    local command
    if vim.fn.executable("rg") == 1 then
        command = { "rg", "--files-with-matches", "--fixed-strings", "--", marker, directory }
    elseif vim.fn.executable("grep") == 1 then
        command = { "grep", "-rlF", "--", marker, directory }
    else
        return nil, "neither 'rg' nor 'grep' is available"
    end

    local result = vim.system(command, { text = true }):wait()
    if result.code > 1 then -- 1 means no match
        return nil, vim.trim(result.stderr or "search failed")
    end

    local files = vim.split(result.stdout or "", "\n", { trimempty = true })
    table.sort(files)
    return files
end

---Temporary prints of the files inside a directory. Loaded buffers are read instead of their files, so unsaved
---changes are listed
---@param directory string? Defaults to the current working directory
---@return TempPrint.ListItem[]? items
---@return string? error
function M.directory_items(directory)
    local files, err = files_with_markers(directory or vim.fn.getcwd())
    if not files then
        return nil, err
    end

    local items = {}
    for _, file in ipairs(files) do
        local path = vim.fn.fnamemodify(file, ":p")
        local buffer = vim.fn.bufnr(path)
        if buffer ~= -1 and vim.api.nvim_buf_is_loaded(buffer) then
            vim.list_extend(items, lines_items(vim.api.nvim_buf_get_lines(buffer, 0, -1, false), path, buffer))
        else
            local ok, read = pcall(vim.fn.readfile, path)
            vim.list_extend(items, lines_items(ok and read or {}, path, nil))
        end
    end
    return items
end

---Temporary prints of the current buffer or of a directory
---@param scope "buffer"|"directory"? Defaults to "buffer"
---@param directory string? Directory of the "directory" scope. Defaults to the current working directory
---@return TempPrint.ListItem[]? items
---@return string? error
function M.items(scope, directory)
    if scope == "directory" then
        return M.directory_items(directory)
    end
    return M.buffer_items()
end

---Items for a picker. Notifies and returns nil on errors or when there is no temporary print
---@param scope "buffer"|"directory"?
---@param directory string?
---@return TempPrint.ListItem[]?
function M.picker_items(scope, directory)
    local items, err = M.items(scope, directory)
    if not items then
        util.notify(err --[[@as string]])
        return nil
    end
    if #items == 0 then
        util.notify("no temporary prints found", vim.log.levels.INFO)
        return nil
    end
    return items
end

---Path shown by the pickers: relative to the current working directory when possible
---@param item TempPrint.ListItem
---@return string
function M.display_path(item)
    if item.filename then
        return vim.fn.fnamemodify(item.filename, ":.")
    end
    return "[No Name]"
end

---Fills the quickfix list with temporary prints and opens it
---@param scope "buffer"|"directory"? Defaults to "buffer"
---@param directory string? Directory searched by the "directory" scope. Defaults to the current working directory
---@return integer? count Number of listed prints
function M.to_quickfix(scope, directory)
    local items, err = M.items(scope, directory)
    if not items then
        util.notify(err --[[@as string]])
        return nil
    end

    vim.fn.setqflist({}, " ", { title = "Temporary prints", items = items })
    vim.cmd("botright copen")
    return #items
end

---Fills the location list of the current window with the temporary prints of its buffer and opens it
---@return integer count
function M.to_loclist()
    local items = M.buffer_items()
    vim.fn.setloclist(0, {}, " ", { title = "Temporary prints", items = items })
    vim.cmd("lopen")
    return #items
end

return M
