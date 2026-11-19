---@module "temp-print.config.language"

local utils = require("temp-print.lang_utils")

---@type TempPrint.Config.LangSource
return {
    escape = utils.escape_double_quoted,
    escape_format = utils.escape_rust_format,
    -- Includes the type of impl blocks in the context: `impl Foo { fn bar() }` -> Foo#bar
    get_node_name = function(node, buffer)
        if node:type() == "impl_item" then
            return utils.field_chain_text(node, buffer, "type")
        end
        return utils.name_field(node, buffer)
    end,
    print_location = { command = 'println!("[<FILE_PATH_FORMATTED_ESCAPED>:<LINE_NUMBER>] <CONTEXT_FORMATTED_ESCAPED>");' },
    print_variable = {
        command = 'println!("[<FILE_PATH_FORMATTED_ESCAPED>] <CONTEXT_FORMATTED_ESCAPED> <VAR_NAME_FORMATTED_ESCAPED>: {:#?}", <VAR>);',
    },
    print_previous_line = {
        command = 'println!("[<FILE_PATH_FORMATTED_ESCAPED>:<LINE_NUMBER>]\\t<LINE_CONTENT_FORMATTED_ESCAPED>");',
    },
}
