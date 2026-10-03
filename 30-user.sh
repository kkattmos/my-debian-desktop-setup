#!/usr/bin/env bash
# Run as your normal user inside the GNOME session (after 10-system.sh + reboot):
#   bash ~/debian13-setup/30-user.sh
set -euo pipefail
[[ $EUID -ne 0 ]] || { echo "!! Run this as your normal user, WITHOUT sudo (it asks for sudo itself when needed)."; exit 1; }
KIT="$(cd "$(dirname "$0")" && pwd)"
DOT="$KIT/dotfiles"
mkdir -p ~/.local/bin ~/.local/opt ~/.config/systemd/user ~/.local/share/fonts
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
step() { printf '\n\033[1;34m== %s\033[0m\n' "$*"; }

step "User session bus (systemctl --user needs it, for SeaDrive)"
# Lingering starts your systemd user manager at boot (SeaDrive needs that anyway) and creates
# /run/user/<uid>/bus. Pointing this shell at it makes the script work from any terminal,
# even one that lost its session variables (a text console, su, ssh ...).
sudo loginctl enable-linger "$USER"
export XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR:-/run/user/$(id -u)}
for _ in $(seq 20); do [[ -S $XDG_RUNTIME_DIR/bus ]] && break; sleep 0.5; done
[[ -S $XDG_RUNTIME_DIR/bus ]] || {
  echo "!! No user D-Bus at $XDG_RUNTIME_DIR/bus."
  echo "   Run: sudo apt install dbus-user-session libpam-systemd   then log out and back in."; exit 1; }
export DBUS_SESSION_BUS_ADDRESS=${DBUS_SESSION_BUS_ADDRESS:-unix:path=$XDG_RUNTIME_DIR/bus}
systemctl --user show-environment >/dev/null || { echo "!! cannot reach your systemd user manager"; exit 1; }

step "ZSH + Powerlevel10k (prompt wizard: p10k configure)"
install -m 644 "$DOT/zshrc" ~/.zshrc
# Debian only packages the old powerlevel9k (no wizard); p10k works without oh-my-zsh
P10K=~/.local/share/powerlevel10k
if [[ -d $P10K/.git ]]; then git -C "$P10K" pull --ff-only -q
else git clone -q --depth=1 https://github.com/romkatv/powerlevel10k.git "$P10K"; fi
# ~/.p10k.zsh (your wizard answers) is never overwritten
[[ $(getent passwd "$USER" | cut -d: -f7) == */zsh ]] || chsh -s /usr/bin/zsh

step "JetBrainsMono Nerd Font (icons for LazyVim + Powerlevel10k)"
curl -fL https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.tar.xz | \
  tar -xJ -C ~/.local/share/fonts --wildcards 'JetBrainsMonoNerdFont-Regular.ttf' 'JetBrainsMonoNerdFont-Bold.ttf' \
  'JetBrainsMonoNerdFont-Italic.ttf' 'JetBrainsMonoNerdFont-BoldItalic.ttf'
fc-cache -f ~/.local/share/fonts

step "Sarabun as the Thai fallback font"
bash "$KIT/35-thai-font.sh"

