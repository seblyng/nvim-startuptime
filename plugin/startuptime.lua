if vim.g.loaded_startuptime then
	return
end
vim.g.loaded_startuptime = 1

local function parse_args(args)
	local options = {}

	local i = 1
	while i <= #args do
		local arg = args[i]

		if arg == "--tries" then
			i = i + 1
			if i > #args then
				return nil, "Expected argument after --tries"
			end
			local tries = tonumber(args[i])
			if not tries or tries < 1 then
				return nil, "Invalid value for --tries: " .. args[i]
			end
			options.tries = tries
		elseif arg:match("^%-%-") then
			return nil, "Unknown option: " .. arg
		end

		i = i + 1
	end

	return {
		options = options,
	}, nil
end

-- Create the StartupTime command
vim.api.nvim_create_user_command("StartupTime", function(opts)
	local parsed, err = parse_args(opts.fargs)
	if not parsed or err then
		return vim.notify("nvim-startuptime: " .. err, vim.log.levels.ERROR)
	end

	require("startuptime").profile(parsed.options.tries or 1)
end, {
	nargs = "*",
	complete = function(arglead, cmdline, cursorpos)
		local all_options = {
			"--tries",
		}

		-- Parse current command line to see what's been used
		local words = vim.split(cmdline:sub(1, cursorpos), "%s+")

		-- Check if we're completing an option value
		if #words >= 2 then
			local prev_word = words[#words - 1]

			if prev_word == "--tries" then
				-- Number suggestions
				if arglead == "" then
					return { "1", "5", "10" }
				end
				return {}
			end
		end

		-- Filter options that match the arglead
		local matches = {}
		for _, opt in ipairs(all_options) do
			if opt:sub(1, #arglead) == arglead then
				table.insert(matches, opt)
			end
		end

		return matches
	end,
	desc = "Profile Neovim startup time",
})
