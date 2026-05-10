#!/usr/bin/env bash
#
# tmux-resurrect-claude-sessions
#
# A tmux plugin that preserves Claude Code sessions across tmux restarts.
# Works with tmux-resurrect to map Claude Code pane titles to session UUIDs,
# so each pane resumes the exact Claude Code session it was running.
#
# License: GPL-3.0

CURRENT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

get_tmux_option() {
	local option="$1"
	local default_value="$2"
	local option_value
	option_value=$(tmux show-option -gqv "$option")
	if [ -z "$option_value" ]; then
		echo "$default_value"
	else
		echo "$option_value"
	fi
}

add_claude_to_resurrect_processes() {
	local existing
	existing=$(get_tmux_option "@resurrect-processes" "")
	if [[ "$existing" != *"claude"* ]]; then
		tmux set-option -g @resurrect-processes "${existing} ~claude"
	fi
}

register_post_save_hook() {
	local hook_script="${CURRENT_DIR}/scripts/post_save_hook.sh"
	local existing_hook
	existing_hook=$(get_tmux_option "@resurrect-hook-post-save-layout" "")

	if [ -n "$existing_hook" ]; then
		# Chain with existing hook to avoid conflicts
		tmux set-option -g @resurrect-hook-post-save-layout \
			"${existing_hook} && ${hook_script}"
	else
		tmux set-option -g @resurrect-hook-post-save-layout \
			"${hook_script}"
	fi
}

main() {
	add_claude_to_resurrect_processes
	register_post_save_hook
}

main
