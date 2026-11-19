-- Telescope extension: `require("telescope").load_extension("temp_print")`, then `:Telescope temp_print` (buffer)
-- or `:Telescope temp_print directory`
local picker = require("temp-print.telescope")

return require("telescope").register_extension({
    exports = {
        temp_print = function(opts)
            picker.buffer(opts)
        end,
        buffer = function(opts)
            picker.buffer(opts)
        end,
        directory = function(opts)
            opts = opts or {}
            picker.directory(opts.cwd, opts)
        end,
    },
})
