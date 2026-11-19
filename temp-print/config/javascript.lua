---@module "temp-print.config.language"

local utils = require("temp-print.lang_utils")

-- JavaScript. Also used by TypeScript, JSX, TSX and Vue. The first argument of `console.log` is a format string
---@type TempPrint.Config.LangSource
return {
    escape = utils.escape_double_quoted,
    escape_format = utils.escape_printf,
    print_location = { command = 'console.log("<FILE_PATH_FORMATTED_ESCAPED>:<LINE_NUMBER> <CONTEXT_FORMATTED_ESCAPED>");' },
    print_variable = {
        command = 'console.log("<FILE_PATH_FORMATTED_ESCAPED> <CONTEXT_FORMATTED_ESCAPED> <VAR_NAME_FORMATTED_ESCAPED>:", <VAR>);',
    },
    print_previous_line = {
        command = 'console.log("<FILE_PATH_FORMATTED_ESCAPED>:<LINE_NUMBER>\\t<LINE_CONTENT_FORMATTED_ESCAPED>");',
    },
}
