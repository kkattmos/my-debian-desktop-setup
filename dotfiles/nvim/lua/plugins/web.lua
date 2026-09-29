-- Express / React: LazyVim's typescript extra (vtsls) already covers .js/.jsx/.ts/.tsx.
-- Here we only make sure the extra servers/formatters are installed by Mason.
return {
  {
    "mason-org/mason.nvim",
    opts = {
      ensure_installed = {
        "pyright", "ruff",                       -- Python / notebooks
        "vtsls", "eslint-lsp", "prettier",       -- Node, Express, React
        "tailwindcss-language-server", "json-lsp", "emmet-language-server",
      },
    },
  },
  {
    "neovim/nvim-lspconfig",
    opts = { servers = { emmet_language_server = {} } }, -- HTML/JSX tag expansion
  },
}
