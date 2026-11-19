---@class TempPrint.Markers
---@field start string Start marker. May be followed by a type suffix, like `_LOCATION`
---@field end string End marker
---@field commented_prefix string Prefix added to the start marker of commented temporary prints

---Tags replaced in the print commands. Text tags have 3 variants: raw, `_escaped` (filetype `escape`, for string
---literals) and `_formatted_escaped` (filetype `escape_format`, for format strings of printf-like functions)
---@class TempPrint.Placeholders
---@field context string Context of the print (default: tree-sitter path, like `MyClass#method`)
---@field context_escaped string
---@field context_formatted_escaped string
---@field file_path string Formatted file path
---@field file_path_escaped string
---@field file_path_formatted_escaped string
---@field var_name string Variable name
---@field var_name_escaped string
---@field var_name_formatted_escaped string
---@field line_content string Formatted content of the printed line (line prints)
---@field line_content_escaped string
---@field line_content_formatted_escaped string
---@field var string Variable expression (never escaped)
---@field line_number string Line number

---@class TempPrint.HighlightOptions
---@field enabled boolean Highlight temporary prints when Neovim starts
---@field marker vim.api.keyset.highlight Style of the marker lines
---@field content vim.api.keyset.highlight Style of the print commands
---@field commented vim.api.keyset.highlight Style of commented temporary prints

---@class TempPrint.ContextInfo
---@field buffer integer
---@field row integer 1-indexed line
---@field col integer 0-indexed byte column
---@field filetype string
---@field ts_node TSNode? Named tree-sitter node at the position (nil if the buffer has no parser)
---@field lang_config TempPrint.Config.Lang

---@alias TempPrint.GetContext fun(info: TempPrint.ContextInfo): string?
---@alias TempPrint.FormatFilePath fun(full_path: string, buffer: integer): string
---@alias TempPrint.GetProjectRoot fun(buffer: integer, full_path: string): string?
---@alias TempPrint.IsNeovimLua fun(buffer: integer): boolean

---@class TempPrint.Options
---@field markers TempPrint.Markers
---@field placeholders TempPrint.Placeholders
---@field context_separator string Separator between the node names of the default context
---@field get_context TempPrint.GetContext? Overrides the default context function (a filetype `get_context` wins)
---@field format_file_path TempPrint.FormatFilePath? Overrides the default file path formatter
---@field get_project_root TempPrint.GetProjectRoot? Returns the project root of a file (default: search `project_markers`)
---@field project_markers string[] Files/directories that identify the project root (default `get_project_root`)
---@field is_neovim_lua TempPrint.IsNeovimLua? Whether a Lua buffer runs inside Neovim (its prints use `vim.print`). Default:
---the file is inside a Neovim directory
---@field auto_update boolean Regenerate location/line prints before saving
---@field command boolean|string Create the `:TempPrint` command (`true`), not (`false`), or with another name (string)
---@field highlight TempPrint.HighlightOptions
---@field languages table<string, TempPrint.Config.LangSource> Per-filetype overrides (highest priority)

---@class TempPrint.UserOptions
---@field markers? TempPrint.Markers
---@field placeholders? table<string, string> See `TempPrint.Placeholders`
---@field context_separator? string
---@field get_context? TempPrint.GetContext
---@field format_file_path? TempPrint.FormatFilePath
---@field get_project_root? TempPrint.GetProjectRoot
---@field is_neovim_lua? TempPrint.IsNeovimLua
---@field project_markers? string[]
---@field auto_update? boolean
---@field command? boolean|string
---@field highlight? TempPrint.HighlightOptions
---@field languages? table<string, TempPrint.Config.LangSource>

local M = {}

---@type TempPrint.Options
M.defaults = {
    markers = {
        start = "TEMP_PRINT_NVIM_MARKER_START",
        ["end"] = "TEMP_PRINT_NVIM_MARKER_END",
        commented_prefix = "COMMENTED_",
    },
    placeholders = {
        context = "<CONTEXT>",
        context_escaped = "<CONTEXT_ESCAPED>",
        context_formatted_escaped = "<CONTEXT_FORMATTED_ESCAPED>",
        file_path = "<FILE_PATH>",
        file_path_escaped = "<FILE_PATH_ESCAPED>",
        file_path_formatted_escaped = "<FILE_PATH_FORMATTED_ESCAPED>",
        var_name = "<VAR_NAME>",
        var_name_escaped = "<VAR_NAME_ESCAPED>",
        var_name_formatted_escaped = "<VAR_NAME_FORMATTED_ESCAPED>",
        line_content = "<LINE_CONTENT>",
        line_content_escaped = "<LINE_CONTENT_ESCAPED>",
        line_content_formatted_escaped = "<LINE_CONTENT_FORMATTED_ESCAPED>",
        var = "<VAR>",
        line_number = "<LINE_NUMBER>",
    },
    context_separator = "#",
    get_context = nil,
    format_file_path = nil,
    get_project_root = nil,
    project_markers = { ".git" },
    is_neovim_lua = nil,
    auto_update = true,
    command = true,
    highlight = {
        enabled = false,
        marker = { link = "DiagnosticVirtualTextWarn" },
        content = { link = "CursorLine" },
        commented = { link = "Comment" },
    },
    languages = {},
}

---@type TempPrint.Options
M.options = vim.deepcopy(M.defaults)

---Options given to the last `setup()` call
---@type TempPrint.UserOptions
M.user_options = {}

---@param opts TempPrint.UserOptions?
---@return TempPrint.Options
local function merge(opts)
    opts = opts or {}
    local options = vim.tbl_deep_extend("force", vim.deepcopy(M.defaults), opts)

    -- Lists and highlight specs are replaced instead of merged
    if opts.project_markers then
        options.project_markers = opts.project_markers
    end
    for _, key in ipairs({ "marker", "content", "commented" }) do
        if opts.highlight and opts.highlight[key] then
            options.highlight[key] = opts.highlight[key]
        end
    end

    return options
end

---@param opts TempPrint.UserOptions?
function M.setup(opts)
    M.user_options = opts or {}
    M.options = merge(opts)

    require("temp-print.config.language").clear_cache()
    require("temp-print.highlight").setup()
    require("temp-print.update").setup()

    -- The command module is only loaded when needed
    local command = package.loaded["temp-print.command"]
    if command then
        command.delete()
    end
    if M.options.command then
        require("temp-print.command").create(M.options.command)
    end
end

return M
