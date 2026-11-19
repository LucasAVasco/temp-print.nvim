-- The `:TempPrint` command. Only loaded when the `command` option is enabled
local util = require("temp-print.util")

local M = {}

---@class TempPrint.Command.Args
---@field args string[] Arguments after the subcommand
---@field range integer Number of range items given to the command (0 means no range)
---@field line1 integer
---@field line2 integer

---@class TempPrint.Command.Subcommand
---@field run fun(args: TempPrint.Command.Args)
---@field complete? fun(arg_lead: string, index: integer): string[] `index` is the position of the completed argument

---@param args TempPrint.Command.Args
---@return integer?
local function offset_arg(args)
    return args.args[1] and tonumber(args.args[1]) or nil
end

---@param args TempPrint.Command.Args
---@return integer first
---@return integer last
local function range_or_cursor(args)
    if args.range > 0 then
        return args.line1, args.line2
    end
    local row = vim.api.nvim_win_get_cursor(0)[1]
    return row, row
end

---Items that start with `arg_lead`
---@param items string[]
---@param arg_lead string
---@return string[]
local function filter_prefix(items, arg_lead)
    return vim.tbl_filter(function(item)
        return vim.startswith(item, arg_lead)
    end, items)
end

---Subcommand that calls a function of a module (loaded only when the subcommand runs) with fixed arguments
---@param module string
---@param name string
---@param ... any
---@return TempPrint.Command.Subcommand
local function call(module, name, ...)
    local args = vim.F.pack_len(...)
    return {
        run = function()
            require(module)[name](vim.F.unpack_len(args))
        end,
    }
end

---Subcommand `[enable|disable|toggle]` (default: toggle) that notifies the resulting state
---@param label string Name of the feature in the notification
---@param get_functions fun(): { enable: fun(), disable: fun(), toggle: fun(), is_enabled: fun(): boolean }
---@return TempPrint.Command.Subcommand
local function toggle_subcommand(label, get_functions)
    local actions = { "enable", "disable", "toggle" }
    return {
        run = function(args)
            local action = args.args[1] or "toggle"
            if not vim.tbl_contains(actions, action) then
                return util.notify("invalid argument: " .. action)
            end
            local functions = get_functions()
            functions[action]()
            util.notify(label .. " " .. (functions.is_enabled() and "enabled" or "disabled"), vim.log.levels.INFO)
        end,
        complete = function(arg_lead, index)
            return index == 1 and filter_prefix(actions, arg_lead) or {}
        end,
    }
end

---Picker subcommand: `[buffer|directory] [dir]`. The picker module is only loaded when the subcommand runs
---@param module string
---@return TempPrint.Command.Subcommand
local function picker_subcommand(module)
    return {
        run = function(args)
            local scope = args.args[1] or "buffer"
            if scope ~= "buffer" and scope ~= "directory" then
                return util.notify("invalid scope: " .. scope .. " (expected 'buffer' or 'directory')")
            end
            local directory = args.args[2] and vim.fn.expand(args.args[2]) or nil
            require(module).open(scope, directory)
        end,
        complete = function(arg_lead, index)
            if index == 1 then
                return filter_prefix({ "buffer", "directory" }, arg_lead)
            elseif index == 2 then
                return vim.fn.getcompletion(arg_lead, "dir")
            end
            return {}
        end,
    }
end

---Opens a scratch buffer with the effective configuration
---@param filetype string
local function show_debug(filetype)
    local config = require("temp-print.config")
    local language = require("temp-print.config.language")
    -- The current buffer is given to the configuration functions when it has the filetype
    local source_buffer = vim.bo.filetype == filetype and vim.api.nvim_get_current_buf() or nil
    local lang_config, lang_err = language.get_filetype_config(filetype, source_buffer)

    local lines = {
        "-- temp-print debug information",
        "",
        "-- State",
        ("auto_update = %s"):format(require("temp-print.update").is_auto_update_enabled()),
        ("highlight = %s"):format(require("temp-print.highlight").is_enabled()),
        "",
        "-- Options given to setup()",
        "user_options = " .. vim.inspect(config.user_options),
        "",
        "-- Effective options",
        "options = " .. vim.inspect(config.options),
        "",
        ("-- Configuration files of the filetype '%s' (lowest to highest priority, then setup().languages)"):format(filetype),
        "files = " .. vim.inspect(language.find_files(filetype)),
        "",
        "-- Name of the command",
        ("command = %s"):format(vim.inspect(M.created_name)),
        "",
        "-- Effective filetype configuration",
        "filetype_config = " .. (lang_config and vim.inspect(lang_config) or vim.inspect(lang_err or "not found")),
    }

    vim.cmd("botright new")
    local buffer = vim.api.nvim_get_current_buf()
    vim.bo[buffer].buftype = "nofile"
    vim.bo[buffer].bufhidden = "wipe"
    vim.bo[buffer].swapfile = false
    vim.api.nvim_buf_set_name(buffer, "temp-print://debug/" .. buffer)
    vim.api.nvim_buf_set_lines(buffer, 0, -1, false, vim.split(table.concat(lines, "\n"), "\n"))
    vim.bo[buffer].modifiable = false
    vim.bo[buffer].filetype = "lua"
end

---Insert subcommand that acts on each non-blank line of a range, or on the cursor
---@param per_line fun(buffer: integer, row: integer)
---@param at_cursor fun(args: TempPrint.Command.Args)
---@return TempPrint.Command.Subcommand
local function line_subcommand(per_line, at_cursor)
    return {
        run = function(args)
            if args.range > 0 then
                require("temp-print.insert").each_code_line(0, args.line1, args.line2, per_line)
            else
                at_cursor(args)
            end
        end,
    }
