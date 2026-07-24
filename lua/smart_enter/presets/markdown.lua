--- Markdown list, checkbox, and blockquote continuation.
---
--- Order matters: checkboxes are tested before plain unordered items, because
--- a "- [ ] x" line also matches the unordered pattern. Pressing the key on an
--- empty item drops the marker and exits the list. A trailing rule continues
--- the list from a wrapped continuation line, where a long item has hard
--- wrapped onto a buffer line that carries no marker of its own.

local api = vim.api

--- Build a handler that continues a list, or exits it when the item is empty.
--- The captures list is expected to hold the leading whitespace at index 1 and
--- the item body as its last element.
---@param marker_prefix fun(caps: string[]): string builds the next line's marker
---@return fun(ctx: SmartEnterContext, caps: string[])
local function continue_or_exit(marker_prefix)
	return function(ctx, caps)
		local ws, body = caps[1], caps[#caps]
		if body == "" then
			ctx.replace_line(ws)
		else
			ctx.split("", marker_prefix(caps))
		end
	end
end

--- The next-entry marker for the list item on `line`, aligned to that line's
--- own indent, or nil when `line` is not a list item. Checkbox resets to
--- unchecked; ordered increments.
---@param line string
---@return string|nil
local function next_entry(line)
	local ws, marker = line:match("^(%s*)([-*+])%s+%[.%]%s")
	if ws then return ws .. marker .. " [ ] " end
	ws, marker = line:match("^(%s*)([-*+])%s")
	if ws then return ws .. marker .. " " end
	local num
	ws, num = line:match("^(%s*)(%d+)%.%s")
	if ws then return ws .. tostring(tonumber(num) + 1) .. ". " end
	return nil
end

return {
	-- Checkbox: "  - [ ] text" or "  * [x] text".
	{
		pattern = "^(%s*)([-*+])%s+%[.%]%s(.*)",
		handle  = continue_or_exit(function(caps)
			return caps[1] .. caps[2] .. " [ ] "
		end),
	},

	-- Unordered: "  - text", "  * text", "  + text".
	{
		pattern = "^(%s*)([-*+])%s(.*)",
		handle  = continue_or_exit(function(caps)
			return caps[1] .. caps[2] .. " "
		end),
	},

	-- Ordered: "  1. text" becomes "  2. " (shared counter action).
	{
		pattern = "^%s*%d+%.%s",
		item    = { text = "{}. ", counter = "arabic" },
	},

	-- Blockquote: "> text" or ">> text".
	{
		pattern = "^(%s*)(>+%s)",
		handle  = function(ctx, caps)
			ctx.split("", caps[1] .. caps[2])
		end,
	},

	-- Wrapped continuation: the current buffer line carries no marker because a
	-- long item hard wrapped onto it. Scan up past the wrapped text to the
	-- governing item and continue it, aligned to the original marker. Stops at
	-- a blank line, so a paragraph following a list is not swept in; requires
	-- the current line to be indented past the marker (a real hanging line).
	{
		match = function(ctx)
			local cur_ws = ctx.line:match("^(%s*)")
			for r = ctx.row - 1, math.max(1, ctx.row - 200), -1 do
				local l = api.nvim_buf_get_lines(ctx.buf, r - 1, r, false)[1]
				if not l or l:match("^%s*$") then
					return nil
				end
				local prefix = next_entry(l)
				if prefix then
					if #cur_ws > #(l:match("^(%s*)")) then
						return { prefix = prefix }
					end
					return nil
				end
			end
			return nil
		end,
		handle = function(ctx, m)
			ctx.split("", m.prefix)
		end,
	},
}
