--- @type processor
local function json_processor(push_crumb)
	--- @type TSNode | nil
	local last_node = nil

	--- @param node TSNode
	return function(node)
		local type = node:type()

		if type == "array" then
			local found = nil
			if last_node then
				for index, value in ipairs(node:named_children()) do
					if value:equal(last_node) then
						local row, col = node:start()
						push_crumb({ "[" .. (index - 1) .. "]" }, { row = row, col = col })
						break
					end
				end
			end
		end

		if type == "pair" then
			local key_node = node:field("key")[1]
			local value_node = node:field("value")[1]
			local suffix = nil

			if key_node then
				push_crumb({ key_node })
			end
		end
		last_node = node
	end
end

return json_processor