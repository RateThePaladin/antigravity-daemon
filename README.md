# Antigravity Headless Daemon

A lightweight, headless Docker wrapper for the Google Antigravity CLI. Designed to run as a persistent remote-control daemon (perfect for Unraid, TrueNAS, or generic Docker hosts), with dynamic configuration via environment variables.

This container strictly follows Unraid Community Application best practices:
- **PUID / PGID Support:** Runs as `nobody:users` to prevent root permission errors.
- **Centralized `/config`:** Uses a single mapped directory for all persistent data.
- **Robust Toolchain:** Pre-installed with Go, Python 3, Node.js, `npm`, `pip`, and `build-essential` so the agent can natively compile and test code without friction.
- **PowerPoint Generation & Rendering:** Includes `python-pptx`, `pptxgenjs`, `pandoc`, `matplotlib`, `Pillow`, `librsvg2-bin`, LibreOffice Impress, `poppler-utils` (`pdftoppm`), and metric-compatible fonts (`Carlito`, `Caladea`, `Liberation`, `DejaVu`, `Noto`) so the agent can build `.pptx` decks and render slides to PDF/PNG for visual inspection.

## Unraid Installation
You can easily deploy this using the included Unraid template:
1. Copy the `unraid-template.xml` file to your Unraid flash drive at `/boot/config/plugins/dockerMan/templates-user/unraid-template.xml`.
2. Open the Unraid web interface.
3. Go to the **Docker** tab and click **Add Container**.
4. In the "Template" dropdown at the top, select **Antigravity-Daemon**.
5. Fill out any optional settings and click **Apply**!

### Manual / Standard Docker Compose
If you are not using Unraid, you can run this with a standard `docker-compose.yml`:
```yaml
services:
  antigravity-daemon:
    image: ghcr.io/ratethepaladin/antigravity-daemon:latest
    container_name: antigravity-daemon
    tty: true
    stdin_open: true
    volumes:
      - /path/to/your/workspace:/workspace
      - /path/to/persistent/config:/config
    environment:
      - PUID=1000
      - PGID=1000
    restart: unless-stopped
```

## Configuration Variables
The container itself is configured via the environment variables below. The model and permission behaviour of the agent are configured in the CLI's `settings.json` (see [Managing Agent Settings](#managing-agent-settings)).

| Variable | Default | Description |
|---|---|---|
| `PUID` / `PGID` | `99` / `100` | The user and group ID the agent will run as. Match this to your host user to avoid file permission issues. |
| `AGY_INSTANCE_NAME` | *(Optional)* | Locks the remote-control session to a specific name. Prevents offline "ghost" instances from being created when the container updates. |
| `AGY_ALLOW_SUDO` | `false` | Set to `true` to give the agent passwordless `sudo` inside the container (e.g. so it can `apt-get install` tools). Off by default: an agent that reads untrusted content can be prompt-injected, and root lets injected commands tamper with the container and create root-owned files on your shares. `pip`, `npm` and `go install` work without it. |
| `AGY_ALLOW_ROOT` | `false` | The container refuses to start with `PUID=0` unless this is `true`. |

> **Upgrading from an older image?** Earlier versions granted the agent passwordless `sudo` unconditionally. Set `AGY_ALLOW_SUDO=true` if you depend on it.

## Automatic Updates
A scheduled GitHub Action checks for new Antigravity CLI releases daily. When one appears it bumps `.antigravity-version` on `main`, builds and publishes `:latest` and `:vX.Y.Z` to GHCR, and creates a GitHub Release. No manual merge is needed, and Unraid simply shows an update as available. The build fails if the installer delivers a different version than the one being tagged.

## First-Time Authentication
The first time the container starts, you will need to authenticate the agent:
1. Open your Unraid web GUI, click the **Antigravity-Daemon** icon, and select **Console**.
2. Run the following command to securely launch the agent as your persistent Unraid user:
   ```bash
   cd /workspace && gosu 99:100 env HOME=/config agy
   ```
3. It will provide a clickable OAuth URL. Open it on your phone or computer and sign in.
4. Exit the console (`Ctrl+D`).
Because your `/config` folder is persistently mapped, you will never have to sign in again!

