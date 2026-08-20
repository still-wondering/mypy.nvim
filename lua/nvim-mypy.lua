---@class nvim-mypy.M
---@field enabled boolean
---@field namespace integer?
---@field use_venv boolean
---@field venv_path string
---@field timeout number
---@field quiet boolean
---@field severities table<string, vim.diagnostic.Severity>
M = {
  namespace = nil,
  enabled = false,
  use_venv = true,
  venv_path = tostring(vim.env.VIRTUAL_ENV or ''),
  timeout = 5 * 1000,
  quiet = true,
  severities = {
    error = vim.diagnostic.severity.ERROR,
    warning = vim.diagnostic.severity.WARN,
    note = vim.diagnostic.severity.HINT,
  },
}

---@class nvim-mypy.Config
---@field use_venv boolean? Whether to try load mypy from venv. Defaults to true.
---@field venv_path string? Path to venv. Defaults to `vim.env.VIRTUAL_ENV`
---@field timeout number? Timeout for mypy process to run in milliseconds. Defaults to 5s.
---@field quiet boolean? Whether to ignore mypy failures, e.g. due invalid syntax in the file.
---@field severities table<string, vim.diagnostic.Severity>? Mypy severiry to diagnostics severity mapping.

---@param config nvim-mypy.Config?
M.setup = function(config)
  M.namespace = vim.api.nvim_create_namespace 'MypyNvim'
  M.enabled = true

  config = config or {}
  if config.use_venv ~= nil then M.use_venv = config.use_venv end
  if config.venv_path ~= nil then M.venv_path = config.venv_path end
  if config.timeout ~= nil then M.timeout = config.timeout end
  if config.quiet ~= nil then M.quiet = config.quiet end
  if config.severities ~= nil then M.severities = config.severities end
end

local function validate_init()
  if not M.namespace then
    vim.notify(
      "nvim-mypy plugin was not initialized properly. did you forget `require('nvim-mypy').setup()`?",
      vim.log.levels.ERROR
    )
  end
end

---@param path string
---@return boolean
local function file_exists(path)
  local f = io.open(path, 'r')
  if not f then return false end

  f:close()
  return true
end

---@return string
local function mypy_path()
  if M.use_venv and M.venv_path ~= '' and file_exists(M.venv_path .. '/bin/mypy') then
    return M.venv_path .. '/bin/mypy'
  end
  if M.use_venv then
    local cwd = vim.fn.getcwd()
    local venv_names = { '.venv', 'venv', 'env' }
    for _, venv in ipairs(venv_names) do
      if file_exists(cwd .. '/' .. venv .. '/bin/mypy') then return cwd .. '/' .. venv .. '/bin/mypy' end
    end
  end
  return 'mypy'
end

---@param buf_num integer
---@param buf_path string
---@param out string
---@return vim.Diagnostic[]
local function parse(buf_num, buf_path, out)
  ---@type vim.Diagnostic[]
  local diagnostics = {}
  for line in out:gmatch '(.-)\n' do
    do -- try long format
      local filename, line_from, col_from, line_to, col_to, severity, message, code =
        line:match '([^:]+):(%d+):(%d+):(%d+):(%d+): (%a+): (.*) %[(%a[%a-]+)%]'
      if filename and buf_path:sub(-#filename) == filename then
        local lnum = math.max(tonumber(line_from) - 1, 0)
        local col = math.max(tonumber(col_from) - 1, 0)
        local end_lnum = math.max(tonumber(line_to) - 1, lnum)
        local end_col = math.max(tonumber(col_to) - 1, col)
        ---@type vim.Diagnostic
        local d = {
          bufnr = buf_num,
          source = 'mypy',
          lnum = lnum,
          col = col,
          end_lnum = end_lnum,
          end_col = end_col,
          message = message,
          severity = M.severities[severity],
          code = code,
        }
        table.insert(diagnostics, d)
        goto continue
      end
    end

    do -- try short format. NOTE: this is really a precautionary thing
      local filename, line_from, severity, message, code = line:match '([^:]+):(%d+): (%a+): (.*) %[(%a[%a-]+)%]'
      if filename and buf_path:sub(-#filename) == filename then
        local lnum = math.max(tonumber(line_from) - 1, 0)
        local src_line = vim.api.nvim_buf_get_lines(buf_num, lnum, lnum + 1, false)
        local col = src_line[1] and #src_line[1] or 0
        ---@type vim.Diagnostic
        local d = {
          bufnr = buf_num,
          source = 'mypy',
          lnum = lnum,
          col = col,
          end_lnum = lnum,
          end_col = col,
          message = message,
          severity = M.severities[severity],
          code = code,
        }
        table.insert(diagnostics, d)
        goto continue
      end
    end

    if not M.quiet then vim.notify(("Can not process mypy output line : '%s'"):format(line), vim.log.levels.WARN) end

    ::continue::
  end
  return diagnostics
end

--- Running processes, buffer -> mypy process
---@type table<integer, vim.SystemObj>
local running_procs_by_buf = {}

---@param proc vim.SystemObj?
local function cancel_mypy(proc)
  if proc then proc:kill(9) end
end

---@param buf_num integer
---@return nil
local function mypy(buf_num)
  local buf_path = vim.api.nvim_buf_get_name(buf_num)

  local cmd = {
    mypy_path(),
    '--show-column-numbers',
    '--show-error-end',
    '--hide-error-context',
    '--no-color-output',
    '--no-error-summary',
    '--no-pretty',
    buf_path,
  }

  cancel_mypy(running_procs_by_buf[buf_num])

  do
    local mypy_proc
    mypy_proc = vim.system(cmd, { timeout = M.timeout }, function(mypy_result)
      ---@diagnostic disable-next-line: redefined-local
      if running_procs_by_buf[buf_num] ~= mypy_proc then return end

      if mypy_result.code ~= 1 then
        vim.schedule(function() vim.diagnostic.reset(M.namespace, buf_num) end)
      else
        vim.schedule(function()
          local diagnostics = parse(buf_num, buf_path, mypy_result.stdout)
          vim.diagnostic.set(M.namespace, buf_num, diagnostics)
        end)
        return
      end

      if mypy_result.code ~= 0 and not M.quiet then
        vim.schedule(
          function()
            vim.notify(
              string.format("Failed to run mypy. stdout: '%s', stderr: '%s'", mypy_result.stdout, mypy_result.stderr),
              vim.log.levels.WARN
            )
          end
        )
      end
    end)
    running_procs_by_buf[buf_num] = mypy_proc
  end
end

M.typecheck_current = function()
  validate_init()
  local current_buf = vim.api.nvim_get_current_buf()

  if not vim.bo[current_buf].modifiable then return end

  if not M.enabled then
    vim.diagnostic.reset(M.namespace, current_buf)
    return
  end

  local ok, call_result = pcall(mypy, current_buf)
  if not ok then vim.notify(string.format('Failed to run mypy: %s', call_result), vim.log.levels.WARN) end
end

--- Stop mypy linting for all the buffers
M.stop_all = function()
  validate_init()
  for buf, proc in pairs(running_procs_by_buf) do
    cancel_mypy(proc)
    vim.diagnostic.reset(M.namespace, buf)
  end
  running_procs_by_buf = {}
end

return M
