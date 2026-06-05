#!/bin/sh
# Claude Code attention marker (tab level).
#
# Prefixes the window name with 🔴 when the window's bell flag is set. Claude Code
# rings the terminal bell (preferredNotifChannel=terminal_bell) on permission prompts
# and idle waits; with monitor-bell on, tmux flags that window.
#
# Why a script instead of `set -g window-status-format '...'`: the active theme
# (egel/tmux-gruvbox) builds its format from powerline separator glyphs that don't
# survive being copied as text. So we read whatever format the theme already set and
# inject the marker right before #W (the window name) byte-for-byte via sed, leaving
# the theme's glyphs intact. Idempotent, and re-syncs automatically if the theme changes.
#
# Run this AFTER the theme loads (i.e. after tpm) — see ~/.tmux.conf.

fmt=$(tmux show-options -gwv window-status-format)

case "$fmt" in
  *'#{?window_bell_flag,🔴 ,}#W'*)
    # Already injected (e.g. helper ran twice without a theme reload) — do nothing.
    exit 0
    ;;
  *)
    tmux set -g window-status-format \
      "$(printf '%s' "$fmt" | sed 's/#W/#{?window_bell_flag,🔴 ,}#W/')"
    ;;
esac
