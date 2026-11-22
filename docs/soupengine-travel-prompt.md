# Prompt for SoupEngine: travel steps need a place to be done

Paste this into the SoupEngine project.

---

OpenXP 2.0.0-dev4 changed how travel steps complete. A travel step is now done only when the player is at the destination right now, or has clearly gone past it. History no longer counts: a flight path the player already knows, a zone they visited before, or quest flags.

The OpenXP engine side is fixed in OpenXP itself (`Engine/Runner.lua` markEntries; `Engine/Goals.lua` "reach"/"fly"). But some guide steps can only be done through history, so the guide writer needs one change.

**Problem.** Some steps take the player somewhere, but their only blocking goal is `fp` ("Get the <X> flight path"). A character who already knows that flight path has the step marked done straight away, wherever they stand, so the guide skips the trip. The step that showed it in game is in `Guides/Leveling/Alliance/PoleStar-01-60.lua`, guide "22-25 Ashenvale, Wetlands & Stonetalon Mountains":

```lua
{
  { "text", text = "To Menethil Harbor" },
  { "goto", x = 9.49, y = 59.69, zone = "1437" },
  { "fp", name = "Menethil Harbor", text = "Get the Menethil Harbor flight path" },
  { "target", name = "Shellei Brondir" },
},
```

The step before it is `{ "reach", text = "Boat to Menethil Harbor", x = 32.4, y = 43.8, zone = "1439" }` (the Auberdine dock). As soon as the player stood at that dock, the "To Menethil Harbor" step was passed for anyone who had the Menethil flight path from an earlier trip.

There are 52 steps like this across the shipped guides, all of them steps whose only blocking goal is `fp`. Examples:
- Alliance 21-30.lua line 704 (Daelyshia), 864 (Teloren)
- Alliance PoleStar-01-60.lua line 15192 ("Menethil Harbor")
- Horde PoleStar-01-60.lua line 11130 ("The Crossroads")

**Change needed in the guide writer.** When a step's purpose is getting somewhere, give it a goal that checks the place, alongside the `fp` goal:

- Add a `reach` goal at the flight master's (or the destination's) coordinates, with the same `zone`. It is done within 25 yards of the spot, in a sub-zone with that name, or (for a step leading into a new zone) once the player is out in that zone. For example:

  ```lua
  { "reach", text = "Menethil Harbor flight master", x = 9.49, y = 59.69, zone = "1437" },
  { "fp", name = "Menethil Harbor", text = "Get the Menethil Harbor flight path" },
  ```

  Put the `reach` first, so the arrow takes the player there.
- Or, for a plain zone change, use `{ "zone", name = "Wetlands" }`. That is "in the zone right now", not history.
- Keep `fp` steps that only learn a path at a flight master the route already stands at, where no travel is involved. Those are fine as they are.
- Don't use `fp`, `home` or quest-flag conditions as the only proof that a travel step is done.

**Check.** After regenerating, every step whose text starts with "To ", "Boat to", "Fly to", "Zeppelin to", "Into " or "Back to", or whose spot is in a different zone from the step before, should have at least one `reach`, `zone` or `fly` goal. Run OpenXP's `python tests/run_tests.py` (the playthrough test plays every guide).
