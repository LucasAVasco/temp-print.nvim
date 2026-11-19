-- Minimal configuration used by the tests (both the test runner and the child Neovim instances)
vim.opt.runtimepath:prepend(vim.fn.getcwd())
vim.opt.runtimepath:append(vim.fn.getcwd() .. "/deps/mini.nvim")

-- Optional picker plugins (the picker tests are skipped without them): `make deps-pickers` clones them into deps/.
-- TEMP_PRINT_TEST_PLUGINS may point to another directory with them (like ~/.local/share/nvim/lazy)
for _, name in ipairs({ "plenary.nvim", "telescope.nvim", "fzf-lua", "snacks.nvim" }) do
    for _, dir in ipairs({ vim.fn.getcwd() .. "/deps", vim.env.TEMP_PRINT_TEST_PLUGINS }) do
        local path = dir and vim.fs.joinpath(vim.fn.expand(dir), name)
        if path and vim.uv.fs_stat(path) then
            vim.opt.runtimepath:append(path)
            break
        end
    end
end

-- Needed so the filetype plugins set 'commentstring'
vim.cmd("filetype plugin on")

-- Only the headless test runner needs mini.test configured
if #vim.api.nvim_list_uis() == 0 then
    require("mini.test").setup()
end
