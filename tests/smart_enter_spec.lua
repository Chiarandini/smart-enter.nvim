-- Regression tests for smart-enter's rule engine and presets.
--
-- Run: tests/run.sh   (or luafile this from any nvim)

-- Bootstrap the plugin onto runtimepath from this file's own location, so the
-- suite runs regardless of how nvim was launched (a full config may have
-- rebuilt 'runtimepath' by now).
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":h:h")
vim.opt.runtimepath:prepend(root)
package.loaded["smart_enter"] = nil

local se = require("smart_enter")

local passed, failed = 0, 0

local function eq(name, got, want)
	if vim.deep_equal(got, want) then
		passed = passed + 1
	else
		failed = failed + 1
		print(string.format("FAIL %s\n  got:  %s\n  want: %s",
			name, vim.inspect(got), vim.inspect(want)))
	end
end

-- Set up a scratch buffer with `lines` and filetype `ft`, put the cursor at
-- (row, col) [1-indexed row, 0-indexed col], run dispatch(), return the
-- resulting lines and the new cursor.
local function run(ft, lines, row, col)
	-- <S-CR> fires in insert mode, where the cursor may sit one past the last
	-- char. Headless runs in normal mode (which clamps), so allow the extra
	-- column to reproduce the real end-of-line insert position.
	vim.o.virtualedit = "onemore"
	local buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
	vim.bo[buf].filetype = ft
	vim.api.nvim_set_current_buf(buf)
	vim.api.nvim_win_set_cursor(0, { row, col })
	local handled = se.dispatch()
	local out = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
	local cur = vim.api.nvim_win_get_cursor(0)
	vim.api.nvim_buf_delete(buf, { force = true })
	return out, cur, handled
end

se.setup({
	key = false,   -- don't touch the real <S-CR> during tests
	filetypes = {
		markdown = { preset = "markdown" },
		-- Pattern-only fake filetypes so the rule engine (declarative append,
		-- prefix, and item indentation) can be exercised without the latex
		-- parser.
		fakelatex = { rules = { { pattern = "^%s*ROW", append = "\\\\", prefix = "&= " } } },
		fakeitem  = { rules = { { pattern = "^", item = "\\item " } } },
		fakearrow = { rules = { { pattern = "^", item = "\\item[($\\Rw$)] " } } },
		fakekeep  = { rules = { { pattern = "^", item = { text = "\\item ", exit_empty = false } } } },
		fakealpha = { rules = { { pattern = "^", item = { text = "\\item[{})] ", counter = "alpha" } } } },
		fakeroman = { rules = { { pattern = "^", item = { text = "{}) ", counter = "roman" } } } },
		["*"]     = { rules = { { pattern = "^WILD", prefix = "wild " } } },
	},
})

-- Markdown: unordered continuation.
do
	local out = run("markdown", { "- foo" }, 1, 5)
	eq("md unordered continue", out, { "- foo", "- " })
end

-- Markdown: ordered increment.
do
	local out = run("markdown", { "  3. bar" }, 1, 8)
	eq("md ordered increment", out, { "  3. bar", "  4. " })
end

-- Markdown: checkbox continuation.
do
	local out = run("markdown", { "- [x] done" }, 1, 10)
	eq("md checkbox continue", out, { "- [x] done", "- [ ] " })
end

-- Markdown: empty item exits the list (marker dropped, no new line).
do
	local out = run("markdown", { "  - " }, 1, 4)
	eq("md empty item exits", out, { "  " })
end

-- Declarative append + prefix + auto-indent (fakelatex).
do
	local out, cur = run("fakelatex", { "\tROW one" }, 1, 8)
	eq("declarative append/prefix", out, { "\tROW one\\\\", "\t&= " })
	eq("declarative cursor at end of prefix", cur, { 2, 4 })   -- "\t&= " = 4 bytes
end

-- actions.item: a continued item on a soft-wrapped line indents to the item's
-- \item, not to the deeper continuation indent. "        wrapped..." is 28
-- bytes; "    \item " is 10 bytes.
do
	local out, cur = run("fakeitem", {
		"    \\item first line",
		"        wrapped continuation",
	}, 2, 28)
	eq("item indent anchors to \\item, not wrap", out, {
		"    \\item first line",
		"        wrapped continuation",
		"    \\item ",
	})
	eq("item indent cursor at end of \\item", cur, { 2 + 1, 10 })
end

