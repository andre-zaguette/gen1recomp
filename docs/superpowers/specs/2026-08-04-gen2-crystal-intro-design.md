# Gen2 (Crystal) New-Game Intro Sequence

Status: approved for planning
Date: 2026-08-04

## Context

The Gen2 (Crystal) work so far (walking skeleton, font, native color) gets the
player from the launcher into a colored, legible New Bark Town — but pressing
NEW GAME skips straight past any introduction: `field.boot.screens.newGame`
points at `src/ui/NoOpScreen.lua`, a placeholder added early on precisely
because no text or character-select data had been extracted yet
(`src/import/RomExtractorGen2.lua`'s Task 10 comment on that file explains
why). This spec replaces that placeholder with Crystal's real intro: Professor
Oak's welcome narration (with a live Wooper demo), the boy-or-girl character
choice, and naming the player.

This is the first Gen2 work to touch dialogue text, a second overworld
sprite, and — narrowly, for one specific demo beat — a species front sprite
and cry. All three formats turn out to closely mirror patterns this project's
Gen1 pipeline and this same Gen2 work already have proven: Crystal's text
byte-encoding is functionally identical to Gen1's (same opcodes, no
compression), Kris's sprite is a straight symbol-swap of the already-working
Chris extraction, Wooper's cry maps directly onto the existing Gen1
chip-synth cry system, and Wooper's front sprite reuses the LZ3 decompressor
this Gen2 pipeline already has for tileset graphics.

The engine side needs almost no new UI work either: `src/ui/OakSpeech.lua`
is already a general, data-driven step-table framework (text/choice/naming/
picture steps), and `src/ui/NamingScreen.lua` is already version-agnostic.
Building Crystal's intro is mostly a new step-table (a Crystal-specific
sibling of `OakSpeech.lua`) fed by newly-extracted data, not new engine
mechanics.

## Goal

Pressing NEW GAME on Crystal plays the real intro — Oak's welcome narration
(with the Wooper demo), a working boy/girl choice that changes the player's
overworld sprite, and player naming — then spawns the named, gendered player
in New Bark Town, exactly like the walking skeleton already does today minus
the placeholder skip.

## Non-goals

- Rival naming and starter selection. Confirmed during planning research:
  neither happens during Crystal's actual intro — both are ordinary map
  events at Elm's Lab, reached later by walking there, which requires NPC/
  object data this project hasn't extracted for any Crystal map yet. Out of
  scope here regardless of intro completeness.
- Any Pokémon besides Wooper, and any Pokédex/species data beyond exactly
  what the intro's Wooper demo needs (front sprite, cry). Not a general
  species-extraction pipeline.