end

---Edit subcommand that acts on the range, or on the cursor row
---@param name string Function of the edit module receiving (buffer, first, last)
---@return TempPrint.Command.Subcommand
local function range_subcommand(name)
    return {
        run = function(args)
            require("temp-print.edit")[name](0, range_or_cursor(args))
        end,
    }
end

---@type table<string, TempPrint.Command.Subcommand>
M.subcommands = {
    location = line_subcommand(function(buffer, row)
        require("temp-print.insert").location_for_line(buffer, row)
    end, function(args)
        require("temp-print.insert").location(0, nil, nil, offset_arg(args))
    end),
    variable = {
        run = function(args)
            require("temp-print.insert").variable(0, nil, nil, offset_arg(args))
        end,
    },
    variable_with_line = {
        run = function(args)
            require("temp-print.insert").variable_with_line(0, nil, nil, offset_arg(args))
        end,
    },
    variable_around = call("temp-print.insert", "variable_around", 0),
    variable_around_with_line = call("temp-print.insert", "variable_around", 0, nil, nil, true),
    previous_line = line_subcommand(function(buffer, row)
        require("temp-print.insert").previous_line(buffer, row)
    end, function()
        require("temp-print.insert").previous_line(0)
    end),
    next_line = line_subcommand(function(buffer, row)
        require("temp-print.insert").next_line(buffer, row)
    end, function()
        require("temp-print.insert").next_line(0)
    end),

    delete = range_subcommand("delete_range"),
    comment = range_subcommand("comment_range"),
    uncomment = range_subcommand("uncomment_range"),
    toggle_comment = range_subcommand("toggle_comment_range"),
    clear = call("temp-print.edit", "clear_all", 0),
    comment_all = call("temp-print.edit", "comment_all", 0),
    uncomment_all = call("temp-print.edit", "uncomment_all", 0),
    update = {
        run = function()
            local updated = require("temp-print.update").update(0)
            if updated then
                util.notify(("%d temporary print(s) updated"):format(updated), vim.log.levels.INFO)
            end
        end,
    },

    next = call("temp-print.navigate", "next"),
    prev = call("temp-print.navigate", "prev"),
    first = call("temp-print.navigate", "first"),
    last = call("temp-print.navigate", "last"),

    auto_update = toggle_subcommand("auto-update", function()
        local update = require("temp-print.update")
        return {
            enable = update.enable_auto_update,
            disable = update.disable_auto_update,
            toggle = update.toggle_auto_update,
            is_enabled = update.is_auto_update_enabled,
        }
    end),
    highlight = toggle_subcommand("highlight", function()
        return require("temp-print.highlight")
    end),

    quickfix = call("temp-print.list", "to_quickfix", "buffer"),
    quickfix_directory = {
        run = function(args)
            require("temp-print.list").to_quickfix("directory", args.args[1] and vim.fn.expand(args.args[1]) or nil)
        end,
        complete = function(arg_lead, index)
            return index == 1 and vim.fn.getcompletion(arg_lead, "dir") or {}
        end,
    },
    loclist = call("temp-print.list", "to_loclist"),

    telescope = picker_subcommand("temp-print.telescope"),
    fzf_lua = picker_subcommand("temp-print.fzf_lua"),
    snacks = picker_subcommand("temp-print.snacks"),

    debug = {
        run = function(args)
            show_debug(args.args[1] or vim.bo.filetype)
        end,
        complete = function(arg_lead, index)
            return index == 1 and vim.fn.getcompletion(arg_lead, "filetype") or {}
        end,
    },
}

---@param opts vim.api.keyset.create_user_command.command_args
local function execute(opts)
    local name = opts.fargs[1]
    local subcommand = M.subcommands[name]
    if not subcommand then
        return util.notify("unknown subcommand: " .. tostring(name))
    end
    subcommand.run({
        args = vim.list_slice(opts.fargs, 2),
        range = opts.range,
        line1 = opts.line1,
        line2 = opts.line2,
    })
end

---@param arg_lead string
---@param cmd_line string
---@return string[]
local function complete(arg_lead, cmd_line)
    local words = vim.split(cmd_line:gsub("^%A*%w+!?%s*", "", 1), "%s+", { trimempty = false })
    if #words <= 1 then
        local names = vim.tbl_keys(M.subcommands)
        table.sort(names)
        return filter_prefix(names, arg_lead)
    end
    local subcommand = M.subcommands[words[1]]
    if subcommand and subcommand.complete then
        return subcommand.complete(arg_lead, #words - 1)
    end
    return {}
end

M.DEFAULT_NAME = "TempPrint"

---Name of the command created by `create()`
---@type string?
M.created_name = nil

---Creates the command
---@param name boolean|string? `true`/nil for `:TempPrint`, or the name of the command
function M.create(name)
    if type(name) ~= "string" then
        name = M.DEFAULT_NAME
    elseif not name:match("^%u%w*$") then
        util.notify(("invalid command name '%s' (it must start with an uppercase letter), using '%s'"):format(name, M.DEFAULT_NAME))
        name = M.DEFAULT_NAME
    end

    M.delete()
    vim.api.nvim_create_user_command(name, execute, {
        nargs = "+",
        range = true,
        complete = complete,
        desc = "temp-print.nvim: insert, edit and list temporary prints",
    })
    M.created_name = name
end

---Deletes the command created by `create()`
function M.delete()
    if M.created_name then
        pcall(vim.api.nvim_del_user_command, M.created_name)
        M.created_name = nil
    end
end

return M
