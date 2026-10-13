-- Plain Linux console (Ctrl+Alt+F3 ..., TERM=linux): its font holds 512 glyphs and no Nerd Font icons,
-- so every icon would show as a diamond. There, swap the icons for ASCII letters/symbols.
-- Nothing changes in Ptyxis or kitty (TERM is xterm-256color / xterm-kitty there).
if vim.env.TERM ~= "linux" then
  return {}
end

-- every string in a (nested) icon table with its non-ASCII characters removed ("󰊕 " -> " ")
local function ascii(v)
  if type(v) == "string" then
    return (v:gsub("[\128-\255]+", ""))
  elseif type(v) == "table" then
    local t = {}
    for k, x in pairs(v) do
      t[k] = ascii(x)
    end
    return t
  end
  return v
end

local bar = { text = "|" }

return {
  { "nvim-mini/mini.icons", opts = { style = "ascii" } }, -- file/filetype icons: "L" for Lua etc.

  {
    "LazyVim/LazyVim",
    opts = function(_, opts)
      local defaults = require("lazyvim.config").icons
      opts.icons = vim.tbl_deep_extend("force", ascii(defaults), {
        misc = { dots = "..." },
        dap = {
          Stopped = { "> ", "DiagnosticWarn", "DapStoppedLine" },
          Breakpoint = "B ",
          BreakpointCondition = "C ",
          BreakpointRejected = { "R ", "DiagnosticError" },
        },
        diagnostics = { Error = "E ", Warn = "W ", Hint = "H ", Info = "I " },
        git = { added = "+", modified = "~", removed = "-" },
      })
    end,
  },

  {
    "nvim-lualine/lualine.nvim",
    opts = function(_, opts)
      opts.options = vim.tbl_extend("force", opts.options or {}, {
        section_separators = { left = "", right = "" },
        component_separators = { left = "|", right = "|" },
      })
    end,
  },

  {
    "akinsho/bufferline.nvim",
    opts = {
      options = {
        buffer_close_icon = "x",
        close_icon = "x",
        modified_icon = "*",
        left_trunc_marker = "<",
        right_trunc_marker = ">",
        indicator = { icon = "|", style = "icon" },
      },
    },
  },

  {
    "lewis6991/gitsigns.nvim",
    opts = {
      signs = { add = bar, change = bar, delete = { text = "_" }, topdelete = { text = "-" },
        changedelete = { text = "~" }, untracked = { text = ":" } },
      signs_staged = { add = bar, change = bar, delete = { text = "_" }, topdelete = { text = "-" },
        changedelete = { text = "~" } },
    },
  },

  {
    "folke/snacks.nvim",
    opts = function(_, opts)
      opts.picker = opts.picker or {}
      opts.picker.prompt = "> "
      opts.picker.icons = ascii(require("snacks.picker.config.defaults").defaults.icons)
      local keys = vim.tbl_get(opts, "dashboard", "preset", "keys")
      for _, k in ipairs(type(keys) == "table" and keys or {}) do
        k.icon = "> "
      end
    end,
  },

  { "folke/which-key.nvim", opts = { icons = { breadcrumb = ">", separator = "->", group = "+", mappings = false } } },

  {
    "folke/noice.nvim",
    opts = {
      cmdline = {
        format = {
          cmdline = { icon = ":" },
          search_down = { icon = "/" },
          search_up = { icon = "?" },
          filter = { icon = "$" },
          lua = { icon = "lua" },
          help = { icon = "help" },
        },
      },
    },
  },
}
