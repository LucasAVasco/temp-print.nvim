---@module "temp-print.config.language"

local utils = require("temp-print.lang_utils")

---@type TempPrint.Config.LangSource
return {
    escape = utils.escape_double_quoted,
    escape_format = utils.escape_python_fstring,
    print_location = { command = 'print("<FILE_PATH_ESCAPED>:<LINE_NUMBER> <CONTEXT_ESCAPED>")' },
    print_variable = {
        command = 'print(f"<FILE_PATH_FORMATTED_ESCAPED> <CONTEXT_FORMATTED_ESCAPED> <VAR_NAME_FORMATTED_ESCAPED>: {<VAR>!r}")',
    },
    print_previous_line = { command = 'print("<FILE_PATH_ESCAPED>:<LINE_NUMBER>\\t<LINE_CONTENT_ESCAPED>")' },
}
