--- :checkhealth smart_enter

local M = {}

--- Is a Treesitter parser for `lang` available?
---@param lang string
---@return boolean
local function has_parser(lang)
	return pcall(vim.treesitter.language.inspect, lang)
end

function M.check()
	local health = vim.health
	health.start("smart-enter")

	if vim.fn.has("nvim-0.10") == 1 then
		health.ok("Neovim " .. tostring(vim.version()))
	else
		health.error("Neovim 0.10 or newer is required")
	end

	local cfg = require("smart_enter.config").get()

	if cfg.key == false then
		health.info("key = false (no global mapping; drive dispatch() yourself)")
	else
		health.ok("key = " .. tostring(cfg.key))
		health.info(
			"the key must reach Neovim distinctly. <S-CR> needs a terminal that "
			.. "sends it separately from <CR> (Kitty, WezTerm, iTerm2 with the "
			.. "CSI u profile, most GUIs). Verify with :execute 'normal! i' then "
			.. "the key, or map a different one via opts.key.")
	end

	health.info("fallback = "
		.. (type(cfg.fallback) == "function" and "<function>" or tostring(cfg.fallback)))

	local fts = vim.tbl_keys(cfg.filetypes)
	table.sort(fts)
	if #fts == 0 then
		health.warn("no filetypes configured; every press uses the fallback")
	else
		health.ok("filetypes: " .. table.concat(fts, ", "))
	end

	-- The built in latex preset resolves environments with the latex parser.
	local needs_latex = false
	for _, ftcfg in pairs(cfg.filetypes) do
		if ftcfg.preset == "latex" then
			needs_latex = true
			break
		end
	end
	if needs_latex then
		if has_parser("latex") then
			health.ok("latex Treesitter parser is installed")
		else
			health.warn(
				"a filetype uses the latex preset, but the latex Treesitter "
				.. "parser is not installed; environment rules will not match. "
				.. "Install it (for example :TSInstall latex).")
		end
	end
end

return M
