-- snacks.nvim picker of the temporary prints. Optional: never loaded by `setup()`. Requires snacks.nvim
--
--   require("temp-print.snacks").open("directory")
local list = require("temp-print.list")
local util = require("temp-print.util")

local M = {}

---Converts list items into snacks.nvim picker items
---@param items TempPrint.ListItem[]
---@return table[]
function M._items(items)
    local result = {}
    for index, item in ipairs(items) do
        local path = list.display_path(item)
        table.insert(result, {
            idx = index,
            text = ("%s:%d %s"):format(path, item.lnum, item.text),
            file = item.filename,
            buf = item.bufnr,
            pos = { item.lnum, 0 },
            path = path,
            item = item,
        })
    end
    return result
end

---Line of a picker item
---@param entry table
---@return table[]
function M._format(entry)
    local item = entry.item --[[@as TempPrint.ListItem]]
    return {
        { entry.path, "SnacksPickerFile" },
        { ":", "SnacksPickerDelim" },
        { tostring(item.lnum), "SnacksPickerRow" },
        { "  " },
        { (item.commented and "commented " or "") .. (item.type or "untyped"), item.commented and "Comment" or "Type" },
        { " " .. item.content },
    }
end

---Opens the picker
---@param scope "buffer"|"directory"? Defaults to "buffer"
---@param directory string? Directory of the "directory" scope. Defaults to the current working directory
---@param opts table? snacks.nvim picker options (merged over the defaults of this picker)
function M.open(scope, directory, opts)
    local ok, snacks = pcall(require, "snacks")
    if not ok then
        return util.notify("snacks.nvim is not installed")
    end
    local items = list.picker_items(scope, directory)
    if not items then
        return
    end

    snacks.picker.pick(vim.tbl_deep_extend("force", {
        source = "temp_print",
        title = scope == "directory" and "Temporary prints (directory)" or "Temporary prints",
        items = M._items(items),
        format = function(entry)
            return M._format(entry)
        end,
        preview = "file",
        confirm = "jump",
    }, opts or {}))
end

---@param opts table?
function M.buffer(opts)
    M.open("buffer", nil, opts)
end

---@param directory string?
---@param opts table?
function M.directory(directory, opts)
    M.open("directory", directory, opts)
end

return M
