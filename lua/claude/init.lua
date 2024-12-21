local M = {}

local unix = require("socket.unix")
local client = nil
-- local uv = vim.loop
local pending_callbacks = {}

function M.connect()
	if client then
		return true
	end
	client = unix()
	local success, err = client:connect("/tmp/nvim-python.sock")
	if not success then
		client = nil
		return false, err
	end
	client:settimeout(0) -- make socket non-blocking
	return true
end

function M.disconnect()
	if client then
		client:close()
		client = nil
	end
end

-- helper function to schedule callback in the main event loop
local function schedule_callback(callback, ...)
	local args = { ... }
	vim.schedule(function()
		callback(unpack(args))
	end)
end

function M.send_to_python(text, callback)
	if not client and not M.connect() then
		if callback then
			schedule_callback(callback, nil, "Failed to connect")
		end
		return
	end

	local request_id = tostring(math.random(1000000))
	local full_message = request_id .. "\n" .. text .. "\n---END---\n"

	-- store the callback
	pending_callbacks[request_id] = callback

	local response = ""
	local function read_handler()
		if not client then
			if callback then
				schedule_callback(callback, nil, "Failed to connect")
			end
			return
		end
		while true do
			local chunk, err = client:receive("*l")
			if err == "timeout" then
				-- no more data available now, schedule next check
				vim.defer_fn(read_handler, 10)
				break
			elseif err then
				if callback then
					schedule_callback(callback, nil, "Error receiving response: " .. err)
				end
				M.disconnect()
				break
			end

			if chunk == "---END---" then
				-- find the request ID in the response
				local lines = vim.split(response, "\n")
				local resp_id = table.remove(lines, 1)
				local cb = pending_callbacks[resp_id]
				if cb then
					pending_callbacks[resp_id] = nil
					schedule_callback(cb, table.concat(lines, "\n"))
				end
				break
			end
			response = response .. chunk .. "\n"
		end
	end
	-- send the request
	local ok, err = pcall(function()
		if not client then
			error("No active connection")
		end
		client:send(full_message)
	end)

	if not ok then
		M.disconnect()
		if callback then
			schedule_callback(callback, nil, "Error sending request: " .. err)
		end
		return
	end

	-- start reading the response
	read_handler()
end

function M.send_visual_selection()
	local start_pos = vim.fn.getpos("'<")
	local end_pos = vim.fn.getpos("'>")
	local lines = vim.fn.getline(start_pos[2], end_pos[2])
	local buffer_path = vim.api.nvim_buf_get_name(0)
	local bufnr = vim.api.nvim_get_current_buf()

	local text
	if type(lines) == "table" then
		text = table.concat(lines, "\n")
	else
		text = lines
	end

	local data = {
		filename = buffer_path,
		content = text,
	}

	local json = vim.fn.json_encode(data)
	vim.notify("Sending request to Claude...", vim.log.levels.INFO)

	M.send_to_python(json, function(response, error)
		if error then
			vim.notify("Error: " .. error, vim.log.levels.ERROR)
			return
		end

		local insert_position = end_pos[2]
		local response_lines = vim.split(response, "\n")
		local formatted_response = { "" }
		table.insert(formatted_response, "## Claude")
		for _, line in ipairs(response_lines) do
			table.insert(formatted_response, line)
		end
		table.insert(formatted_response, "___")

		if vim.api.nvim_buf_is_valid(bufnr) then
			vim.api.nvim_buf_set_lines(bufnr, insert_position, insert_position, false, formatted_response)
		else
			vim.notify("Buffer no longer valid", vim.log.levels.WARN)
		end
	end)
end

return M
