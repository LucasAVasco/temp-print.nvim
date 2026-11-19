---@alias TempPrint.Config.Lang.GetNodeName fun(ts_node: TSNode, buffer: integer): string?
---@alias TempPrint.Config.Lang.GetVar fun(ts_node: TSNode, buffer: integer): string?
---@alias TempPrint.Config.Lang.Formatter fun(line: string): string

---@class TempPrint.Config.Lang.PrintLocation
---@field command string Print command. May span multiple lines (separated by "\n")

---@class TempPrint.Config.Lang.PrintVariable
---@field command string Print command. May span multiple lines (separated by "\n")
---@field get_var? TempPrint.Config.Lang.GetVar Returns the variable expression
---@field get_var_name? TempPrint.Config.Lang.GetVar Returns the variable name (defaults to the expression)

---@class TempPrint.Config.Lang.PrintLine
---@field command string Print command. May span multiple lines (separated by "\n")
---@field formatter? TempPrint.Config.Lang.Formatter Formats the printed line before it is escaped. Defaults to `vim.trim`

---@class TempPrint.Config.Lang
---@field commentstring? string Overrides the buffer 'commentstring'
---@field escape? fun(text: string): string Escapes the `_ESCAPED` tags, placed inside string literals. Defaults to identity
---@field escape_format? fun(text: string): string Escapes the `_FORMATTED_ESCAPED` tags, placed inside the format string of
---a printf-like function. Defaults to `escape`
---@field placeholders? table<string, string> Tags of this filetype. Override the `placeholders` setup option
---@field get_context? TempPrint.GetContext Context function of this filetype (highest priority)
---@field get_node_name? TempPrint.Config.Lang.GetNodeName Node name used by the default context function
---@field print_location? TempPrint.Config.Lang.PrintLocation
---@field print_variable? TempPrint.Config.Lang.PrintVariable
---@field print_previous_line? TempPrint.Config.Lang.PrintLine
---@field print_next_line? TempPrint.Config.Lang.PrintLine Defaults to `print_previous_line`

---A filetype configuration, or a function that builds it for a buffer (nil when no buffer is known). Returned by the
---configuration files and accepted by the `languages` setup option
---@alias TempPrint.Config.LangSource TempPrint.Config.Lang|fun(buffer: integer?): TempPrint.Config.Lang

local util = require("temp-print.util")

local M = {}

---Sources of filetype configuration files, from the lowest to the highest priority
---@alias TempPrint.Config.Source "builtin"|"plugins"|"user"
---@type TempPrint.Config.Source[]
M.SOURCES = { "builtin", "plugins", "user" }

---@class TempPrint.Config.File
---@field path string
---@field source TempPrint.Config.Source

