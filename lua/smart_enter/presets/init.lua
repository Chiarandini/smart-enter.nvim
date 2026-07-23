--- Preset registry. A preset is a list of rule specs (see rules.lua). get()
--- accepts a preset name (loaded from smart_enter.presets.<name>) or a rule
--- list passed inline.

local M = {}

---@type table<string, SmartEnterRule[]|false>
local cache = {}

--- Resolve a preset to its rule list.
---@param preset string|SmartEnterRule[]|nil a preset name, an inline rule list, or nil
---@return SmartEnterRule[]|nil
function M.get(preset)
	if type(preset) == "table" then
		return preset
	end
	if preset == nil then
		return nil
	end
	if cache[preset] ~= nil then
		return cache[preset] or nil
	end
	local ok, rules = pcall(require, "smart_enter.presets." .. preset)
	cache[preset] = ok and rules or false
	return cache[preset] or nil
end

return M
