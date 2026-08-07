# Shiny Pokemon

Rolls shiny DVs on new wilds, applies Gen 2 Crystal shiny colors, and draws sparkles in battle and on the overworld (including voxel and follower packs when those mods are present).

## Requires

gen1recomp / pokemon-love2d with mod API 2.

Optional: Wilds of Kanto, PokéPC Followers, Followers EX, Dramatic Shape for overworld/follower/voxel sparkles.

## OPTIONS

Pause **OPTIONS → SHINY POKEMON → OPEN**:

- **SHINY POKEMON** — master enable
- **SHINY RATE** — OFF through Always
- **SHINY COLORS** — recolor battle/overworld art
- **SHINY INTRO** — battle intro sparkle/SFX (+ looping overworld sparkles)
- **DEBUG OW** — overworld debug overlay (leave off normally)

## Performance (1.0.1)

Overworld shiny sheets bake across frames (not all at once on map enter), draw uses a cached image, and voxel mode draws sparkles once via the projected FX pass (same stars as 2D, correct billboard position). Battle shiny intro and SFX are unchanged.

## License

MIT