-- Root directory of the plugin: <root>/lua/temp-print/config/language.lua
local plugin_root = util.real_path(vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h:h:h"))

---@class TempPrint.Config.Layer
---@field layer TempPrint.Config.LangSource
---@field origin string Configuration file, or `setup().languages.<filetype>`. Used in error messages

---@class TempPrint.Config.CacheEntry
---@field layers TempPrint.Config.Layer[] Loaded layers, from the lowest to the highest priority
---@field static TempPrint.Config.Lang? Merged configuration, when no layer is a function

---Cached configurations. `false` means that the filetype has no configuration
---@type table<string, TempPrint.Config.CacheEntry|false>
local cache = {}

---Filetypes being loaded (detects recursive loads)
---@type table<string, boolean>
local loading = {}

---@param path string
---@return TempPrint.Config.Source
local function classify(path)
    if util.is_inside(path, plugin_root) then
        return "builtin"
    end
    -- `after/` is inside the configuration directory
    if
        util.is_inside(path, util.real_path(vim.fn.stdpath("config") --[[@as string]]))
    then
        return "user"
    end
    return "plugins"
end

---Finds the configuration files of a filetype (`temp-print/config/<filetype>.lua` in the 'runtimepath'), from the lowest
---to the highest priority: this plugin, other plugins ('runtimepath' order, the last one wins), and the user config
---@param filetype string
---@param sources TempPrint.Config.Source[]? Sources to search. Defaults to all
---@return TempPrint.Config.File[]
function M.find_files(filetype, sources)
    sources = sources or M.SOURCES
    local relative = "temp-print/config/" .. filetype .. ".lua"

    local paths = { vim.fs.joinpath(plugin_root, relative) }
    vim.list_extend(paths, vim.api.nvim_get_runtime_file(relative, true))
    table.insert(paths, vim.fs.joinpath(vim.fn.stdpath("config") --[[@as string]], relative))

    local by_source = { builtin = {}, plugins = {}, user = {} }
    local seen = {}
    for _, path in ipairs(paths) do
        if vim.uv.fs_stat(path) then
            path = util.real_path(path)
            if not seen[path] then
                seen[path] = true
                table.insert(by_source[classify(path)], path)
            end
        end
    end

    local files = {}
    for _, source in ipairs(M.SOURCES) do
        if vim.tbl_contains(sources, source) then
            for _, path in ipairs(by_source[source]) do
                table.insert(files, { path = path, source = source })
            end
        end
    end
    return files
end

---@param file string
---@return TempPrint.Config.LangSource
local function load_file(file)
    local chunk, load_err = loadfile(file)
    if not chunk then
        error(load_err, 0)
    end

    local ok, result = pcall(chunk)
    if not ok then
        error(("error loading %s: %s"):format(file, result), 0)
    end
    if type(result) ~= "table" and type(result) ~= "function" then
        error(file .. " must return a table or a function", 0)
    end
    return result
end

---Builds a configuration layer for a buffer
---@param layer TempPrint.Config.LangSource
---@param buffer integer?
---@param origin string Origin of the layer, used in the error message
---@return TempPrint.Config.Lang
local function resolve(layer, buffer, origin)
    if type(layer) ~= "function" then
        return layer
    end
    local ok, result = pcall(layer, buffer)
    if not ok then
        error(("error building the configuration of %s: %s"):format(origin, result), 0)
    end
    if type(result) ~= "table" then
        error(("the configuration function of %s must return a table"):format(origin), 0)
    end
    return result
end

---Raw layers of a filetype (configuration files of the sources), from the lowest to the highest priority
---@param filetype string
---@param sources TempPrint.Config.Source[]?
---@return TempPrint.Config.Layer[]
local function load_layers(filetype, sources)
    return vim.tbl_map(function(file)
        return { layer = load_file(file.path), origin = file.path }
    end, M.find_files(filetype, sources))
end

---Resolves (see `resolve`) and merges layers
---@param layers TempPrint.Config.Layer[]
---@param buffer integer?
---@return TempPrint.Config.Lang
local function merge_layers(layers, buffer)
    local resolved = vim.tbl_map(function(entry)
        return resolve(entry.layer, buffer, entry.origin)
    end, layers)
    return vim.tbl_deep_extend("force", {}, unpack(resolved))
end

---Loads and merges the configuration files of a filetype (see `find_files`). Files that return a function are called
---with `buffer`. The result is a new table that can be modified. Defaults are not applied and the `languages` setup
---option is not included. Raises an error if a file is invalid. Can be used by filetype configuration files to reuse
---other configurations:
---
---```lua
---local language = require("temp-print.config.language")
---return language.extend(language.load("c", { "builtin" }), { commentstring = "// %s" })
---```
---@param filetype string
---@param sources TempPrint.Config.Source[]? Defaults to all
---@param buffer integer? Buffer given to the configuration functions
---@return TempPrint.Config.Lang? config Nil if there is no file
function M.load(filetype, sources, buffer)
    -- Files and configuration functions may call `load`: detect loops
    local key = filetype .. ":" .. table.concat(sources or M.SOURCES, ",")
    if loading[key] then
        error(("recursive load of the '%s' filetype configuration"):format(filetype), 0)
    end

    loading[key] = true
    local ok, result = pcall(function()
        local layers = load_layers(filetype, sources)
        if #layers > 0 then
            return merge_layers(layers, buffer)
        end
    end)
    loading[key] = nil

    if not ok then
        error(result, 0)
    end
    return result
end

---Returns a copy of `base` with `overrides` deep-merged over it
---@param base TempPrint.Config.Lang?
---@param overrides TempPrint.Config.Lang
---@return TempPrint.Config.Lang
function M.extend(base, overrides)
    assert(base, "temp-print: can not extend a missing filetype configuration")
    return vim.tbl_deep_extend("force", vim.deepcopy(base), overrides)
end

---@param text string
---@return string
local function identity(text)
    return text
end

---Applies the defaults to a merged configuration
---@param config TempPrint.Config.Lang
---@return TempPrint.Config.Lang
local function apply_defaults(config)
    config.placeholders = vim.tbl_extend("force", require("temp-print.config").options.placeholders, config.placeholders or {})
    config.escape = config.escape or identity
    config.escape_format = config.escape_format or config.escape
    config.print_next_line = config.print_next_line or config.print_previous_line
    return config
end

---Loads the layers of a filetype (configuration files and `languages` setup option) and caches them
---@param filetype string
---@return TempPrint.Config.CacheEntry|false? entry `false` if the filetype has no configuration, nil on error
---@return string? error
local function cache_entry(filetype)
    if cache[filetype] ~= nil then
        return cache[filetype]
    end

    local ok, layers = pcall(load_layers, filetype)
    if not ok then
        return nil, tostring(layers) -- Not cached, so the user can fix the file and retry
    end
    local setup_layer = require("temp-print.config").options.languages[filetype]
    if setup_layer then
        table.insert(layers, { layer = setup_layer, origin = ("setup().languages.%s"):format(filetype) })
    end
    if #layers == 0 then
        cache[filetype] = false
        return false
    end

    local entry = { layers = layers }
    local dynamic = vim.iter(layers):any(function(layer)
        return type(layer.layer) == "function"
    end)
    if not dynamic then
        entry.static = apply_defaults(merge_layers(layers))
    end
    cache[filetype] = entry
    return entry
end

---Returns the effective configuration of a filetype: the configuration files (see `find_files`) merged with the
---`languages` setup option, with defaults. Configurations without functions are cached; the ones with functions are
---built for the buffer on each call
---@param filetype string
---@param buffer integer? Buffer given to the configuration functions
---@return TempPrint.Config.Lang?
---@return string? error
function M.get_filetype_config(filetype, buffer)
    local entry, err = cache_entry(filetype)
    if not entry then
        return nil, err
    end
    if entry.static then
        return entry.static
    end

    local ok, config = pcall(merge_layers, entry.layers, buffer)
    if not ok then
        return nil, tostring(config)
    end
    return apply_defaults(config)
end

---Clears the configuration cache. Called when the user options change. Call it after loading a plugin that provides
---filetype configurations
function M.clear_cache()
    cache = {}
end

return M
