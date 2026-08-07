--- Composable predicate builders.
---
--- A matcher is a `fun(ctx: SmartEnterContext): table|nil`. It returns match
--- data (a truthy table, possibly empty) when it applies, or nil when it does
--- not. The match data is passed on to the rule's action.

local M = {}

--- Lua pattern match against the current line.
---@param pat string a Lua pattern; its captures become the match data
---@return fun(ctx: SmartEnterContext): string[]|nil
function M.pattern(pat)
	return function(ctx)
		if not ctx.line:find(pat) then
			return nil
		end
		return { ctx.line:match(pat) }
	end
end

--- Read the environment name out of a "begin" node, for example the "align" in
--- "\begin{align}". Works whether or not the environment takes trailing curly
--- arguments (the theorem style "\begin{env}{label}{tag}"), because the begin
--- node text is just "\begin{env}".
---@param begin_node TSNode a node of type "begin"
---@param buf integer
---@return string|nil
local function begin_name(begin_node, buf)
	local text = vim.treesitter.get_node_text(begin_node, buf)
	return text and text:match("\\begin%s*{%s*([^}]-)%s*}")
end

--- Walk the Treesitter ancestors of the node at the cursor, outermost last,
--- and collect every enclosing environment name. Used by ts_env and by the
--- debug inspector.
---
--- LaTeX shaped, deliberately: it looks for a node type ending in
--- "environment" holding a "begin" child that reads "\begin{name}". `lang` is
--- for LaTeX under another parser (an injection inside markdown, say), NOT for
--- other languages -- pass "bash" and you get an empty chain, because bash has
--- no nodes of that shape. To match structure in another language, write a
--- `match` function over vim.treesitter.get_node() yourself; the shell preset
--- does the equivalent job with a line scan and no parser at all.
---@param ctx SmartEnterContext
---@param lang? string parser language for LaTeX (default "latex")
---@return string[] names innermost first
---@return string? err reason the chain is empty (no parser, no tree)
function M.env_chain(ctx, lang)
	lang = lang or "latex"

	local ok, parser = pcall(vim.treesitter.get_parser, ctx.buf, lang)
	if not ok or not parser then
		return {}, "no '" .. lang .. "' parser for this buffer"
	end
	local tree = (parser:parse() or {})[1]
	if not tree then
		return {}, "parser produced no tree"
	end

	local names = {}
	local node = tree:root():named_descendant_for_range(
		ctx.row - 1, ctx.col, ctx.row - 1, ctx.col)
	while node do
		if node:type():match("environment$") then
			for child in node:iter_children() do
				if child:type() == "begin" then
					local name = begin_name(child, ctx.buf)
					if name then
						names[#names + 1] = name
					end
					break
				end
			end
		end
		node = node:parent()
	end
	return names
end

--- Match when the cursor's nearest enclosing LaTeX environment is named in
--- `names`. Treesitter based, so there is no VimTeX dependency and nesting is
--- honoured. LaTeX only -- see env_chain for why, and for the alternative.
---@param names string[] environment names to match, for example { "align", "align*" }
---@param lang? string parser language for LaTeX (default "latex")
---@return fun(ctx: SmartEnterContext): { env: string }|nil
function M.ts_env(names, lang)
	local set = {}
	for _, n in ipairs(names) do
		set[n] = true
	end

	return function(ctx)
		for _, name in ipairs(M.env_chain(ctx, lang)) do
			if set[name] then
				return { env = name }
			end
		end
		return nil
	end
end

return M
