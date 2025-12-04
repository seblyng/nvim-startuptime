local M = {}

local ns_id = vim.api.nvim_create_namespace("startuptime")

local EVENT_TYPES = {
	sourcing = 0,
	other = 1,
}

---@param numbers number[]
---@return { mean: number, std: number }
local function stats(numbers)
	local sum, sq_sum = 0, 0
	for _, n in ipairs(numbers) do
		sum, sq_sum = sum + n, sq_sum + n * n
	end
	local mean = sum / #numbers
	return { mean = mean, std = math.sqrt((sq_sum - sum * mean) / (#numbers - 1)) }
end

---@param file string
---@return table[], number
local function parse(file)
	local tfields = { "start", "finish", "elapsed", "self", "self+sourced" }
	local items = {}
	local key_to_item = {}
	local occurrences = {}

	local skip_block = false
	for line in io.lines(file) do
		if line:find("^--- Startup times for process: Primary") then
			skip_block = true
		elseif line:find("^--- Startup times for process: Embedded") then
			skip_block = false
			occurrences = {}
		elseif not skip_block and #line ~= 0 and line:find("^%d") ~= nil then
			local idx = line:find(":")
			local times = {}
			for s in line:sub(1, idx - 1):gmatch("[^ ]+") do
				table.insert(times, tonumber(s))
			end

			local event = line:sub(idx + 2)
			local type = #times == 3 and EVENT_TYPES.sourcing or EVENT_TYPES.other

			local occ_key = type .. "-" .. event
			occurrences[occ_key] = (occurrences[occ_key] or 0) + 1

			local item = {
				event = event,
				occurrence = occurrences[occ_key],
				type = type,
				finish = { times[1] },
				start = { times[1] - times[2] },
				elapsed = type == EVENT_TYPES.other and { times[2] } or nil,
				self = type == EVENT_TYPES.sourcing and { times[3] } or nil,
				["self+sourced"] = type == EVENT_TYPES.sourcing and { times[2] } or nil,
			}

			-- Consolidate into items
			local key = type .. "-" .. item.occurrence .. "-" .. event
			local existing = key_to_item[key]
			if existing then
				for _, tfield in ipairs(tfields) do
					if item[tfield] then
						table.insert(existing[tfield], item[tfield][1])
					end
				end
				existing.tries = existing.tries + 1
			else
				item.tries = 1
				table.insert(items, item)
				item.idx = #items
				key_to_item[key] = item
			end
		end
	end

	local startup_time = 0
	for _, item in ipairs(items) do
		for _, tfield in ipairs(tfields) do
			if item[tfield] ~= nil then
				item[tfield] = stats(item[tfield])
			end
		end

		item.time = item.type == EVENT_TYPES.sourcing and item["self+sourced"].mean or item.elapsed.mean

		startup_time = math.max(startup_time, item.finish.mean)
	end

	table.sort(items, function(a, b)
		return a.time > b.time
	end)

	return items, startup_time
end

local BLOCKS = { "▏", "▎", "▍", "▌", "▋", "▊", "▉", "█" }

-- Create a visual plot line
local function create_plot(value, max_value, width)
	if max_value == 0 then
		return ""
	end

	local ratio = value / max_value
	local total_chars = ratio * width
	local full_blocks = math.floor(total_chars)
	local remainder = total_chars - full_blocks

	local plot = ""
	local block_char = BLOCKS[#BLOCKS]

	-- Add full blocks
	for _ = 1, full_blocks do
		plot = plot .. block_char
	end

	-- Add partial block
	if remainder > 0 and full_blocks < width then
		local block_idx = math.floor(remainder * #BLOCKS) + 1
		block_idx = math.min(block_idx, #BLOCKS)
		plot = plot .. BLOCKS[block_idx]
	end

	return plot
end

local function simplify_event(item)
	if item.type ~= EVENT_TYPES.sourcing then
		return item.event
	end

	local module = item.event:match("^require%('([^']+)'%)")
	if module then
		return module
	end

	local sourcing = item.event:match("^sourcing (.+)$")
	if sourcing then
		return vim.fn.fnamemodify(sourcing, ":t")
	end
end

local function create_output(items, startup_time)
	local lines = { string.format("%25s%.3f", "startup: ", startup_time) }
	local max_time = 0
	for _, item in ipairs(items) do
		if item.time > max_time then
			max_time = item.time
		end
	end

	table.insert(lines, string.format("%-50s  %7s  %7s  %s", "event", "time", "percent", "plot"))
	for _, item in ipairs(items) do
		local name = simplify_event(item)
		local event = #name > 50 and name:sub(1, 50 - 3) .. "..." or name
		local percent = (item.time / startup_time) * 100
		local plot = create_plot(item.time, max_time, 26)
		table.insert(lines, string.format("%-50s  %7.3f  %6.2f%%  %s", event, item.time, percent, plot))
	end

	return lines
end

-- Column layout: event (50) + "  " (2) + time (7) + "  " (2) + percent (7) + "  " (2) + plot
local function highlight(bufnr, items, lines)
	-- Highlight startup line (centered in event column)
	local colon = lines[1]:find(":")
	vim.api.nvim_buf_set_extmark(bufnr, ns_id, 0, colon - 8, { end_col = colon, hl_group = "Title" })
	vim.api.nvim_buf_set_extmark(bufnr, ns_id, 0, colon + 1, { end_col = #lines[1], hl_group = "Number" })

	-- Highlight header
	vim.api.nvim_buf_set_extmark(bufnr, ns_id, 1, 0, { end_line = 2, hl_group = "Type" })

	-- Highlight data rows
	for i, item in ipairs(items) do
		local row = i + 1 -- +1 for header
		local hl = item.type == EVENT_TYPES.sourcing and "String" or "Identifier"
		vim.api.nvim_buf_set_extmark(bufnr, ns_id, row, 0, { end_col = 50, hl_group = hl })
		vim.api.nvim_buf_set_extmark(bufnr, ns_id, row, 52, { end_col = 59, hl_group = "Number" })
		vim.api.nvim_buf_set_extmark(bufnr, ns_id, row, 61, { end_col = 68, hl_group = "Special" })
		vim.api.nvim_buf_set_extmark(bufnr, ns_id, row, 70, { end_col = #lines[row + 1], hl_group = "Normal" })
	end
end

local function setup_keymaps(bufnr, items, startup_time)
	-- Setup keymaps
	-- TODO(seb): Do not hardcode to gh...
	-- I want to use the same keymap as configured for vim.lsp.hover
	-- Do I need to create an in process language server for that?
	vim.keymap.set("n", "gh", function()
		local item = items[vim.api.nvim_win_get_cursor(0)[1] - 2]
		if not item then
			return vim.api.nvim_echo({ { "No details found", "WarningMsg" } }, false, {})
		end

		-- stylua: ignore start
		local fmt = function(t)
			return t.std ~= t.std and string.format("%.3f ms", t.mean) or string.format("%.3f ± %.3f ms", t.mean, t.std)
		end
		local parts = {
			{ "Event: ", "Title" }, { item.event .. "\n" },
			{ "Start: ", "Title" }, { fmt(item.start) .. "\n", "Number" },
			{ "Finish: ", "Title" }, { fmt(item.finish) .. "\n", "Number" },
		}

		if item.type == EVENT_TYPES.sourcing then
			vim.list_extend(parts, {
				{ "Self: ", "Title" }, { fmt(item.self) .. "\n", "Number" },
				{ "Self+sourced: ", "Title" }, { fmt(item["self+sourced"]) .. "\n", "Number" },
			})
		else
			vim.list_extend(parts, { { "Elapsed: ", "Title" }, { fmt(item.elapsed) .. "\n", "Number" } })
		end

		vim.list_extend(parts, {
			{ "Occurrence: ", "Title" }, { item.occurrence .. "\n", "Number" },
			{ "Tries: ", "Title" }, { tostring(item.tries), "Number" },
		})

		vim.api.nvim_echo(parts, false, {})
		-- stylua: ignore end
	end, { buffer = bufnr, silent = true, nowait = true })

	vim.keymap.set("n", "gf", function()
		local item = items[vim.api.nvim_win_get_cursor(0)[1] - 2]
		if not item or item.type ~= EVENT_TYPES.sourcing then
			return vim.api.nvim_echo({ { "Not a sourcing event", "WarningMsg" } }, false, {})
		end

		local module = item.event:match("^require%('([^']+)'%)")
		if module then
			local module_path = module:gsub("%.", "/")
			local file = vim.api.nvim_get_runtime_file(string.format("lua/%s.lua", module_path), false)[1]
				or vim.api.nvim_get_runtime_file(string.format("lua/%s/init.lua", module_path), false)[1]

			if not file then
				return vim.notify("Could not find file for module: " .. module, vim.log.levels.WARN)
			end

			vim.cmd("edit " .. vim.fn.fnameescape(file))
		else
			local sourcing = item.event:match("^sourcing (.+)$")
			local file = sourcing and sourcing or item.event

			vim.cmd("edit " .. vim.fn.fnameescape(file))
		end
	end, { buffer = bufnr, silent = true, nowait = true })

	local sort_key = "time"
	vim.keymap.set("n", "<C-s>", function()
		sort_key = sort_key == "time" and "idx" or "time"
		table.sort(items, function(a, b)
			if sort_key == "idx" then
				return a.idx < b.idx
			else
				return a.time > b.time
			end
		end)

		local lines = create_output(items, startup_time)

		vim.bo[bufnr].modifiable = true
		vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
		vim.bo[bufnr].modifiable = false

		highlight(bufnr, items, lines)
	end, { buffer = bufnr, silent = true, nowait = true })
end

-- Create and display the startuptime buffer
local function display(items, startup_time)
	local lines = create_output(items, startup_time)

	-- Create or reuse buffer
	local bufnr = vim.fn.bufnr("StartupTime")
	if bufnr == -1 then
		bufnr = vim.api.nvim_create_buf(false, true)
		vim.api.nvim_buf_set_name(bufnr, "StartupTime")
	end

	-- Set buffer content
	vim.bo[bufnr].modifiable = true
	vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
	vim.bo[bufnr].modifiable = false
	vim.bo[bufnr].buftype = "nofile"
	vim.bo[bufnr].swapfile = false
	vim.bo[bufnr].filetype = "startuptime"

	highlight(bufnr, items, lines)

	setup_keymaps(bufnr, items, startup_time)

	vim.cmd("sbuffer " .. bufnr)
end

---@param tries number
function M.profile(tries)
	local progress = { kind = "progress", title = "nvim-startuptime" }

	--- @type fun(kind: 'begin'|'report'|'end', _completed: number, total: number): nil
	local report_progress = vim.schedule_wrap(function(kind, completed, total)
		progress.status = kind == "end" and "success" or "running"
		progress.percent = math.floor((completed / tries) * 100)
		local msg = ("Running (%d/%d)"):format(completed, total)
		progress.id = vim.api.nvim_echo({ { msg } }, false, progress)
	end)

	local completed = 0
	local temp_file = vim.fn.tempname()

	local function run_try(try_num)
		if try_num > tries then
			report_progress("end", tries, tries)
			local items, startup = parse(temp_file)
			vim.fn.delete(temp_file)
			return display(items, startup)
		end

		-- Use timer-based quit to capture all events including VimEnter and UIEnter
		-- This ensures we capture:
		-- - VimEnter autocommands
		-- - UIEnter autocommands
		-- - before starting main loop
		-- - first screen update
		-- - --- VIM STARTED ---
		-- Disable shada/viminfo to avoid issues with parallel runs
		-- Run profiling asynchronously for multiple tries
		local cmd = {
			vim.v.progpath,
			"--startuptime",
			temp_file,
			"--cmd",
			"let g:loaded_unnest = 1",
			"-c",
			"autocmd VimEnter * set shada= shadafile=NONE",
			"-c",
			'call timer_start(0, {-> execute("qall!")})',
		}

		-- Start the job with a PTY so UIEnter events are captured
		vim.fn.jobstart(cmd, {
			pty = true,
			on_exit = function(_, exit_code, _)
				if exit_code ~= 0 then
					vim.fn.delete(temp_file)
					return vim.notify(string.format("Failed with exit code %d", exit_code), vim.log.levels.ERROR)
				end

				completed = completed + 1

				if completed < tries then
					report_progress("report", completed, tries)
				end

				run_try(try_num + 1)
			end,
		})
	end

	report_progress("begin", 0, tries)
	run_try(1)
end

return M
