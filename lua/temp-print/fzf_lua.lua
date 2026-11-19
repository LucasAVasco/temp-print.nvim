-- fzf-lua picker of the temporary prints. Optional: never loaded by `setup()`. Requires fzf-lua
--
--   require("temp-print.fzf_lua").open("directory")
local list = require("temp-print.list")
local util = require("temp-print.util")

local M = {}

---Converts list items into fzf-lua entries (`path:line:col:text`, parsed by its previewer and file actions)
---@param items TempPrint.ListItem[]
---@return string[]
function M._entries(items)
    local entries = {}
    for _, item in ipairs(items) do
        if item.filename then
            table.insert(entries, ("%s:%d:%d: %s"):format(list.display_path(item), item.lnum, item.col, item.text))
        end
    end
    return entries
end

---Opens the picker
---@param scope "buffer"|"directory"? Defaults to "buffer"
---@param directory string? Directory of the "directory" scope. Defaults to the current working directory
---@param opts table? fzf-lua options (merged over the defaults of this picker)
function M.open(scope, directory, opts)
    local ok, fzf_lua = pcall(require, "fzf-lua")
    if not ok then
        return util.notify("fzf-lua is not installed")
    end
    if scope ~= "directory" and vim.api.nvim_buf_get_name(0) == "" then
        return util.notify("the buffer has no name")
    end
    local items = list.picker_items(scope, directory)
    if not items then
        return
    end

    fzf_lua.fzf_exec(
        M._entries(items),
        vim.tbl_deep_extend("force", {
            prompt = "Temp prints> ",
            previewer = "builtin",
            actions = { ["default"] = fzf_lua.actions.file_edit_or_qf },
        }, opts or {})
    )
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
