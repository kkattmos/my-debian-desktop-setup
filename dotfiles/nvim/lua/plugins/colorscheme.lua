-- Match the Ptyxis terminal profile, which uses the built-in "Gooey" palette
-- (bg #0D101B, fg #EBEEF9, opacity 0.70 + Blur my Shell). There is no Gooey Neovim theme, so this
-- registers a "gooey" style for tokyonight built from the terminal's 16 colors.
-- Every derived color (popups, diffs, lualine, ...) is computed from it.

-- stylua: ignore
local ansi = {
  "#000009", "#BB4F6C", "#72CCAE", "#C65E3D", "#58B6CA", "#6488C4", "#8D84C6", "#858893",
  "#1F222D", "#EE829F", "#A5FFE1", "#F99170", "#8BE9FD", "#97BBF7", "#C0B7F9", "#FFFFFF",
}

local gooey = {
  bg = "#0D101B",
  bg_dark = "#090B13",
  bg_dark1 = "#06080F",
  bg_highlight = ansi[9],
  blue = ansi[14], -- functions
  blue0 = "#34466B", -- search / visual selection
  blue1 = ansi[13], -- types
  blue2 = ansi[5],
  blue5 = ansi[5], -- operators
  blue6 = ansi[11],
  blue7 = "#2E3F5E",
  comment = ansi[8],
  cyan = ansi[13],
  dark3 = "#4A4E5C",
  dark5 = ansi[8],
  fg = "#EBEEF9",
  fg_dark = "#C5C8D3",
  fg_gutter = "#2A2E3C",
  green = ansi[3], -- strings
  green1 = ansi[11], -- properties
  green2 = "#4E9C84",
  magenta = ansi[15], -- keywords
  magenta2 = ansi[10],
  orange = ansi[4], -- constants / numbers
  purple = ansi[7],
  red = ansi[10],
  red1 = ansi[2],
  teal = ansi[3],
  terminal_black = ansi[9],
  yellow = ansi[12],
  git = { add = "#4E9C84", change = ansi[6], delete = ansi[2] },
}

return {
  {
    "folke/tokyonight.nvim",
    opts = {
      style = "gooey",
      transparent = true, -- let the terminal's own background (and opacity) show through
      styles = { sidebars = "transparent", floats = "transparent" },
      on_colors = function(c)
        -- :terminal buffers use exactly the same ANSI colors as Ptyxis
        -- stylua: ignore
        c.terminal = {
          black = ansi[1], red = ansi[2], green = ansi[3], yellow = ansi[4],
          blue = ansi[5], magenta = ansi[6], cyan = ansi[7], white = ansi[8],
          black_bright = ansi[9], red_bright = ansi[10], green_bright = ansi[11], yellow_bright = ansi[12],
          blue_bright = ansi[13], magenta_bright = ansi[14], cyan_bright = ansi[15], white_bright = ansi[16],
        }
      end,
    },
    config = function(_, opts)
      require("tokyonight.colors").styles.gooey = gooey
      require("tokyonight").setup(opts)
    end,
  },
  {
    "LazyVim/LazyVim",
    opts = { colorscheme = "tokyonight" },
  },
}
