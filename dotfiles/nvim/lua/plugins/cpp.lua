-- C/C++: compile + run the current file, and debug it with codelldb (dap.core + lang.clangd extras,
-- imported in lua/config/lazy.lua).
-- <leader>cr is LazyVim's LSP rename, hence <leader>cb ("build & run") + F5.

-- Compiler command for the current buffer (debug info, no optimisation, so every line is steppable)
local function compile_cmd(src, exe)
  local cc = vim.bo.filetype == "c" and "gcc -std=c17" or "g++ -std=c++20"
  return ("%s -Wall -Wextra -g -O0 %s -o %s"):format(cc, vim.fn.shellescape(src), vim.fn.shellescape(exe))
end

-- Run in a floating terminal (stdin works, so cin/scanf are fine)
local function build_and_run()
  vim.cmd("write")
  local src, exe = vim.fn.expand("%:p"), vim.fn.expand("%:p:r")
  Snacks.terminal(compile_cmd(src, exe) .. " && " .. vim.fn.shellescape(exe),
    { cwd = vim.fn.expand("%:p:h"), interactive = true })
end

-- Used by the debugger: build synchronously, return the executable (or abort the launch)
local function build_for_debug()
  vim.cmd("write")
  local src, exe = vim.fn.expand("%:p"), vim.fn.expand("%:p:r")
  local out = vim.fn.system(compile_cmd(src, exe) .. " 2>&1")
  if vim.v.shell_error ~= 0 then
    vim.notify(out, vim.log.levels.ERROR, { title = "Build failed" })
    return require("dap").ABORT
  end
  return exe
end

return {
  {
    "folke/snacks.nvim",
    keys = {
      { "<leader>cb", build_and_run, ft = { "c", "cpp" }, desc = "Build & Run (C/C++)" },
      { "<F5>", build_and_run, ft = { "c", "cpp" }, desc = "Build & Run (C/C++)" },
    },
  },
  {
    "mfussenegger/nvim-dap",
    -- runs after the clangd extra's opts, so these configurations replace its "Launch file" (asks for a path)
    opts = function()
      local dap = require("dap")
      for _, lang in ipairs({ "c", "cpp" }) do
        dap.configurations[lang] = {
          {
            type = "codelldb",
            request = "launch",
            name = "Build & debug current file",
            program = build_for_debug,
            cwd = "${fileDirname}",
            -- program runs in the dap-ui console panel, a real terminal: cin works there
            terminal = "integrated",
          },
          {
            type = "codelldb",
            request = "attach",
            name = "Attach to process",
            pid = require("dap.utils").pick_process,
            cwd = "${workspaceFolder}",
          },
        }
      end
    end,
  },
}
