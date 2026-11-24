# Image Usage for Omarchy

A native Omarchy bar widget for your ChatGPT subscription's image generation
limit, the one Codex's built-in `image_gen` tool runs into. It shows how much
of the limit is used and when it resets. It looks and behaves like the
first-party `omarchy.agents` panel, and it follows the theme.

- **Bar:** an image icon. It turns the urgent color once the share used
  reaches your warning threshold. Hovering it shows the summary.
  Left click opens the panel. Middle or right click refreshes.
- **Panel:** the plan, one meter per limit window with the time to its reset,
  and the exact share used and reset time on hover.
  Keys: `r` refreshes, Enter runs the selected action, and Esc closes.

## Install

```bash
omarchy plugin add https://github.com/YousefElGhoul/omarchy-image-usage.git --enable
```

You can also place it with `omarchy plugin enable io.github.yousefelghoul.image-usage --section right`.

Requirements: Python 3.11+ and a Codex CLI signed in with ChatGPT
(`codex login`). There are no other dependencies.

## Remove

```bash
omarchy plugin remove io.github.yousefelghoul.image-usage
```

This leaves the cached usage data in `${XDG_STATE_HOME:-$HOME/.local/state}/omarchy/image-usage/`.
If you no longer want the cache, you can delete that directory after removing the plugin.

## Settings

| Key | Default | Meaning |
|---|---|---|
| `refreshIntervalSec` | `300` | How often to check, in seconds (minimum 60). |
| `warnPercent` | `90` | The share used (%) at which the icon and meter turn the urgent color. |

IPC: `omarchy-shell io.github.yousefelghoul.image-usage open|close|toggle|refresh`.

## How it works

`bin/omarchy-image-usage` is a collector in the style of Omarchy's
`omarchy-agent-usage-*` collectors. It prints one display-ready JSON record
and writes it atomically to
`$XDG_STATE_HOME/omarchy/image-usage/usage.json`, which the panel watches.

**Where the limit comes from.** These sources don't report it:

- the Codex app-server's `account/rateLimits/read`;
- `/backend-api/wham/usage`;
- ChatGPT's web-app image counter (`conversation/init`), which is a different
  allowance from the one that turns Codex away.

Codex's image endpoint reports the limit in the same `x-codex-*` headers the
Responses API uses for the Codex windows:

```
x-codex-active-limit: imagegen_premium
x-codex-primary-used-percent: 100
x-codex-primary-window-minutes: 1440
x-codex-primary-reset-at: <epoch seconds>
```

The collector sends `POST https://chatgpt.com/backend-api/codex/images/edits`
with an empty JSON object. An edit with neither a prompt nor an image can't
produce anything, but the request passes the limit check, which answers with
those headers. When the limit is reached, it answers `429 usage_limit_reached`
with `resets_at`. The endpoint is undocumented and may change without notice.
The collector only sends credentials to the official `chatgpt.com` endpoint
and does not follow redirects. Custom Codex backend URLs are not supported.
The server reports a share used, not a number of images, so the panel shows a
share.

**Authentication reuses Codex's ChatGPT sign-in, and nothing new signs in:**

1. For the active Codex account, the collector asks `omarchy-agent-account-home codex`, so
   Omarchy's account switching is followed. It falls back to `CODEX_HOME`, then
   `~/.codex`.
2. A file-store login whose access token is still valid is read from
   `auth.json`.
3. A keyring or auto credential store, an expiring token, or a token ChatGPT
   rejects goes through `codex app-server` (`getAuthStatus` with
   `includeToken` and `refreshToken`, plus `account/read`). Codex refreshes and
   stores the token itself.

The collector never writes credentials. The record holds no email or account
IDs, only a short hash that keeps one account's numbers apart from another's.

**Caching and failures.** A record under a minute old answers any refresh that
isn't forced, so opening the panel repeatedly or running a bar on several
monitors sends one request. A file lock keeps it to one request at a time. When
a check fails, the last good numbers stay on show with their age and an
ⓘ note explaining why. A network failure triggers one retry 30 seconds later.
Once a window's reset time passes, the panel shows it as empty until the next
reading.

## Manual run

```bash
bin/omarchy-image-usage --print-only | jq   # check without writing the record
bin/omarchy-image-usage --force             # skip the one-minute reuse
```

## Credits

The Codex mark in `assets/` comes from Omarchy's `omarchy.agents` plugin (MIT).
The panel's layout and components follow that plugin.
