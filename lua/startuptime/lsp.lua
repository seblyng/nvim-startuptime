local M = {}

local capabilities = {
	hoverProvider = true,
	definitionProvider = true,
}
--- @type table<string,function>
local methods = {}

--- @param callback function
function methods.initialize(_, callback)
	return callback(nil, { capabilities = capabilities })
end

--- @param callback function
function methods.shutdown(_, callback)
	return callback(nil, nil)
end

--- @param params { textDocument: { uri: string }, position: vim.pack.lsp.Position }
--- @param callback function
methods["textDocument/hover"] = function(params, callback)
	local items = require("startuptime").items
	local item = items and items[params.position.line - 1]
	if not item then
		return callback(nil, nil)
	end

	local function fmt(t)
		if t.std ~= t.std then
			return ("%.3f ms"):format(t.mean)
		end
		return ("%.3f ± %.3f ms"):format(t.mean, t.std)
	end

	local is_sourcing = item.type == require("startuptime").EVENT_TYPES.sourcing
	local rows = {
		{ "Start", fmt(item.start) },
		{ "Finish", fmt(item.finish) },
	}
	if is_sourcing then
		table.insert(rows, { "Self", fmt(item.self) })
		table.insert(rows, { "Self+sourced", fmt(item["self+sourced"]) })
	else
		table.insert(rows, { "Elapsed", fmt(item.elapsed) })
	end
	table.insert(rows, { "Occurrence", tostring(item.occurrence) })
	table.insert(rows, { "Tries", tostring(item.tries) })

	local function markdown_table(tbl)
		local w1, w2 = 6, 5 -- min widths for "Metric", "Value"
		for _, row in ipairs(tbl) do
			w1 = math.max(w1, vim.api.nvim_strwidth(row[1]))
			w2 = math.max(w2, vim.api.nvim_strwidth(row[2]))
		end

		local lines = {
			("| %-" .. w1 .. "s | %-" .. w2 .. "s |"):format("Metric", "Value"),
			"|-" .. ("-"):rep(w1) .. "-|-" .. ("-"):rep(w2) .. "-|",
		}
		for _, row in ipairs(tbl) do
			local cell = ("**%s**%s"):format(row[1], (" "):rep(w1 - #row[1]))
			local pad = w2 - vim.api.nvim_strwidth(row[2])
			table.insert(lines, ("| %s | %s%s |"):format(cell, row[2], (" "):rep(pad)))
		end
		return table.concat(lines, "\n")
	end

	local markdown = ("## %s\n\n%s"):format(item.event, markdown_table(rows))
	callback(nil, { contents = { kind = vim.lsp.protocol.MarkupKind.Markdown, value = markdown } })
end

--- @param params { textDocument: { uri: string }, position: vim.pack.lsp.Position }
--- @param callback function
methods["textDocument/definition"] = function(params, callback)
	local items = require("startuptime").items
	local item = items and items[params.position.line - 1]
	if not item or item.type ~= require("startuptime").EVENT_TYPES.sourcing then
		return callback(nil, nil)
	end

	local file
	local module = item.event:match("^require%('([^']+)'%)")
	if module then
		local module_path = module:gsub("%.", "/")
		file = vim.api.nvim_get_runtime_file(("lua/%s.lua"):format(module_path), false)[1]
			or vim.api.nvim_get_runtime_file(("lua/%s/init.lua"):format(module_path), false)[1]
	else
		file = item.event:match("^sourcing (.+)$") or item.event
	end

	if not file then
		return callback(nil, nil)
	end

	callback(nil, {
		uri = vim.uri_from_fname(file),
		range = { start = { line = 0, character = 0 }, ["end"] = { line = 0, character = 0 } },
	})
end

local dispatchers = {}

-- TODO: Simplify after `vim.lsp.server` is a thing
-- https://github.com/neovim/neovim/pull/24338
function M.cmd(disp)
	-- Store dispatchers to use for showing progress notifications
	dispatchers = disp
	local res, closing, request_id = {}, false, 0

	function res.request(method, params, callback)
		local method_impl = methods[method]
		if method_impl ~= nil then
			method_impl(params, callback)
		end
		request_id = request_id + 1
		return true, request_id
	end

	function res.notify(method, _)
		if method == "exit" then
			dispatchers.on_exit(0, 15)
		end
		return false
	end

	function res.is_closing()
		return closing
	end

	function res.terminate()
		closing = true
	end

	return res
end

M.client_id =
	assert(vim.lsp.start({ cmd = M.cmd, name = "nvim-startuptime", root_dir = vim.uv.cwd() }, { attach = false }))

return M
