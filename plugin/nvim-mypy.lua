if vim.g.loaded_nvim_mypy then return end
vim.g.loaded_nvim_mypy = true

vim.api.nvim_create_user_command('MypyEnable', function()
  M.enabled = true
  require('nvim-mypy').typecheck_current()
end, { desc = 'Enable mypy diagnostics' })

vim.api.nvim_create_user_command('MypyDisable', function()
  M.enabled = false
  require('nvim-mypy').stop_all()
end, { desc = 'Disable mypy diagnostics' })

vim.api.nvim_create_user_command('MypyRestart', function()
  local mypy = require 'nvim-mypy'
  mypy.stop_all()
  M.enabled = true
  mypy.typecheck_current()
end, { desc = 'Restart mypy diagnostics' })

vim.api.nvim_create_user_command('MypyStop', require('nvim-mypy').stop_all, { desc = 'Stop mypy diagnostics' })

vim.api.nvim_create_autocmd({ 'BufEnter', 'BufWritePost' }, {
  group = vim.api.nvim_create_augroup('MypyNvim', { clear = true }),
  pattern = { '*.py', '*.pyi' },
  callback = require('nvim-mypy').typecheck_current,
})
