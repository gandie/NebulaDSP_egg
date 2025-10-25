# NebulaDSP_egg

A Pterodactyl "egg" for installing and running a headless Dyson Sphere Program (DSP) dedicated server.
This repository contains the egg JSON (`egg-dyson-sphere-program-bep-in-ex.json`) and the installer script `install.sh` used by the egg to perform the actual server installation inside the container.

## Highlights
- Non-interactive, container-first installer for DSP (works in Pterodactyl environments)
- Automatic SteamCMD handling with Steam Guard (2FA) awareness
- Automatic BepInEx installation and optional mod/profile installation from Thunderstore
- Keeps `install.sh` separate from the egg JSON to make diffs and review easier

## Quick: Importing the egg into Pterodactyl
1. Download or place `egg-dyson-sphere-program-bep-in-ex.json` where you can access it from the panel.
2. In the Pterodactyl panel (admin UI): Nests → Eggs → Import
3. Select the JSON file and import. Review the egg variables and save.
4. Create a new server from the imported egg, set the necessary variables (see Configuration below), then start the server.

Note: If you manage Pterodactyl via automation or the API, import the same JSON using your current tooling.

## Configuration (important environment variables)
The installer and egg JSON declare a set of environment variables used at install and runtime. Set these as egg/server variables in the Pterodactyl panel. The list below includes variables present in `install.sh` and the egg JSON; for a full authoritative list, inspect `egg-dyson-sphere-program-bep-in-ex.json` -> `variables` and the `install.sh` defaults.

- `STEAM_USER` — Steam username. Leave empty to attempt anonymous install (may fail for paid games).
- `STEAM_PASS` — Steam password (empty for anonymous).
- `STEAM_AUTH` — Steam Guard 2FA token (one-time or email). If omitted and credentials require 2FA, the installer writes `/mnt/server/steamcmd_manual_instructions.txt` and exits with instructions.
- `WINDOWS_INSTALL` — `1` (default) to request a Windows platform install via SteamCMD platform override.
- `SRCDS_APPID` — Steam AppID to install (default: `1366540` in this repo).
- `SRCDS_BETAID` — (optional) Steam beta branch id (used when provided).
- `SRCDS_BETAPASS` — (optional) Steam beta password (supported by `install.sh`).
- `INSTALL_FLAGS` — (optional) extra flags passed to SteamCMD `app_update`.
- `V_PROFILECODE` — (optional) Thunderstore/R2modman profile code to automatically fetch and install mods into BepInEx.
- `BEPINEX_UPDATE_OVERWRITE` — `0` (default) to avoid overwriting config files when applying a profile; `1` to overwrite everything.
- `SERVER_ARGS` — arguments passed to the DSP server process at runtime (declared in the egg JSON).

Additional variables are declared in the egg JSON (for example: `AUTO_UPDATE`, `WINEPATH`, `WINEDEBUG`, `WINETRICKS_RUN`, `VALIDATE`). Check `egg-dyson-sphere-program-bep-in-ex.json` -> `variables` for the authoritative set and defaults.

These variables are declared and used in `install.sh` and/or the egg JSON — update the script defaulting lines if you add new variables.

## Why `install.sh` is kept separate
- The egg JSON contains the metadata Pterodactyl needs (variables, container image, startup, etc.). The heavy installer logic is intentionally kept in `install.sh`.
- Benefits:
	- Easier diffs and code reviews when the installer changes (large shell scripts embedded in JSON are noisy).
	- Simpler local testing: you can run `install.sh` directly in a compatible environment to iterate faster.
	- Clear separation of configuration (egg JSON) and implementation (shell script).

When making changes to installation behavior, edit `install.sh` and keep the egg JSON changes minimal (variable additions or metadata) so reviewers can focus on the actual logic.

## Mod/profile handling
- `install.sh` supports fetching BepInEx from Thunderstore and optionally downloading a profile via `V_PROFILECODE`.
- Key functions inside `install.sh` to review when changing mod behavior: `thunderstore_get_profile`, `fix_filenames`, `thunderstore_download`, `update_from_profile_code`.
- Filename sanitation is applied to handle Windows-created archives (backslashes converted to forward slashes).

## Troubleshooting
- If Steam login requires Steam Guard (2FA) and you did not provide `STEAM_AUTH`, the installer will create `/mnt/server/steamcmd_manual_instructions.txt` with next steps. Read that file and either provide `STEAM_AUTH` and re-run the installer or perform an interactive login on a host where you can interact with SteamCMD.
- Installer logs and stdout are visible in the server's build/installation output in Pterodactyl — check the task logs if installation fails.
- The Goldberg steam emulator DLL is downloaded to `$HOME/DSPGAME_Data/Plugins/steam_api64.dll` during installation. Do not replace or redistribute this asset without verifying license/permission.

## Development & testing tips
- Lint shell scripts locally with `shellcheck install.sh` before opening a PR.
- Keep network calls robust: the script uses `curl -sfSL` / `wget --https-only` style patterns; follow the same pattern for new downloads.
- If you add a new server variable, add a default at the top of `install.sh` like:

```bash
NEW_VAR="${NEW_VAR:-default}"
```

and document it in this README under Configuration.

## Contributing
- Make small, focused commits. Example commit message: `install.sh: add NEW_VAR with default and README docs`.
- When changing install behavior, prefer editing `install.sh` and keep egg JSON changes minimal to aid reviews. A new egg export can be created when review has been approved.

## Shoutouts

- [Nebula Mod Team](https://github.com/NebulaModTeam/nebula) for awesome mod and great support
- [Avril112113](https://github.com/Avril112113) creating the initial egg file this is based on and sharing knowledge
- [WhyKickAmooCow](https://github.com/WhyKickAmooCow) for groundwork done in DSP servers
- [AlienXAXS](https://github.com/AlienXAXS) for even more groundwork this is based on
- [Pelican egg base](https://github.com/pelican-eggs/eggs/) provding base eggs to work from

Your name not here? Just contact us. This is a community effort based on several people's work.

## AI usage disclaimer

This repository received limited assistance from AI tools to help draft documentation and small developer-facing text changes. Specifically:

- Where AI was used
	- Drafting and editing this README content (clarity, formatting, and examples).
	- Small, low-risk shell script helper text and comments during development (for example, suggested environment variable descriptions). No production logic or complex shell code was automatically generated and committed without human review.

- Why AI was used
	- Speed up routine writing and improve clarity of documentation.
	- Reduce repetitive editing so maintainers can focus on the installer logic in `install.sh`.

- What to expect and limitations
	- All AI-assisted text changes were reviewed and adjusted by a human maintainer before being committed.
	- The AI was not given any secrets, credentials, or other sensitive information. Do not store secrets in the repository; continue to use Pterodactyl variables or secret management for credentials.
	- If you see behavioural changes in scripts or automation, assume human review is required and inspect the corresponding files (notably `install.sh`) before trusting them in production.

- Contact and review
	- If you have concerns about any AI-assisted content or want a rationale for a specific change, open an issue and tag `maintainers` so a human reviewer can follow up.

This statement is intentionally brief and developer-focused; it documents that AI helped with documentation and small edits, but that human review remains the source of truth for functional code.

## Support
Open issues on the repository with logs and the exact egg variables you used. Even better join Nebula Mod Discord and check support forum and faq.
