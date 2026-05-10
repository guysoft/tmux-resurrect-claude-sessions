#!/usr/bin/env bash
#
# post_save_hook.sh
#
# Called by tmux-resurrect after saving pane layout (via @resurrect-hook-post-save-layout).
# Receives the save file path as $1.
#
# For each pane running Claude Code (via the claude-tmux wrapper), this script:
#   1. Extracts the session UUID from the pane title (format: "CC | <uuid>")
#   2. Verifies the session transcript exists on disk
#   3. Rewrites the saved command from "claude" to "claude --resume <uuid>"
#
# On restore, tmux-resurrect will re-run the rewritten command, resuming the exact session.
#
# License: GPL-3.0

set -euo pipefail

RESURRECT_FILE="${1:-}"

# --- Preflight checks ---

if [ -z "$RESURRECT_FILE" ] || [ ! -f "$RESURRECT_FILE" ]; then
	exit 0
fi

# --- Helper functions ---

# Encode a directory path the way Claude Code does for its projects folder
# /Users/foo/workspace → -Users-foo-workspace
encode_cwd() {
	echo "$1" | sed 's|^/||; s|/|-|g; s|^|-|'
}

# Check if a Claude Code session transcript exists
session_exists() {
	local uuid="$1"
	local pane_dir="$2"
	local encoded
	encoded=$(encode_cwd "$pane_dir")
	local projects_dir="${HOME}/.claude/projects/${encoded}"

	[ -f "${projects_dir}/${uuid}.jsonl" ]
}

# --- Main processing ---

tmpfile="$(mktemp "${RESURRECT_FILE}.XXXXXX")"
trap 'rm -f "$tmpfile"' EXIT

modified=0

while IFS= read -r line || [ -n "$line" ]; do
	# Only process pane lines (tab-delimited, starts with "pane")
	if [[ "$line" != pane$'\t'* ]]; then
		printf '%s\n' "$line" >> "$tmpfile"
		continue
	fi

	# Split into fields by tab
	IFS=$'\t' read -r line_type sess_name win_idx win_active win_flags \
		pane_idx pane_title pane_dir pane_active pane_cmd full_cmd <<< "$line"

	# Only process panes running claude with a Claude Code pane title
	if [[ "$pane_cmd" == "claude" ]] && [[ "$pane_title" == "CC | "* ]]; then
		# Extract the UUID from the pane title
		uuid="${pane_title#CC | }"

		# Validate UUID format (lowercase hex with dashes, 36 chars)
		if [[ "$uuid" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]]; then
			# Verify the session transcript exists
			if session_exists "$uuid" "$pane_dir"; then
				full_cmd=":claude --resume ${uuid}"
				modified=1
			fi
		fi
	fi

	printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
		"$line_type" "$sess_name" "$win_idx" "$win_active" "$win_flags" \
		"$pane_idx" "$pane_title" "$pane_dir" "$pane_active" "$pane_cmd" \
		"$full_cmd" >> "$tmpfile"
done < "$RESURRECT_FILE"

# Only overwrite if we actually changed something
if [ "$modified" -eq 1 ]; then
	mv "$tmpfile" "$RESURRECT_FILE"
else
	rm -f "$tmpfile"
fi

trap - EXIT
