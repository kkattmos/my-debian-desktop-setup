#!/usr/bin/env bash
# HP Mini 311: Neovim + LazyVim, built on this machine (Neovim publishes no 32-bit binaries and
# Debian 12's 0.7.2 is too old: LazyVim needs >= 0.11.2 with LuaJIT). Slow on the Atom - start it
# and let it run; plug in the charger. Called by m30-user.sh; safe to rerun (skips what is done):
#   bash m31-neovim.sh
# Also builds the tree-sitter CLI (LazyVim's nvim-treesitter needs >= 0.26.1; the official 32-bit
# builds need glibc 2.39, Debian 12 has 2.36) with Rust from rustup. Skip that part with:
#   SKIP_TREESITTER=1 bash m31-neovim.sh
set -euo pipefail
[[ $EUID -ne 0 ]] || { echo "!! Run this as your normal user, WITHOUT sudo."; exit 1; }
KIT="$(cd "$(dirname "$0")" && pwd)"
SHARED="$(dirname "$KIT")/dotfiles"
BUILD=~/.cache/build
mkdir -p ~/.local/bin ~/.local/opt "$BUILD"
export PATH=~/.local/bin:~/.cargo/bin:$PATH
step() { printf '\n\033[1;34m== %s\033[0m\n' "$*"; }

missing=()
for p in build-essential cmake ninja-build gettext curl unzip git; do
  dpkg-query -W -f='${Status}' "$p" 2>/dev/null | grep -q 'ok installed' || missing+=("$p")
done
(( ${#missing[@]} == 0 )) || sudo apt-get install -y "${missing[@]}"

step "Neovim: latest stable release, compiled here"
TAG=$(curl -fsS https://api.github.com/repos/neovim/neovim/releases/latest | python3 -c 'import json,sys;print(json.load(sys.stdin)["tag_name"])')
HAVE=$(~/.local/opt/nvim/bin/nvim --version 2>/dev/null | sed -n 1p || true)
if [[ $HAVE == "NVIM $TAG" ]]; then
  echo "  $HAVE already built"
else
  echo "  building $TAG (have: ${HAVE:-none}) - this takes a long time on the Atom"
  rm -rf "$BUILD/neovim"
  git clone -q --depth 1 --branch "$TAG" https://github.com/neovim/neovim "$BUILD/neovim"
  cd "$BUILD/neovim"
  # bundled deps (LuaJIT, libuv, ...) are downloaded and built too; nice = the desktop stays usable
  nice make CMAKE_BUILD_TYPE=Release CMAKE_INSTALL_PREFIX="$HOME/.local/opt/nvim"
  rm -rf ~/.local/opt/nvim
  make install
  cd ~; rm -rf "$BUILD/neovim"
fi
ln -sf ~/.local/opt/nvim/bin/nvim ~/.local/bin/nvim
nvim --version | sed -n 1,3p
nvim --version | grep LuaJIT >/dev/null || { echo "!! this Neovim was built without LuaJIT (LazyVim needs it)"; exit 1; }

step "tree-sitter CLI (built with Rust; the 32-bit downloads need a newer glibc than Debian 12's)"
if [[ ${SKIP_TREESITTER:-0} == 1 ]]; then
  echo "  skipped (SKIP_TREESITTER=1) - nvim-treesitter can't install parsers without it"
elif tree-sitter --version 2>/dev/null | grep -E 'tree-sitter 0\.(2[6-9]|[3-9][0-9])' >/dev/null; then
  echo "  $(tree-sitter --version) already installed"
else
  if ! command -v cargo >/dev/null; then
    # official installer from rust-lang.org; minimal profile, PATH is set in the Mini's zshrc
    curl --proto '=https' --tlsv1.2 -fsSL https://sh.rustup.rs | sh -s -- -y --profile minimal --no-modify-path
  fi
  rustup show active-toolchain
  echo "  compiling tree-sitter-cli (slow: expect a long while)"
  nice cargo install --locked tree-sitter-cli
  ln -sf ~/.cargo/bin/tree-sitter ~/.local/bin/tree-sitter
  tree-sitter --version
fi

step "Python env for Neovim notebooks"
# Debian's packages provide the compiled parts (pynvim, jupyter_client, ipykernel: PyPI has no
# 32-bit wheels for psutil/tornado/debugpy); the venv sees them and only adds jupytext.
missing=()
for p in python3-venv python3-pynvim python3-jupyter-client python3-ipykernel python3-nbformat; do
  dpkg-query -W -f='${Status}' "$p" 2>/dev/null | grep -q 'ok installed' || missing+=("$p")
done
(( ${#missing[@]} == 0 )) || sudo apt-get install -y "${missing[@]}"
[[ -x ~/.local/share/nvim-py/bin/python ]] || python3 -m venv --system-site-packages ~/.local/share/nvim-py
~/.local/share/nvim-py/bin/pip install -q jupytext
ln -sf ~/.local/share/nvim-py/bin/jupytext ~/.local/bin/jupytext
~/.local/share/nvim-py/bin/python -m ipykernel install --user --name python3 --display-name "Python 3 (nvim-py)"

step "LazyVim"
if [[ ! -d ~/.config/nvim ]]; then
  git clone --depth 1 https://github.com/LazyVim/starter ~/.config/nvim
  rm -rf ~/.config/nvim/.git
  # same extras as on the Dell, minus Docker (no Docker on 32-bit)
  sed -i '/import = "lazyvim.plugins" },/a\
    { import = "lazyvim.plugins.extras.lang.python" },\
    { import = "lazyvim.plugins.extras.lang.typescript" },\
    { import = "lazyvim.plugins.extras.lang.tailwind" },\
    { import = "lazyvim.plugins.extras.lang.json" },\
    { import = "lazyvim.plugins.extras.lang.markdown" },\
    { import = "lazyvim.plugins.extras.formatting.prettier" },\
    { import = "lazyvim.plugins.extras.linting.eslint" },' ~/.config/nvim/lua/config/lazy.lua
  grep -q 'extras.lang.python' ~/.config/nvim/lua/config/lazy.lua || { echo "!! could not add the LazyVim extras (starter changed?)"; exit 1; }
  cp "$SHARED"/nvim/lua/plugins/*.lua ~/.config/nvim/lua/plugins/
  printf '\nvim.g.python3_host_prog = vim.fn.expand("~/.local/share/nvim-py/bin/python")\n' >> ~/.config/nvim/lua/config/options.lua
fi
install -m 644 "$KIT/dotfiles/nvim/lua/plugins/i386.lua" ~/.config/nvim/lua/plugins/i386.lua
nvim --headless "+Lazy! sync" +qa || true
nvim --headless "+UpdateRemotePlugins" +qa || true
echo
echo "Done. The first interactive start of nvim installs the language servers via Mason (:Mason to watch)."
echo "Expected on 32-bit: no lua-language-server / stylua (no 32-bit builds; switched off in i386.lua)."
