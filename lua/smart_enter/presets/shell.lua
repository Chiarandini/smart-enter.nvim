--- Shell line continuation: close the line with "\" and open an indented one.
---
--- The action is shared (actions.continuation); what is shell specific is
--- where a backslash is legal, so this preset is mostly a guard. It declines,
--- falling through to the plain newline, wherever a "\" would be wrong:
---
---   blank line          nothing to continue
---   comment             the backslash would be commented out, silently
---                       ending the command
---   single quotes       "\" is literal inside '...', not a continuation
---   already continued   a second "\" escapes the first one, which ends the
---                       command instead of continuing it (the worst case,
---                       because it still looks right)
---   open operator       after | || && ; { ( then do else in, the shell
---                       already continues on its own
---   heredoc body        the body is data; a "\" there is text
---
--- Applies to filetype sh, which covers both .sh and .bash, and to zsh.

--- How far up in_heredoc looks. A heredoc longer than this reads as closed,
--- which costs a spurious backslash rather than a hang.
local SCAN_LIMIT = 200

--- Tokens after which the shell continues the command by itself. A trailing
--- backslash is handled separately, since it need not be its own token
--- ("echo hi\" continues just as "echo hi \" does).
local OPEN = {
	["|"] = true, ["||"] = true, ["&&"] = true, ["&"] = true,
	[";"] = true, [";;"] = true, ["{"] = true, ["("] = true,
	["then"] = true, ["do"] = true, ["else"] = true, ["in"] = true,
}

--- Single pass over the text before the cursor. Quoting is what decides
--- whether a "#" opens a comment, so both facts come out of one scan instead
--- of two patterns that would disagree on `echo "a # b"`.
---@param head string
---@return boolean commented a comment starts before the cursor
---@return string|nil quote the quote still open at the cursor
local function scan(head)
	local i, quote = 1, nil
	while i <= #head do
		local c = head:sub(i, i)
		if quote then
			if c == "\\" and quote == '"' then
				i = i + 1 -- escaped, inside "" only
			elseif c == quote then
				quote = nil
			end
		elseif c == "'" or c == '"' then
			quote = c
		elseif c == "\\" then
			i = i + 1     -- escapes the next char, quotes included
		elseif c == "#" and (i == 1 or head:sub(i - 1, i - 1):match("[%s;|&(]")) then
			return true, nil -- a "#" mid-word (a#b, ${#x}) is not a comment
		end
		i = i + 1
	end
	return false, quote
end

--- Does the shell already carry this line on to the next?
---@param head string
---@return boolean
local function open_ended(head)
	local trimmed = head:gsub("%s+$", "")
	if trimmed:sub(-1) == "\\" then
		return true
	end
	local last = trimmed:match("%S+$")
	return last ~= nil and OPEN[last] == true
end

--- Is the cursor inside an unterminated heredoc body? Walks the lines above,
--- opening on `<<WORD` / `<<-'WORD'` and closing on the delimiter alone. A
--- herestring (`<<<`) does not open one, since `<` is not a delimiter char.
---@param ctx SmartEnterContext
---@return boolean
local function in_heredoc(ctx)
	local from = math.max(1, ctx.row - SCAN_LIMIT)
	local delim
	for _, l in ipairs(vim.api.nvim_buf_get_lines(ctx.buf, from - 1, ctx.row - 1, false)) do
		if delim then
			if l:match("^%s*" .. vim.pesc(delim) .. "%s*$") then
				delim = nil
			end
		else
			delim = l:match("<<%-?%s*[\"']?([%w_]+)")
		end
	end
	return delim ~= nil
end

return {
	{
		match = function(ctx)
			if ctx.head:match("^%s*$") then
				return nil
			end
			local commented, quote = scan(ctx.head)
			if commented or quote == "'" then
				return nil
			end
			if open_ended(ctx.head) or in_heredoc(ctx) then
				return nil
			end
			return {}
		end,

		continuation = "\\",
	},
}
