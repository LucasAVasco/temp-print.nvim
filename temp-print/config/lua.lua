---@module "temp-print.config.language"

local utils = require("temp-print.lang_utils")

-- Neovim Lua files use `vim.print` (tables are inspected), other Lua files use `print` and `tostring`. The check is the
-- `is_neovim_lua` setup option (default: the file is inside a Neovim directory)
---@type TempPrint.Config.LangSource
return function(buffer)
    local print = utils.is_neovim_lua(buffer) and "vim.print" or "print"
    local print_variable = print == "vim.print" and 'vim.print("<FILE_PATH_ESCAPED> <CONTEXT_ESCAPED> <VAR_NAME_ESCAPED>:", <VAR>)'
        or 'print("<FILE_PATH_ESCAPED> <CONTEXT_ESCAPED> <VAR_NAME_ESCAPED>: " .. tostring(<VAR>))'

    return {
        escape = utils.escape_double_quoted,
        print_location = { command = print .. '("<FILE_PATH_ESCAPED>:<LINE_NUMBER> <CONTEXT_ESCAPED>")' },
        print_variable = { command = print_variable },
        print_previous_line = { command = print .. '("<FILE_PATH_ESCAPED>:<LINE_NUMBER>\\t<LINE_CONTENT_ESCAPED>")' },
    }
end
