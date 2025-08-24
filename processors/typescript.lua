--- @type processor
local function typescript_processor(push_crumb, bfr)
	--- @type TSNode | nil
	local last_node = nil
	local stuff = {
		method_definition = true,
		class_declaration = true,
		function_declaration = true,
	}
	local test_functions = {
		it = true,
		describe = true,
	}

	return function(node)
		local type = node:type()
		local crumb = type
		if stuff[type] then
			local name_node = node:field("name")[1]

			if name_node then
				local prev_sibling = name_node:prev_sibling()
				local to_push = {}
				if prev_sibling and (prev_sibling:type() == "get" or prev_sibling:type() == "set") then
					-- table.insert(crumbs, 1, '['.. prev_sibling:type() ..']')
					to_push = { prev_sibling, " " }
				end

				table.insert(to_push, name_node)
				push_crumb(to_push)
			end
		end

		if type == "variable_declarator" then
			local value_node = node:field("value")[1]
			local name_node = node:field("name")[1]

			if value_node and value_node:type() == "arrow_function" then
				if name_node then
					-- table.insert(crumbs, 1, vim.treesitter.get_node_text(name_node, 0))
					push_crumb({ name_node })
				end
			end
		end

		if type == "arguments" then
			if
					last_node
					and last_node:type() == "arrow_function"
					and node:parent()
					and node:parent():type() == "call_expression"
			then
				local function_node = node:parent():field("function")[1]
				if function_node then
					local func_name = vim.treesitter.get_node_text(function_node, bfr)
					local to_push = nil

					-- Special case to print the description of the test case in jest tests
					if test_functions[func_name] then
						local args_node = node:parent():field("arguments")[1]
						local first_arg = args_node and args_node:named_child(0)

						if first_arg and first_arg:type() == "string" then
							to_push = { function_node, "(", first_arg, ")" }
						end
					end

					push_crumb(to_push or { function_node, "()" })
				end
			end
		end

		if type == "jsx_self_closing_element" then
			local name_node = node:field("name")[1]

			if name_node then
				-- table.insert(crumbs, 1, '<'..vim.treesitter.get_node_text(name_node, 0)..' />')
				push_crumb({ "<", name_node, " />" })
			end
		end

		if type == "jsx_element" or type == "jsx_self_closing_element" then
			local open_node = node:field("open_tag")[1]
			local name_node = open_node and open_node:field("name")[1]

			if name_node then
				-- table.insert(crumbs, 1, '<'..vim.treesitter.get_node_text(name_node, 0)..'>')
				push_crumb({ "<", name_node, ">" })
			end
		end

		last_node = node
	end
end

return typescript_processor