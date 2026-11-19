-- Picker modules (Telescope, fzf-lua, snacks.nvim). The tests that open a picker are skipped when it is not installed
local H = dofile("tests/helpers.lua")
local eq = H.eq

local child, T = H.new_set()

local S = "-- TEMP_PRINT_NVIM_MARKER_START"
local E = "-- TEMP_PRINT_NVIM_MARKER_END"

local lines = {
    "local a = 1", -- 1
    S .. "_LOCATION", -- 2
    "  print(1)",
    E,
    "local b = 2", -- 5
    "-- COMMENTED_TEMP_PRINT_NVIM_MARKER_START_VARIABLE", -- 6
    "-- print(2)",
    E,
}

---Writes a project with prints in the child's working directory and opens its first file
local function project()
    local dir = child.fn.tempname()
    child.fn.mkdir(dir .. "/sub", "p")
    child.fn.writefile(lines, dir .. "/sub/one.lua")
    child.fn.writefile({ "x", S .. "_NEXT_LINE", "print(3)", E }, dir .. "/two.lua")
    child.fn.writefile({ "nothing here" }, dir .. "/three.lua")
    child.cmd("cd " .. dir)
    child.cmd("edit sub/one.lua")
    return dir
end

local function has(module)
    return H.lua(child, ("return pcall(require, %q)"):format(module))
end

local function row()
    return child.api.nvim_win_get_cursor(0)[1]
end

---Waits until `fn` returns true (pickers open asynchronously)
local function wait(fn, timeout)
    local start = vim.uv.now()
    while vim.uv.now() - start < (timeout or 3000) do
        if fn() then
            return true
        end
        vim.uv.sleep(20)
    end
    return false
end

T["items"] = MiniTest.new_set()

T["items"]["directory items are parsed like buffer items"] = function()
    local dir = project()
    local items = H.lua(child, "return require('temp-print.list').directory_items()")
    eq(#items, 3)
    eq({ items[1].filename, items[1].lnum, items[1].text }, { dir .. "/sub/one.lua", 2, "location: print(1)" })
    eq({ items[2].commented, items[2].type, items[2].content }, { true, "variable", "-- print(2)" })
    eq({ items[3].filename, items[3].text }, { dir .. "/two.lua", "next_line: print(3)" })
end

T["items"]["directory items read unsaved changes of loaded buffers"] = function()
    project()
    child.api.nvim_buf_set_lines(0, 0, -1, false, { S .. "_LOCATION", "changed", E })
    local items = H.lua(child, "return require('temp-print.list').directory_items()")
    eq(items[1].text, "location: changed")
end

T["items"]["entries of each picker"] = function()
    project()
    local entries = H.lua(
        child,
        [[
        local items = require("temp-print.list").buffer_items()
        local telescope = require("temp-print.telescope")._entry_maker(items[1])
        local snacks = require("temp-print.snacks")._items(items)
        return {
            telescope = { telescope.display, telescope.lnum, telescope.bufnr == vim.api.nvim_get_current_buf() },
            fzf = require("temp-print.fzf_lua")._entries(items),
            snacks = { snacks[2].text, snacks[2].pos, snacks[2].file == vim.api.nvim_buf_get_name(0) },
        }
    ]]
    )
    eq(entries.telescope, { "sub/one.lua:2  location: print(1)", 2, true })
    eq(entries.fzf, { "sub/one.lua:2:1: location: print(1)", "sub/one.lua:6:1: commented variable: -- print(2)" })
    eq(entries.snacks, { "sub/one.lua:6 commented variable: -- print(2)", { 6, 0 }, true })
end

T["items"]["the picker modules are not loaded by setup"] = function()
    eq(
        H.lua(
            child,
            [[return { package.loaded["temp-print.telescope"], package.loaded["temp-print.fzf_lua"], package.loaded["temp-print.snacks"] }]]
        ),
        {}
    )
end

T["command"] = MiniTest.new_set()

T["command"]["completes the scope and the directory"] = function()
    eq(child.fn.getcompletion("TempPrint telescope d", "cmdline"), { "directory" })
    eq(child.fn.getcompletion("TempPrint snacks ", "cmdline"), { "buffer", "directory" })
    eq(#child.fn.getcompletion("TempPrint fzf_lua directory ", "cmdline") > 0, true)
    eq(child.fn.getcompletion("TempPrint highlight toggle ", "cmdline"), {})
end

T["command"]["reports a missing picker or an invalid scope"] = function()
    project()
    H.lua(child, [[package.preload["telescope"] = function() error("not installed") end]])
    H.lua(child, [[package.loaded["telescope"] = nil]])
    child.cmd("TempPrint telescope")
    child.cmd("TempPrint snacks wrong")
    local messages = vim.tbl_map(function(m)
        return m.msg
    end, H.messages(child))
    eq(messages, { "[temp-print] telescope.nvim is not installed", "[temp-print] invalid scope: wrong (expected 'buffer' or 'directory')" })
end

T["pickers"] = MiniTest.new_set()

T["pickers"]["telescope"] = function()
    if not has("telescope") then
        MiniTest.skip("telescope.nvim is not installed")
    end
    project()
    child.cmd("TempPrint telescope directory")
    eq(
        wait(function()
            return child.bo.filetype == "TelescopePrompt"
        end),
        true
    )
    child.type_keys("two")
    vim.uv.sleep(300)
    child.type_keys("<CR>")
    eq(
        wait(function()
            return child.fn.expand("%:t") == "two.lua"
        end),
        true
    )
    eq(row(), 2)
end

T["pickers"]["fzf-lua"] = function()
    if not has("fzf-lua") or vim.fn.executable("fzf") == 0 then
        MiniTest.skip("fzf-lua or fzf is not installed")
    end
    project()
    child.cmd("TempPrint fzf_lua")
    eq(
        wait(function()
            return child.bo.buftype == "terminal"
        end),
        true
    )
    vim.uv.sleep(500)
    child.type_keys("commented")
    vim.uv.sleep(300)
    child.type_keys("<CR>")
    eq(
        wait(function()
            return child.bo.buftype == "" and row() == 6
        end),
        true
    )
end

T["pickers"]["snacks"] = function()
    if not has("snacks") then
        MiniTest.skip("snacks.nvim is not installed")
    end
    project()
    child.cmd("TempPrint snacks directory")
    eq(
        wait(function()
            return child.bo.filetype == "snacks_picker_input"
        end),
        true
    )
    child.type_keys("two")
    vim.uv.sleep(300)
    child.type_keys("<CR>")
    eq(
        wait(function()
            return child.fn.expand("%:t") == "two.lua"
        end),
        true
    )
    eq(row(), 2)
end

return T