-- actions.item derives its anchor from the template's leading macro, so a
-- custom \item[...] entry lines up with the prior one.
do
	local out = run("fakearrow", { "  \\item[($\\Rw$)] premise" }, 1, 24)
	eq("templated item continues at same indent", out, {
		"  \\item[($\\Rw$)] premise",
		"  \\item[($\\Rw$)] ",
	})
end

-- Exit on empty: pressing on an entry that is only its marker clears it.
do
	local out, cur = run("fakeitem", { "  \\item " }, 1, 8)
	eq("item exits on empty", out, { "  " })
	eq("item exit cursor at indent", cur, { 1, 2 })
end

-- exit_empty = false keeps continuing even on an empty entry.
do
	local out = run("fakekeep", { "  \\item " }, 1, 8)
	eq("item keeps empty entry when exit_empty=false", out, { "  \\item ", "  \\item " })
end

-- Counter: alpha marker increments a -> b.
do
	local out = run("fakealpha", { "\\item[a)] first" }, 1, 15)
	eq("alpha counter increments", out, { "\\item[a)] first", "\\item[b)] " })
end

-- Counter: alpha rolls z -> aa.
do
	local out = run("fakealpha", { "\\item[z)] last" }, 1, 14)
	eq("alpha counter rolls over", out, { "\\item[z)] last", "\\item[aa)] " })
end

-- Counter: roman marker increments iii -> iv.
do
	local out = run("fakeroman", { "iii) third" }, 1, 10)
	eq("roman counter increments", out, { "iii) third", "iv) " })
end

-- Markdown: continue an unordered item from a hard-wrapped continuation line.
-- "  wrapped tail" is 14 bytes; the new "- " aligns with the original marker.
do
	local out = run("markdown", { "- some long item", "  wrapped tail" }, 2, 14)
	eq("md continues unordered from wrapped line", out,
		{ "- some long item", "  wrapped tail", "- " })
end

-- Markdown: continue an ordered item from a wrapped line ("   tail" is 3-space
-- hang indent under "1. "); the number increments.
do
	local out = run("markdown", { "3. long ordered", "   tail here" }, 2, 12)
	eq("md continues ordered from wrapped line", out,
		{ "3. long ordered", "   tail here", "4. " })
end

-- Markdown: a paragraph after a list (blank line between) is not swept in.
do
	local _, _, handled = run("markdown", { "- item", "", "para" }, 3, 4)
	eq("md wrapped rule stops at a blank line", handled, false)
end

-- Wildcard "*" rules apply to a filetype with no config of its own.
do
	local out, _, handled = run("randomft", { "WILD one" }, 1, 8)
	eq("wildcard rule applies to any filetype", out, { "WILD one", "wild " })
	eq("wildcard rule counts as handled", handled, true)
end

-- Wildcard runs after the filetype's own rules (specific wins).
do
	-- fakelatex has its own rule; a WILD line there is not matched by it, so
	-- the wildcard still applies.
	local out = run("fakelatex", { "WILD two" }, 1, 8)
	eq("wildcard still applies under a configured ft", out, { "WILD two", "wild " })
end

-- No rule for the filetype and no wildcard match -> fallback.
do
	local _, _, handled = run("randomft", { "plain" }, 1, 5)
	eq("unmatched ft falls back", handled, false)
end

-- LaTeX environment detection via Treesitter. Skipped when the latex parser
-- isn't installed (e.g. a bare -u NONE run).
do
	local buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
		"\\begin{exercise}", "foo", "\\end{exercise}",
	})
	vim.bo[buf].filetype = "tex"
	vim.api.nvim_set_current_buf(buf)
	vim.api.nvim_win_set_cursor(0, { 2, 0 })

	local has_parser = pcall(function()
		vim.treesitter.get_parser(buf, "latex"):parse()
	end)
	if has_parser then
		local matchers = require("smart_enter.matchers")
		local ctx = require("smart_enter.context").build()
		eq("ts_env detects enclosing exercise",
			matchers.ts_env({ "exercise" })(ctx), { env = "exercise" })
		eq("ts_env rejects a non-enclosing env",
			matchers.ts_env({ "align" })(ctx), nil)
	else
		print("SKIP ts_env (latex parser not installed)")
	end
	vim.api.nvim_buf_delete(buf, { force = true })
end

print(string.format("\nsmart-enter: %d passed, %d failed", passed, failed))
if failed > 0 then vim.cmd("cq") end
