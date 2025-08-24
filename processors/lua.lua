--- @type processor
local function lua_processor(push_crumb)
	local context = nil

	--- @param node TSNode
	return function(node)
		local type = node:type()

		if context ~= nil then
			local last = context
			context = nil

			if type == "expression_list" and last == "function_definition" then
				context = type
			end

			if type == "return_statement" and last == "expression_list" then
				local child = node:child(0)
				if child and child:type() == "return" then
					push_crumb({ child })
				end
			end

			if type == "assignment_statement" and last == "expression_list" then
				local child = node:named_child(0)
				if child and child:type() == "variable_list" then
					local name_node = child:field("name")[1]

					if name_node then
						push_crumb({ name_node })
					end
				end
			end
		end

		if type == "function_declaration" then
			local name_node = node:field("name")[1]

			if name_node then
				push_crumb({ name_node })
			end
		end

		if type == "function_definition" then
			context = type
		end
	end
end

return lua_processor