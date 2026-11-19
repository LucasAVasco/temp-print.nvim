-- Small helpers shared by the modules
local M = {}

---@param msg string
---@param level integer? Defaults to ERROR
function M.notify(msg, level)
    vim.notify("[temp-print] " .. msg, level or vim.log.levels.ERROR)
end

---Replaces every occurrence of `placeholder` in `str` by `value`. Neither argument is treated as a Lua pattern
---@param str string
---@param placeholder string
---@param value string
---@return string
function M.replace_plain(str, placeholder, value)
    local result = str:gsub(vim.pesc(placeholder), function()
        return value
    end)
    return result
end

---@param buffer integer?
---@return integer
function M.resolve_buffer(buffer)
    if not buffer or buffer == 0 then
        return vim.api.nvim_get_current_buf()
    end
    return buffer
end

---Returns the window to use for cursor-based defaults: the current window if it shows the buffer, otherwise any
---window showing it
---@param buffer integer
---@return integer? window
function M.window_of(buffer)
    if vim.api.nvim_win_get_buf(0) == buffer then
        return vim.api.nvim_get_current_win()
    end
    local win = vim.fn.bufwinid(buffer)
    return win ~= -1 and win or nil
end

---Absolute and normalized path. `~` and relative paths (to the working directory) are expanded
---@param path string
---@return string
function M.absolute_path(path)
    return vim.fs.normalize(vim.fn.fnamemodify(vim.fs.normalize(path), ":p"))
end

---Normalized path with its symbolic links resolved. The path is returned normalized if it does not exist
---@param path string
---@return string
function M.real_path(path)
    return vim.fs.normalize(vim.uv.fs_realpath(path) or path)
end

---Whether a path is strictly inside a directory. Both must be normalized
---@param path string
---@param dir string? Nil or empty is never a parent
---@return boolean
function M.is_inside(path, dir)
    return dir ~= nil and dir ~= "" and vim.startswith(path, dir .. "/")
end

---Cursor position in a window showing the buffer (see `window_of`)
---@param buffer integer
---@return integer? row 1-indexed
---@return integer|string col 0-indexed, or the error message when no window shows the buffer
function M.cursor(buffer)
    local win = M.window_of(buffer)
    if not win then
        return nil, ("buffer %d is not displayed in any window, so a position must be provided"):format(buffer)
    end
    local cursor = vim.api.nvim_win_get_cursor(win)
    return cursor[1], cursor[2]
end

---@param buffer integer
---@param row integer 1-indexed
---@return string?
function M.get_line(buffer, row)
    return vim.api.nvim_buf_get_lines(buffer, row - 1, row, false)[1]
end

---@param line string?
---@return boolean
function M.is_blank(line)
    return line == nil or line:match("^%s*$") ~= nil
end

---@param line string?
---@return string
function M.indentation(line)
    return (line or ""):match("^%s*")
end

---Splits a 'commentstring' into its trimmed left and right parts. Example: "/* %s */" -> "/*", "*/"
---@param commentstring string
---@return string left
---@return string right
function M.comment_parts(commentstring)
    local left, right = commentstring:match("^(.-)%%s(.-)$")
    if not left then
        left, right = commentstring, ""
    end
    return vim.trim(left), vim.trim(right)
end

---Comments a line, keeping its indentation. Blank lines are returned unchanged
---@param commentstring string
---@param line string
---@return string
function M.comment_line(commentstring, line)
    if M.is_blank(line) then
        return line
    end
    local left, right = M.comment_parts(commentstring)
    local indent = M.indentation(line)
    local text = line:sub(#indent + 1)
    return indent .. left .. " " .. text .. (right ~= "" and (" " .. right) or "")
end

---Uncomments a line commented by `comment_line`. Lines that are not commented are returned unchanged
---@param commentstring string
---@param line string
---@return string
function M.uncomment_line(commentstring, line)
    local left, right = M.comment_parts(commentstring)
    local indent = M.indentation(line)
    local text = line:sub(#indent + 1)

    if left == "" or text:sub(1, #left) ~= left then
        return line
    end
    text = text:sub(#left + 1):gsub("^ ", "", 1)

    if right ~= "" and text:sub(-#right) == right then
        text = text:sub(1, -#right - 1):gsub(" $", "", 1)
    end
    return indent .. text
end

---Returns the comment string of the buffer, preferring the filetype configuration
---@param buffer integer
---@return string? commentstring
---@return string? error
function M.get_commentstring(buffer)
    local filetype = vim.bo[buffer].filetype
    local lang_config = require("temp-print.config.language").get_filetype_config(filetype, buffer)
    local commentstring = lang_config and lang_config.commentstring or vim.bo[buffer].commentstring
    if not commentstring or commentstring == "" then
        return nil, ("no comment string found for filetype '%s'"):format(filetype)
    end
    return commentstring
end

---Sets the cursor row of every window showing the buffer that is tracked by an extmark, keeping the column.
---Used to keep the cursor on its code line when lines are inserted above it
---@param buffer integer
---@param fn fun() Function that changes the buffer
function M.keep_cursor(buffer, fn)
    local ns = vim.api.nvim_create_namespace("temp-print-cursor")
    local tracked = {}
    for _, win in ipairs(vim.fn.win_findbuf(buffer)) do
        local cursor = vim.api.nvim_win_get_cursor(win)
        local mark = vim.api.nvim_buf_set_extmark(buffer, ns, cursor[1] - 1, 0, {})
        tracked[win] = { mark = mark, col = cursor[2] }
    end

    local ok, err = pcall(fn)

    for win, data in pairs(tracked) do
        local pos = vim.api.nvim_buf_get_extmark_by_id(buffer, ns, data.mark, {})
        if pos[1] and vim.api.nvim_win_is_valid(win) then
            pcall(vim.api.nvim_win_set_cursor, win, { pos[1] + 1, data.col })
        end
        vim.api.nvim_buf_del_extmark(buffer, ns, data.mark)
    end

    if not ok then
        error(err, 0)
    end
end

return M
