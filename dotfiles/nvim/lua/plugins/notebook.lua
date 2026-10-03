-- Jupyter notebooks in Neovim.
-- jupytext.nvim: opening foo.ipynb shows it as Python with "# %%" cell markers,
--   so pyright/ruff/completion work exactly like in a .py file; saving writes the .ipynb back.
-- molten-nvim: runs code on a Jupyter kernel and shows output inline.
--   First time in a notebook: <localleader>mi and pick a kernel.
--   A project venv becomes a kernel with:
--     pip install ipykernel && python -m ipykernel install --user --name <project>

local function run_cell()
  local s = vim.fn.search("^# %%", "bcnW")
  local e = vim.fn.search("^# %%", "nW")
  s = (s == 0) and 1 or s + 1
  e = (e == 0) and vim.fn.line("$") or e - 1
  if e >= s then vim.fn.MoltenEvaluateRange(s, e) end
end

return {
  {
    "GCBallesteros/jupytext.nvim",
    lazy = false,
    opts = {
      style = "percent",
      output_extension = "auto",
      force_ft = nil,
      -- The plugin passes `--to auto:percent` to jupytext, which needs metadata.language_info.
      -- Colab notebooks only have a kernelspec, so jupytext fails ("does not have a 'language_info'").
      -- Naming the extension makes it `--to py:percent`.
      custom_language_formatting = {
        python = { extension = "py", style = "percent", force_ft = "python" },
      },
    },
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
    end,
  },
  {
    "benlubas/molten-nvim",
    version = "^1.0.0",
    lazy = false,
    build = ":UpdateRemotePlugins",
    init = function()
      vim.g.molten_image_provider = "none" -- plots open in a separate window; see guide for image.nvim + kitty
      vim.g.molten_auto_open_output = false
      vim.g.molten_virt_text_output = true
      vim.g.molten_virt_lines_off_by_1 = true
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
    keys = {
      { "<localleader>mi", "<cmd>MoltenInit<cr>", desc = "Molten: start kernel" },
      { "<localleader>rc", run_cell, desc = "Run cell (# %%)" },
      { "<localleader>rl", "<cmd>MoltenEvaluateLine<cr>", desc = "Run line" },
      { "<localleader>rr", "<cmd>MoltenReevaluateCell<cr>", desc = "Re-run cell" },
      { "<localleader>r", ":<C-u>MoltenEvaluateVisual<cr>gv", mode = "v", desc = "Run selection" },
      { "<localleader>ro", "<cmd>noautocmd MoltenEnterOutput<cr>", desc = "Open output" },
      { "<localleader>rh", "<cmd>MoltenHideOutput<cr>", desc = "Hide output" },
      { "<localleader>rd", "<cmd>MoltenDelete<cr>", desc = "Delete cell output" },
    },
  },
}
