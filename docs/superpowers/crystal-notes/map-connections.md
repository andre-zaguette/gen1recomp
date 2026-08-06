# Map connections

Confirmed from `roms/pokecrystal/data/maps/attributes.asm` (the single
source of truth for the seamless map-edge `connection` graph — not
per-map `.asm` files, which only carry `warp_event`/`coord_event`/
`bg_event`/`object_event`) and from `tools/rom_manifest_crystal.json`
after regeneration. See [[conventions]] for the warp-tolerance note (a
`connection` to an unregistered map degrades gracefully at render time;
a `warp_event` to one used to hard-crash import until this session's
fix).

Two different mechanisms, easy to conflate:

- **`connection`** (`data/maps/attributes.asm`): a seamless edge crossing
  — walk off one map's border cell and you're on the neighbor, no load.
  This is what `OverworldState.computeNeighbors` walks for the survey
  zoom, and what New Bark Town ↔ Route 29 uses.
- **`warp_event`** (per-map `.asm`, `def_warp_events`): a door/stairs/mat
  tile — an explicit teleport to a specific `(map, warp id)`. Route 29's
  path into its Route 46 gate building is a warp, not a connection.

## Confirmed graph so far

```
                    ROUTE_46 (north, offset 10 — unregistered)
                       |
                       | connection
                       |
CHERRYGROVE_CITY --- ROUTE_29 --- NEW_BARK_TOWN --- ROUTE_27 (unregistered)
  (west, off 0)    (connection)   (east/west,        (east, offset 0 —
                                    offset 0)          unregistered)
       |
       | connection (north, offset 5)
       |
   ROUTE_30 --- ROUTE_31 (north, offset -10 — unregistered)
  (unregistered)
```

- `ROUTE_29` also has a `warp_event` (not a connection) at cell (27,1) →
  `ROUTE_29_ROUTE_46_GATE` warp 3 — a small building, not the open Route
  46 itself. Registering it is [[README|Task 4]] of the 2026-08-06
  roadmap's Milestone 1.
- `CHERRYGROVE_CITY`'s own object/sign/warp inventory hasn't been read
  yet (Milestone 1's [[README|Task 5]]) — only its `attributes.asm`
  connections are confirmed so far: north to `ROUTE_30` (offset 5), east
  to `ROUTE_29` (offset 0).
- `MrPokemonsHouse` (Milestone 1's [[README|Task 6]]) is reached by warp,
  not a connection — its own `.asm` hasn't been fully mapped for exact
  entry coordinates yet, only the errand-completion script's flag
  side-effects (see [[conventions]]'s SET=hidden section).

Nothing south/further west/further north of this cluster has been read
yet — do not assume anything about Violet City's approach direction
until Milestone 5 actually reads `Route30.asm`/`Route31.asm`.
