# Gen1Recomp Agent Handoff

Last updated: 2026-08-05

## Purpose

This repository is `gen1recomp`: a native LÖVE2D reimplementation of Pokemon Red, Blue, and Yellow that runs against data extracted from a ROM supplied by the player.

It does **not**:

- ship a ROM,
- emulate the Game Boy,
- transpile assembly,
- download a disassembly at runtime.

It **does**:

- validate the user's ROM by SHA-1,
- extract structured data, graphics, and compact audio programs,
- write a private generated cache,
- run the game engine entirely from that generated cache.

The long-term direction of this worktree is to extend that same architecture to **Gen2 / Pokemon Crystal**, without breaking the existing Gen1 path.

## What This Worktree Is

This worktree is focused on a Crystal-specific parallel import pipeline.

The design choice is deliberate:

- keep the existing Gen1 extractor stable,
- add Gen2-specific tooling and runtime extraction beside it,
- reuse only generic helpers that are already safe to share,
- avoid premature abstraction between Gen1 and Gen2 extraction logic.

The immediate goal has been a staged Crystal bring-up:

1. prove extraction with a walking skeleton,
2. make Crystal legible with font extraction,
3. make Crystal visually correct with native GBC color,
4. replace placeholders with Crystal-specific intro/audio/title behavior.

## Core Architecture

High-level runtime flow:

1. User selects a supported ROM.
2. Importer validates SHA-1 and ROM size.
3. A manifest provides symbol/address metadata.
4. The extractor reads real ROM bytes by address.
5. Extracted data is written under generated Lua/PNG/audio artifacts.
6. The engine loads only generated artifacts after import.

Relevant docs:

- [README.md](/Users/andreaugustozaguettefernandes/repos/gen1recomp/.claude/worktrees/gen2-crystal-skeleton/README.md)
- [docs/architecture.md](/Users/andreaugustozaguettefernandes/repos/gen1recomp/.claude/worktrees/gen2-crystal-skeleton/docs/architecture.md)
- [docs/extraction-notes.md](/Users/andreaugustozaguettefernandes/repos/gen1recomp/.claude/worktrees/gen2-crystal-skeleton/docs/extraction-notes.md)

## Gen1 Baseline

Gen1 is the established, working product path:

- Red, Blue, and Yellow are supported versions.
- The game engine, renderer, state stack, scripting, battle system, save system, and modding system already exist.
- The extractor writes `data/generated/*.lua` and `assets/generated/**`.
- Audio is synthesized by the project's chip audio pipeline from compact extracted programs.

Any Gen2 work should preserve this baseline.

## Crystal Strategy

Crystal support is being added as a **parallel pipeline**.

Main Crystal entry points:

- [src/core/GameVersion.lua](/Users/andreaugustozaguettefernandes/repos/gen1recomp/.claude/worktrees/gen2-crystal-skeleton/src/core/GameVersion.lua)
- [src/import/RomExtractorGen2.lua](/Users/andreaugustozaguettefernandes/repos/gen1recomp/.claude/worktrees/gen2-crystal-skeleton/src/import/RomExtractorGen2.lua)
- [tools/make_rom_manifest_crystal.py](/Users/andreaugustozaguettefernandes/repos/gen1recomp/.claude/worktrees/gen2-crystal-skeleton/tools/make_rom_manifest_crystal.py)
- [tools/rom_manifest_crystal.json](/Users/andreaugustozaguettefernandes/repos/gen1recomp/.claude/worktrees/gen2-crystal-skeleton/tools/rom_manifest_crystal.json)
- [tools/build_rom_data_gen2.py](/Users/andreaugustozaguettefernandes/repos/gen1recomp/.claude/worktrees/gen2-crystal-skeleton/tools/build_rom_data_gen2.py)

Crystal is registered as a first-class version in `GameVersion` with:

- its own SHA-1,
- 2 MiB ROM size,
- its own manifest,
- its own cache prefix `crystal/`,
- its own save suffix `_crystal`,
- extractor type `gen2`.

## Crystal Scope Implemented So Far

The Crystal runtime extractor currently has 9 stages in [src/import/RomExtractorGen2.lua](/Users/andreaugustozaguettefernandes/repos/gen1recomp/.claude/worktrees/gen2-crystal-skeleton/src/import/RomExtractorGen2.lua):

1. player sprites,
2. Johto tileset,
3. New Bark Town map,
4. intro pictures,
5. font,
6. palettes,
7. intro text,
8. field/bootstrap data,
9. cry and title music/title graphics.

`RomExtractorGen2:run()` currently extracts all of these:

- New Bark Town map,
- Johto tileset,
- Chris and Kris sprites,
- Oak and Wooper intro art,
- Crystal font,
- Crystal palette data,
- intro text labels,
- field boot data wired to `CrystalIntro`,
- Wooper cry,
- Crystal title graphics,
- Crystal title music.

