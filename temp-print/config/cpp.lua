---@module "temp-print.config.language"

local language = require("temp-print.config.language")

---@type TempPrint.Config.LangSource
return language.load("c", { "builtin" })
