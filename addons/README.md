# OpenXP 2.0 (based on Polestar)

These folders are OpenXP 2.0: a fork of Polestar
(https://github.com/fitzforge/polestar), GPL-3.0 with Polestar's guide-pack
exception. They are made by `tools/fork_polestar.py` from a Polestar release
zip; see `OpenXP/NOTICE.md` for what changed and the credits.

Install: copy every folder here into `World of Warcraft/_forever_/Interface/AddOns/`
(this replaces OpenXP 1.x's `OpenXP` folder).

To take a newer Polestar release:

    python3 tools/fork_polestar.py Polestar-<version>.zip addons

Then re-apply our own changes on top (keep them small and listed in NOTICE.md).

OpenXP 1.x (the files at the top of this repository) is a separate addon
under CC BY-NC-SA 4.0 and is not part of 2.0.
