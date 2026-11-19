-- temp-print.nvim public API. Modules are only loaded when their functions are first called.
-- Rows are 1-indexed and columns are 0-indexed bytes. Nil arguments default to the current buffer and the cursor.
local M = {}

---Configures the plugin
---@param opts TempPrint.UserOptions?
function M.setup(opts)
    require("temp-print.config").setup(opts)
end

---@param module string
---@param name string
---@return function
local function forward(module, name)
    return function(...)
        return require(module)[name](...)
    end
end

-- Filetype configurations

---Loads and merges the configuration files of a filetype (`temp-print/config/<filetype>.lua`) of the given sources
---(default: all), without the `languages` setup option. Raises an error if a file is invalid
---@type fun(filetype: string, sources: TempPrint.Config.Source[]?, buffer: integer?): TempPrint.Config.Lang?
M.load_filetype_config = forward("temp-print.config.language", "load")
---Returns a copy of a configuration with other fields deep-merged over it
---@type fun(base: TempPrint.Config.Lang?, overrides: TempPrint.Config.Lang): TempPrint.Config.Lang
M.extend_filetype_config = forward("temp-print.config.language", "extend")
---Effective configuration of a filetype (all sources, `languages` setup option and defaults)
---@type fun(filetype: string, buffer: integer?): TempPrint.Config.Lang?, string?
M.get_filetype_config = forward("temp-print.config.language", "get_filetype_config")
---Whether the buffer is a Lua file that runs inside Neovim. Uses the `is_neovim_lua` setup option (default: the file is
---inside a Neovim directory). Useful in filetype configuration functions
---@type fun(buffer: integer?): boolean
M.is_neovim_lua = forward("temp-print.lang_utils", "is_neovim_lua")
---Default check of the `is_neovim_lua` setup option: the file of the buffer is inside a Neovim directory
---@type fun(buffer: integer): boolean
M.default_is_neovim_lua = forward("temp-print.lang_utils", "default_is_neovim_lua")
---Whether a file is inside a Neovim directory: configuration, data (plugins), runtime or a 'runtimepath' entry. Symbolic
---links are resolved
---@type fun(path: string): boolean
M.in_neovim_directory = forward("temp-print.lang_utils", "in_neovim_directory")
---Clears the cached filetype configurations. Call it after loading a plugin that provides filetype configurations
M.clear_filetype_config_cache = forward("temp-print.config.language", "clear_cache")

-- Insertion. Return `true` on success

---Inserts a location print after the line `row + offset`
---@type fun(buffer: integer?, row: integer?, col: integer?, offset: integer?): boolean
M.insert_location = forward("temp-print.insert", "location")

---Inserts a print of the variable at the position, after the line `row + offset`
---@type fun(buffer: integer?, row: integer?, col: integer?, offset: integer?): boolean
M.insert_variable = forward("temp-print.insert", "variable")

---Inserts a print of the line at the position followed by a print of the variable, after the line `row + offset`
---@type fun(buffer: integer?, row: integer?, col: integer?, offset: integer?): boolean
M.insert_variable_with_line = forward("temp-print.insert", "variable_with_line")

---Inserts a print of the variable before and after its line (`with_line` also prints the line after it)
---@type fun(buffer: integer?, row: integer?, col: integer?, with_line: boolean?): boolean
M.insert_variable_around = forward("temp-print.insert", "variable_around")

---Inserts, after the row, a print of the row (blank lines are skipped upwards)
---@type fun(buffer: integer?, row: integer?): boolean
M.insert_previous_line = forward("temp-print.insert", "previous_line")

---Inserts, before the row, a print of the row (blank lines are skipped downwards)
---@type fun(buffer: integer?, row: integer?): boolean
M.insert_next_line = forward("temp-print.insert", "next_line")

-- Edition. Return the number of affected prints, or nil if the buffer has invalid prints

---@type fun(buffer: integer?, row: integer?): integer?
M.delete_at = forward("temp-print.edit", "delete_at")
---@type fun(buffer: integer?, first: integer, last: integer): integer?
M.delete_range = forward("temp-print.edit", "delete_range")
---Deletes all prints. Fails without changes if the buffer has invalid prints
---@type fun(buffer: integer?): integer?
M.clear_all = forward("temp-print.edit", "clear_all")

---@type fun(buffer: integer?, row: integer?): integer?
M.comment_at = forward("temp-print.edit", "comment_at")
---@type fun(buffer: integer?, row: integer?): integer?
M.uncomment_at = forward("temp-print.edit", "uncomment_at")
---@type fun(buffer: integer?, row: integer?): integer?
M.toggle_comment_at = forward("temp-print.edit", "toggle_comment_at")
---@type fun(buffer: integer?, first: integer, last: integer): integer?
M.comment_range = forward("temp-print.edit", "comment_range")
---@type fun(buffer: integer?, first: integer, last: integer): integer?
M.uncomment_range = forward("temp-print.edit", "uncomment_range")
---@type fun(buffer: integer?, first: integer, last: integer): integer?
M.toggle_comment_range = forward("temp-print.edit", "toggle_comment_range")
---@type fun(buffer: integer?): integer?
M.comment_all = forward("temp-print.edit", "comment_all")
---@type fun(buffer: integer?): integer?
M.uncomment_all = forward("temp-print.edit", "uncomment_all")

-- Auto-update

---Regenerates the location and line prints of the buffer
---@type fun(buffer: integer?): integer?
M.update = forward("temp-print.update", "update")
M.enable_auto_update = forward("temp-print.update", "enable_auto_update")
M.disable_auto_update = forward("temp-print.update", "disable_auto_update")
M.toggle_auto_update = forward("temp-print.update", "toggle_auto_update")
---@type fun(): boolean
M.is_auto_update_enabled = forward("temp-print.update", "is_auto_update_enabled")

-- Navigation (current window). Return `true` if the cursor moved

---@type fun(count: integer?): boolean
M.goto_next = forward("temp-print.navigate", "next")
---@type fun(count: integer?): boolean
M.goto_prev = forward("temp-print.navigate", "prev")
---@type fun(): boolean
M.goto_first = forward("temp-print.navigate", "first")
---@type fun(): boolean
M.goto_last = forward("temp-print.navigate", "last")

-- Lists

---@type fun(scope: "buffer"|"directory"?, directory: string?): integer?
M.to_quickfix = forward("temp-print.list", "to_quickfix")
---@type fun(): integer
M.to_loclist = forward("temp-print.list", "to_loclist")

-- Highlight

M.enable_highlight = forward("temp-print.highlight", "enable")
M.disable_highlight = forward("temp-print.highlight", "disable")
M.toggle_highlight = forward("temp-print.highlight", "toggle")
---@type fun(): boolean
M.is_highlight_enabled = forward("temp-print.highlight", "is_enabled")

return M
