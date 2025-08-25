local M = {}

local function load_processor(lang)
	return function ()
		return require('nvim-breadcrumbs.processors.'..lang)
	end
end

--- @type processor_loader_map
M.default_processors_loader = {
		-- typescript
		typescript = load_processor('typescript'),
		javascript = load_processor('typescript'),
		typescriptreact = load_processor('typescript'),
		javascriptreact = load_processor('typescript'),
		tsx = load_processor('typescript'),
		jsx = load_processor('typescript'),

		-- json
		json = load_processor('json'),
		jsonc = load_processor('json'),
		json5 = load_processor('json'),

		-- lua
		lua = load_processor('lua'),
}

return M