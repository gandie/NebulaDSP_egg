<!--
Repository: NebulaDSP_egg
Purpose: Guidance for AI coding agents (CoPilot-like) to be immediately productive in this repo.
Keep this file short, specific, and grounded on existing files: README.md, install.sh, egg-dyson-sphere-program-bep-in-ex.json.
-->

# Copilot instructions for NebulaDSP_egg

These are short, actionable rules to help an AI coding agent make safe, useful changes in this repository.

1. Big picture
   - This repo contains a Pterodactyl "egg" for installing and running a headless Dyson Sphere Program (DSP) server.
   - Core behavior lives in the installer script `install.sh`. Changes to install logic, SteamCMD handling, mod installation, or environment variables should be made there.
   - `README.md` documents usage and environment variables (e.g., `DSP_PORT`, `DSP_SAVE_PATH`). Use it as the first source for user-facing docs.

2. Primary files and patterns to inspect before editing
   - `install.sh` — the single most important script. It:
     - installs packages (apt), downloads and runs SteamCMD, handles Steam Guard/2FA logic, and installs BepInEx and mod profiles.
     - relies heavily on environment variables: `STEAM_USER`, `STEAM_PASS`, `STEAM_AUTH`, `WINDOWS_INSTALL`, `SRCDS_APPID`, `V_PROFILECODE`, `BEPINEX_UPDATE_OVERWRITE`.
     - uses `timeout --foreground` to avoid hanging in non-interactive environments — preserve this behavior when modifying login flows.
     - writes helpful instruction files to `/mnt/server/steamcmd_manual_instructions.txt` when Steam Guard is required — keep or improve this UX when introducing interactive flows.
   - `notes` — contains small JSON snippets showing how BepInEx config mapping is intended (e.g. port wiring). Reference it when modifying config templates.

3. Editing rules (must-follow)
   - Preserve non-interactive and container-friendly behavior: do not introduce commands that require stdin unless guarded by an explicit environment flag (e.g., `INTERACTIVE=1`).
   - When changing `install.sh`, maintain idempotence: repeated runs should either be safe or document when a reinstall is required.
   - For network downloads (curl/wget), preserve `--https-only` or error handling. Fail early with clear messages when required artifacts cannot be fetched.
   - Shell strictness: `set -eo pipefail` is used; avoid unguarded expansions that can break with `set -u` in future.

4. Tests, builds, and manual checks
   - There are no automated tests in this repo. Quick validation steps for edits:
     - Syntax/lint: run `shellcheck install.sh` locally (recommended).
     - Dry-run checks: ensure `install.sh` still exits with clear non-zero codes on failures and produces `/mnt/server/steamcmd_manual_instructions.txt` for Steam Guard flows.
     - If you add new files under the egg JSON workflows, update `README.md` examples and the top-level README.

5. Common edit examples (use these patterns)
   - Add a new environment variable with default and documented behavior:
     - In `install.sh` add: `NEW_VAR="${NEW_VAR:-default}"` near the other variable defaults.
     - Document it in `README.md` under "Configuration" with a one-line example.
   - Add a new download step with robust failure handling:
     - Use `curl -sfSL -o file` and `if ! curl ...; then fail "message"; fi` as in existing code.
   - Modify Steam login flow safely:
     - Keep the short `timeout --foreground 30s` probe that triggers Steam Guard when no `STEAM_AUTH` is provided. If you change timings, keep the fallback that writes manual instructions and exits non-hanging.

6. Integration and external dependencies
   - Upstream downloads:
     - SteamCMD: https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz
     - Goldberg emulator DLL is fetched into `$HOME/DSPGAME_Data/Plugins/steam_api64.dll` — avoid replacing this without validating licensing.
     - BepInEx package is fetched from Thunderstore API; changes to mod installation must preserve profile extraction and filename-fixing logic (`fix_filenames`).
   - System packages: `apt` installs (wget, p7zip, jq, unzip, ca-certificates, coreutils) — use the same minimal install flags.

7. Project-specific conventions
   - Non-interactive-first: The egg targets containerized, non-interactive installs — prefer environment variables and files over prompts.
   - Mod/profile handling: `V_PROFILECODE` triggers a multi-step download+extract+fix flow and writes into `/mnt/server/BepInEx`. Keep filename sanitation (`sed 's/\\/\//g'`) when working with archives created on Windows.
   - Overwrite semantics: `BEPINEX_UPDATE_OVERWRITE` controls whether mods overwrite existing files. Preserve this toggle when touching mod update paths.

8. When to ask the human
   - If a change requires credentials (e.g., testing a Steam login with a real account), stop and ask for CI-safe test instructions or a dummy account — never request secrets in the repo.
   - If a download target or license is unclear (Goldberg DLL, third-party packages), ask for confirmation before replacing.

9. What to commit and how
   - Small, focused commits with a short message referencing the impacted file (e.g., "install.sh: add NEW_VAR with default and README docs").
   - Update `README.md` for any user-visible change (config variables, new files written to /mnt/server).

10. Examples found in this repo (explicit references)
   - Steam timeout probe and Steam Guard handling: `install.sh` lines around the `timeout --foreground 30s ./steamcmd.sh +login ...` block.
   - Mod profile extraction and filename fixes: functions `thunderstore_get_profile`, `fix_filenames`, and `thunderstore_download` in `install.sh`.
   - BepInEx overwrite flag: `BEPINEX_UPDATE_OVERWRITE` usage in the `update_from_profile_code` function.

If anything here is unclear or you'd like additional rules (e.g., commit templates, branch naming, or automated test suggestions), say which area to expand and I'll update this file.
