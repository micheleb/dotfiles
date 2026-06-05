# Installing these dotfiles (agent guide)

These are my personal dotfiles. If you're a coding agent and I've asked you to install or sync them, this is for you. The README is the human version; this is the one with the sharp edges marked.

The repo mirrors `$HOME`. A file tracked at `.tmux.conf` goes to `~/.tmux.conf`, `.claude/settings.json` to `~/.claude/settings.json`, `.tmux/claude-attention-marker.sh` to `~/.tmux/claude-attention-marker.sh`. There's no installer and no symlink farm — you put files in place yourself.

One rule above all: **this machine probably already has some of these files. Read the target before you write it, and merge — keep what's there, add what's mine.** Copying blindly over an existing `~/.claude/settings.json` or `~/.tmux.conf` destroys real config. When a target doesn't exist, copy mine straight over.

## What's actually worth understanding

Most of this is ordinary shell and editor config (zsh, vim, powerline). Copy it and move on; the README has the manual bits like setting `ZSH_THEME` and the powerline colorscheme. The part that needs explaining is a small system that flags which Claude Code session wants my attention, so I can run several across tmux panes and tabs and not miss one. Read this before you merge it — the pieces span two files plus a script, and they fail quietly when they're wrong.

It comes in two halves.

Tab dots: when a Claude session needs input (a permission prompt, or it's gone idle) it rings the terminal bell. tmux's `monitor-bell` catches that and sets the window's bell flag, and a red dot (`🔴`) appears next to that window's name in the status bar, injected just before `#W` in `window-status-format`. tmux clears a window's bell flag the moment you focus it, so the dot only ever shows on tabs you're *not* looking at. That's the point of it.

Pane dots: tmux tracks the bell per window, not per pane, so the bell alone can't say which pane inside a tab is waiting. Instead, Claude hooks set a per-pane tmux variable, `@claude_attention`, and `pane-border-format` renders `🔴 WAITING` on that pane's border. `Stop` and `Notification` set it; `UserPromptSubmit` clears it.

### .claude/settings.json

No existing file: copy mine. Existing file: merge in two things and leave the rest alone — `"preferredNotifChannel": "terminal_bell"`, and the three hooks (`Notification`, `Stop`, `UserPromptSubmit`) under `"hooks"`. If they already have hooks on those events, append to the event's array rather than replacing it.

**Keep the file valid JSON.** This is the trap that cost me a debugging session: one trailing comma (say, after the last entry in `permissions.allow`) makes Claude fail to load the whole file. It doesn't complain — the hooks just stop firing and the bell goes silent, so the dots vanish with no obvious cause. Validate after every edit:

```
node -e "JSON.parse(require('fs').readFileSync(process.env.HOME+'/.claude/settings.json','utf8'))" && echo ok
```

No restart needed. Claude watches the settings file and reloads hooks and `preferredNotifChannel` on change, in every running session.

### .tmux.conf

No existing file: copy mine. Existing file: add three things and don't touch their prefix, bindings, or theme:

- `set -g monitor-bell on`
- the `pane-border-status` and `pane-border-format` lines
- `run-shell -b 'sleep 1; ~/.tmux/claude-attention-marker.sh'`, placed *after* the `run '~/.tmux/plugins/tpm/tpm'` line

Order matters for that last one. The theme sets `window-status-format` while tpm loads it, so the helper has to run afterward or it injects into the wrong (or empty) format. The `-b` and `sleep 1` are a deliberate hack: they background the helper and give tpm a moment to finish, because plugin loading isn't strictly synchronous.

**Do not hand-edit `window-status-format`.** The theme I use (gruvbox) builds the tab out of powerline separator glyphs — private-use Unicode characters. They don't survive being copied as text: they disappear, and you're left with mangled tabs and the dot on the wrong tab. That whole class of bug is why the helper exists. It reads the live format with `tmux show-options` and injects the dot with `sed`, touching only the bytes around `#W` and leaving the glyphs intact. Let the script do it; never retype the format string.

The dots don't actually depend on gruvbox. Any theme works as long as `monitor-bell` is on and the format contains `#W`. Some themes enable `monitor-bell` themselves and some don't, so set it explicitly.

### .tmux/claude-attention-marker.sh

Copy it to `~/.tmux/claude-attention-marker.sh` and make it executable (`chmod +x`). Leave the rest of `~/.tmux/` alone — `~/.tmux/plugins/` is tpm's and isn't tracked here. The script guards against double-injecting, so re-running it or reloading the config is safe.

## After installing

Reload tmux with `tmux source-file ~/.tmux.conf` (or `prefix + r`). On a brand-new machine, install tpm first and press `prefix + I` to fetch the plugins, or the theme and the markers have nothing to attach to.

Then check the pieces:

- the settings file parses (the `node -e` command above exits clean)
- `tmux show -gwv window-status-format | grep -q '#{?window_bell_flag,🔴 ,}#W'` finds the injected marker — if not, run the helper by hand and look again
- `tmux show -gwv pane-border-status` prints `top`
- `test -x ~/.tmux/claude-attention-marker.sh`
- in a Claude session, `/hooks` lists `Notification`, `Stop`, and `UserPromptSubmit`

For an end-to-end check, leave a Claude session working in a tab you're not viewing and wait for it to want input. Its tab should get the dot, and switching to it should clear it.