step "Neovim (latest stable upstream; Debian's 0.10 is too old for LazyVim)"
cd "$TMP"
curl -fLO https://github.com/neovim/neovim/releases/latest/download/nvim-linux-x86_64.tar.gz
SUM=$(curl -fsS https://api.github.com/repos/neovim/neovim/releases/latest | python3 -c 'import json,sys;print(next(a["digest"] for a in json.load(sys.stdin)["assets"] if a["name"]=="nvim-linux-x86_64.tar.gz").split(":")[1])')
echo "$SUM  nvim-linux-x86_64.tar.gz" | sha256sum -c -
rm -rf ~/.local/opt/nvim && mkdir -p ~/.local/opt/nvim
tar -xzf nvim-linux-x86_64.tar.gz -C ~/.local/opt/nvim --strip-components=1
ln -sf ~/.local/opt/nvim/bin/nvim ~/.local/bin/nvim
export PATH=~/.local/bin:$PATH
nvim --version | sed -n 1p

step "tree-sitter CLI (newer than Debian's, needed by nvim-treesitter)"
npm config set prefix ~/.local
npm install -g tree-sitter-cli

step "Python env for Neovim notebooks (pynvim, jupyter_client, jupytext, ipykernel + Colab basics)"
python3 -m venv ~/.local/share/nvim-py
~/.local/share/nvim-py/bin/pip install -q --upgrade pip
~/.local/share/nvim-py/bin/pip install -q pynvim jupyter_client jupytext nbformat ipykernel
# the python3 kernel runs in this venv: the libraries Colab has preinstalled, Pillow for plots,
# pylatexenc's latex2text for rendering $math$ in Markdown cells
~/.local/share/nvim-py/bin/pip install -q numpy scipy matplotlib pandas sympy pillow pylatexenc
ln -sf ~/.local/share/nvim-py/bin/jupytext ~/.local/bin/jupytext
~/.local/share/nvim-py/bin/python -m ipykernel install --user --name python3 --display-name "Python 3 (nvim-py)"
# jupytext.nvim: hide the notebook metadata header in the buffer (kept in the .ipynb)
mkdir -p ~/.config/jupytext
cp "$DOT/jupytext/jupytext.toml" ~/.config/jupytext/jupytext.toml

step "LazyVim"
if [[ ! -d ~/.config/nvim ]]; then
  git clone --depth 1 https://github.com/LazyVim/starter ~/.config/nvim
  rm -rf ~/.config/nvim/.git
  # enable extras (inserted right after the core LazyVim import, as LazyVim expects)
  sed -i '/import = "lazyvim.plugins" },/a\
    { import = "lazyvim.plugins.extras.lang.python" },\
    { import = "lazyvim.plugins.extras.lang.typescript" },\
    { import = "lazyvim.plugins.extras.lang.tailwind" },\
    { import = "lazyvim.plugins.extras.lang.json" },\
    { import = "lazyvim.plugins.extras.lang.markdown" },\
    { import = "lazyvim.plugins.extras.lang.docker" },\
    { import = "lazyvim.plugins.extras.formatting.prettier" },\
    { import = "lazyvim.plugins.extras.linting.eslint" },' ~/.config/nvim/lua/config/lazy.lua
  cp "$DOT"/nvim/lua/plugins/*.lua ~/.config/nvim/lua/plugins/
  printf '\nvim.g.python3_host_prog = vim.fn.expand("~/.local/share/nvim-py/bin/python")\n' >> ~/.config/nvim/lua/config/options.lua
fi
nvim --headless "+Lazy! sync" +qa || true
nvim --headless "+UpdateRemotePlugins" +qa || true
echo "First interactive start of nvim finishes installing LSP servers via Mason (:Mason to watch)."

step "GNOME: extensions (Tiling Shell, Blur my Shell, ...), Thai keyboard, dark style, workspaces"
# a wrong GNOME setting must not stop Tailscale/SeaDrive/PhotoPrism below; reported again at the end
GNOME_OK=1; bash "$KIT/31-gnome-settings.sh" || GNOME_OK=0

step "Terminal look: Ptyxis (Gooey, translucent) + fastfetch + cava"
bash "$KIT/36-terminal-look.sh" || GNOME_OK=0

step "Desktop look: Gooey colours + blur for the shell, GNOME apps, Firefox, ONLYOFFICE, Neovim"
bash "$KIT/37-desktop-look.sh" || GNOME_OK=0

step "Tailscale (Seafile server lives on your tailnet)"
if ! tailscale status >/dev/null 2>&1; then
  echo "Log in to Tailscale in the browser window/URL that follows:"
  sudo tailscale up
fi

step "SeaDrive CLI (AppImage) as a user service that starts at boot"
SD_PAGE=$(curl -fsSL https://www.seafile.com/en/download/)
SD_URL=$(grep -oE 'https?://[^"]*SeaDrive-cli-x86_64-[0-9.]+\.AppImage' <<<"$SD_PAGE" | sed -n 1p)
[[ -n $SD_URL ]] || { echo "!! could not find the SeaDrive CLI download link on seafile.com"; exit 1; }
curl -fL "$SD_URL" -o ~/.local/bin/seadrive && chmod +x ~/.local/bin/seadrive
mkdir -p ~/.config/seadrive
if [[ ! -f ~/.config/seadrive/seadrive.conf ]]; then
  # your server's tailnet address: `tailscale status` lists it
  SF_URL=
  while [[ -z $SF_URL ]]; do read -rp "Seafile server URL (e.g. http://<tailscale-ip>:8000): " SF_URL; done
  read -rp  "Seafile login (username/email): " SF_USER
  read -rsp "Seafile password (used once to get a token, not stored): " SF_PW; echo
  TOKEN=$(curl -fsS -d "username=$SF_USER" --data-urlencode "password=$SF_PW" "$SF_URL/api2/auth-token/" | python3 -c 'import json,sys;print(json.load(sys.stdin)["token"])')
  unset SF_PW
  read -rp  "Local cache limit [10GB]: " SF_CACHE; SF_CACHE=${SF_CACHE:-10GB}
  umask 077
  cat > ~/.config/seadrive/seadrive.conf <<EOF
[account]
server = $SF_URL
username = $SF_USER
token = $TOKEN
is_pro = false

[general]
client_name = $(hostname)-debian

[cache]
size_limit = $SF_CACHE
clean_cache_interval = 10
EOF
  umask 022
fi
install -m 644 "$DOT/systemd/seadrive.service" ~/.config/systemd/user/
# lingering was enabled at the top: seadrive.service starts at boot, before you log in
systemctl --user daemon-reload
systemctl --user enable --now seadrive.service
sleep 5
systemctl --user is-active --quiet seadrive.service || {
  echo "!! seadrive.service is not running:"; systemctl --user status seadrive --no-pager | tail -15; exit 1; }
echo "SeaDrive is running: $(findmnt -n -o FSTYPE ~/SeaDrive || echo 'mounting...') at ~/SeaDrive"

step "PhotoPrism user service (off by default -> svc photoprism on)"
mkdir -p ~/.config/photoprism ~/.local/share/photoprism/{config,storage} ~/Pictures/import
if [[ ! -f ~/.config/photoprism/photoprism.env ]]; then
  read -rsp "Choose a PhotoPrism admin password (min 8 chars): " PP_PW; echo
  umask 077
  cat > ~/.config/photoprism/photoprism.env <<EOF
PHOTOPRISM_ADMIN_USER=admin
PHOTOPRISM_ADMIN_PASSWORD=$PP_PW
PHOTOPRISM_CONFIG_PATH=$HOME/.local/share/photoprism/config
PHOTOPRISM_STORAGE_PATH=$HOME/.local/share/photoprism/storage
PHOTOPRISM_ORIGINALS_PATH=$HOME/Pictures
PHOTOPRISM_IMPORT_PATH=$HOME/Pictures/import
PHOTOPRISM_DATABASE_DRIVER=sqlite
PHOTOPRISM_HTTP_HOST=127.0.0.1
PHOTOPRISM_HTTP_PORT=2342
PHOTOPRISM_SITE_URL=http://localhost:2342/
PHOTOPRISM_DISABLE_RAW=true
EOF
  umask 022; unset PP_PW
fi
install -m 644 "$DOT/systemd/photoprism.service" ~/.config/systemd/user/
systemctl --user daemon-reload

echo
(( GNOME_OK )) || echo "!! The GNOME, terminal or desktop-look step reported a problem (scroll up). Fix it, then rerun: bash $KIT/31-gnome-settings.sh / 36-terminal-look.sh / 37-desktop-look.sh"
echo "Done. Log out and back in (Tiling Shell + zsh + groups take effect)."
echo "Check everything afterwards with:  bash $KIT/32-check.sh"
echo "Then: 40-stm32cubeide.sh <installer>  and  41-packettracer.sh <deb>"
