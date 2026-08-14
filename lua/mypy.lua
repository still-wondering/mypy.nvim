---@class mypy.M
---@field use_venv boolean
---@field venv_path string
---@field timeout number
---@field severities table<string, vim.diagnostic.Severity>
M = {
	use_venv = true,
	venv_path = tostring(vim.env.VIRTUAL_ENV or ""),
	timeout = 5 * 1000,
	severities = {
		error = vim.diagnostic.severity.ERROR,
		warning = vim.diagnostic.severity.WARN,
		note = vim.diagnostic.severity.HINT,
	},
}

--- Running processes by buffer -> linting process
---@type table<integer, vim.SystemObj>
local running_procs_by_buf = {}

---@param proc vim.SystemObj?
local function cancel_mypy(proc)
	if proc then
		proc:kill(9)
	end
end

---@class mypy.Config
---@field use_venv boolean? Whether to try load mypy from venv. Defaults to true.
---@field venv_path string? Path to venv. Defaults to `vim.env.VIRTUAL_ENV`
---@field timeout number? Timeout for mypy process to run in milliseconds. Defaults to 5s.
---@field severities table<string, vim.diagnostic.Severity>? Mypy severiry to diagnostics severity mapping.

---@param config mypy.Config?
M.setup = function(config)
	M.namespace = vim.api.nvim_create_namespace("MypyNvim")
	M.enabled = true

	config = config or {}
	if config.use_venv ~= nil then
		M.use_venv = config.use_venv
	end
	if config.venv_path ~= nil then
		M.venv_path = config.venv_path
	end
	if config.timeout ~= nil then
		M.timeout = config.timeout
	end
	if config.severities ~= nil then
		M.severities = config.severities
	end

	vim.api.nvim_create_autocmd({ "BufEnter", "BufWritePost", "InsertLeave" }, {
		group = vim.api.nvim_create_augroup("MypyNvim", { clear = true }),
		pattern = { "*.py", "*.pyi" },
		callback = M.typecheck_current_buffer,
	})

	vim.api.nvim_create_user_command("MypyEnable", function()
		M.enabled = true
		M.typecheck_current_buffer()
	end, { desc = "Enable mypy diagnostics" })
	vim.api.nvim_create_user_command("MypyDisable", function()
		M.enabled = false
		for buf, proc in pairs(running_procs_by_buf) do
			cancel_mypy(proc)
			running_procs_by_buf[buf] = nil
		end
	end, { desc = "Disable mypy diagnostics" })
	vim.api.nvim_create_user_command("MypyToggle", function()
		M.enabled = not M.enabled
		if M.enabled then
			M.typecheck_current_buffer()
		end
	end, { desc = "Toggle mypy diagnostics" })
end

---@return string
local function mypy_path()
	if M.use_venv and M.venv_path and vim.fn.filereadable(M.venv_path .. "/bin/mypy") then
		return M.venv_path .. "/bin/mypy"
	end

	return "mypy"
end

--- Parse full mypy line format.
---@param line string
---@return vim.Diagnostic?
local function try_parse_long(line)
	local filename, line_from, col_from, line_to, col_to, severity, message, code =
		line:match("([^:]+):(%d+):(%d+):(%d+):(%d+): (%a+): (.*) %[(%a[%a-]+)%]")

	if not filename then
		return nil
	end

	local lnum = math.max(tonumber(line_from) - 1, 0)
	local col = math.max(tonumber(col_from) - 1, 0)
	local end_lnum = math.max(tonumber(line_to) - 1, lnum)
	local end_col = math.max(tonumber(col_to) - 1, col)

	return {
		source = "mypy",
		lnum = lnum,
		col = col,
		end_lnum = end_lnum,
		end_col = end_col,
		message = message,
		severity = M.severities[severity],
		code = code,
	}
end

--- Parse short mypy line format.
--- Some lines are still produced in short format for some reason, e.g. 'ignore-without-code'
---@param buf_num integer
---@param line string
---@return vim.Diagnostic?
local function try_parse_short(buf_num, line)
	local filename, line_from, severity, message, code = line:match("([^:]+):(%d+): (%a+): (.*) %[(%a[%a-]+)%]")

	if not filename then
		return nil
	end

	local lnum = math.max(tonumber(line_from) - 1, 0)
	local col = #vim.api.nvim_buf_get_lines(buf_num, lnum, lnum + 1, true)[1]

	return {
		source = "mypy",
		lnum = lnum,
		col = col,
		end_lnum = lnum,
		end_col = col,
		message = message,
		severity = M.severities[severity],
		code = code,
	}
end

---@param buf_num integer
---@param out string
---@return vim.Diagnostic[]
local function parse(buf_num, out)
	---@type vim.Diagnostic[]
	local diagnostics = {}
	for line in out:gmatch("(.-)\n") do
		local d = try_parse_long(line)
		if d ~= nil then
			table.insert(diagnostics, d)
			goto continue
		end

		d = try_parse_short(buf_num, line)
		if d ~= nil then
			table.insert(diagnostics, d)
		else
			vim.notify(("Can not process mypy output line : '%s'"):format(line), vim.log.levels.WARN)
		end

		::continue::
	end
	return diagnostics
end

---@param buf_num integer
---@return nil
local function mypy(buf_num)
	local buf_path = vim.api.nvim_buf_get_name(buf_num)

	local cmd = {
		mypy_path(),
		"--show-column-numbers",
		"--show-error-end",
		"--hide-error-context",
		"--no-color-output",
		"--no-error-summary",
		"--no-pretty",
		buf_path,
	}

	cancel_mypy(running_procs_by_buf[buf_num])

	do
		local mypy_proc
		mypy_proc = vim.system(cmd, { timeout = M.timeout }, function(mypy_result)
			---@diagnostic disable-next-line: redefined-local
			if running_procs_by_buf[buf_num] ~= mypy_proc then
				return
			end
			running_procs_by_buf[buf_num] = nil

			if mypy_result.code == 0 then
				vim.schedule(function()
					vim.diagnostic.reset(M.namespace, buf_num)
				end)
				return
			end

			if mypy_result.code == 1 then
				vim.schedule(function()
					local diagnostics = parse(buf_num, mypy_result.stdout)
					vim.diagnostic.set(M.namespace, buf_num, diagnostics)
				end)
				return
			end

			vim.notify(
				string.format("Failed to run mypy. stdout: '%s', stderr: '%s'", mypy_result.stdout, mypy_result.stderr),
				vim.log.levels.WARN
			)
		end)
		running_procs_by_buf[buf_num] = mypy_proc
	end
end

M.typecheck_current_buffer = function()
	local current_buf = vim.api.nvim_get_current_buf()

	if not vim.bo[current_buf].modifiable then
		return
	end

	if not M.enabled then
		vim.diagnostic.reset(M.namespace, current_buf)
		return
	end

	local ok, call_result = pcall(mypy, current_buf)
	if not ok then
		vim.notify(string.format("Failed to run mypy: %s", call_result), vim.log.levels.WARN)
	end
end

return M
