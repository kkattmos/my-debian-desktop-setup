-- HP Mini 311 (32-bit x86): tools that only ship 64-bit binaries are switched off, so LazyVim
-- doesn't try (and fail) to install or start them.
--   lua-language-server, stylua: no 32-bit Linux builds -> not installed by Mason
--   blink.cmp: its prebuilt Rust matcher has no 32-bit build -> use the Lua matcher (no warning)
return {
  {
    "neovim/nvim-lspconfig",
    opts = { servers = { lua_ls = { enabled = false } } },
  },
  {
    "mason-org/mason.nvim",
    opts = function(_, opts)
      opts.ensure_installed = vim.tbl_filter(function(tool)
        return tool ~= "stylua"
      end, opts.ensure_installed or {})
    end,
  },
  {
    "saghen/blink.cmp",
    optional = true,
    opts = { fuzzy = { implementation = "lua" } },
  },
}
