---@module "temp-print.config.language"

local utils = require("temp-print.lang_utils")

---@type TempPrint.Config.LangSource
return {
    escape = utils.escape_double_quoted,
    escape_format = utils.escape_printf,
    print_location = { command = 'fmt.Println("<FILE_PATH_ESCAPED>:<LINE_NUMBER> <CONTEXT_ESCAPED>")' },
    print_variable = {
        command = 'fmt.Printf("<FILE_PATH_FORMATTED_ESCAPED> <CONTEXT_FORMATTED_ESCAPED> <VAR_NAME_FORMATTED_ESCAPED>: %+v\\n", <VAR>)',
    },
    print_previous_line = { command = 'fmt.Println("<FILE_PATH_ESCAPED>:<LINE_NUMBER>\\t<LINE_CONTENT_ESCAPED>")' },
}
