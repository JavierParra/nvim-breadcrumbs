local helpers = require('nvim-breadcrumbs.helpers')
local M = {}
--- @alias crumbs { [1]: string, captures: table, hl_groups: string[]}[]
--- @alias push_crumb fun(nodes: (TSNode | string)[])
--- @alias processor fun(push_crumb: push_crumb, bfr: number): fun(node: TSNode)
--- @alias crumb { [1]: string, captures: table, hl_groups: string[]}[]
--- @alias processor_loader_map { [string]: nil | fun(): processor }

--- @class opts
--- @field processors processor_loader_map
--- @field debug boolean | nil
--- @field throttle_ms integer | nil
--- @field max_depth integer | nil

local _options = {
	debug = false,
	throttle_ms = 200,
	max_depth = 50,
	setup_called = false,
}

--- @type processor_loader_map
local processors = {}

--- @param captures { capture: string, lang: string }[]
--- @return string[]
local function captures_to_hl_groups(captures)
	local groups = {}

	for _, cap in pairs(captures) do
		local group = "@" .. cap.capture .. (cap.lang and "." .. cap.lang or "")
		table.insert(groups, group)
	end

	return groups
end

--- @return processor | nil
local function get_processor(lang)
	local loader = processors[lang]

	if not loader then
		return nil
	end

	return loader()
end

local ui_state = {
	--- @type integer
	win = nil,
	--- @type integer
	augr = nil,
	--- @type function | nil
	cancel_timer = nil,
	--- @type crumbs | nil
	crumbs = nil
}

local ensure_setup = function()
	if not _options.setup_called then
		M.setup()
	end
end

local options = function()
	ensure_setup()
	return _options
end

local is_loaded = function()
	return ui_state.win ~= nil or ui_state.augr ~= nil
end

--- @param crumbs { [1]: string, captures: table, hl_groups: string[]}[] | nil
--- @param buf integer
local function print_crumbs(crumbs, buf)
	if not is_loaded() then
		return
	end
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, {})

	ui_state.crumbs = crumbs
	if not crumbs then
		return
	end

	local col = 0
	local ns = vim.api.nvim_create_namespace("jp_nvim_breadcrumbs")
	local crumbs_length = #crumbs

	for i, crumb in pairs(crumbs) do
		for _, part in pairs(crumb) do
			local txt = part[1]
			local len = vim.fn.strlen(txt)

			vim.api.nvim_buf_set_text(buf, 0, col, 0, col, { txt })

			vim.api.nvim_buf_set_extmark(buf, ns, 0, col, {
				end_row = 0,
				end_col = col + len,
				hl_group = part.hl_groups,
			})
			col = col + len
		end

		local sep = "  "
		if i < crumbs_length then
			vim.api.nvim_buf_set_text(buf, 0, col, 0, col, { sep })

			col = col + vim.fn.strlen(sep)
		end
	end
end

--- @param opts opts | nil
M.setup = function(opts)
	opts = opts or {}
	if not opts.processors then
		processors = require('nvim-breadcrumbs.processors').default_processors_loader
	else
		processors = opts.processors
	end

	if opts.debug then
		_options.debug = true
	end

	_options.setup_called = true
end

