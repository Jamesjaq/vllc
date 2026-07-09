# vllc — VLC Extension Skills

This repository contains Manus AI skills for developing and extending VLC Media Player using Lua.

## Contents

### `skill-creator/`

Manus skill packages that can be loaded to guide VLC Lua extension development.

| Skill | Description |
|-------|-------------|
| `vlc-lua-extension` | Complete guide for building, debugging, and deploying VLC Lua extensions. Includes API reference, dialog patterns, HTTP networking, playlist management, and cross-platform deployment instructions. |

## Usage

Each skill directory contains a `SKILL.md` file with instructions, and optional `templates/`, `scripts/`, and `references/` subdirectories with reusable assets.

To use a skill, load the `SKILL.md` into your Manus context and follow the instructions.

## Related

- [Jamesjaq/vlc](https://github.com/Jamesjaq/vlc/tree/vlc-infinity) — The VLC Infinity extension built using this skill.
