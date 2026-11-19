-- Information about a position used to build the print commands: tree-sitter context, variable, file path...
local config = require("temp-print.config")
local language = require("temp-print.config.language")
local util = require("temp-print.util")

local M = {}

---Returns the named tree-sitter node at the position, including injected languages
---@param buffer integer
---@param row integer
---@param col integer
---@return TSNode?
local function get_ts_node(buffer, row, col)
    local ok, parser = pcall(vim.treesitter.get_parser, buffer)
    if not ok or not parser then
        return nil
    end
    parser:parse(true)

    local node_ok, node = pcall(vim.treesitter.get_node, { bufnr = buffer, pos = { row - 1, col }, ignore_injections = false })
    return node_ok and node or nil
end

---Creates the context of a position. The row and column default to the cursor of a window showing the buffer
---@param buffer integer?
---@param row integer?
---@param col integer?
---@return TempPrint.ContextInfo?
---@return string? error
function M.new(buffer, row, col)
    buffer = util.resolve_buffer(buffer)
    local filetype = vim.bo[buffer].filetype

    if not row or not col then
        local cursor_row, cursor_col = util.cursor(buffer)
        if not cursor_row then
            return nil, cursor_col --[[@as string]]
        end
        row, col = row or cursor_row, col or cursor_col --[[@as integer]]
    end

    local lang_config, err = language.get_filetype_config(filetype, buffer)
    if not lang_config then
        return nil, err or ("no language configuration found for filetype '%s'"):format(filetype)
    end

    return {
        buffer = buffer,
        row = row,
        col = col,
        filetype = filetype,
        ts_node = get_ts_node(buffer, row, col),
        lang_config = lang_config,
    }
end

---Context of a line, at its first non-blank character
---@param buffer integer
---@param row integer
---@return TempPrint.ContextInfo?
---@return string? error
function M.for_line(buffer, row)
    local line = util.get_line(buffer, row) or ""
    return M.new(buffer, row, #util.indentation(line))
end

---Default context: the names of the tree-sitter ancestors, from the root to the node (e.g. `MyClass#my_method`)
---@type TempPrint.GetContext
function M.default_get_context(info)
    local get_node_name = info.lang_config.get_node_name or require("temp-print.lang_utils").name_field
    local names = {}

    ---@type TSNode?
    local node = info.ts_node
    while node do
        local name = get_node_name(node, info.buffer)
        if name and name ~= "" then
            table.insert(names, 1, name)
        end
        node = node:parent()
    end

    return table.concat(names, config.options.context_separator)
end

---Context string. Uses the filetype function, then the setup function, then the default one
---@param info TempPrint.ContextInfo
---@return string
function M.get_context(info)
    local get_context = info.lang_config.get_context or config.options.get_context or M.default_get_context
    local ok, result = pcall(get_context, info)
    if not ok then
        util.notify("error in get_context: " .. tostring(result))
        return ""
    end
    return result or ""
end

---Default function to get the variable expression: the identifier under the cursor joined with the preceding
---identifier (`identifier`, `property_identifier`, `field_identifier`, ...) and `.` siblings (e.g. `foo.bar`)
---@type TempPrint.Config.Lang.GetVar
function M.default_get_var(ts_node, buffer)
    local parts = {}
    ---@type TSNode?
    local node = ts_node
    while node and (node:type() == "." or node:type():find("identifier$")) do
        table.insert(parts, 1, vim.treesitter.get_node_text(node, buffer))
        node = node:prev_sibling()
    end

    if #parts == 0 then
        return nil
    end
    return table.concat(parts)
end

---Expression under the position, without tree-sitter. Example: `foo.bar` in `x = foo.bar + 1`
---@param buffer integer
---@param row integer
---@param col integer
---@return string?
local function expression_at(buffer, row, col)
    local line = util.get_line(buffer, row) or ""
    local first, last = col + 1, col + 1
    if not line:sub(first, first):match("[%w_]") then
        return nil
    end
    while first > 1 and line:sub(first - 1, first - 1):match("[%w_%.]") do
        first = first - 1
    end
    while last < #line and line:sub(last + 1, last + 1):match("[%w_]") do
        last = last + 1
    end
    return line:sub(first, last)
end

---Variable under the position
---@param info TempPrint.ContextInfo
---@return string? name
---@return string? expression
function M.get_variable(info)
    if not info.ts_node then
        local expression = expression_at(info.buffer, info.row, info.col)
        return expression, expression
    end

    local print_config = info.lang_config.print_variable or {}
    local get_var = print_config.get_var or M.default_get_var
    local get_var_name = print_config.get_var_name or get_var
    return get_var_name(info.ts_node, info.buffer), get_var(info.ts_node, info.buffer)
end

---Default project root: the nearest ancestor directory with one of the `project_markers`
---@type TempPrint.GetProjectRoot
function M.default_get_project_root(buffer)
    return vim.fs.root(buffer, config.options.project_markers)
end

---Default file path formatter: relative to the deepest directory among the project root and the current working
---directory that contains the file. Falls back to the path relative to the home directory
---@type TempPrint.FormatFilePath
function M.default_format_file_path(full_path, buffer)
    local bases = { vim.fn.getcwd() }
    local get_project_root = config.options.get_project_root or M.default_get_project_root
    local ok, root = pcall(get_project_root, buffer, full_path)
    if ok and type(root) == "string" then
        table.insert(bases, root)
    end

    local best = nil
    for _, base in ipairs(bases) do
        base = vim.fs.normalize(base)
        if util.is_inside(full_path, base) and (not best or #base > #best) then
            best = base
        end
    end

    if best then
        return full_path:sub(#best + 2)
    end
    return vim.fn.fnamemodify(full_path, ":~")
end

---Formatted path of the buffer file
---@param buffer integer
---@return string
function M.get_file_path(buffer)
    local name = vim.api.nvim_buf_get_name(buffer)
    if name == "" then
        return "[No Name]"
    end
    local full_path = util.absolute_path(name)
    local format = config.options.format_file_path or M.default_format_file_path
    return format(full_path, buffer)
end

---Indentation of a block inserted after `after_row`: the largest one among the line above and the first non-blank
---line below. Handles inserting right after a line that opens a scope, like `func main() {`
---@param buffer integer
---@param after_row integer 0 inserts at the top of the buffer
---@return string
function M.insert_indentation(buffer, after_row)
    local above = after_row >= 1 and util.indentation(util.get_line(buffer, after_row)) or ""

    local below = ""
    local lines = vim.api.nvim_buf_get_lines(buffer, after_row, -1, false)
    for _, line in ipairs(lines) do
        if not util.is_blank(line) then
            below = util.indentation(line)
            break
        end
    end

    return #below > #above and below or above
end

return M
