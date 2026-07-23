--- smart-enter.nvim: a context dispatched newline.
---
--- One insert mode key (default <S-CR>) runs the first matching rule for the
--- current filetype, continuing a LaTeX environment, a Markdown list, a
--- blockquote, and so on, and falls back to a plain newline everywhere else.
--- Rules are plain data; extend per filetype through setup() opts. See
--- :help smart-enter.

local M = {}

--- filetype to normalized rule list. Rebuilt on setup(). Filetypes rarely
--- change mid session, so caching keeps dispatch allocation free on the hot
--- path.
---@type table<string, SmartEnterNormalRule[]>
local cache = {}

--- Resolve and cache the normalized rules for a filetype. User rules come
--- first so they win over the preset's.
---@param ft string
---@return SmartEnterNormalRule[]
local function rules_for(ft)
	if cache[ft] then
		return cache[ft]
	end

	local cfg   = require("smart_enter.config").get()
	local rules = require("smart_enter.rules")
	local list  = {}

	-- Append a filetype config's user rules (they win), then its preset's.
	local function add(ftcfg)
		if not ftcfg then
			return
		end
		for _, r in ipairs(ftcfg.rules or {}) do
			list[#list + 1] = rules.normalize(r)
		end
		for _, r in ipairs(require("smart_enter.presets").get(ftcfg.preset) or {}) do
			list[#list + 1] = rules.normalize(r)
		end
	end

	add(cfg.filetypes[ft])
	if ft ~= "*" then
		add(cfg.filetypes["*"]) -- rules for every filetype, after the specific ones
	end

	cache[ft] = list
	return list
end

--- Insert a plain newline that does not re-insert a comment leader: strip r
--- and o from 'formatoptions' for the single <CR>, then restore once the
--- change settles. The TextChangedI fires after the buffer edit, so the
--- restore cannot race the <CR>.
---@param buf integer
local function fallback_newline(buf)
	local fo = vim.bo[buf].formatoptions
	local stripped = fo:gsub("[ro]", "")
	if stripped ~= fo then
		vim.bo[buf].formatoptions = stripped
		vim.api.nvim_create_autocmd("TextChangedI", {
			buffer   = buf,
			once     = true,
			callback = function()
				vim.bo[buf].formatoptions = fo
			end,
		})
	end
	vim.api.nvim_feedkeys(vim.keycode("<CR>"), "n", false)
end

--- Run the configured fallback for a context that no rule handled.
---@param ctx SmartEnterContext
local function run_fallback(ctx)
	local fb = require("smart_enter.config").get().fallback
	if fb == false then
		return
	end
	if type(fb) == "function" then
		fb(ctx)
		return
	end
	if fb == "cr" then
		vim.api.nvim_feedkeys(vim.keycode("<CR>"), "n", false)
		return
	end
	fallback_newline(ctx.buf)
end

--- Run the smart action for the current context. Safe to bind from your own
--- keymap.
---
--- Pass `{ fallback = false }` to skip the built in fallback and only report
--- whether a rule matched. Use this to compose with autopairs or completion
--- when binding to plain <CR>: call dispatch first, and run your own <CR>
--- behaviour when it returns false.
---@param opts? { fallback?: boolean }
---@return boolean handled true when a rule handled the key
function M.dispatch(opts)
	local ctx     = require("smart_enter.context").build()
	local handled = require("smart_enter.rules").evaluate(rules_for(ctx.filetype), ctx)
	if not handled and (not opts or opts.fallback ~= false) then
		run_fallback(ctx)
	end
	return handled
end

--- Report the enclosing environment chain at the cursor, as smart-enter sees
--- it, plus which configured rules would match. Meant for `:lua` or a debug
--- command when a rule is not firing where you expect.
---@param lang? string parser language for env detection (default "latex")
---@return string report a human readable multiline summary
function M.inspect(lang)
	local ctx      = require("smart_enter.context").build()
	local matchers = require("smart_enter.matchers")
	local names, err = matchers.env_chain(ctx, lang)

	local lines = {
		"smart-enter inspect",
		("  filetype   : %s"):format(ctx.filetype),
		("  cursor     : row %d, col %d"):format(ctx.row, ctx.col),
		("  env chain  : %s"):format(#names > 0 and table.concat(names, " > ") or "(none)"),
	}
	if err then
		lines[#lines + 1] = ("  note       : %s"):format(err)
	end

	local rules = rules_for(ctx.filetype)
	lines[#lines + 1] = ("  rules (%d) for this filetype, first match wins:"):format(#rules)
	for i, r in ipairs(rules) do
		local m = r.match(ctx)
		lines[#lines + 1] = ("    %d. %s"):format(i, m and "MATCH " .. vim.inspect(m):gsub("%s+", " ") or "no")
	end

	local report = table.concat(lines, "\n")
	vim.notify(report, vim.log.levels.INFO)
	return report
end

--- Apply configuration and, unless key is false, install the insert mode map.
---@param opts? table see smart_enter.config defaults
function M.setup(opts)
	require("smart_enter.config").apply(opts)
	cache = {}

	local cfg = require("smart_enter.config").get()
	if cfg.key then
		vim.keymap.set("i", cfg.key, function()
			M.dispatch()
		end, { silent = true, desc = "smart enter" })
	end
end

return M