This means the branch is already past the original walking skeleton.

## Current Crystal Status By Area

### 1. Walking Skeleton

Status: implemented and documented as verified.

Goal achieved:

- import Crystal,
- extract New Bark Town,
- render map and player,
- walk around with real collision.

Primary docs:

- [docs/superpowers/specs/2026-08-03-gen2-crystal-extraction-skeleton-design.md](/Users/andreaugustozaguettefernandes/repos/gen1recomp/.claude/worktrees/gen2-crystal-skeleton/docs/superpowers/specs/2026-08-03-gen2-crystal-extraction-skeleton-design.md)
- [docs/superpowers/plans/2026-08-03-gen2-crystal-extraction-skeleton.md](/Users/andreaugustozaguettefernandes/repos/gen1recomp/.claude/worktrees/gen2-crystal-skeleton/docs/superpowers/plans/2026-08-03-gen2-crystal-extraction-skeleton.md)

Key implementation files:

- [tools/extract_gen2/lz3.py](/Users/andreaugustozaguettefernandes/repos/gen1recomp/.claude/worktrees/gen2-crystal-skeleton/tools/extract_gen2/lz3.py)
- [src/import/Lz3.lua](/Users/andreaugustozaguettefernandes/repos/gen1recomp/.claude/worktrees/gen2-crystal-skeleton/src/import/Lz3.lua)
- [tools/extract_gen2/collision.py](/Users/andreaugustozaguettefernandes/repos/gen1recomp/.claude/worktrees/gen2-crystal-skeleton/tools/extract_gen2/collision.py)
- [tools/build_rom_data_gen2.py](/Users/andreaugustozaguettefernandes/repos/gen1recomp/.claude/worktrees/gen2-crystal-skeleton/tools/build_rom_data_gen2.py)

### 2. Font Extraction

Status: implemented and documented as verified.

Goal:

- make Crystal UI strings render correctly by extracting font glyphs and charmap.

Primary docs:

- [docs/superpowers/specs/2026-08-03-gen2-crystal-font-extraction-design.md](/Users/andreaugustozaguettefernandes/repos/gen1recomp/.claude/worktrees/gen2-crystal-skeleton/docs/superpowers/specs/2026-08-03-gen2-crystal-font-extraction-design.md)
- [docs/superpowers/plans/2026-08-03-gen2-crystal-font-extraction.md](/Users/andreaugustozaguettefernandes/repos/gen1recomp/.claude/worktrees/gen2-crystal-skeleton/docs/superpowers/plans/2026-08-03-gen2-crystal-font-extraction.md)

Key implementation files:

- [tools/extract_gen2/font.py](/Users/andreaugustozaguettefernandes/repos/gen1recomp/.claude/worktrees/gen2-crystal-skeleton/tools/extract_gen2/font.py)
- `RomExtractorGen2:extractFont()`

### 3. Native Crystal Color

Status: implemented in code and documented as verified.

Goal:

- use Crystal's real GBC palette data,
- apply morning/day/night palette buckets from host local time,
- bypass Gen1-style `COLORS` mode behavior for Crystal.

Primary docs:

- [docs/superpowers/specs/2026-08-04-gen2-crystal-color-design.md](/Users/andreaugustozaguettefernandes/repos/gen1recomp/.claude/worktrees/gen2-crystal-skeleton/docs/superpowers/specs/2026-08-04-gen2-crystal-color-design.md)
- [docs/superpowers/plans/2026-08-04-gen2-crystal-color.md](/Users/andreaugustozaguettefernandes/repos/gen1recomp/.claude/worktrees/gen2-crystal-skeleton/docs/superpowers/plans/2026-08-04-gen2-crystal-color.md)

Key implementation files:

- [tools/extract_gen2/palettes.py](/Users/andreaugustozaguettefernandes/repos/gen1recomp/.claude/worktrees/gen2-crystal-skeleton/tools/extract_gen2/palettes.py)
- [src/render/PaletteFX.lua](/Users/andreaugustozaguettefernandes/repos/gen1recomp/.claude/worktrees/gen2-crystal-skeleton/src/render/PaletteFX.lua)
- [src/world/OverworldController.lua](/Users/andreaugustozaguettefernandes/repos/gen1recomp/.claude/worktrees/gen2-crystal-skeleton/src/world/OverworldController.lua)

Important behavior:

- Crystal uses `PaletteFX.timeOfDay()` based on `os.date`.
- Time buckets are `morn`, `day`, `nite`.
- Crystal palette rebakes are cache-keyed by time bucket.

### 4. Crystal New Game Intro

Status: code exists; planning/spec docs lag behind implementation state.

Goal:

- replace `NoOpScreen` with a real Crystal intro flow,
- support boy/girl choice,
- use Kris when appropriate,
- show Oak and Wooper demo,
- name the player,
- then spawn into New Bark Town.

Primary docs:

- [docs/superpowers/specs/2026-08-04-gen2-crystal-intro-design.md](/Users/andreaugustozaguettefernandes/repos/gen1recomp/.claude/worktrees/gen2-crystal-skeleton/docs/superpowers/specs/2026-08-04-gen2-crystal-intro-design.md)
- [docs/superpowers/plans/2026-08-04-gen2-crystal-intro.md](/Users/andreaugustozaguettefernandes/repos/gen1recomp/.claude/worktrees/gen2-crystal-skeleton/docs/superpowers/plans/2026-08-04-gen2-crystal-intro.md)

Key implementation files:

- [src/ui/CrystalIntro.lua](/Users/andreaugustozaguettefernandes/repos/gen1recomp/.claude/worktrees/gen2-crystal-skeleton/src/ui/CrystalIntro.lua)
- [src/world/Player.lua](/Users/andreaugustozaguettefernandes/repos/gen1recomp/.claude/worktrees/gen2-crystal-skeleton/src/world/Player.lua)
- `RomExtractorGen2:extractIntroPics()`
- `RomExtractorGen2:extractIntroText()`
- `RomExtractorGen2:extractField()`

Important detail:

- `field.boot.screens.newGame` is now wired to `CrystalIntro`.
- `Player.new`/sprite refresh supports gender-driven swap to Kris.

### 5. Cry Transcoding

Status: code exists and tests exist.

Goal:

- translate Crystal cry bytecode into the Gen1/ChipAsm-compatible form,
- avoid modifying the shared chip playback engine.

Primary docs:

- [docs/superpowers/specs/2026-08-04-gen2-crystal-cry-transcoder-design.md](/Users/andreaugustozaguettefernandes/repos/gen1recomp/.claude/worktrees/gen2-crystal-skeleton/docs/superpowers/specs/2026-08-04-gen2-crystal-cry-transcoder-design.md)
- [docs/superpowers/plans/2026-08-04-gen2-crystal-cry-transcoder.md](/Users/andreaugustozaguettefernandes/repos/gen1recomp/.claude/worktrees/gen2-crystal-skeleton/docs/superpowers/plans/2026-08-04-gen2-crystal-cry-transcoder.md)

Key implementation files:

- [src/audio/CrystalCryTranscoder.lua](/Users/andreaugustozaguettefernandes/repos/gen1recomp/.claude/worktrees/gen2-crystal-skeleton/src/audio/CrystalCryTranscoder.lua)
- `RomExtractorGen2:extractCry()`

Important limitation:

- this transcoder is intentionally narrow, scoped to the opcode set needed by Wooper's cry path.

### 6. Crystal Title Screen and Title Music

Status: code exists; docs still describe it as proposed/planned.

Goal:

- add Crystal-specific title visuals,
- extract title graphics from ROM,
- transcode title music into the existing song playback pipeline,
- avoid touching core audio playback unnecessarily.

Primary docs:

- [docs/superpowers/specs/2026-08-05-gen2-crystal-title-screen-design.md](/Users/andreaugustozaguettefernandes/repos/gen1recomp/.claude/worktrees/gen2-crystal-skeleton/docs/superpowers/specs/2026-08-05-gen2-crystal-title-screen-design.md)
- [docs/superpowers/plans/2026-08-05-gen2-crystal-title-screen.md](/Users/andreaugustozaguettefernandes/repos/gen1recomp/.claude/worktrees/gen2-crystal-skeleton/docs/superpowers/plans/2026-08-05-gen2-crystal-title-screen.md)

Key implementation files:

- [src/ui/TitleState.lua](/Users/andreaugustozaguettefernandes/repos/gen1recomp/.claude/worktrees/gen2-crystal-skeleton/src/ui/TitleState.lua)
- [src/audio/CrystalMusicTranscoder.lua](/Users/andreaugustozaguettefernandes/repos/gen1recomp/.claude/worktrees/gen2-crystal-skeleton/src/audio/CrystalMusicTranscoder.lua)
- `RomExtractorGen2:extractTitle()`
- `RomExtractorGen2:extractTitleMusic()`

Important limitation:

- channel 3 wave support is still explicitly out of scope in the title music transcoder.

## Source of Truth for Planning

There are two kinds of truth in this worktree:

1. **Code truth**: what is actually implemented now.
2. **Spec/plan truth**: the reasoning, constraints, and intended scope behind each slice.

When they disagree, prefer this order:

1. current code,
2. tests,
3. most recent plan/spec.

Example:

- the intro and title docs still contain language like "approved for planning" or "proposed",
- but code for `CrystalIntro`, `CrystalMusicTranscoder`, title extraction, and title layout already exists.

