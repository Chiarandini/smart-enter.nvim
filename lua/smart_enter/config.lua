--- Resolved, read only config for smart-enter. setup() calls apply(); the rest
--- of the plugin calls get().

---@class SmartEnterFiletypeConfig
---@field preset? string|SmartEnterRule[] a preset name or an inline rule list
---@field rules? SmartEnterRule[] rules tried before the preset's (they win)

---@class SmartEnterConfig
---@field key string|false insert mode key that dispatches; false skips the mapping
---@field fallback "newline"|"cr"|false|fun(ctx: SmartEnterContext) action when no rule matches
---@field filetypes table<string, SmartEnterFiletypeConfig>

local M = {}

---@type SmartEnterConfig
local defaults = {
	-- Insert mode key that dispatches the smart action. Set to false to skip
	-- the global mapping and drive dispatch() from your own keymap. Requires a
	-- terminal that distinguishes <S-CR> from <CR> (Kitty, WezTerm, iTerm2 with
	-- the CSI u profile, most GUIs).
	key = "<S-CR>",

	-- What happens when no rule matches, for any filetype.
	--   "newline"      newline without comment leader continuation (strips r
	--                  and o from 'formatoptions' for the one <CR>, restores)
	--   "cr"           a literal <CR> (keeps comment continuation and autoindent)
	--   false          do nothing
	--   function(ctx)  arbitrary handler
	fallback = "newline",

	-- Per filetype rules. Each entry is { preset = <name|list>, rules = {...} }.
	-- Effective order is user `rules` first (they win), then the preset's. A
	-- ["*"] entry applies to every filetype, after that filetype's own rules.
	--   filetypes = {
	--     markdown = { preset = "markdown" },
	--     tex      = { preset = "latex", rules = { { env = "exercise", item = "\\Question " } } },
	--     ["*"]    = { rules = { <a rule for every filetype> } },
	--   }
	filetypes = {},
}

---@type SmartEnterConfig
local resolved = vim.deepcopy(defaults)

--- Merge user opts over the defaults.
---@param opts? table
function M.apply(opts)
	resolved = vim.tbl_deep_extend("force", vim.deepcopy(defaults), opts or {})
end

--- The resolved config.
---@return SmartEnterConfig
function M.get()
	return resolved
end

return M
