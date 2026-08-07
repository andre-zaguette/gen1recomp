# Changelog

## 0.2.0

**0.1.0 did nothing at all. Update.** It threw on its first line and
registered none of its five options, neither of its two patches, and not the
Atlas screen. If you installed it, you were running vanilla.

- **Fixed: the mod never ran.** `main.lua` opened with
  `require("data.split")`, and a mod-relative `require` does not resolve —
  the engine loads a mod's entry file itself, and `package.path` still points
  at the engine root, so `data.split` is looked for beside `main.lua`
  nowhere. All four modules are inlined into `main.lua`; the mod now has no
  `require` of its own beyond engine modules.
- **Fixed: the test suite could not see that.** It `dofile`'d the library
  files directly, so it tested code the mod had never loaded. It now goes
  through the loader and asserts the registrations — options defined, screen
  registered, screen *opens* — and refuses to run against a disabled mod.
  Two further holes it now closes: the mod is experimental, so the loader
  leaves it off until the player opts in, which made `#errors == 0` true and
  meaningless; and the type-chart assertions read the chart *after* GHOST FIX
  had rewritten it, checking the mod's output against itself.

No behaviour was intentionally changed. Everything below is what 0.1.0
described and now actually does.

## 0.1.0

First beta. Four separately switchable pieces; the ones that move the
balance are off by default.

- **SPLIT** (off) — the Gen 4 physical/special split, as per-move data.
  `Damage.categoryOf` already prefers a move's own category over its type's,
  so this is 17 registry patches rather than a damage hook, and it composes
  with anything else that touches a battle.
- **TYPE CHART** (GEN 1) — the three rows Gen 2 rebalanced.
- **GHOST FIX** (on) — Ghost does 0x to Psychic in Gen 1, where 2x was
  intended. On by default because it is a bug, not a balance decision; the
  other three rows are taste, and live behind TYPE CHART.
- **SMART AI** (off) — patches the vanilla LAYER_3 type pass, whose own
  comment admits it "only reads the FIRST matching row -- no dual-type
  product". It multiplies them out, so 2x against an immune second type
  reads as immune instead of as a good idea.
- **ATLAS** (on) — a screen over the merged encounter data: every area, the
  species in it with their level range, and whether you own one yet.
