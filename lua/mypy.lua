M = {
	use_env = true,
}

---@class mypy.Config
---@field use_env boolean?

---@param config mypy.Config?
M.setup = function(config)
	M.namespace = vim.api.nvim_create_namespace("MypyNvim")
	M.enabled = true

	config = config or {}
	if config.use_env ~= nil then
		M.use_env = config.use_env
	end

	vim.api.nvim_create_autocmd({ "BufEnter", "BufWritePost", "InsertLeave" }, {
		group = vim.api.nvim_create_augroup("MypyNvim", { clear = true }),
		pattern = { "*.py", "*.pyi" },
		callback = M.typecheck_current_buffer,
	})

	-- vim.api.nvim_create_user_command('MypyEnable', function(_)
	--   M.enabled = true
	--   M.typecheck_current_buffer()
	-- end, { desc = 'Enable Mypy diagnostics' })
	-- vim.api.nvim_create_user_command('MypyDisable', function(_)
	--   M.enabled = false
	--   M.typecheck_current_buffer()
	-- end, { desc = 'Disable Mypy diagnostics' })
	-- vim.api.nvim_create_user_command('MypyToggle', function(_)
	--   M.enabled = not M.enabled
	--   M.typecheck_current_buffer()
	-- end, { desc = 'Toggle Mypy diagnostics' })
end

local severities = {
	error = vim.diagnostic.severity.ERROR,
	warning = vim.diagnostic.severity.WARN,
	note = vim.diagnostic.severity.HINT,
}

---@param use_env boolean
---@return string
local function mypy_path(use_env)
	local venv_path = vim.env.VIRTUAL_ENV .. "/bin/mypy"
	if use_env and vim.env.VIRTUAL_ENV and vim.fn.filereadable(venv_path) then
		return venv_path
	end

	return "mypy"
end

---@param out string
---@return vim.Diagnostic[]
local function parse(out)
	---@type vim.Diagnostic[]
	local diagnostics = {}

	--- filename:line_from:col_from:line_to:col_to: severity: message [code]
	for _, line_from, col_from, line_to, col_to, severity, message, code in
		out:gmatch("([^:]+):(%d+):(%d+):(%d+):(%d+): (%a+): (.*) %[(%a[%a-]+)%]")
	do
		local lnum = math.max(tonumber(line_from) - 1, 0)
		local col = math.max(tonumber(col_from) - 1, 0)
		local end_lnum = math.max(tonumber(line_to) - 1, lnum)
		local end_col = math.max(tonumber(col_to) - 1, col)

		table.insert(diagnostics, {
			source = "mypy",
			lnum = lnum,
			col = col,
			end_lnum = end_lnum,
			end_col = end_col,
			message = message,
			severity = severities[severity],
			code = code,
		})
	end

	return diagnostics
end

---@param buf_num integer
---@return nil
local function mypy(buf_num)
	local buf_path = vim.api.nvim_buf_get_name(0)

	local cmd = {
		mypy_path(M.use_env),
		"--show-column-numbers",
		"--show-error-end",
		"--hide-error-context",
		"--no-color-output",
		"--no-error-summary",
		"--no-pretty",
		buf_path,
	}

	local mypy_result = vim.system(cmd, {}):wait()
	if mypy_result.code == 0 then
		vim.schedule(function()
			vim.diagnostic.reset(M.namespace, buf_num)
		end)
		return
	end

	local diagnostics = parse(mypy_result.stdout)
	vim.schedule(function()
		vim.diagnostic.set(M.namespace, buf_num, diagnostics)
	end)
end

M.typecheck_current_buffer = function()
	if not vim.bo.modifiable then
		return
	end

	local current_buf = vim.api.nvim_get_current_buf()

	if not M.enabled then
		vim.diagnostic.reset(M.namespace, current_buf)
		return
	end

	local ok, call_result = pcall(mypy, current_buf)
	if not ok then
		error(string.format("Failed to run mypy: %s", call_result))
	end
end

return M

