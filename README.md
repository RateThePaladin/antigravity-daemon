# Antigravity Headless Daemon

A lightweight, headless Docker wrapper for the Google Antigravity CLI. Designed to run as a persistent remote-control daemon (perfect for Unraid, TrueNAS, or generic Docker hosts), with dynamic configuration via environment variables.

This container strictly follows Unraid Community Application best practices:
- **PUID / PGID Support:** Runs as `nobody:users` to prevent root permission errors.
- **Centralized `/config`:** Uses a single mapped directory for all persistent data.
- **Robust Toolchain:** Pre-installed with Python 3, Node.js, `npm`, `pip`, and `build-essential` so the agent can natively compile and test code without friction.

## Unraid Installation
You can easily deploy this using the included Unraid template:
1. Copy the `unraid-template.xml` file to your Unraid flash drive at `/boot/config/plugins/dockerMan/templates-user/unraid-template.xml`.
2. Open the Unraid web interface.
3. Go to the **Docker** tab and click **Add Container**.
4. In the "Template" dropdown at the top, select **Antigravity-Daemon**.
5. Fill out any optional settings (like your Doppler Token) and click **Apply**!

### Manual / Standard Docker Compose
If you are not using Unraid, you can run this with a standard `docker-compose.yml`:
```yaml
services:
  antigravity-daemon:
    image: ghcr.io/RateThePaladin/antigravity-daemon:latest
    container_name: antigravity-daemon
    tty: true
    stdin_open: true
    volumes:
      - /path/to/your/workspace:/workspace
      - /path/to/persistent/config:/config
    environment:
      - PUID=1000
      - PGID=1000
      - AGY_MODEL=gemini-3.1-pro
      - AGY_SKIP_PERMISSIONS=false
      - DOPPLER_TOKEN=dp.st....
    restart: unless-stopped
```

## Configuration Variables
This daemon is entirely configured via environment variables.

| Variable | Default | Description |
|---|---|---|
| `PUID` / `PGID` | `99` / `100` | The user and group ID the agent will run as. Match this to your host user to avoid file permission issues. |
| `AGY_MODEL` | *(None)* | The LLM model you want the agent to use (e.g. `gemini-3.1-pro`). |
| `AGY_SKIP_PERMISSIONS` | `false` | Set to `true` to run fully autonomously. This bypasses human approval checks, allowing the agent to execute commands and write files headlessly. |
| `DOPPLER_TOKEN` | *(Optional)* | Your Doppler service token for auto-injecting project secrets. |
| `AGY_INSTANCE_NAME` | *(Optional)* | Locks the remote-control session to a specific name. Prevents offline "ghost" instances from being created when the container updates. |

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
Instead of setting Docker environment variables, this container utilizes the Antigravity CLI's native configuration file for persistence.

To change the LLM model or edit permission settings (like disabling confirmation prompts), simply edit the `settings.json` file in your mapped Appdata folder:
`/mnt/user/appdata/antigravity-daemon/.gemini/antigravity-cli/settings.json`

Example:
```json
{
  "model": "Gemini 3.1 Pro (High)",
  "permissions": {
    "allow": ["*"]
  },
  "trustedWorkspaces": [
    "/workspace"
  ]
}
```
Restart the container to apply any manual edits to this file!

## Secrets Management (Doppler)
If you provide a `DOPPLER_TOKEN` environment variable, the container automatically authenticates with Doppler and securely injects your remote project secrets into the agent's environment.

**Updating Secrets:** Because Doppler injects the variables when the process boots, you do **not** need to recreate or rebuild the container when you change a value in the Doppler dashboard. Simply restart the container to sync the latest secrets:
```bash
docker restart antigravity-daemon
```

## Disclaimer & Attribution
- **AI Generation Disclosure:** The architecture, Dockerfile, and CI/CD pipelines in this repository were generated in collaboration with an AI coding assistant.
- **Trademarks:** "Antigravity" is a trademark of Google LLC. "Doppler" is a trademark of Doppler, Inc. This project is an independent, non-monetized, community-created wrapper and is **not** officially endorsed by, affiliated with, or supported by Google or Doppler.