## Tests and Validation

Relevant Crystal-focused tests already in the tree:

- [tools/extract_gen2/test_lz3.py](/Users/andreaugustozaguettefernandes/repos/gen1recomp/.claude/worktrees/gen2-crystal-skeleton/tools/extract_gen2/test_lz3.py)
- [tools/extract_gen2/test_font.py](/Users/andreaugustozaguettefernandes/repos/gen1recomp/.claude/worktrees/gen2-crystal-skeleton/tools/extract_gen2/test_font.py)
- [tools/extract_gen2/test_palettes.py](/Users/andreaugustozaguettefernandes/repos/gen1recomp/.claude/worktrees/gen2-crystal-skeleton/tools/extract_gen2/test_palettes.py)
- [tests/engine/gen2_crystal_intro.lua](/Users/andreaugustozaguettefernandes/repos/gen1recomp/.claude/worktrees/gen2-crystal-skeleton/tests/engine/gen2_crystal_intro.lua)
- [tests/engine/gen2_cry_transcoder.lua](/Users/andreaugustozaguettefernandes/repos/gen1recomp/.claude/worktrees/gen2-crystal-skeleton/tests/engine/gen2_cry_transcoder.lua)
- [tests/engine/gen2_music_transcoder.lua](/Users/andreaugustozaguettefernandes/repos/gen1recomp/.claude/worktrees/gen2-crystal-skeleton/tests/engine/gen2_music_transcoder.lua)
- Crystal palette fixture coverage inside [tests/run_tests.lua](/Users/andreaugustozaguettefernandes/repos/gen1recomp/.claude/worktrees/gen2-crystal-skeleton/tests/run_tests.lua)

If you are resuming work, start by running the smallest relevant targeted tests first, then the broader suite.

## Important Constraints

These are recurring project rules and should be treated as hard constraints:

- Do not commit ROM bytes.
- Do not make the runtime depend on a local disassembly checkout.
- Manifest generation may depend on a local `pret/pokecrystal` checkout and built `.sym`, but committed output must remain metadata only.
- Keep the Gen1 pipeline stable.
- Prefer extraction-time translation over risky shared-runtime rewrites.
- Reuse existing generic helpers when they are already proven safe.
- Keep Crystal work scoped and slice-based rather than attempting a full Johto implementation in one step.

## Known Gaps / Likely Next Work

The biggest remaining gaps are still gameplay breadth, not bootstrap:

- only a narrow Crystal slice is extracted,
- map coverage is still centered on New Bark Town,
- broader world/object/script extraction is not done,
- general Crystal species/moves/items/battle data is not done,
- wave-channel audio is not done,
- broader Crystal music/SFX support is not done,
- Gold/Silver support is not started as a comparable pipeline.

If continuing Crystal work, the next likely milestones are:

1. expand extracted map/object/script coverage beyond New Bark Town,
2. promote current intro/title/audio code from "implemented but branch-local" to fully verified against real-ROM flows,
3. extend data extraction for species/items/moves as needed by gameplay,
4. handle additional audio scope only when a concrete gameplay/UI surface needs it.

## Recommended Resume Procedure For Another Agent

1. Read this file.
2. Read [docs/architecture.md](/Users/andreaugustozaguettefernandes/repos/gen1recomp/.claude/worktrees/gen2-crystal-skeleton/docs/architecture.md).
3. Read [src/core/GameVersion.lua](/Users/andreaugustozaguettefernandes/repos/gen1recomp/.claude/worktrees/gen2-crystal-skeleton/src/core/GameVersion.lua) and [src/import/RomExtractorGen2.lua](/Users/andreaugustozaguettefernandes/repos/gen1recomp/.claude/worktrees/gen2-crystal-skeleton/src/import/RomExtractorGen2.lua).
4. Read the latest relevant plan/spec under [docs/superpowers/plans](/Users/andreaugustozaguettefernandes/repos/gen1recomp/.claude/worktrees/gen2-crystal-skeleton/docs/superpowers/plans) and [docs/superpowers/specs](/Users/andreaugustozaguettefernandes/repos/gen1recomp/.claude/worktrees/gen2-crystal-skeleton/docs/superpowers/specs).
5. Run the narrowest relevant tests for the area you are changing.
6. Only then decide whether you are fixing, verifying, or expanding Crystal support.

## Practical Summary

If you need the shortest accurate mental model:

- this is a working Gen1 engine with ROM-driven extraction,
- this worktree is porting that extraction model to Crystal,
- New Bark Town bootstrap is already in place,
- font and native color are in place,
- intro, cry, title visuals, and title music have code in the branch,
- specs are partially behind the code,
- the safest next work is to verify and then extend Crystal breadth without destabilizing Gen1.
