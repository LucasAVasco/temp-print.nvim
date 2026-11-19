-- Helpers for the filetype configurations (`temp-print/config/<filetype>.lua`). Can also be used by user configurations
local util = require("temp-print.util")

local M = {}

---Escapes text for a double-quoted string literal in C-like languages (C, Go, JavaScript, Lua, Python, Rust...)
---@param text string
---@return string
function M.escape_double_quoted(text)
    local escaped = text:gsub("\\", "\\\\"):gsub('"', '\\"')
    return escaped
end

---Escapes text for the double-quoted format string of printf-like functions (C, Go, JavaScript `console.log`...)
---@param text string
---@return string
function M.escape_printf(text)
    local escaped = M.escape_double_quoted(text):gsub("%%", "%%%%")
    return escaped
end

---Escapes text for the format string of Rust formatting macros (`println!`, `format!`...)
---@param text string
---@return string
function M.escape_rust_format(text)
    local escaped = M.escape_double_quoted(text):gsub("{", "{{"):gsub("}", "}}")
    return escaped
end

---Escapes text for a double-quoted Python f-string
---@param text string
---@return string
function M.escape_python_fstring(text)
    local escaped = M.escape_double_quoted(text):gsub("{", "{{"):gsub("}", "}}")
    return escaped
end

---Escapes text for a single-quoted shell string
---@param text string
---@return string
function M.escape_single_quoted_shell(text)
    local escaped = text:gsub("'", "'\\''")
    return escaped
end

---Escapes text for the single-quoted format string of the shell `printf`
---@param text string
---@return string
function M.escape_printf_shell(text)
    local escaped = text:gsub("\\", "\\\\"):gsub("%%", "%%%%")
    return M.escape_single_quoted_shell(escaped)
end

---Text of the first node of a chain of fields. Example: `field_chain_text(node, buffer, "declarator", "declarator")`
---@param node TSNode
---@param buffer integer
---@param ... string Field names
---@return string?
function M.field_chain_text(node, buffer, ...)
    ---@type TSNode?
    local current = node
    for _, field in ipairs({ ... }) do
        current = current and current:field(field)[1]
    end
    return current and vim.treesitter.get_node_text(current, buffer) or nil
end

---Default node name: the `name` field
---@type TempPrint.Config.Lang.GetNodeName
function M.name_field(node, buffer)
    return M.field_chain_text(node, buffer, "name")
end

---Whether a file is inside a Neovim directory: the configuration (`stdpath("config")`), the data directory where plugin
---managers install plugins (`stdpath("data")`), the runtime (`$VIMRUNTIME`) or any 'runtimepath' entry. Symbolic links
---of the file and of the directories are resolved, so a configuration managed with symbolic links (like GNU stow) is
---detected when the file is opened through its real path. Not detected: a file opened through its real path when only
---some subdirectories of the configuration are links
---@param path string File path (absolute, relative to the working directory, or starting with `~`)
---@return boolean
function M.in_neovim_directory(path)
    if path == "" then
        return false
    end
    -- Each path is compared as given and with its symbolic links resolved
    local file_path = util.absolute_path(path)
    local file_paths = { file_path, util.real_path(file_path) }

    local neovim_dirs = { vim.fn.stdpath("config"), vim.fn.stdpath("data"), vim.env.VIMRUNTIME }
    vim.list_extend(neovim_dirs, vim.api.nvim_list_runtime_paths())
    local dirs = {}
    for _, dir in ipairs(neovim_dirs) do
        if dir and dir ~= "" then
            vim.list_extend(dirs, {
                vim.fs.normalize(dir --[[@as string]]),
                util.real_path(dir --[[@as string]]),
            })
        end
    end

    for _, dir in ipairs(dirs) do
        for _, candidate in ipairs(file_paths) do
            if util.is_inside(candidate, dir) then
                return true
            end
        end
    end
    return false
end

---Default `is_neovim_lua` check: the file of the buffer is inside a Neovim directory (see `in_neovim_directory`)
---@type TempPrint.IsNeovimLua
function M.default_is_neovim_lua(buffer)
    return M.in_neovim_directory(vim.api.nvim_buf_get_name(buffer))
end

---Whether the buffer is a Lua file that runs inside Neovim (with the `vim` module, like `vim.print`). Uses the
---`is_neovim_lua` setup option, or `default_is_neovim_lua`. A custom `is_neovim_lua` option must not call this function
---(it would call itself): use `default_is_neovim_lua` or `in_neovim_directory` instead
---@param buffer integer? 0 for the current buffer
---@return boolean
function M.is_neovim_lua(buffer)
    if not buffer then
        return false
    end
    if buffer == 0 then
        buffer = vim.api.nvim_get_current_buf()
    end
    if not vim.api.nvim_buf_is_valid(buffer) then
        return false
    end
    local check = require("temp-print.config").options.is_neovim_lua or M.default_is_neovim_lua
    return check(buffer) == true
end

return M
