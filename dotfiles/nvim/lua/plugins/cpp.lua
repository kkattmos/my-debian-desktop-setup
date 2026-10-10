-- Compile + run the current C/C++ file in a floating terminal (stdin works, so cin/scanf are fine).
-- <leader>cr is LazyVim's LSP rename, hence <leader>cb ("build & run") + F5.
-- clangd itself comes from the lang.clangd extra (imported in lua/config/lazy.lua).
local function build_and_run()
  vim.cmd("write")
  local src = vim.fn.expand("%:p")
  local exe = vim.fn.expand("%:p:r")
  local cc = vim.bo.filetype == "c" and "gcc -std=c17" or "g++ -std=c++20"
  local cmd = ("%s -Wall -Wextra -g %s -o %s && %s"):format(
    cc, vim.fn.shellescape(src), vim.fn.shellescape(exe), vim.fn.shellescape(exe))
  Snacks.terminal(cmd, { cwd = vim.fn.expand("%:p:h"), interactive = true })
end

return {
  {
    "folke/snacks.nvim",
    keys = {
      { "<leader>cb", build_and_run, ft = { "c", "cpp" }, desc = "Build & Run (C/C++)" },
      { "<F5>", build_and_run, ft = { "c", "cpp" }, desc = "Build & Run (C/C++)" },
    },
  },
}
