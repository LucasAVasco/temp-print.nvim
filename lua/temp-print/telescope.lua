-- Telescope picker of the temporary prints. Optional: never loaded by `setup()`. Requires telescope.nvim
--
--   require("temp-print.telescope").open("directory")
local list = require("temp-print.list")
local util = require("temp-print.util")

local M = {}

---Converts a list item into a Telescope entry
---@param item TempPrint.ListItem
---@return table
function M._entry_maker(item)
    local path = list.display_path(item)
    local display = ("%s:%d  %s"):format(path, item.lnum, item.text)
    return {
        value = item,
        display = display,
        ordinal = display,
        filename = item.filename,
        bufnr = item.bufnr,
        lnum = item.lnum,
        col = item.col,
    }
end

---Opens the picker
---@param scope "buffer"|"directory"? Defaults to "buffer"
---@param directory string? Directory of the "directory" scope. Defaults to the current working directory
---@param opts table? Telescope picker options
function M.open(scope, directory, opts)
    if not pcall(require, "telescope") then
        return util.notify("telescope.nvim is not installed")
    end
    local items = list.picker_items(scope, directory)
    if not items then
        return
    end

    local conf = require("telescope.config").values
    opts = opts or {}
    require("telescope.pickers")
        .new(opts, {
            prompt_title = scope == "directory" and "Temporary prints (directory)" or "Temporary prints",
            finder = require("telescope.finders").new_table({ results = items, entry_maker = M._entry_maker }),
            sorter = conf.generic_sorter(opts),
            previewer = conf.grep_previewer(opts),
        })
        :find()
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
