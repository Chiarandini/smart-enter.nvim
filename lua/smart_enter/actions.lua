--- Reusable rule actions for the built in presets and for user rules.

local api = vim.api

local M = {}

-- ── Counter kinds ────────────────────────────────────────────────────────
-- Each kind parses a marker token to an integer and formats an integer back,
-- so a list entry can continue to the next number, letter, or numeral.

--- Bijective base 26: "a" is 1, "z" is 26, "aa" is 27.
---@param s string
---@return integer
local function alpha_from(s)
	s = s:lower()
	local n = 0
	for i = 1, #s do
		n = n * 26 + (s:byte(i) - 96)
	end
	return n
end

---@param n integer
---@param upper boolean
---@return string
local function alpha_to(n, upper)
	local out = ""
	while n > 0 do
		local r = (n - 1) % 26
		out = string.char(97 + r) .. out
		n = math.floor((n - 1) / 26)
	end
	if out == "" then
		out = "a"
	end
	return upper and out:upper() or out
end

local roman_pairs = {
	{ 1000, "m" }, { 900, "cm" }, { 500, "d" }, { 400, "cd" },
	{ 100, "c" }, { 90, "xc" }, { 50, "l" }, { 40, "xl" },
	{ 10, "x" }, { 9, "ix" }, { 5, "v" }, { 4, "iv" }, { 1, "i" },
}

---@param n integer
---@param upper boolean
---@return string
local function roman_to(n, upper)
	local out = ""
	for _, p in ipairs(roman_pairs) do
		while n >= p[1] do
			out = out .. p[2]
			n = n - p[1]
		end
	end
	return upper and out:upper() or out
end

---@param s string
---@return integer
local function roman_from(s)
	local val = { i = 1, v = 5, x = 10, l = 50, c = 100, d = 500, m = 1000 }
	s = s:lower()
	local n, prev = 0, 0
	for i = #s, 1, -1 do
		local v = val[s:sub(i, i)] or 0
		if v < prev then
			n = n - v
		else
			n = n + v
			prev = v
		end
	end
	return n
end

---@class SmartEnterCounter
---@field pat string Lua pattern class matching one counter token
---@field from fun(s: string): integer
---@field to fun(n: integer): string

---@type table<string, SmartEnterCounter>
local counters = {
	arabic = { pat = "%d+", from = function(s) return tonumber(s) end, to = function(n) return tostring(n) end },
	alpha  = { pat = "%a+", from = alpha_from, to = function(n) return alpha_to(n, false) end },
	Alpha  = { pat = "%a+", from = alpha_from, to = function(n) return alpha_to(n, true) end },
	roman  = { pat = "%a+", from = roman_from, to = function(n) return roman_to(n, false) end },
	Roman  = { pat = "%a+", from = roman_from, to = function(n) return roman_to(n, true) end },
}

-- ── item ─────────────────────────────────────────────────────────────────

local COUNTER_PLACEHOLDER = "{}"

--- Pattern matching an existing entry line: captures the leading whitespace,
--- and the counter token when the marker carries a "{}" placeholder.
---@param marker string the entry marker with trailing whitespace removed
---@param counter SmartEnterCounter|nil
---@return string
local function entry_pattern(marker, counter)
	if counter then
		local before, after = marker:match("^(.-)" .. vim.pesc(COUNTER_PLACEHOLDER) .. "(.*)$")
		if before then
			return "^(%s*)" .. vim.pesc(before) .. "(" .. counter.pat .. ")" .. vim.pesc(after)
		end
	end
	return "^(%s*)" .. vim.pesc(marker)
end

--- Nearest entry line at or above `row`, scanning no further up than the
--- enclosing "\begin" (and bounded so a stray rule cannot walk a whole file).
---@param buf integer
---@param row integer 1 indexed
---@param pat string entry pattern from entry_pattern()
---@return string[]|nil captures the pattern's captures (ws, [counter]) or nil
local function scan_entry(buf, row, pat)
	for r = row, math.max(1, row - 200), -1 do
		local l = api.nvim_buf_get_lines(buf, r - 1, r, false)[1]
		if not l then
			break
		end
		local caps = { l:match(pat) }
		if caps[1] then
			return caps
		end
		if l:match("^%s*\\begin") then
			break
		end
	end
	return nil
end

