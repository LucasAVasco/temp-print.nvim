---@module "temp-print.config.language"

local utils = require("temp-print.lang_utils")

-- C. Also used by C++. The variable print uses `%d`: edit the format to match the type of the variable
---@type TempPrint.Config.LangSource
return {
    escape = utils.escape_double_quoted,
    escape_format = utils.escape_printf,
    -- Functions have no `name` field: function_definition > function_declarator > identifier
    get_node_name = function(node, buffer)
        if node:type() == "function_definition" then
            return utils.field_chain_text(node, buffer, "declarator", "declarator")
        end
        return utils.name_field(node, buffer)
    end,
    print_location = { command = 'printf("<FILE_PATH_FORMATTED_ESCAPED>:<LINE_NUMBER> <CONTEXT_FORMATTED_ESCAPED>\\n");' },
    print_variable = {
        command = 'printf("<FILE_PATH_FORMATTED_ESCAPED> <CONTEXT_FORMATTED_ESCAPED> <VAR_NAME_FORMATTED_ESCAPED>: %d\\n", <VAR>);',
    },
    print_previous_line = {
        command = 'printf("<FILE_PATH_FORMATTED_ESCAPED>:<LINE_NUMBER>\\t<LINE_CONTENT_FORMATTED_ESCAPED>\\n");',
    },
}