--- @param opts { debug: boolean | nil, bfr: integer | nil } | nil
--- @return crumb | nil
M.build = function(opts)
	local node = vim.treesitter.get_node()
	local last_node = nil
	local all = {}
	local crumbs = {}
	local i = 0
	opts = opts or {}
	local bfr = opts.bfr or 0
	local debug = opts.debug or options().debug
	local lang = vim.api.nvim_get_option_value("filetype", { buf = bfr })

	--- @type push_crumb
	local push_crumb = function(nodes)
		--- @param node TSNode
		--- @param bfr integer
		--- @param res crumb | nil
		local function descend(node, bfr, res)
			local result = res or {}

			if node:child_count() == 0 then
				local row, col = node:start()
				local captures = vim.treesitter.get_captures_at_pos(bfr, row, col)

				table.insert(result, {
					vim.treesitter.get_node_text(node, bfr),
					captures = captures,
					hl_groups = captures_to_hl_groups(captures),
				})
				return result
			end

			for child, field in node:iter_children() do
				descend(child, bfr, result)
			end

			return result
		end

		--- @type crumb
		local res = {}

		for _, node in pairs(nodes) do
			if type(node) == "string" then
				table.insert(res, {
					node,
					captures = {},
					hl_groups = {},
				})
			else
				local crbs = descend(node, bfr)
				if crbs then
					for _, crb in pairs(crbs) do
						table.insert(res, crb)
					end
				end
			end
		end

		table.insert(crumbs, 1, res)
	end

	local processor = get_processor(lang)

	if not processor then
		if debug then
			vim.notify('[nvim-breadcrumbs] missing processor for ' .. lang, vim.log.levels.DEBUG)
		end
		return nil
	end

	local process_node = processor(push_crumb, bfr)

	while node do
		if debug then
			table.insert(all, node:type())
		end

		local success = pcall(process_node, node)

		if not success and options().debug then
			vim.notify("[nvim-breadcrumbs] Processing node for lang=" .. lang .. " failed", vim.log.levels.WARN)
		end

		node = node:parent()
		i = i + 1
		if i == options().max_depth then
			vim.notify("[nvim-breadcrumbs] Giving up after " .. options().max_depth .. " parents", vim.log.levels.WARN)
			return
		end
	end

	if debug then
		vim.notify('[nvim-breadcrumbs] ' .. vim.inspect(all), vim.log.levels.DEBUG)
	end

	return crumbs
end

M.hide = function()
	if ui_state.augr then
		vim.api.nvim_clear_autocmds({
			group = ui_state.augr,
		})
	end

	if ui_state.win and vim.api.nvim_win_is_valid(ui_state.win) then
		vim.api.nvim_win_close(ui_state.win, true)
	end

	if ui_state.cancel_timer then
		ui_state.cancel_timer()
	end

	for _, k in pairs(ui_state) do
		ui_state[k] = nil
	end
end

M.show = function(win)
	ensure_setup()

	if ui_state.augr then
		vim.api.nvim_clear_autocmds({
			group = ui_state.augr,
		})
	end
	if ui_state.win then
		vim.api.nvim_win_close(ui_state.win, true)
		ui_state.win = nil
		return
	end
	local crumbs = M.build()
	if not crumbs then
		return
	end
	local buf = vim.api.nvim_create_buf(false, true)
	local win_width = vim.api.nvim_win_get_width(win or 0)
	local float_height = 1
	local float_width = win_width - 1

	local opts = {
		relative = "laststatus",
		width = vim.o.columns,
		height = float_height,
		row = 0,
		anchor = "SW",
		col = 1,
		style = "minimal",
	}
	local float = vim.api.nvim_open_win(buf, false, opts)

	ui_state.win = float

	ui_state.augr = vim.api.nvim_create_augroup("breadcrumbs", { clear = true })

	local on_cursor_moved = function()
		print_crumbs(M.build({ debug = false, bfr = 0 }), buf)
	end

	local throttled_on_cursor_moved, cancel_cursor_moved = helpers.throttle(
		on_cursor_moved,
		options().throttle_ms,
		{
			leading = false,
			trailing = true
		}
	)

	ui_state.cancel_timer = cancel_cursor_moved

	vim.api.nvim_create_autocmd({ "CursorMoved" }, {
		group = ui_state.augr,
		callback = function()
			throttled_on_cursor_moved()
			local float_y = vim.api.nvim_win_get_position(float)[1]
			local win_y = vim.api.nvim_win_get_position(0)[1]
			local cursor_win_line = vim.fn.winline()
			local cursor_screen_row = win_y + cursor_win_line

			-- If the cursor is where our float window is drawn, scroll by 1 line
			if cursor_screen_row == float_y then
				vim.fn.winrestview({ topline = vim.fn.winsaveview().topline + 1 })
			end
		end
	})

	vim.api.nvim_create_autocmd({ "BufUnload" }, {
		group = ui_state.augr,
		callback = function()
			M.hide()
		end,
		buffer = buf,
	})

	print_crumbs(crumbs, buf)
end

return M