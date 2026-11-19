# temp-print.nvim

Insert, update and remove temporary debug prints ("printf debugging") in Neovim.

Each print is wrapped in marker comments, so the plugin can find it later to regenerate, comment, list or remove it:

```go
func main() {
    var name string = ""
    // TEMP_PRINT_NVIM_MARKER_START_PREVIOUS_LINE
    fmt.Println("cmd/main.go:2\tvar name string = \"\"")
    // TEMP_PRINT_NVIM_MARKER_START_VARIABLE
    fmt.Printf("%s: %+v\n", "cmd/main.go main name", name)
    // TEMP_PRINT_NVIM_MARKER_END
}
```

## Features

- **Print types**: location (file, line and context, like `MyClass#method`), variable, previous line, and next line. There are also
  combinations, like a variable printed before and after a line.
- **Auto-update**: before saving, location and line prints are regenerated, so their line numbers, file path and context stay correct.
- **Edit**: delete, comment or uncomment one print, a range of prints, or all of them.
- **Navigate** to the next, previous, first or last print.
- **List** the prints of the buffer or of a directory in the quickfix or location list, or in
  [Telescope](https://github.com/nvim-telescope/telescope.nvim), [fzf-lua](https://github.com/ibhagwan/fzf-lua) or
  [snacks.nvim](https://github.com/folke/snacks.nvim) (optional).
- **Highlight** prints, with customizable styles.
- **Dot repeat** for every insertion, deletion and comment action. Visual mode is supported.
- A `:TempPrint` command, with completion.
- **Filetype configurations** for C, C++, Go, JavaScript, TypeScript (and React), Vue, Lua, Python, Rust and shell (sh, bash, zsh). It's
  easy to add or override languages.

The context uses tree-sitter. Without a parser, location and line prints still work (with an empty context), and variable detection falls
back to the word under the cursor.

## Installation

Requires Neovim 0.10+. Example with [lazy.nvim](https://github.com/folke/lazy.nvim), with every option at its default value and example
keymaps:

> [!NOTE] The `opts` below only show the default values, you don't need to copy them. Set only the options you want to change, or leave
> `opts` empty (`opts = {}`) to use the defaults. Your options are merged over the defaults.

```lua
-- Keymap callback that loads the actions module only when the keymap is used
local function action(name, ...)
    local args = { ... }
    return function()
        require("temp-print.actions")[name](unpack(args))
    end
end

return {
    "LucasAVasco/temp-print.nvim",
    event = "VeryLazy", -- load early, so the auto-update and the highlight work before a keymap is used
    cmd = "TempPrint",
    -- Default values: write only the options you want to change, or use `opts = {}`
    ---@module "temp-print"
    ---@type TempPrint.UserOptions
    opts = {
        markers = {
            start = "TEMP_PRINT_NVIM_MARKER_START", -- followed by a type suffix, like _LOCATION
            ["end"] = "TEMP_PRINT_NVIM_MARKER_END",
            commented_prefix = "COMMENTED_",
        },
        -- Tags replaced in the commands of the filetype configurations. Can also be set per filetype, see below
        placeholders = {
            context = "<CONTEXT>",
            context_escaped = "<CONTEXT_ESCAPED>",
            context_formatted_escaped = "<CONTEXT_FORMATTED_ESCAPED>",
            file_path = "<FILE_PATH>",
            file_path_escaped = "<FILE_PATH_ESCAPED>",
            file_path_formatted_escaped = "<FILE_PATH_FORMATTED_ESCAPED>",
            var_name = "<VAR_NAME>",
            var_name_escaped = "<VAR_NAME_ESCAPED>",
            var_name_formatted_escaped = "<VAR_NAME_FORMATTED_ESCAPED>",
            line_content = "<LINE_CONTENT>",
            line_content_escaped = "<LINE_CONTENT_ESCAPED>",
            line_content_formatted_escaped = "<LINE_CONTENT_FORMATTED_ESCAPED>",
            var = "<VAR>",
            line_number = "<LINE_NUMBER>",
        },
        context_separator = "#", -- between the names of the default context: MyClass#method
        -- fun(info: TempPrint.ContextInfo): string?. Replaces the default context function. A `get_context` in the
        -- filetype configuration takes precedence over this one
        get_context = nil,
        -- fun(full_path: string, buffer: integer): string. Formats <FILE_PATH>. The default makes the path relative to
        -- the deepest directory, among the project root and the current working directory, that contains the file
        format_file_path = nil,
        -- fun(buffer: integer, full_path: string): string?. Returns the project root of a file. The default returns the
        -- nearest ancestor directory that contains one of the `project_markers`
        get_project_root = nil,
        project_markers = { ".git" }, -- used by the default `get_project_root`
        -- fun(buffer: integer): boolean. Whether a Lua buffer runs inside Neovim, so its prints use `vim.print`. The default
        -- checks if the file is inside a Neovim directory (configuration, plugins, runtime or 'runtimepath')
        is_neovim_lua = nil,
        auto_update = true, -- regenerate location and line prints before saving
        command = true, -- true: create the :TempPrint command, false: no command, string: name of the command
        highlight = {
            enabled = false,
            marker = { link = "DiagnosticVirtualTextWarn" }, -- marker lines
            content = { link = "CursorLine" }, -- print commands
            commented = { link = "Comment" }, -- commented prints
        },
        languages = {}, -- per-filetype configurations, see below
    },
    keys = {
        -- Insertion. In Visual mode, the line prints are inserted for each selected line
        { "<leader>pl", action("location"), mode = { "n", "x" }, desc = "Print location (after each selected line)" },
        { "<leader>pL", action("location", -1), desc = "Print location before the line" },
        { "<leader>pv", action("variable"), desc = "Print variable" },
        { "<leader>pV", action("variable", -1), desc = "Print variable before the line" },
        { "<leader>pw", action("variable_with_line"), desc = "Print line and variable" },
        { "<leader>pa", action("variable_around"), desc = "Print variable before and after the line" },
        { "<leader>pA", action("variable_around_with_line"), desc = "Print variable around, and the line" },
        { "<leader>pj", action("previous_line_below"), mode = { "n", "x" }, desc = "Print the line (after it)" },
        { "<leader>pk", action("next_line_above"), mode = { "n", "x" }, desc = "Print the line (before it)" },

        -- Edition
        { "<leader>pd", action("delete"), mode = { "n", "x" }, desc = "Delete temporary print(s)" },
        { "<leader>pD", action("clear_all"), desc = "Delete all temporary prints" },
        { "<leader>pc", action("toggle_comment"), mode = { "n", "x" }, desc = "Toggle comment of temporary print(s)" },
        { "<leader>pC", action("comment_all"), desc = "Comment all temporary prints" },
        { "<leader>pU", action("uncomment_all"), desc = "Uncomment all temporary prints" },
        { "<leader>pu", action("update"), desc = "Update temporary prints" },

        -- Navigation
        { "]p", action("next"), desc = "Next temporary print" },
        { "[p", action("prev"), desc = "Previous temporary print" },
        { "[P", action("first"), desc = "First temporary print" },
        { "]P", action("last"), desc = "Last temporary print" },

        -- Lists and pickers (use the picker you have installed: telescope, fzf_lua or snacks)
        { "<leader>pq", action("quickfix"), desc = "Temporary prints in quickfix" },
        { "<leader>pQ", action("quickfix_directory"), desc = "Temporary prints of the directory in quickfix" },
        { "<leader>pf", function() require("temp-print.telescope").buffer() end, desc = "Pick temporary prints" },
        { "<leader>pF", function() require("temp-print.telescope").directory() end, desc = "Pick temporary prints of the directory" },

        { "<leader>ph", action("toggle_highlight"), desc = "Toggle temporary print highlight" },
    },
}
```

`setup()` (called by lazy.nvim with `opts`) is needed for the auto-update, the highlight options and the `:TempPrint` command. The functions
work without it.

## Configuration

The options are listed in the [installation example](#installation).

`info` (`TempPrint.ContextInfo`) has these fields: `buffer`, `row` (1-indexed), `col` (0-indexed), `filetype`, `ts_node` (the tree-sitter
node at the position, possibly nil) and `lang_config` (the effective filetype configuration).

### Filetype configurations

A filetype configuration is a Lua table. These layers are merged, from the lowest to the highest priority:

1. This plugin: `temp-print/config/<filetype>.lua` inside the plugin.
2. Other plugins: `temp-print/config/<filetype>.lua` in any other directory of the `'runtimepath'` (in `'runtimepath'` order, the last one
   wins). See [Extending with other plugins](#extending-with-other-plugins).
3. Your files: `~/.config/nvim/temp-print/config/<filetype>.lua` (`stdpath("config")`, also its `after/` directory).
4. The `languages[<filetype>]` setup option.

So you only need to write the fields you want to change. Example (`~/.config/nvim/temp-print/config/go.lua`):

```lua
local utils = require("temp-print.lang_utils")

return {
    commentstring = "// %s", -- optional, defaults to the buffer 'commentstring'
    escape = utils.escape_double_quoted, -- escapes the _ESCAPED tags (default: no escaping)
    escape_format = utils.escape_printf, -- escapes the _FORMATTED_ESCAPED tags (default: `escape`)
    get_context = nil, -- fun(info): string?, context function of this filetype only
    get_node_name = nil, -- fun(node, buffer): string?, node name used by the default context (default: `name` field)
    placeholders = nil, -- tags of this filetype, override the `placeholders` setup option. Example: { context = "{{ctx}}" }

    print_location = { command = 'log.Println("<FILE_PATH_ESCAPED>:<LINE_NUMBER> <CONTEXT_ESCAPED>")' },
    print_variable = {
        command = 'log.Printf("<FILE_PATH_FORMATTED_ESCAPED> <CONTEXT_FORMATTED_ESCAPED> <VAR_NAME_FORMATTED_ESCAPED>: %+v\\n", <VAR>)',
        get_var = nil, -- fun(node, buffer): string?, the variable expression
        get_var_name = nil, -- fun(node, buffer): string?, the variable name (default: the expression)
    },
    print_previous_line = {
        command = 'log.Println("<FILE_PATH_ESCAPED>:<LINE_NUMBER>\\t<LINE_CONTENT_ESCAPED>")',
        formatter = nil, -- fun(line): string, formats the printed line before escaping it (default: vim.trim)
    },
    print_next_line = nil, -- defaults to print_previous_line
}
```

Commands can span multiple lines (`\n`). Tags:

| Tag              | Value                                                                                              |
| ---------------- | -------------------------------------------------------------------------------------------------- |
| `<CONTEXT>`      | Context of the print. By default, the names of the tree-sitter ancestors: `MyClass#method`         |
| `<FILE_PATH>`    | Path of the file, formatted by `format_file_path`                                                  |
| `<VAR_NAME>`     | Name of the variable                                                                               |
| `<LINE_CONTENT>` | Line prints: the printed line, formatted by `formatter`                                            |
| `<VAR>`          | The variable expression, inserted as code (never escaped)                                          |
| `<LINE_NUMBER>`  | Location and variable prints: the first line of the print statement. Line prints: the printed line |

The first four tags have three variants:

| Variant                       | Escaped by      | Use it inside                                                        |
| ----------------------------- | --------------- | -------------------------------------------------------------------- |
| `<CONTEXT>`                   | nothing         | code, comments, or strings that don't need escaping                  |
| `<CONTEXT_ESCAPED>`           | `escape`        | a string literal, like `"..."` (`\` and `"` are escaped)             |
| `<CONTEXT_FORMATTED_ESCAPED>` | `escape_format` | the format string of a `printf`-like function (`%` becomes `%%` too) |

The tag names come from the `placeholders` setup option, merged with the `placeholders` of the filetype configuration (the filetype ones
win).

Precedence of the context function: the filetype `get_context`, then the `get_context` setup option, then the default.

`require("temp-print.lang_utils")` has escapers for your configurations: `escape_double_quoted`, `escape_printf`, `escape_rust_format`,
`escape_python_fstring`, `escape_single_quoted_shell` and `escape_printf_shell`. It also has the tree-sitter helpers `field_chain_text` and
`name_field`.

#### Dynamic configurations

A configuration file (or a `languages` setup entry) can also return a function that builds the configuration for a buffer. Its type is
`TempPrint.Config.LangSource`. The function receives the buffer number, or nil when no buffer is known (like `:TempPrint debug` for another
filetype). The bundled Lua configuration uses it to print with `vim.print` in Neovim Lua files and with `print` and `tostring` in other Lua
files:

```lua
-- ~/.config/nvim/temp-print/config/lua.lua
---@type TempPrint.Config.LangSource
return function(buffer)
    if require("temp-print").is_neovim_lua(buffer) then
        return { print_variable = { command = 'vim.notify("<VAR_NAME_ESCAPED>: " .. vim.inspect(<VAR>))' } }
    end
    return {} -- keep the bundled configuration
end
```

`is_neovim_lua(buffer)` uses the `is_neovim_lua` setup option. By default (`default_is_neovim_lua`), a buffer is Neovim Lua if its file is
inside a Neovim directory: the configuration (`stdpath("config")`), the plugins (`stdpath("data")`), the runtime (`$VIMRUNTIME`) or any
`'runtimepath'` entry. Symbolic links are resolved, so a configuration managed with links (like GNU stow) is detected when a file is opened
through its real path (if only some subdirectories of the configuration are links, use the option). `in_neovim_directory(path)` does this
check for a path, so you can build your own check with it:

```lua
opts = {
    -- Also treat a plugin under development as Neovim Lua
    is_neovim_lua = function(buffer)
        local tp = require("temp-print")
        return tp.default_is_neovim_lua(buffer)
            or vim.startswith(vim.api.nvim_buf_get_name(buffer), vim.fn.expand("~/projects/my-plugin/"))
    end,
}
```

The option must not call `is_neovim_lua` itself, which would call the option again.

Configurations without functions are cached per filetype. Configurations with a function are rebuilt for the buffer each time a print is
inserted or updated, so keep these functions fast.

#### Reusing configurations

A configuration file can load another filetype's configuration. `load_filetype_config(filetype, sources?, buffer?)` loads and merges the
files of the given sources (`"builtin"`, `"plugins"`, `"user"`; default: all). Files that return a function are called with `buffer`. It
returns a new table, without the `languages` setup option.
`extend_filetype_config(base, overrides)` returns a deep copy of `base` with `overrides` merged over it:

```lua
-- ~/.config/nvim/temp-print/config/typescript.lua: same as JavaScript, with another print
local tp = require("temp-print")
return tp.extend_filetype_config(tp.load_filetype_config("javascript"), {
    print_location = { command = 'logger.debug("<FILE_PATH_ESCAPED>:<LINE_NUMBER> <CONTEXT_ESCAPED>");' },
})
```

The bundled files do this: `cpp` loads `c`; `typescript`, `javascriptreact`, `typescriptreact` and `vue` load `javascript`; `bash` and `zsh`
load `sh`. They only load the `"builtin"` source, so your `c.lua` changes `c` but not `cpp`.

To reuse a dynamic configuration, return a function and pass the buffer along:

```lua
local tp = require("temp-print")
return function(buffer)
    return tp.extend_filetype_config(tp.load_filetype_config("lua", { "builtin" }, buffer), { commentstring = "-- %s" })
end
```

#### Extending with other plugins

A plugin can add or change filetype configurations without changes to temp-print.nvim. It only needs a `temp-print/config/<filetype>.lua`
file. These files are merged over this plugin's and under the user's. The plugin must be in the `'runtimepath'` before the filetype is first
used. With lazy.nvim, add it as a dependency of temp-print.nvim, or call `require("temp-print").clear_filetype_config_cache()` after loading
it.

## Temporary print format

```
<comment> TEMP_PRINT_NVIM_MARKER_START[_TYPE]
print command(s)
<comment> TEMP_PRINT_NVIM_MARKER_END
```

- The type suffix is `_LOCATION`, `_VARIABLE`, `_PREVIOUS_LINE` or `_NEXT_LINE`. Any other suffix, or no suffix, is allowed.
- A start marker also closes the print that is still open. So prints can be chained and share one end marker, and a print may end at the
  start of the next one.
- A start marker that is never closed, or an end marker without a start, is an error. Operations that change the buffer (delete, clear,
  comment, update) refuse to run and report the line instead of guessing.

### Auto-update

Before a buffer is saved, every print whose type is `location`, `previous_line` or `next_line` is regenerated from the code around it:

- A location print uses the nearest code line above it as its context.
- A previous-line print prints the nearest non-blank line above it, skipping other prints.
- A next-line print prints the nearest non-blank line below it, skipping other prints.

A print changed by a code formatter (re-indented, split into multiple lines, with trailing commas) is not rewritten. It is only regenerated
when its values (file path, line number, context, line) change.

**Variable prints are never updated automatically.** Some languages need manual edits in the generated statement (C's `printf` needs the
right `%d` / `%s` / ...), and regenerating would overwrite them. For the same reason, the bundled variable prints don't include line
numbers, which would become outdated.

Removing the type suffix of a print (`TEMP_PRINT_NVIM_MARKER_START`) also protects it from the auto-update. Commented prints are not updated
either.

The auto-update can be turned off with `auto_update = false`, or at runtime with `enable_auto_update()`, `disable_auto_update()` and
`toggle_auto_update()`. `update()` regenerates the prints immediately.

### Commented prints

Commenting a print adds the `COMMENTED_` prefix to its start marker and comments its commands:

```go
var name string = ""
// TEMP_PRINT_NVIM_MARKER_START_PREVIOUS_LINE
fmt.Println("cmd/main.go:1\tvar name string = \"\"")
// COMMENTED_TEMP_PRINT_NVIM_MARKER_START_VARIABLE
// fmt.Printf("%s: %+v\n", "cmd/main.go main name", name)
// TEMP_PRINT_NVIM_MARKER_END
```

A commented print still closes the print before it. Uncommenting restores it.

## Keymaps

The plugin creates no keymaps. `require("temp-print.actions")` has functions made for keymaps (see the `keys` of the
[installation example](#installation)). They act on the cursor in Normal mode and on the selected lines in Visual mode, and the editing ones
can be repeated with `.`.

Other actions: `comment`, `uncomment`, `loclist`, and `toggle_auto_update`.

Offsets: the print goes after the line `cursor + offset`, so `-1` places it before the cursor line. The variable always comes from the
cursor.

## Command

`:[range]TempPrint {subcommand} [args]`

| Subcommand                                                   | Description                                                                               |
| ------------------------------------------------------------ | ----------------------------------------------------------------------------------------- |
| `location [offset]`                                          | Location print. With a range: after each non-blank line                                   |
| `variable [offset]`, `variable_with_line [offset]`           | Variable print, optionally preceded by a print of the line                                |
| `variable_around`, `variable_around_with_line`               | Variable print before and after the line                                                  |
| `previous_line`, `next_line`                                 | Print of the line, after / before it. With a range: each non-blank line                   |
| `delete`, `comment`, `uncomment`, `toggle_comment`           | Act on the print under the cursor, or on the range                                        |
| `clear`, `comment_all`, `uncomment_all`                      | Act on every print of the buffer                                                          |
| `update`                                                     | Regenerate location and line prints                                                       |
| `auto_update [enable\|disable\|toggle]`                      | Control the auto-update                                                                   |
| `highlight [enable\|disable\|toggle]`                        | Control the highlight                                                                     |
| `next`, `prev`, `first`, `last`                              | Navigation                                                                                |
| `quickfix`, `quickfix_directory [dir]`, `loclist`            | List the prints                                                                           |
| `telescope`, `fzf_lua`, `snacks` `[buffer\|directory] [dir]` | Open a picker with the prints (default: `buffer`). Loads the picker module only when used |
| `debug [filetype]`                                           | Show the options, the merged configuration files and the effective filetype configuration |

## Pickers

The prints of the current buffer or of a directory can be listed in Telescope, fzf-lua or snacks.nvim. Each picker shows the file, line,
type and first line of each print, previews it, and jumps to it. Each one has its own module. `setup()` never loads them, so the picker
plugins are optional:

```lua
-- open(scope, directory, opts): scope is "buffer" (default) or "directory" (default: the working directory).
-- opts are passed to the picker
require("temp-print.telescope").open("buffer")
require("temp-print.fzf_lua").open("directory", "~/project")
require("temp-print.snacks").open("directory", nil, { layout = "ivy" })

-- Shortcuts: buffer(opts) and directory(directory, opts). See the `keys` of the installation example
require("temp-print.telescope").buffer()
```

Directory listings read unsaved changes of loaded buffers, and use `rg` (or `grep`) to find the files.

Telescope also has an extension: after `require("telescope").load_extension("temp_print")`, use `:Telescope temp_print` (buffer) or
`:Telescope temp_print directory`.

## Lua API

`require("temp-print")` exposes all the functions. Rows are 1-indexed and columns are 0-indexed. Nil arguments default to the current buffer
and the cursor.

```lua
local tp = require("temp-print")

-- Return true on success
tp.insert_location(buffer, row, col, offset)
tp.insert_variable(buffer, row, col, offset)
tp.insert_variable_with_line(buffer, row, col, offset)
tp.insert_variable_around(buffer, row, col, with_line)
tp.insert_previous_line(buffer, row)
tp.insert_next_line(buffer, row)

-- Return the number of affected prints, or nil if the buffer has invalid prints
tp.delete_at(buffer, row)
tp.delete_range(buffer, first, last)
tp.clear_all(buffer)
tp.comment_at(buffer, row) -- also uncomment_at, toggle_comment_at
tp.comment_range(buffer, first, last) -- also uncomment_range, toggle_comment_range
tp.comment_all(buffer) -- also uncomment_all
tp.update(buffer)

tp.enable_auto_update() -- also disable_auto_update, toggle_auto_update, is_auto_update_enabled
tp.enable_highlight() -- also disable_highlight, toggle_highlight, is_highlight_enabled
tp.goto_next(count) -- also goto_prev, goto_first, goto_last
tp.to_quickfix("buffer" | "directory", directory)
tp.to_loclist()

-- Filetype configurations
tp.get_filetype_config(filetype, buffer) -- effective configuration (buffer: given to configuration functions)
tp.load_filetype_config(filetype, sources, buffer)
tp.extend_filetype_config(base, overrides)
tp.is_neovim_lua(buffer) -- uses the is_neovim_lua option
tp.default_is_neovim_lua(buffer)
tp.in_neovim_directory(path)
tp.clear_filetype_config_cache()
```

## Development

```sh
make deps          # clone mini.nvim (test framework) into deps/
make deps-pickers  # optional: clone plenary, telescope, fzf-lua and snacks into deps/ for the picker tests
make test          # or: make test FILE=tests/test_insert.lua
make lint          # luacheck
make format        # stylua (make format-check to only check)
make typecheck     # lua-language-server
make check         # everything
```

The picker tests are skipped when the picker plugins are missing. To run them with plugins installed elsewhere, set
`TEMP_PRINT_TEST_PLUGINS` to the directory that holds them (like `~/.local/share/nvim/lazy`).

## License

[MIT](LICENSE)
