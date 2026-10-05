-- Jupyter notebooks in Neovim, laid out like Google Colab.
-- jupytext.nvim: opening foo.ipynb shows it as Markdown. Text cells are plain Markdown,
--   code cells are ```python blocks; saving writes the .ipynb back.
--   ~/.config/jupytext/jupytext.toml hides the notebook metadata header (it is kept in the .ipynb).
-- render-markdown.nvim (LazyVim markdown extra): headings, lists and $math$ are drawn, and every
--   code cell is a full-width shaded box. Insert mode shows the raw text.
-- otter.nvim: pyright/ruff completion, hover and diagnostics inside the code cells.
-- molten-nvim: a Jupyter kernel ("python3" = ~/.local/share/nvim-py) starts when the notebook opens,
--   saved outputs are shown under their cells, and new outputs are saved into the .ipynb.
-- Plots: inside kitty (`nb x.ipynb`, or opening a .ipynb from Files) image.nvim draws them under the
--   cell with the kitty graphics protocol. Ptyxis can't draw images (it doesn't enable VTE's sixel
--   support), so there they open in the image viewer instead.
--
-- Keys in a notebook (\ is the localleader):
--   Alt+Enter / \rn  run cell, go to the next one (adds a cell at the end)
--   \rc  run cell      \ra  run all       \rl  run line      \r (visual)  run selection
--   \ro  open output   \rh  hide output   \rd  delete output \ri  open image of the output
--   ]c [c  next / previous code cell      \cb \ca  new code cell below / above
--   \mi  pick another kernel   \mr  restart kernel   \mx  interrupt
-- Another venv becomes a kernel with:
--   pip install ipykernel && python -m ipykernel install --user --name <project>

local CELL_START, CELL_END = "^```python", "^```%s*$"
local IN_KITTY = vim.env.KITTY_WINDOW_ID ~= nil

-- Code cells of the current buffer: { open = fence line, close = fence line } (1-based)
local function code_cells()
  local cells, open = {}, nil
  for i, line in ipairs(vim.api.nvim_buf_get_lines(0, 0, -1, false)) do
    if not open and line:match(CELL_START) then
      open = i
    elseif open and line:match(CELL_END) then
      cells[#cells + 1] = { open = open, close = i }
      open = nil
    end
  end
  return cells
end

local function cell_at(row, cells)
  for i, c in ipairs(cells) do
    if row >= c.open and row <= c.close then return c, i end
  end
end

local function ensure_kernel()
  if require("molten.status").initialized() ~= "Molten" then vim.cmd("MoltenInit python3") end
end

local function eval_cell(c)
  if c and c.close - 1 >= c.open + 1 then vim.fn.MoltenEvaluateRange(c.open + 1, c.close - 1) end
end

local function add_cell(above)
  local row = vim.api.nvim_win_get_cursor(0)[1]
  local c = cell_at(row, code_cells())
  local at = c and (above and c.open - 1 or c.close) or (above and row - 1 or row)
  vim.api.nvim_buf_set_lines(0, at, at, false, { "", "```python", "", "```" })
  vim.api.nvim_win_set_cursor(0, { at + 3, 0 })
  vim.cmd("startinsert")
end

local function run_cell()
  ensure_kernel()
  eval_cell(cell_at(vim.api.nvim_win_get_cursor(0)[1], code_cells()))
end

-- Shift+Enter in Colab: run, then move to the next code cell (a new one after the last)
local function run_and_next()
  vim.cmd("stopinsert")
  ensure_kernel()
  local row = vim.api.nvim_win_get_cursor(0)[1]
  local cells = code_cells()
  local c = cell_at(row, cells)
  eval_cell(c)
  for _, n in ipairs(cells) do
    if n.open > (c and c.close or row) then
      vim.api.nvim_win_set_cursor(0, { n.open + 1, 0 })
      return
    end
  end
  vim.api.nvim_win_set_cursor(0, { vim.api.nvim_buf_line_count(0), 0 })
  add_cell(false)
end

local function run_all()
  ensure_kernel()
  for _, c in ipairs(code_cells()) do
    eval_cell(c)
  end
end

local function goto_cell(dir)
  local row = vim.api.nvim_win_get_cursor(0)[1]
  local cells = code_cells()
  for i = dir > 0 and 1 or #cells, dir > 0 and #cells or 1, dir do
    local c = cells[i]
    if (dir > 0 and c.open > row) or (dir < 0 and c.close < row) then
      return vim.api.nvim_win_set_cursor(0, { c.open + 1, 0 })
    end
  end
end

local function setup_notebook(buf)
  if vim.b[buf].notebook then return end -- jupytext sets the filetype twice
  vim.b[buf].notebook = true
  vim.b[buf].autoformat = false -- prettier/markdownlint would rewrite the cells on every save
  require("otter").activate({ "python" }, true, true)

  local function map(mode, lhs, rhs, desc)
    vim.keymap.set(mode, lhs, rhs, { buffer = buf, silent = true, desc = desc })
  end
  map({ "n", "i" }, "<M-CR>", run_and_next, "Run cell, next")
  map({ "n", "i" }, "<S-CR>", run_and_next, "Run cell, next") -- only if the terminal sends Shift+Enter
  map("n", "<localleader>rn", run_and_next, "Run cell, next")
  map("n", "<localleader>rc", run_cell, "Run cell")
  map("n", "<localleader>ra", run_all, "Run all cells")
  map("n", "<localleader>rl", "<cmd>MoltenEvaluateLine<cr>", "Run line")
  map("v", "<localleader>r", ":<C-u>MoltenEvaluateVisual<cr>gv", "Run selection")
  map("n", "<localleader>ro", "<cmd>noautocmd MoltenEnterOutput<cr>", "Open output")
  map("n", "<localleader>rh", "<cmd>MoltenHideOutput<cr>", "Hide output")
  map("n", "<localleader>rd", "<cmd>MoltenDelete<cr>", "Delete cell output")
  map("n", "<localleader>ri", "<cmd>MoltenImagePopup<cr>", "Open image output")
  map("n", "]c", function() goto_cell(1) end, "Next code cell")
  map("n", "[c", function() goto_cell(-1) end, "Previous code cell")
  map("n", "<localleader>cb", function() add_cell(false) end, "New code cell below")
  map("n", "<localleader>ca", function() add_cell(true) end, "New code cell above")
  map("n", "<localleader>mi", "<cmd>MoltenInit<cr>", "Pick kernel")
  map("n", "<localleader>mr", "<cmd>MoltenRestart!<cr>", "Restart kernel")
  map("n", "<localleader>mx", "<cmd>MoltenInterrupt<cr>", "Interrupt kernel")

  -- Like Colab: connect to the kernel on open and show the outputs saved in the notebook.
  -- Molten would add an "Out[_]: Never Run" line under every cell without output,
  -- so it imports from a copy that only has the cells with output.
  local file = vim.api.nvim_buf_get_name(buf)
  vim.schedule(function()
    if not vim.api.nvim_buf_is_valid(buf) then return end
    vim.api.nvim_buf_call(buf, function()
      ensure_kernel()
      local ok, nb = pcall(function() return vim.json.decode(table.concat(vim.fn.readfile(file), "\n")) end)
      if not ok then return end
      nb.cells = vim.tbl_filter(function(c) return c.cell_type == "code" and #(c.outputs or {}) > 0 end, nb.cells)
      if #nb.cells == 0 then return end
      local tmp = vim.fn.tempname() .. ".ipynb"
      vim.fn.writefile({ vim.json.encode(nb) }, tmp)
      pcall(vim.cmd, "MoltenImportOutput " .. vim.fn.fnameescape(tmp))
      vim.fn.delete(tmp)
    end)
  end)
end

return {
  {
    "GCBallesteros/jupytext.nvim",
    lazy = false,
    -- "md" instead of "auto": auto needs metadata.language_info, which Colab notebooks don't have
    opts = { style = "markdown", output_extension = "md", force_ft = "markdown" },
    init = function()
      -- jupytext.nvim reads the .ipynb from disk first and crashes (utils.lua:16) on a new or
      -- empty file, e.g. `nvim new.ipynb`. Write an empty Python notebook before it runs
      -- (init runs before the plugin's setup, so this BufReadCmd fires first).
      vim.api.nvim_create_autocmd("BufReadCmd", {
        pattern = "*.ipynb",
        callback = function(ev)
          local f = vim.fn.fnamemodify(ev.match, ":p")
          if vim.fn.getfsize(f) <= 0 and vim.fn.isdirectory(vim.fn.fnamemodify(f, ":h")) == 1 then
            vim.fn.writefile({
              '{"cells": [], "metadata": {"kernelspec": {"display_name": "Python 3",'
                .. ' "language": "python", "name": "python3"}, "language_info": {"name": "python"}},'
                .. ' "nbformat": 4, "nbformat_minor": 5}',
            }, f)
          end
        end,
      })
      vim.api.nvim_create_autocmd("FileType", {
        pattern = "markdown",
        callback = function(ev)
          if ev.file:match("%.ipynb$") then setup_notebook(ev.buf) end
        end,
      })
    end,
  },
  {
    "jmbuhr/otter.nvim",
    lazy = true,
    dependencies = { "nvim-treesitter/nvim-treesitter" },
    opts = {},
  },
  {
    "MeanderingProgrammer/render-markdown.nvim",
    opts = {
      -- one shaded box per code cell; language_info off hides Colab's cell id (```python id="...")
      code = { width = "full", border = "thick", language_info = false },
      latex = { converter = vim.fn.expand("~/.local/share/nvim-py/bin/latex2text") },
    },
  },
  {
    "nvim-treesitter/nvim-treesitter",
    opts = { ensure_installed = { "latex" } }, -- render-markdown finds $math$ with it
  },
  {
    "mfussenegger/nvim-lint",
    opts = {
      linters = {
        ["markdownlint-cli2"] = {
          condition = function(ctx) return not ctx.filename:match("%.ipynb$") end,
        },
      },
    },
  },
  {
    "3rd/image.nvim",
    lazy = true, -- loaded by molten, only when nvim runs in kitty
    build = false, -- the magick_cli processor needs no luarocks
    opts = {
      backend = "kitty",
      processor = "magick_cli", -- ImageMagick (apt) resizes and crops the plots
      -- only molten's outputs: no images from Markdown/HTML links (and no downloads)
      integrations = vim.iter({ "markdown", "asciidoc", "neorg", "rst", "typst", "html", "css" })
        :fold({}, function(t, k) t[k] = { enabled = false } return t end),
      max_width = 100,
      max_height = 20, -- lines; like Colab's default figure height
      max_height_window_percentage = math.huge,
      max_width_window_percentage = math.huge,
      window_overlap_clear_enabled = true, -- hide plots under popups (completion, hover)
      window_overlap_clear_ft_ignore = { "cmp_menu", "cmp_docs", "blink-cmp-menu", "blink-cmp-documentation", "" },
    },
  },
  {
    "benlubas/molten-nvim",
    version = "^1.0.0",
    lazy = false,
    build = ":UpdateRemotePlugins",
    init = function()
      -- molten writes the kernel connection file here but doesn't create the folder
      -- ("Could not initialize kernel ... No such file or directory")
      vim.fn.mkdir(vim.fn.expand("~/.local/share/jupyter/runtime"), "p")
      vim.g.molten_image_provider = IN_KITTY and "image.nvim" or "none"
      vim.g.molten_image_location = "virt" -- under the cell, not in the output popup
      vim.g.molten_auto_image_popup = not IN_KITTY -- Ptyxis: plots open in the image viewer (Loupe)
      vim.g.molten_auto_open_output = false
      vim.g.molten_virt_text_output = true -- output stays visible under the cell
      vim.g.molten_virt_lines_off_by_1 = true -- below the closing ``` of the cell
      vim.g.molten_virt_text_max_lines = 30
      vim.g.molten_wrap_output = true
      vim.g.molten_output_win_max_height = 20

      -- keep outputs inside the .ipynb when saving (only once a kernel is running)
      vim.api.nvim_create_autocmd("BufWritePost", {
        pattern = "*.ipynb",
        callback = function()
          if require("molten.status").initialized() == "Molten" then vim.cmd("MoltenExportOutput!") end
        end,
      })
    end,
  },
}
