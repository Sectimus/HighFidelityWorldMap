# Security Policy

## Supported versions

Only the latest release of each addon is supported. Fixes ship as a new release; older versions are not patched.

| Component | Supported |
|---|---|
| `HighFidelityWorldMap` (client addon), latest release | Yes |
| `HighFidelityWorldMap_Art_Forever` (optional art addon), latest release | Yes |
| Anything older, or an unreleased fork | No |

The addon targets World of Warcraft Forever. Behaviour on other clients or game builds is still under development.

## Reporting a vulnerability

**Do not open a public issue for a security problem.**

Report it privately through GitHub: <https://github.com/Sectimus/HighFidelityWorldMap/security/advisories/new>

Include:

- affected version (the TOC `## Version` or release tag) and game build
- what you can do that you should not be able to, and the steps to reproduce it
- a proof of concept, if you have one

You can expect an acknowledgement within 7 days and a status update within 14. This is a one-person, volunteer project, so those are targets, not guarantees. If a report is accepted, I will fix it, publish a release, and credit you in the release notes unless you ask not to be named. Please allow a reasonable time to ship a fix before disclosing publicly.

## Scope

### What the addon does and does not do

The in-game addon (`src/addon/client/`) is Lua that runs inside the WoW client's sandbox. 

- It makes **no network requests**. The WoW addon API does not allow it.
- It does not send chat messages or addon messages, and does not register any addon-message prefix.
- It does not use `loadstring`, `RunScript`, or load code from saved data.
- It stores only its own settings in the `HighFidelityWorldMapDB` SavedVariable (AceDB).
- It reads map art from the game's own data files and ships its own `.blp` textures and generated Lua tables for those not available in-game (such as the continental view of kalimdo).
- It registers the slash commands `/hfwm`.
- It hooks Blizzard's world map frame with `hooksecurefunc` (post-hooks), not by replacing protected functions.

### In scope

- Anything that lets the addon, or crafted data it loads (SavedVariables, slash command arguments), run unintended code, cause taint that breaks protected UI actions, or leak data out of the client.
- Malicious or tampered content in a **published release** (CurseForge zip or GitHub Release), or a way to produce one: compromised build or release pipeline, workflow injection, secret exposure in `.github/`.
- Supply-chain problems in how releases are built: the Ace3 externals in `.pkgmeta`, `src/addon/client/dev/fetch-libs.sh`, GitHub Actions, or the generator's Python dependencies.
- Unsafe handling of downloaded data in the generator (`src/generator/`), e.g. path traversal or code execution from a crafted response or archive.

### Out of scope

- Bugs that are not security issues: visual glitches, map misalignment, Lua errors, performance. Use the normal [issue tracker](https://github.com/Sectimus/HighFidelityWorldMap/issues).
- Vulnerabilities in the WoW client, in Blizzard's UI code, or in other addons. Report those to their owners.
- Vulnerabilities in third-party libraries (Ace3, LibStub) themselves. Report those upstream; I will update the dependency once a fix exists.
- Attacks that need an attacker who already has local access to your machine or your WoW install folder.
- Copies of this addon distributed anywhere other than the official pages below.

## Getting the addon safely

Install only from the official sources:

- CurseForge: [High Fidelity World Map](https://www.curseforge.com/projects/1701034) and its [Art companion](https://www.curseforge.com/wow/addons/hfwm-art)
- GitHub Releases: <https://github.com/Sectimus/HighFidelityWorldMap/releases>

Releases are built by GitHub Actions from tags on `main`, and the CurseForge upload runs only from `main` or a tag on `main`. The addon contains no executable binaries, only Lua, XML, `.toc`, and texture files. If a download contains an `.exe`, `.dll`, `.bat`, `.sh`, or a similar file, do not run it. Report it.

## Building from source

Running the generator (`src/generator/generateHFWM.py`) downloads game data from third-party hosts over HTTPS and installs Python packages (`Pillow`, `numpy`, `psd-tools`). Use a virtual environment, and review `src/generator/requirements.txt` first.