--- Build a handler that continues a list-like environment.
---
--- `spec` is the entry text, or a table:
---   { text = "\\item ", exit_empty = true, counter = "arabic" }
--- `text` is placed on the next line, indented to match the current entry
--- rather than a soft wrapped continuation line (the anchor is the marker, so
--- the whole prefix before content). When `counter` is set (one of "arabic",
--- "alpha"/"Alpha", "roman"/"Roman"), the "{}" in `text` is replaced by the
--- previous entry's counter incremented by one. When `exit_empty` is true (the
--- default), pressing on an entry that has only its marker clears it and exits
--- the list instead of adding another.
---@param spec string|{ text: string, exit_empty?: boolean, counter?: string }
---@return fun(ctx: SmartEnterContext): true
function M.item(spec)
	if type(spec) == "string" then
		spec = { text = spec }
	end
	local text       = spec.text
	local exit_empty = spec.exit_empty ~= false
	local counter    = spec.counter and counters[spec.counter] or nil
	local marker     = text:gsub("%s+$", "")
	local pat        = entry_pattern(marker, counter)
	local empty_pat  = pat .. "%s*$"

	return function(ctx)
		if exit_empty and ctx.line:match(empty_pat) then
			ctx.replace_line(ctx.ws)
			return true
		end

		local caps   = scan_entry(ctx.buf, ctx.row, pat)
		local indent = (caps and caps[1]) or ctx.ws
		local entry  = text
		if counter then
			local prev = caps and caps[2]
			local next_n = prev and (counter.from(prev) + 1) or 1
			entry = text:gsub(COUNTER_PLACEHOLDER, counter.to(next_n))
		end
		ctx.split("", indent .. entry)
		return true
	end
end

-- ── continuation ─────────────────────────────────────────────────────────
-- The suffix counterpart of item: instead of opening the new line with a
-- marker, close the old one with it. Shell, Dockerfile, make, and C macros all
-- spell "this command continues below" as a trailing backslash.

--- One indent level for `buf`, honouring 'expandtab' and 'shiftwidth'.
---@param buf integer
---@return string
local function indent_unit(buf)
	if vim.bo[buf].expandtab then
		return string.rep(" ", vim.fn.shiftwidth())
	end
	return "\t"
end

--- Indent for the continued line: one level in when opening a continuation
--- block, the current indent when already inside one (so a five line command
--- stays a ladder instead of a staircase). The previous line ending in the
--- marker is what says we are already inside one.
---@param ctx SmartEnterContext
---@param marker string
---@return string
local function continuation_indent(ctx, marker)
	local prev = api.nvim_buf_get_lines(ctx.buf, ctx.row - 2, ctx.row - 1, false)[1]
	if prev and prev:match(vim.pesc(marker) .. "%s*$") then
		return ctx.ws
	end
	return ctx.ws .. indent_unit(ctx.buf)
end

--- Build a handler that continues the current logical line onto the next
--- physical one: `marker` closes the line being left, and the new line opens
--- at a continuation indent, carrying whatever followed the cursor.
---
--- `spec` is the marker, or a table:
---   { marker = "\\", sep = " ", indent = "  " | function(ctx) }
--- `sep` sits between the code and the marker (dropped when nothing precedes
--- it). `indent` overrides the default one-level-then-hold policy.
---
--- Deciding WHERE this is legal belongs to the rule's matcher, not here: the
--- token that means "continues below" is a fact about the language, but the
--- places a marker would be wrong (comments, heredocs, an operator that
--- already continues) differ per language.
---@param spec string|{ marker: string, sep?: string, indent?: string|fun(ctx: SmartEnterContext): string }
---@return fun(ctx: SmartEnterContext): true
function M.continuation(spec)
	if type(spec) == "string" then
		spec = { marker = spec }
	end
	local marker = spec.marker
	local sep    = spec.sep or " "

	return function(ctx)
		local head = ctx.head:gsub("%s+$", "")
		local tail = ctx.tail:gsub("^%s+", "")

		local indent = spec.indent
		if type(indent) == "function" then
			indent = indent(ctx)
		end
		indent = indent or continuation_indent(ctx, marker)

		-- One call, so one undo unit (the contract ctx.split holds). split
		-- itself cannot serve here: it glues text at the cursor verbatim, and a
		-- continuation has to trim both sides of the break.
		api.nvim_buf_set_lines(ctx.buf, ctx.row - 1, ctx.row, false, {
			head == "" and marker or head .. sep .. marker,
			indent .. tail,
		})
		api.nvim_win_set_cursor(ctx.win, { ctx.row + 1, #indent })
		return true
	end
end

return M
