--- Markdown list, checkbox, and blockquote continuation.
---
--- Order matters: checkboxes are tested before plain unordered items, because
--- a "- [ ] x" line also matches the unordered pattern. Pressing the key on an
--- empty item (marker only) drops the marker and exits the list.

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

	-- Ordered: "  1. text" becomes "  2. ". Uses the shared counter action
	-- (unordered and checkbox cannot, since they echo the existing bullet
	-- char and reset the checkbox).
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
}