## Managing Agent Settings
The agent's model and permission behaviour are configured in the Antigravity CLI's own `settings.json`, not in Docker environment variables. The file lives in your mapped appdata folder:

| Inside the container | On Unraid (default mapping) |
|---|---|
| `/config/.gemini/antigravity-cli/settings.json` | `/mnt/user/appdata/antigravity-daemon/.gemini/antigravity-cli/settings.json` |

On first start the container creates a minimal file containing only `"model": "Gemini 4 Argon (Medium)"`. It never overwrites an existing file. **Restart the container after editing it.**

> The CLI reads the file as plain JSON. **Comments are not allowed**, and an invalid value opens an interactive "Settings Error" screen that blocks a headless daemon. On every start the CLI also rewrites the file in its own format and drops keys that are set to their default values, so don't be surprised when your formatting changes.

### Setting it up (recommended)
The repo ships a ready-made headless configuration in [`examples/settings.json`](examples/settings.json), and the image includes a copy. To apply it from the Unraid console:
```bash
docker exec -u 99:100 Antigravity-Daemon \
  cp /usr/share/antigravity-daemon/settings.example.json /config/.gemini/antigravity-cli/settings.json
docker restart Antigravity-Daemon
```
Back up your current file first if you've customised it. The example:

```json
{
  "$schema": "https://antigravity.google/schemas/v1/settings.json",
  "model": "Gemini 4 Argon (Medium)",
  "toolPermission": "always-proceed",
  "permissions": {
    "allow": ["write_file(*)"],
    "deny": ["command(sudo)", "command(rm -rf /)"]
  },
  "trustedWorkspaces": ["/workspace"]
}
```

What it does:
- **Runs without prompts.** `always-proceed` runs terminal commands, web requests and MCP tools without asking. File edits aren't covered by that mode, so `write_file(*)` allows them too.
- **Keeps guard rails.** Deny rules win over everything else, even in `always-proceed`:
  - `command(sudo)` blocks sudo, which is opt-in anyway via `AGY_ALLOW_SUDO`.
  - `command(rm -rf /)` blocks wiping the filesystem.
- **Can edit its own config.** The agent can change its own settings, MCP servers and agent files under `/config/.gemini`, which is handy for live debugging. To lock that down, add `"write_file(/config/.gemini)"` to `deny`. That stops the file-edit tool from touching those files, but it isn't a hard boundary: with `always-proceed`, shell commands like `echo … > /config/.gemini/…` still run.
- **Trusts `/workspace`.** It's pre-trusted, so the CLI doesn't stop to ask.
- **`$schema`** is optional. The CLI ignores it, but it gives editors autocompletion.

### Settings reference
These are the keys that matter for this container. See Google's [settings reference](https://antigravity.google/docs/cli/reference) for the full list, which also covers display options like `colorScheme`.

| Key | Values (default first) | What it does |
|---|---|---|
| `model` | label, e.g. `"Gemini 4 Argon (Medium)"` | The model the agent uses. Use the **label** exactly as `agy models` prints it (see below). An unavailable model falls back to the default with a warning. |
| `toolPermission` | `"request-review"`, `"always-proceed"`, `"proceed-in-sandbox"`, `"strict"` | How much runs without approval. See the next table. |
| `permissions` | `{ "allow": [], "ask": [], "deny": [] }` | Rules of the form `action(target)`. Precedence is **deny > ask > allow**. |
| `trustedWorkspaces` | `[]` | Folders the CLI trusts. It adds entries itself when you approve a folder. |
| `agentMode` | `""`, `"accept-edits"`, `"plan"`, `"auto"` | Startup execution mode. `"auto"` needs the terminal sandbox (see below). |
| `artifactReviewPolicy` | `"asks-for-review"`, `"always-proceed"` | Whether the agent waits for you to review plans and other artifacts. It doesn't affect file edits. |
| `allowNonWorkspaceAccess` | `false` | Lets the agent read and edit files outside its workspace folders. |
| `enableTerminalSandbox` | `false` | Runs agent commands in an OS sandbox. |

`toolPermission` values:

