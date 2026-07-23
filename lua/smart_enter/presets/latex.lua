--- LaTeX environment continuation.
---
--- Environment detection is Treesitter based (matchers.ts_env), so there is no
--- VimTeX dependency and nesting is honoured. For math rows, `append` is glued
--- to the current line at the cursor (the row separator "\\") and `prefix`
--- opens the next line. For lists, `item` anchors the indent to the current
--- entry, so continuing a soft wrapped item still lines the new "\item" up
--- with the item it follows.

return {
	-- Row separated math: close the row with "\\", open a bare indented line.
	{
		envs = {
			"cases", "gather", "gather*", "multline", "multline*",
			"matrix", "pmatrix", "bmatrix", "Bmatrix", "vmatrix", "Vmatrix", "smallmatrix",
		},
		append = "\\\\",
	},

	-- Alignment environments: "\\" plus a fresh "&= " alignment point.
	{
		envs   = { "align", "align*", "alignat", "alignat*", "aligned", "flalign", "flalign*" },
		append = "\\\\",
		prefix = "&= ",
	},

	-- List environments: a new "\item ", indented to the current item.
	{
		envs = { "itemize", "enumerate", "description" },
		item = "\\item ",
	},
}
