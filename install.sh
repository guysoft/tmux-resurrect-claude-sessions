#!/usr/bin/env bash
#
# install.sh - Install tmux-resurrect-claude-sessions plugin
#
# This script:
#   1. Symlinks the plugin to ~/.tmux/plugins/tmux-resurrect-claude-sessions/
#   2. Creates a 'claude-tmux' symlink in ~/.local/bin/ for use as @ide-agent
#   3. Adds the plugin to ~/.tmux.conf if not already present
#   4. Reloads tmux config if tmux is running
#
# Usage:
#   ./install.sh           # Install
#   ./install.sh --remove  # Uninstall
#
# License: GPL-3.0

set -euo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PLUGIN_DIR="$HOME/.tmux/plugins/tmux-resurrect-claude-sessions"
BIN_DIR="$HOME/.local/bin"
TMUX_CONF="$HOME/.tmux.conf"
PLUGIN_LINE="set -g @plugin 'guysoft/tmux-resurrect-claude-sessions'"

# --- Colors ---

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

info()  { echo -e "${GREEN}[+]${NC} $1"; }
warn()  { echo -e "${YELLOW}[!]${NC} $1"; }
error() { echo -e "${RED}[-]${NC} $1"; }

# --- Cross-platform sed -i ---

sed_inplace() {
	if [[ "$OSTYPE" == "darwin"* ]]; then
		sed -i '' "$@"
	else
		sed -i "$@"
	fi
}

# --- Uninstall ---

uninstall() {
	info "Uninstalling tmux-resurrect-claude-sessions..."

	if [ -L "$PLUGIN_DIR" ] || [ -d "$PLUGIN_DIR" ]; then
		rm -rf "$PLUGIN_DIR"
		info "Removed $PLUGIN_DIR"
	fi

	if [ -L "$BIN_DIR/claude-tmux" ]; then
		rm "$BIN_DIR/claude-tmux"
		info "Removed $BIN_DIR/claude-tmux symlink"
	fi

	if [ -f "$TMUX_CONF" ] && grep -qF "$PLUGIN_LINE" "$TMUX_CONF"; then
		sed_inplace "\|${PLUGIN_LINE}|d" "$TMUX_CONF"
		info "Removed plugin line from $TMUX_CONF"
	fi

	if [ -n "${TMUX:-}" ]; then
		tmux source-file "$TMUX_CONF" 2>/dev/null || true
		info "Reloaded tmux config"
	fi

	info "Uninstall complete."
	exit 0
}

# --- Install ---

install() {
	info "Installing tmux-resurrect-claude-sessions..."

	# 1. Install plugin directory
	mkdir -p "$(dirname "$PLUGIN_DIR")"

	if [ "$SCRIPT_DIR" = "$PLUGIN_DIR" ]; then
		info "Already installed at $PLUGIN_DIR"
	elif [ -d "$PLUGIN_DIR" ] || [ -L "$PLUGIN_DIR" ]; then
		warn "Existing installation found at $PLUGIN_DIR, replacing..."
		rm -rf "$PLUGIN_DIR"
		ln -sfn "$SCRIPT_DIR" "$PLUGIN_DIR"
		info "Symlinked $SCRIPT_DIR -> $PLUGIN_DIR"
	else
		ln -sfn "$SCRIPT_DIR" "$PLUGIN_DIR"
		info "Symlinked $SCRIPT_DIR -> $PLUGIN_DIR"
	fi

	# 2. Create 'claude-tmux' CLI command symlink
	mkdir -p "$BIN_DIR"
	ln -sfn "$SCRIPT_DIR/scripts/claude-tmux" "$BIN_DIR/claude-tmux"
	info "Created 'claude-tmux' command at $BIN_DIR/claude-tmux"

	if [[ ":$PATH:" != *":$BIN_DIR:"* ]]; then
		warn "$BIN_DIR is not in your PATH. Add it to your shell profile:"
		warn "  export PATH=\"\$HOME/.local/bin:\$PATH\""
	fi

	# 3. Add plugin to tmux.conf
	if [ ! -f "$TMUX_CONF" ]; then
		warn "$TMUX_CONF not found. Creating it..."
		echo "$PLUGIN_LINE" > "$TMUX_CONF"
		info "Created $TMUX_CONF with plugin line"
	elif grep -qF "tmux-resurrect-claude-sessions" "$TMUX_CONF"; then
		info "Plugin already in $TMUX_CONF"
	else
		if grep -qE "run.*(tpack init|tpm/tpm)" "$TMUX_CONF"; then
			awk -v line="$PLUGIN_LINE" '/run.*(tpack init|tpm\/tpm)/{print line}{print}' "$TMUX_CONF" > "$TMUX_CONF.tmp" && mv "$TMUX_CONF.tmp" "$TMUX_CONF"
			info "Added plugin to $TMUX_CONF (before plugin manager init)"
		else
			echo "$PLUGIN_LINE" >> "$TMUX_CONF"
			info "Appended plugin to $TMUX_CONF"
		fi
	fi

	# 4. Reload tmux config if inside tmux
	if [ -n "${TMUX:-}" ]; then
		tmux source-file "$TMUX_CONF" 2>/dev/null || true
		info "Reloaded tmux config"
	else
		warn "Not inside tmux. Reload config manually: tmux source-file $TMUX_CONF"
	fi

	echo ""
	info "Installation complete!"
	echo ""
	echo "  Usage:"
	echo "    In ~/.tmux.conf:"
	echo "      set -g @ide-agent \"claude-tmux\""
	echo ""
	echo "    Or run directly:"
	echo "      claude-tmux"
	echo ""
}

# --- Main ---

if [ "${1:-}" = "--remove" ] || [ "${1:-}" = "uninstall" ]; then
	uninstall
else
	install
fi