| Value | Behaviour |
|---|---|
| `request-review` (default) | Asks before write, terminal, web and MCP tools unless an `allow` rule covers the action. In a headless daemon, approve from the remote-control web UI. |
| `always-proceed` | Runs terminal commands, web requests and MCP tools without asking, except for actions that match an `ask` or `deny` rule. This replaces the old `AGY_SKIP_PERMISSIONS` variable and `--dangerously-skip-permissions`. |
| `proceed-in-sandbox` | Runs sandboxed commands without asking. **Most containers can't run the sandbox**, because it needs unprivileged user namespaces. Without it this behaves like `request-review`. |
| `strict` | Asks before every tool action, including file reads, even when an `allow` rule matches. |

**Rule syntax.** A rule is an action plus a target, with no space before the parenthesis.
- **Actions:** `command`, `read_file`, `write_file`, `read_url`, `execute_url`, `mcp`.
- **Command targets:** literal, word-by-word prefixes such as `command(git)`. Use `regex:` for patterns, e.g. `command(regex:npm run (build|lint|test))`.
- **Paths:** absolute, or relative to the workspace. Directory rules apply recursively.
- **Wildcard:** `*` works only as the whole target, e.g. `command(*)` or `mcp(server/*)`. A bare `"*"` is not a valid rule.
- **Write implies read:** `write_file` also allows `read_file` on the same path.

See Google's [permissions guide](https://antigravity.google/docs/cli/permissions) for details.

**"Always allow" approvals are stored separately.** When you click "always allow" on a prompt, the CLI saves the rule in `/config/.gemini/config/config.json` under `userSettings.globalPermissionGrants`, not in `settings.json`. Those rules are combined with the ones in `settings.json`, and deny still wins. They pile up over time, so review them now and then. There are two ways to do that:
- Run `/permissions` in a terminal session from the Unraid console (`gosu 99:100 env HOME=/config agy`). The remote-control web UI can't change settings.
- Edit the `allow` list in `config.json` directly, or ask the agent to do it. Back the file up first, and restart the container afterwards.

### Listing available models
Model names change as Google ships new ones. To see the current list from the Unraid console (or `docker exec`):
```bash
docker exec -u 99:100 -e HOME=/config Antigravity-Daemon agy models
```
Each line shows an ID and a label, e.g. `gemini-4-argon-medium    Gemini 4 Argon (Medium)`. Put the **label** in `settings.json`. (The `--model` command-line flag takes the ID.)

### What lives in `/config` (back this up)
Everything the agent needs to come back as it was is in the `/config` mapping:

| Path under `/config/.gemini/` | Contents |
|---|---|
| `antigravity-cli/antigravity-oauth-token` | Your sign-in. Without it you must redo [First-Time Authentication](#first-time-authentication). Treat it like a password. |
| `antigravity-cli/settings.json` | Model and permission settings (above). |
| `config/mcp_config.json` | MCP servers available to the agent. The format is documented in Google's [MCP guide](https://antigravity.google/docs/mcp?tab=cli). The CLI supports `command` (stdio) and `serverUrl` (Streamable HTTP) servers; the older HTTP+SSE transport isn't supported. |
| `config/config.json` | CLI account and user settings, including the remote-control hostname and your saved "always allow" grants. |
| `config/plugins/` | Installed plugins. |
| `antigravity-cli/conversations/`, `brain/`, `conversation_summaries.db` | Conversation history and memory, so `-c` can resume where it left off. |

Go modules and binaries installed by the agent persist in `/config/go`.

### Rebuilding from scratch
1. Start the container with an empty `/config`. It creates the default `settings.json`.
2. Sign in as described in [First-Time Authentication](#first-time-authentication).
3. Apply the example settings (see [Setting it up](#setting-it-up-recommended)), or restore your backed-up `settings.json`.
4. Restore `config/mcp_config.json` if you use MCP servers.
5. Restart the container.


## Disclaimer & Attribution
- **AI Generation Disclosure:** The architecture, Dockerfile, and CI/CD pipelines in this repository were generated in collaboration with an AI coding assistant.
- **Trademarks:** "Antigravity" is a trademark of Google LLC. This project is an independent, non-monetized, community-created wrapper and is **not** officially endorsed by, affiliated with, or supported by Google.
