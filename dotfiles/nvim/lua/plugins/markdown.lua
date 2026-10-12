-- Markdown files: lint messages stay out of the text.
-- The inline messages (virtual text) pushed the tables and diagrams that render-markdown draws out of
-- shape, so in .md files diagnostics are only signs in the left column + underlines.
-- Read them with <leader>cd (line), ]d / [d (jump) or <leader>xx (list).
-- Notebooks (.ipynb, also filetype markdown) keep the inline pyright messages in their code cells.
-- markdownlint: ~/.config/nvim/.markdownlint-cli2.yaml turns off line length and table pipe spacing.

local MDL_CONFIG = vim.fn.stdpath("config") .. "/.markdownlint-cli2.yaml"

local function inline_hidden(bufnr)
  return vim.bo[bufnr].filetype == "markdown" and not vim.api.nvim_buf_get_name(bufnr):match("%.ipynb$")
end

return {
  {
    "neovim/nvim-lspconfig",
    opts = function(_, opts)
      -- vim.diagnostic.config is global; a nil message hides that diagnostic's virtual text
      opts.diagnostics.virtual_text.format = function(d)
        if inline_hidden(d.bufnr) then return nil end
        return d.message
      end
    end,
  },
  {
    "mfussenegger/nvim-lint",
    opts = {
      linters = {
        ["markdownlint-cli2"] = { prepend_args = { "--config", MDL_CONFIG } },
      },
    },
  },
  {
    "stevearc/conform.nvim",
    opts = {
      formatters = {
        ["markdownlint-cli2"] = { prepend_args = { "--config", MDL_CONFIG } },
      },
    },
  },
}
