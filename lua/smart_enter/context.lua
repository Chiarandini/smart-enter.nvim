--- The context object handed to every matcher and action, plus the small set
--- of buffer editing primitives the built in rules use. All edits go through a
--- single nvim_buf_set_text or nvim_set_current_line call, so each smart enter
--- press is one undo unit.

---@class SmartEnterContext
---@field win integer window handle
---@field buf integer buffer handle
---@field row integer 1 indexed cursor row
---@field col integer 0 indexed byte column of the cursor
---@field line string text of the current line
---@field ws string leading whitespace of the current line
---@field filetype string filetype of the buffer
---@field split fun(append?: string, prefix?: string) break the line at the cursor
---@field replace_line fun(text: string) replace the whole current line

local M = {}

--- Build the context for the current window, buffer, and cursor position.
---@return SmartEnterContext
function M.build()
	local win = vim.api.nvim_get_current_win()
	local buf = vim.api.nvim_win_get_buf(win)
	local row, col = unpack(vim.api.nvim_win_get_cursor(win))
	local line = vim.api.nvim_get_current_line()

	local ctx = {
		win      = win,
		buf      = buf,
		row      = row,
		col      = col,
		line     = line,
		ws       = line:match("^%s*") or "",
		filetype = vim.bo[buf].filetype,
	}

	--- Break the line at the cursor. `append` is glued to the end of the
	--- current line (for example LaTeX's "\\"). `prefix` opens the new line
	--- (for example "\item ", "&= "). Whatever followed the cursor trails
	--- prefix on the new line. The cursor lands at the end of prefix.
	---@param append? string text appended to the current line at the cursor
	---@param prefix? string text that opens the new line
	function ctx.split(append, prefix)
		append = append or ""
		prefix = prefix or ""
		vim.api.nvim_buf_set_text(buf, row - 1, col, row - 1, col, { append, prefix })
		vim.api.nvim_win_set_cursor(win, { row + 1, #prefix })
	end

	--- Replace the whole current line, for dropping an empty list marker to
	--- exit the list. The cursor lands at the end of the replacement.
	---@param text string replacement line
	function ctx.replace_line(text)
		vim.api.nvim_set_current_line(text)
		vim.api.nvim_win_set_cursor(win, { row, #text })
	end

	return ctx
end

return M
