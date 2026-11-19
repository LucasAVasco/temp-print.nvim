---@module "temp-print.config.language"

local language = require("temp-print.config.language")

---@type TempPrint.Config.LangSource
return language.extend(language.load("javascript", { "builtin" }), {
    -- Prints are placed in the <script> section
    commentstring = "// %s",
})
