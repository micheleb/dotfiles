# Installing these dotfiles (agent guide)

These are my personal dotfiles. If you're a coding agent and I've asked you to install or sync them, this is for you. The README is the human version; this is the one with the sharp edges marked.

The repo mirrors `$HOME`. A file tracked at `.tmux.conf` goes to `~/.tmux.conf`, `.claude/settings.json` to `~/.claude/settings.json`, `.tmux/claude-attention-marker.sh` to `~/.tmux/claude-attention-marker.sh`. There's no installer and no symlink farm — you put files in place yourself.

One rule above all: **this machine probably already has some of these files. Read the target before you write it, and merge — keep what's there, add what's mine.** Copying blindly over an existing `~/.claude/settings.json` or `~/.tmux.conf` destroys real config. When a target doesn't exist, copy mine straight over.

## What's actually worth understanding

Most of this is ordinary shell and editor config (zsh, vim, powerline). Copy it and move on; the README has the manual bits like setting `ZSH_THEME` and the powerline colorscheme. The part that needs explaining is a small system that flags which Claude Code session wants my attention, so I can run several across tmux panes and tabs and not miss one. Read this before you merge it — the pieces span two files plus a script, and they fail quietly when they're wrong.

It comes in two halves.

Tab dots: when a Claude session needs input (a permission prompt, or it's gone idle) it rings the terminal bell. tmux's `monitor-bell` catches that and sets the window's bell flag, and a red dot (`🔴`) appears next to that window's name in the status bar, injected just before `#W` in `window-status-format`. tmux clears a window's bell flag the moment you focus it, so the dot only ever shows on tabs you're *not* looking at. That's the point of it.

Pane dots: tmux tracks the bell per window, not per pane, so the bell alone can't say which pane inside a tab is waiting. Instead, Claude hooks set a per-pane tmux variable, `@claude_attention`, and `pane-border-format` renders `🔴 WAITING` on that pane's border (and `pane-border-style` turns the border red). `Stop` and `Notification` set it; `UserPromptSubmit` clears it; the `pane-focus-in/out` hooks also clear it on focus changes.

**What clears the marker.** It's set by `Notification`/`Stop` and cleared by several events:
- `UserPromptSubmit` — typing in the **main prompt and pressing Enter**;
- `PostToolUse` (matcher `*`) — **any tool completing**. This is the important one: answering an
  in-conversation question (`AskUserQuestion`) and approving a **permission prompt** are both tool
  completions, so this is what clears the marker in those cases. `UserPromptSubmit` alone does
  NOT fire for them — that's why the `PostToolUse` hook exists.
- `pane-focus-in/out` — switching focus.

The one thing that genuinely **can't** clear it: **plain typing without submitting** — tmux/Claude
have no keystroke hook, so nothing fires until you actually submit/answer/act or change focus.
Also: `Notification` (which *sets* the marker) fires for permission prompts and ~60s idle, but
**not** for auto-approved tool calls — so an auto-approved command won't turn the border red.

**Don't add `tmux refresh-client` to the hooks as a "redraw nudge."** Setting/unsetting a `@` option already forces a full client redraw in tmux (`options_push_changes()` → `server_redraw_client()`), so the border repaints on the hook's `set-option` alone — `refresh-client` is redundant. It also correlated with the bell/tab-dot going silent during testing (cause unconfirmed), so it's both unnecessary and risky. If a marker seems not to clear on a genuine clean submit, suspect hook firing/targeting (log `$TMUX_PANE` / `#{pane_id}` / `#{window_id}`), not tmux's ability to redraw.

### .claude/settings.json

No existing file: copy mine. Existing file: merge in two things and leave the rest alone — `"preferredNotifChannel": "terminal_bell"`, and the four hooks (`Notification`, `Stop`, `UserPromptSubmit`, `PostToolUse`) under `"hooks"`. If they already have hooks on those events, append to the event's array rather than replacing it. (`Notification`/`Stop` *set* `@claude_attention`; `UserPromptSubmit` and `PostToolUse` with matcher `*` *clear* it — see the behavioral note below for why `PostToolUse` is needed.)

**Keep the file valid JSON.** This is the trap that cost me a debugging session: one trailing comma (say, after the last entry in `permissions.allow`) makes Claude fail to load the whole file. It doesn't complain — the hooks just stop firing and the bell goes silent, so the dots vanish with no obvious cause. Validate after every edit:

```
node -e "JSON.parse(require('fs').readFileSync(process.env.HOME+'/.claude/settings.json','utf8'))" && echo ok
```

No restart needed. Claude watches the settings file and reloads hooks and `preferredNotifChannel` on change, in every running session.

### .tmux.conf

No existing file: copy mine. Existing file: add these and don't touch their prefix, bindings, or theme:

- `set -g monitor-bell on`
- `set -g focus-events on`
- the `pane-border-status` and `pane-border-format` lines
- `run-shell -b 'sleep 1; ~/.tmux/claude-attention-marker.sh'`, placed *after* the `run '~/.tmux/plugins/tpm/tpm'` line
- `set -gw window-status-bell-style default`, also *after* tpm
- `set-hook -g pane-focus-in 'set -pu @claude_attention'` and `set-hook -g pane-focus-out 'set -pu @claude_attention'`
- the two `pane-*-border-style` lines that redden the border while WAITING, also *after* tpm

Order matters for the `run-shell` line. The theme sets `window-status-format` while tpm loads it, so the helper has to run afterward or it injects into the wrong (or empty) format. The `-b` and `sleep 1` are a deliberate hack: they background the helper and give tpm a moment to finish, because plugin loading isn't strictly synchronous.

**`focus-events on` is not optional, and the failure is silent.** Claude only rings the bell when it believes its terminal is unfocused (so it doesn't beep at you while you're watching it). Inside tmux, Claude learns it lost focus only from the focus-out escape sequence tmux sends — and tmux sends it *only* when `focus-events` is on. With it off, Claude thinks it's always focused, never rings the bell, and you get no sound and no tab dot even from a tab you're not looking at. The WAITING pane label still shows (it's driven by hooks, not the bell), which is exactly the misleading half-working state that hides the cause. This same setting is what makes the `pane-focus-in` hook fire.

**`window-status-bell-style default` undoes a theme default.** gruvbox (and nord, and others) reverse-video a tab when its bell rings, which greys out the whole tab — ugly, and redundant once the 🔴 dot is the signal. Setting the bell style to `default` keeps the tab's normal colors; the dot alone marks it. Must come after tpm, since the theme sets the style during load.

**The `pane-focus-in` / `pane-focus-out` hooks clear the WAITING marker on focus changes.** Without them the marker only clears on `UserPromptSubmit` (i.e. when you press Enter), so a pane you've glanced at but not answered keeps saying WAITING. focus-in clears it when you look at the pane; focus-out clears it when you leave (handy when Claude stops while you're already *in* its pane — otherwise that marker lingers until you hit Enter). Both clear per *pane*, not per window. The focus-out hook fires for the pane *losing* focus (verified), so `set -pu` with no `-t` targets the right one. Tradeoff: switching away from a multi-pane window clears that pane's marker immediately, so returning won't show which pane had been waiting — fine for one-Claude-per-tab. Both need `focus-events on`.

**The red border is the one theme-coupled piece.** tmux style options accept `#{...}` formats evaluated per pane, so `pane-active-border-style` / `pane-border-style` branch on `@claude_attention` to go red while WAITING. The catch is the *else* branch: setting these overrides the theme's own border colors, so the non-waiting branch has to reproduce them or panes change color when idle. Commas inside a style (`fg=red,bold`) are escaped `#,` so they aren't read as the `#{?}` separator; the `#` in a hex color is fine. Must come after tpm.

The two themes I actually use — match the else branch to whichever one is loaded:

- **gruvbox dark** (egel/tmux-gruvbox) — what the repo's tracked `.tmux.conf` ships. Active `fg=#d5c4a1` (col_fg2), inactive `fg=#3c3836` (col_bg1); pulled from `src/palette_gruvbox_dark.sh` + `src/theme_gruvbox_dark.sh`. So:
  - `set -g pane-active-border-style '#{?@claude_attention,fg=red#,bold,fg=#d5c4a1}'`
  - `set -g pane-border-style '#{?@claude_attention,fg=red,fg=#3c3836}'`
- **nord** (nordtheme/tmux) — active `bg=default,fg=blue`, inactive `bg=default,fg=brightblack`; straight from `src/nord.conf`. Note the extra `bg=default` (nord sets it), and the commas inside each else branch must also be escaped `#,`:
  - `set -g pane-active-border-style '#{?@claude_attention,fg=red#,bold,bg=default#,fg=blue}'`
  - `set -g pane-border-style '#{?@claude_attention,fg=red,bg=default#,fg=brightblack}'`

On any other theme, look up its border colors the same way and use them as the else branch (or use `default` and accept a slightly different idle border).

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
- `tmux show -gv focus-events` prints `on`
- `tmux show -gwv window-status-bell-style` prints `default`
- `tmux show-hook -g pane-focus-in` prints `pane-focus-in[0] set-option -pu @claude_attention` (and `pane-focus-out` likewise)
- `test -x ~/.tmux/claude-attention-marker.sh`
- in a Claude session, `/hooks` lists `Notification`, `Stop`, and `UserPromptSubmit`

For an end-to-end check, leave a Claude session working in a tab you're not viewing and wait for it to want input. Its tab should get the dot (in the tab's normal colors, not greyed out) and the terminal should beep; switching to it should clear both the dot and the pane's WAITING marker.