- Animated front-sprite frame-blending. Gen2 front pics support a two-frame
  animated blend; the intro only needs the static pic (`GetMonFrontpic`'s
  path, not `GetAnimatedFrontpic`'s). Confirm during implementation which
  call `OakSpeech`'s real Wooper beat actually uses, and stay on the static
  path even if the animated one turns out to be used — matches this
  project's existing "minimum needed for the one visible outcome" pattern.
- Any Crystal map besides New Bark Town (same constraint every Gen2 spec so
  far has kept).
- A general text/dialogue extraction pipeline (`data/generated/text.lua`'s
  full pointer-table sweep). This spec reads exactly the ~8 named ROM labels
  the intro needs, by symbol, the same way font/palette work already reads
  individually-named symbols — not a change to the still-empty
  `text_pointers` stub.
- Mobile-adapter-specific intro branches (`PlayerProfileSetup`'s mobile
  check) — this project has no mobile-adapter concept; always take the
  non-mobile path.

## Reference

Same ROM and local `pret/pokecrystal` checkout as every prior Gen2 spec.
Confirmed-real, addressable symbols (from `pokecrystal.sym`):

- **`KrisSpriteGFX`** — bank `$31`, addr `$7a40`. Same shape as the already-
  extracted `ChrisSpriteGFX` (`overworld_sprite` macro, 12 tiles,
  `WALKING_SPRITE`, 2bpp, 384 raw bytes) — only the default palette differs
  (`PAL_OW_BLUE` vs `PAL_OW_RED`), which this skeleton's rendering doesn't
  need to honor (Crystal's real-color sprite work already resolves Chris's
  palette independently of this ROM-side default; Kris gets the same
  treatment).
- **Oak's narration + gender prompt** — plain charmap byte runs, no pointer
  table needed for this scoped set, each independently addressable:
  `_OakText1` (`70:5d35`), `_OakText2` (`70:5da4`), `_OakText4`
  (`70:5de5`), `_OakText5` (`70:5e51`), `_OakText6` (`71:4000`),
  `_OakText7` (`71:4026`), `_AreYouABoyOrAreYouAGirlText` (`70:4ca3`).
  (`_OakText3` carries no string — it's a prompt-and-wait beat around the
  Wooper cry/demo, not a text label.) Same opcode set and terminator
  (`TX_END` = `$50`) as Gen1; decode with Crystal's already-resolved
  charmap (`crystal/data/generated/font.lua`'s `charmap`, from the font
  spec).
- **`WooperFrontpic`** — bank `$55`, addr `$7846`. LZ3-compressed (this
  Gen2 pipeline's existing `src/import/Lz3.lua` applies), decompresses to a
  7×7 tile grid (56×56px), 2bpp — confirmed via `_GetFrontpic`'s `c = 7*7`
  call in the real engine code. The compressed asset is Gen2's animated-pic
  format (two blended frames); the intro only needs the static base frame
  (see the animated-front-sprite non-goal above) — confirm during
  implementation exactly how to decode just that frame without the
  bitmask-blend machinery.
- **`PokemonProfPic`** (Oak's trainer portrait) — bank `$56`, addr
  `$415e`. Same LZ3-compressed 2bpp scheme as `WooperFrontpic`, but a
  trainer pic, not a species pic — Gen2 trainer portraits aren't animated,
  so this should be a plain static decode; confirm the exact tile-grid
  dimensions against `engine/gfx/load_pics.asm`'s trainer-pic load call
  during implementation (likely also 7×7/56×56, matching Gen1's own
  trainer-pic convention, but verify rather than assume).
- **`Cry_Wooper`** — bank `$3c`, addr `$6df6` (plus its three channel
  sub-tracks, `Cry_Wooper_Ch5`/`Ch6`/`Ch8`), a 3-channel chip-synth opcode
  program in the same format Gen1's existing cry system already consumes
  (`src/import/RomExtractor.lua`'s cry extraction, `src/core/ChipSynth.lua`/
  `ChipAudio.lua`'s playback). The per-species pitch/length row's exact
  Crystal-side table symbol (analogous to Gen1's `cryData`) needs
  confirming against source during planning, not yet pinned down here.

## Architecture

New files:

| New file | Mirrors | Responsibility |
| --- | --- | --- |
| `src/ui/CrystalIntro.lua` | `src/ui/OakSpeech.lua` | Crystal's own intro sequence: gender choice, Oak narration + portrait, Wooper demo, naming, spawn. Delegates to `OakSpeech`'s existing shared mechanics (text/pic/reveal/naming/shrink-outro handling) via Lua metatable inheritance (`setmetatable(CrystalIntro, {__index = OakSpeech})`) rather than duplicating them — `OakSpeech.lua` itself is not modified, so this carries zero regression risk to Gen1's intro. Only the parts that are genuinely different (the step list, the demo beat's text key, the gender step, no rival anything) are overridden. |
| `tools/extract_gen2/text.py` or a `RomExtractorGen2:extractIntroText()` addition (exact split decided in planning) | `RomExtractor.lua`'s `decodeTextCommands` | Reads the ~8 named Oak/gender-prompt labels by symbol, decodes with the existing charmap, mirroring Gen1's byte-for-byte technique. |

Existing files, additions:

- `src/import/RomExtractorGen2.lua`: extend the existing sprite extraction to also pull Kris (same function, second symbol); a new small extraction for Wooper's static front pic and Oak's trainer portrait (LZ3 decompress + 2bpp decode, reusing `Lz3.lua`/`ImageWriter.lua` exactly as the tileset extraction already does); a new small extraction for Wooper's cry (mirrors Gen1's cry-table read shape); the intro text labels above. `field.boot.screens.newGame` changes from `"NoOpScreen"` to `"CrystalIntro"`; `field.playerSprites` gains a second, gender-alternate entry pointing at Kris's sprite.
- `tools/make_rom_manifest_crystal.py`: new required symbols for all of the above, following the exact pattern already established for map/tileset/sprite/font symbols.
- `src/world/Player.lua`: `Player.new` gains an optional trailing `save` parameter (only one real call site today, `OverworldController.lua`); when present and `save.player.gender` is set to the alternate gender, sprite selection prefers the alternate `playerSprites` entry over the default one. Fully backward compatible — no existing call passes this parameter, and no existing save sets that field, so Gen1/Yellow/Red/Blue behavior is untouched.

### Data flow

Same overall shape as every prior Gen2 spec — manifest built once from a
local pokecrystal checkout, runtime extractor reads the player's own ROM
bytes at import time:

```
local pokecrystal checkout (dev-only, not committed)
        |
        v  tools/make_rom_manifest_crystal.py
tools/rom_manifest_crystal.json  (committed; gains Kris/Oak-text/
                                   Wooper-pic/Wooper-cry symbols)
        |
        v  RomExtractorGen2.lua, at the player's first boot
player's real Crystal ROM ------------+
        |                             |
        v                             v
   SHA-1 validation           decode Kris sprite, Oak's narration text,
                               Wooper's front pic + cry
        |
        v
crystal/data/generated/{sprites,text}.lua (extended) +
crystal/assets/generated/{sprites/kris.png, pokemon/wooper_front.png}
```

### Approaches considered

- **Chosen — mirror every existing pattern this project already has proven**
  (Gen1's text-decode technique, Gen1's cry-data shape, this Gen2 work's own
  LZ3/2bpp tileset decode, `OakSpeech.lua`'s step-table framework,
  `NamingScreen.lua` reused unchanged). Every piece of this feature is a
  recombination of already-working code, not new engineering — confirmed
  file-by-file during planning research.
- **Rejected — build a general Pokédex/species extraction pipeline now,
  since Wooper needs some of that shape anyway.** Would set up later battle/
  Pokédex work, but multiplies this slice's scope far beyond "make the
  intro playable," and this project's own established pattern (walking
  skeleton, font, color) is to extract exactly what one visible outcome
  needs, not to anticipate future slices.
- **Rejected — skip the Wooper demo and gender choice, ship text+naming
  only.** Was the original minimal proposal; the user explicitly chose the
  fuller, still well-scoped version instead once the actual cost (both
  pieces turn out to mirror already-proven patterns) was clear.

## Testing

- Lua fixture-backed structural test in `tests/run_tests.lua`'s Gen2
  section (matching every prior Gen2 spec's precedent): hand-built step
  data proves `CrystalIntro.lua`'s step sequencing (text → gender choice →
  demo → naming → done) resolves correctly against `OakSpeech.lua`'s
  existing, unmodified step-runner primitives, with no ROM present.
- Manual real-ROM verification (as with every prior Gen2 spec): reimport,
  play NEW GAME start to finish — narration legible, gender choice changes
  the spawned sprite, Wooper's demo shows its sprite and plays its cry,
  naming works and the name shows up in-game, player lands correctly in
  New Bark Town afterward.

## Acceptance criteria

1. `tools/make_rom_manifest_crystal.py` runs clean and gains the new
   symbols/resolved text.
2. Reimporting Crystal generates the new sprite/text/pic/cry assets.
3. Pressing NEW GAME plays the real intro instead of skipping straight to
   New Bark Town.
4. Choosing boy or girl changes the player's in-game sprite accordingly.
5. Oak's portrait renders during the narration; the Wooper demo beat shows
   Wooper's sprite and plays its cry.
6. Naming the player works and the chosen name appears in-game afterward.
7. `luajit tests/run_tests.lua` passes the new fixture-backed case with no
   ROM present.
8. Zero regression to Gen1's existing `OakSpeech.lua` flow (the file itself
   is not modified).

## Follow-on work (explicitly out of scope here)

- Rival naming and starter selection (Elm's Lab, once NPC/object data for
  that map is extracted).
- General Pokédex/species/moves/items extraction.
- Animated front-sprite support.
- Full-game text/dialogue extraction.
