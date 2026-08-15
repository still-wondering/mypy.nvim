# nvim-mypy

Mypy linting plugin for neovim. If having a plugin like `nvim-lint` just to have mypy ever seemed like an overkill, then this plugin might solve that problem.
It
- runs mypy on open python buffers
- discovers mypy executable from virtual environment if available
- provides helper commands to `MypyEnable`, `MypyDisable`, `MypyStop`, `MypyRestart` (`vim.lsp` style).

## Installation 

### With vim.pack

```lua
vim.pack.add { 'https://github.com/still-wondering/nvim-mypy' }

require("nvim-mypy").setup()
```

## Venv discovery

By default plugin will try to find `mypy` executable in a virtual environment if any exists.
Tried paths precednce:
- `{venv_path}/bin/mypy` (by default `{vim.env.VIRTUAL_ENV}/bin/mypy`)
- `{cwd}/.venv/bin/mypy`
- `{cwd}/venv/bin/mypy`
- `{cwd}/env/bin/mypy`
- `mypy`

if you don't want mypy discovery, you can disable it with `use_venv` setting. 

## Configuration 

Default configuration:

```lua
require("nvim-mypy").setup{
	use_venv = true, -- whether to try discover mypy from venv
	venv_path = tostring(vim.env.VIRTUAL_ENV or ""), -- default venv path
	timeout = 5 * 1000, -- timeout per each mypy process
    quite = true, -- whether to not report mypy failures other than type checking
	severities = {
		error = vim.diagnostic.severity.ERROR,
		warning = vim.diagnostic.severity.WARN,
		note = vim.diagnostic.severity.HINT,
	}, -- mypy serverities mapping to nvim diagnostics.
}
```
