--- Rule normalization and evaluation.
---
--- A rule is either declarative or functional.
---
--- Declarative rules insert static text, keyed by environment or line pattern.
--- The new line is auto indented with the current line's leading whitespace,
--- then `prefix`. `append` is glued to the old line at the cursor.
---     { env = "align",  append = "\\\\", prefix = "&= " }
---     { pattern = "^%s*> ", prefix = "> " }
---
--- The `item` field continues a list-like environment: it inserts the given
--- entry text on the next line, indented to match the current entry rather
--- than a soft wrapped continuation line, and (by default) exits the list when
--- the current entry is empty. It may be a string, or a table for a counter or
--- to turn off exit on empty (see actions.item).
---     { envs = { "itemize", "enumerate" }, item = "\\item " }
---     { env = "exercise", item = "\\Question " }
---     { env = "steps", item = { text = "\\item[{})] ", counter = "alpha" } }
---
--- Functional rules take full control (list renumbering, exit on empty, and so
--- on). `handle` returns false to fall through to the next rule; anything else
--- (including nil) counts as handled and stops the chain.
---     { match = <matcher>, handle = function(ctx, m) ... end }
---     { pattern = "^(%s*)(%d+)%.", handle = function(ctx, caps) ... end }
---
--- A rule with no env, envs, pattern, or match always matches.

---@class SmartEnterRule
---@field env? string a single environment name to match
---@field envs? string[] environment names to match
---@field pattern? string a Lua pattern to match against the current line
---@field match? fun(ctx: SmartEnterContext): table|nil a custom matcher
---@field append? string declarative: text glued to the current line at the cursor
---@field prefix? string declarative: text that opens the new line
---@field item? string|{ text: string, exit_empty?: boolean, counter?: string } declarative list continuation (see actions.item)
---@field handle? fun(ctx: SmartEnterContext, match: table): boolean|nil functional action

---@class SmartEnterNormalRule
---@field match fun(ctx: SmartEnterContext): table|nil
---@field run fun(ctx: SmartEnterContext, match: table): boolean|nil

local matchers = require("smart_enter.matchers")

local M = {}

--- Turn a rule spec into a { match, run } pair with both halves resolved.
---@param rule SmartEnterRule
---@return SmartEnterNormalRule
function M.normalize(rule)
	local match = rule.match
	if not match then
		if rule.env or rule.envs then
			match = matchers.ts_env(rule.envs or { rule.env })
		elseif rule.pattern then
			match = matchers.pattern(rule.pattern)
		else
			match = function()
				return {}
			end
		end
	end

	local run = rule.handle
	if not run then
		if rule.item then
			run = require("smart_enter.actions").item(rule.item)
		else
			run = function(ctx)
				ctx.split(rule.append, ctx.ws .. (rule.prefix or ""))
				return true
			end
		end
	end

	return { match = match, run = run }
end

--- Try each normalized rule in order and run the first whose matcher fires.
---@param rules SmartEnterNormalRule[]
---@param ctx SmartEnterContext
---@return boolean handled true when a rule handled the key
function M.evaluate(rules, ctx)
	for _, r in ipairs(rules) do
		local m = r.match(ctx)
		if m then
			if r.run(ctx, m) ~= false then
				return true
			end
		end
	end
	return false
end

return M
