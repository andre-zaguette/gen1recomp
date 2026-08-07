# gen1recomp-modern-kanto

> **Beta.** Four separately switchable changes, and the ones that move the
> balance are off until you turn them on.

Gen 1 decided by *type* what every generation since decides by *move*, and
shipped a battle system nobody could argue with because nobody could see it.
This is four answers to that, for
[Gen1Recomp](https://github.com/bryanthaboi/gen1recomp).

## Install

Download `modern_kanto-<version>.zip` from [Releases](../../releases), then
**Launcher → MODS → Import mod .zip**.

The launcher can also keep it up to date on its own — the manifest declares
this repo, so a newer release is offered from the mod's row, and it can be
installed from the **Find mods** tab without touching a file.

## The four pieces

**START → MODS → Modern Kanto → OPTIONS..**

| Option | Default | What |
| --- | --- | --- |
| `SPLIT` | off | physical/special per move, not per type |
| `TYPE CHART` | `GEN 1` | the three rows Gen 2 rebalanced |
| `GHOST FIX` | **on** | Ghost 0x → 2x against Psychic |
| `SMART AI` | off | the type pass multiplies both defender types |
| `ATLAS` | on | a screen for what lives where |

`SPLIT` and `TYPE CHART` are load-time registry patches, so changing them
takes effect on the next launch rather than mid-battle. That is deliberate:
a move that changed category halfway through a fight would be worse than
either answer.

### SPLIT — the Gen 4 move split

In Gen 1 the category comes from the type. Every Water move is special
because Water is a special type; every Normal move is physical. So Gyarados
— **125 Attack, 60 Special** — throws Hydro Pump off the wrong stat, and
Hitmonchan cannot meaningfully use its elemental punches at all.

The engine already supports the per-move answer. `Damage.categoryOf`:

> the move's own category field wins, then the merged type record's

Gen 1 simply never fills the move's own field. So this ships as **17
registry patches** — pure data, no damage hook, nothing intercepted — and it
composes with any other mod that touches a battle instead of racing it.

Only the differences are listed. A move already categorised the way its type
implies needs no entry.

### GHOST FIX — separate, and on by default

Ghost was meant to be strong against Psychic. The games say so, Sabrina's
gym is built as though it were true, and the shipped table says `0`: Ghost
does **literally nothing** to Psychic. Gen 1's only Ghost moves sit on
Poison-typed Pokémon, which Psychic resists, so Psychic ends up with no
counterplay and eats the generation.

That is a bug, so it is on by default and lives on its own switch. The other
three rows — Bug/Poison, Poison/Bug, Ice/Fire — are Gen 2 rebalancing a
working chart, which is a matter of taste, so they sit behind `TYPE CHART`.

All four were read out of the decoded chart, not from memory, and a test
asserts the ROM still says what this claims it says.

### SMART AI — a fix, not an addition

Registering a new AI layer would have done nothing: `TrainerAI` walks the
trainer class's *own* list of layers and looks each id up, so an id nobody
references is a record that never runs — working in appearance, inert in
fact.

So this patches `LAYER_3`, the vanilla type pass every type-aware trainer
already uses. The engine's own comment on it:

> AIGetTypeEffectiveness only reads the FIRST matching TypeEffects row for
> (move type vs either defender type) — **no dual-type product**

Which is why a Gen 1 trainer will throw Earthquake at a Pidgey until it
faints: it reads the 2x against Rock and never reaches the Flying immunity.
This multiplies the rows out, the way the damage calculation does when the
move actually lands.

It still only nudges scores. Vanilla's other passes run untouched, so a
trainer keeps its personality and simply stops firing Water Gun at Gyarados.

### ATLAS — what lives here, and what you still need

Gen 1 holds a complete encounter table and shows the player none of it. The
Pokédex says what a species is once you have met it; nothing says where to
go and find the one you have not.

The Atlas reads the **merged** encounter dataset — so a mod that adds or
edits encounters shows up here too — folds the slots into one row per
species with the level range it actually spans, and marks each against your
dex. Areas are counted by how many of their species you own, because the
question the screen exists to answer is not "what is here" but "is there
anything here I still need".

## Requirements and legal

Lua source only: **no ROM, no ROM-derived data, no game assets** — `modkit
lint` reports `no ROM-derived content`, and the tables here are factual
statements about how the game behaves. You need Gen1Recomp and your own
legally obtained Pokémon Red or Blue ROM; neither is provided here.

Not affiliated with, endorsed by, or connected to Nintendo, Game Freak, or
The Pokémon Company. Pokémon and all related names are trademarks of their
respective owners, used here only to describe what this software does.

## Support

If this made Kanto make more sense, you can support the author here:
<https://linktr.ee/made_in_taly>

## Licence

[MIT](LICENSE) — see the file for terms.
