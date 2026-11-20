# German localization

`locale/deDE.lua` contains the German interface strings. `locale/deDE_guide.lua`
contains the titles, instruction text and item labels for the bundled Forever
leveling, dungeon and collectible guides. Both catalogs follow the client locale.

The guide catalog applies to the listed guide groups and titles. Display titles
are translated separately from the guide names, links and arguments used by the
step engine. The catalog supports exact instruction text and reusable phrases
whose names, icons, item brackets and numbers are restored from placeholders.

Check the catalog after upstream guide updates from the repository root.

```sh
node tools/locale/check_de_locale.cjs .
python tests/run_tests.py
```

The coverage check reports new or unused text, missing names and mismatched
placeholders. Update the Lua catalog directly. The generic guide-locale builder
currently generates the phrase-only catalogs used by other languages.

Starter-area translations incorporate the German RestedXP guides at the
upstream revision identified in `NOTICE.md`. Some names unique to WoW Forever
are translated descriptively and can benefit from further language review.
