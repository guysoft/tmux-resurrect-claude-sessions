# tmux-resurrect-claude-sessions

A [tmux](https://github.com/tmux/tmux) plugin that preserves [Claude Code](https://claude.ai/code) sessions across tmux restarts.

When tmux dies and [tmux-resurrect](https://github.com/tmux-plugins/tmux-resurrect) restores your panes, Claude Code panes normally come back as empty shells. This plugin makes them resume the **exact session** they were running before.

## How It Works

1. The `claude-tmux` wrapper (shipped with this plugin) launches Claude Code with a pinned `--session-id <uuid>` and sets the tmux pane title to `CC | <uuid>`.
2. tmux-resurrect saves pane titles in its save file (every 15 minutes via tmux-continuum, or on manual save).
3. After each save, this plugin's hook:
   - Extracts the session UUID from each Claude Code pane title
   - Verifies the session transcript exists on disk (`~/.claude/projects/<encoded-cwd>/<uuid>.jsonl`)
   - Rewrites the saved command from `claude` to `claude --resume <uuid>`
4. On restore, tmux-resurrect runs the rewritten command, and Claude Code resumes the exact session.

## Requirements

- [tmux](https://github.com/tmux/tmux) >= 2.0
- [tmux-resurrect](https://github.com/tmux-plugins/tmux-resurrect)
- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) CLI (`claude`)

## Installation

### One-Line Install

```bash
git clone https://github.com/guysoft/tmux-resurrect-claude-sessions ~/.tmux/plugins/tmux-resurrect-claude-sessions \
  && ~/.tmux/plugins/tmux-resurrect-claude-sessions/install.sh
```

This will:
1. Symlink the plugin into `~/.tmux/plugins/tmux-resurrect-claude-sessions/`
2. Create a `claude-tmux` command in `~/.local/bin/`
3. Add the plugin to `~/.tmux.conf` (before tpack/TPM init if present)
4. Reload your tmux config

### With [TPM](https://github.com/tmux-plugins/tpm)

Add this line to your `~/.tmux.conf`, **after** tmux-resurrect and **before** the TPM init line:

```tmux
set -g @plugin 'tmux-plugins/tmux-resurrect'
set -g @plugin 'tmux-plugins/tmux-continuum'                    # optional, for auto-save/restore
set -g @plugin 'guysoft/tmux-resurrect-claude-sessions'         # <-- add this
set -g @plugin 'guysoft/tmux-ide'

set -g @ide-agent "claude-tmux"
set -g @resurrect-processes '~claude'

# Initialize TPM (keep at the very bottom)
run '~/.tmux/plugins/tpm/tpm'
```

Then press `prefix + I` to install.

After install, create the `claude-tmux` symlink:

```bash
~/.tmux/plugins/tmux-resurrect-claude-sessions/install.sh
```

### With [tpack](https://github.com/tmuxpack/tpack)

Same as TPM but replace the init line with `run 'tpack init'`.

### Manual

Clone the repo:

```bash
git clone https://github.com/guysoft/tmux-resurrect-claude-sessions \
    ~/.tmux/plugins/tmux-resurrect-claude-sessions
```

Add to `~/.tmux.conf`:

```tmux
run-shell ~/.tmux/plugins/tmux-resurrect-claude-sessions/claude-sessions.tmux
```

## Usage

### Setting up the agent

In `~/.tmux.conf`, configure [tmux-ide](https://github.com/guysoft/tmux-ide) to use the `claude-tmux` wrapper:

```tmux
set -g @ide-agent "claude-tmux"
```

When you press `prefix + e`, the IDE layout spawns with Claude Code in the right pane, session-tracked automatically.

### GuyIDE config.yaml

If you use [GuyIDE](https://github.com/guysoft/GuyIDE), set Claude Code as the agent in `~/.guyide/config.yaml`:

```yaml
# ~/.guyide/config.yaml
schema: guyide/config/v1
channel: stable
components:
  editor:
    driver: nvim
  multiplexer:
    driver: tmux
  agent:
    driver: claude-code          # was: opencode (default)
claude-code:
  cli: claude                    # executable name (default)
  extra_args: ["--model", "opus"] # optional passthrough flags
```

Then re-run `guyide install` — it will wire up `claude-tmux` and install this plugin automatically.

### Passing extra flags to Claude

The `claude-tmux` wrapper passes all arguments through to `claude`:

```tmux
set -g @ide-agent "claude-tmux --model opus"
```

### Manual save/restore

- **Save**: `prefix + Ctrl-s` (or automatic via tmux-continuum)
- **Restore**: `prefix + Ctrl-r` (or automatic on tmux server start via tmux-continuum)

After a restore, each pane that was running Claude Code will resume the same session it had before.

## How It Works (Technical Details)

### Pane Title Contract

The `claude-tmux` wrapper sets the tmux pane title to `CC | <uuid>` before launching Claude Code. This mirrors how OpenCode sets pane titles to `OC | <session title>`, but uses the session UUID directly (deterministic, no fuzzy matching needed).

### Session Storage

Claude Code stores session transcripts as JSONL files:

```
~/.claude/projects/<encoded-cwd>/<session-uuid>.jsonl
```

Where `<encoded-cwd>` is the working directory with `/` replaced by `-` (e.g., `/Users/foo/project` becomes `-Users-foo-project`).

### Save Flow

```
tmux-resurrect saves pane state
        |
        v
post-save-layout hook fires
        |
        v
For each pane where command = "claude"
and pane title matches "CC | <uuid>":
        |
        v
Validate UUID format -> verify .jsonl exists on disk
        |
        v
Rewrite command: "claude ..." -> "claude --resume <uuid>"
        |
        v
Modified save file written back
```

### Restore Flow

```
tmux-resurrect reads save file
        |
        v
Sees "claude --resume <uuid>"
(matches "claude" in @resurrect-processes)
        |
        v
Sends command to pane via send-keys
        |
        v
Claude Code resumes the exact session
```

### Save File Format

tmux-resurrect saves pane state in a tab-delimited text file. The relevant fields:

| Field | Description |
|-------|-------------|
| Column 7 | Pane title (e.g., `CC \| a1b2c3d4-...`) |
| Column 8 | Pane working directory |
| Column 10 | Pane command (e.g., `claude`) |
| Column 11 | Full command (e.g., `:claude --session-id a1b2c3d4-...`) |

The plugin rewrites Column 11 with the session-specific resume command.

## Troubleshooting

### Claude Code panes still open fresh sessions after restore

1. Check that `claude-tmux` is on your PATH: `which claude-tmux`
2. Verify the pane title is being set: in a Claude Code pane, run `tmux display-message -p '#{pane_title}'` — it should show `CC | <uuid>`
3. Trigger a manual save (`prefix + Ctrl-s`), then inspect the save file:
   ```bash
   grep claude ~/.local/share/tmux/resurrect/last
   ```
   You should see lines like `:claude --resume <uuid>` in the last column.

### Session transcript not found (pane opens fresh)

The plugin validates that `~/.claude/projects/<encoded-cwd>/<uuid>.jsonl` exists before rewriting. If the transcript was deleted or rotated, the pane will open a fresh Claude session instead. This is by design — better a fresh session than a crash.

### The plugin conflicts with another resurrect hook

This plugin uses the `@resurrect-hook-post-save-layout` hook. If another plugin also uses this hook, the plugin will chain them together with `&&` so both run. If you experience issues, check:
```bash
tmux show-option -gv @resurrect-hook-post-save-layout
```

## Comparison with tmux-resurrect-opencode-sessions

| Feature | opencode plugin | claude plugin |
|---------|----------------|---------------|
| Pane title format | `OC \| <session title>` | `CC \| <uuid>` |
| Session lookup | SQLite DB query by title prefix | Direct UUID → file path |
| Resume flag | `opencode --session <id>` | `claude --resume <uuid>` |
| Wrapper needed | No (opencode sets title natively) | Yes (`claude-tmux`) |
| Multiple sessions per cwd | Disambiguated by title | Disambiguated by UUID (deterministic) |

## Related Plugins

- [tmux-resurrect-opencode-sessions](https://github.com/guysoft/tmux-resurrect-opencode-sessions) — Same concept for OpenCode
- [tmux-ide](https://github.com/guysoft/tmux-ide) — 3-pane IDE layout that spawns the agent
- [tmux-resurrect](https://github.com/tmux-plugins/tmux-resurrect) — Save and restore tmux sessions
- [tmux-continuum](https://github.com/tmux-plugins/tmux-continuum) — Automatic save and restore

## License

GPL-3.0. See [LICENSE](LICENSE) for details.
