---@module "temp-print.config.language"

local utils = require("temp-print.lang_utils")

-- Shell scripts. Also used by bash and zsh. Prints to stderr, so the output of the script is not changed
---@type TempPrint.Config.LangSource
return {
    escape = utils.escape_single_quoted_shell,
    escape_format = utils.escape_printf_shell,
    print_location = { command = "printf '<FILE_PATH_FORMATTED_ESCAPED>:<LINE_NUMBER> <CONTEXT_FORMATTED_ESCAPED>\\n' >&2" },
    print_variable = {
        command = "printf '<FILE_PATH_FORMATTED_ESCAPED> <CONTEXT_FORMATTED_ESCAPED> <VAR_NAME_FORMATTED_ESCAPED>: %s\\n' \"${<VAR>}\" >&2",
        -- In `$foo` and `foo=1`, the node under the cursor is a `variable_name`
        get_var = function(node, buffer)
            if node:type() == "variable_name" then
                return vim.treesitter.get_node_text(node, buffer)
            end
        end,
    },
    print_previous_line = {
        command = "printf '<FILE_PATH_FORMATTED_ESCAPED>:<LINE_NUMBER>\\t<LINE_CONTENT_FORMATTED_ESCAPED>\\n' >&2",
    },
}
