# Crystal notes

A running index of facts and conventions learned while porting Pokémon
Crystal onto gen1recomp's Gen1 engine, so future work doesn't re-derive
them from scratch. Grows one milestone at a time — see
`docs/superpowers/plans/2026-08-06-gen2-crystal-roadmap.md` for the
milestone sequence this feeds.

Written as plain markdown with `[[wikilink]]`-style cross-references
(Obsidian-compatible, but no app required — any editor or `grep` reads
these fine).

- [[conventions]] — patterns that hold across every Crystal map/object/
  sprite touched so far (flag polarity, text markers, palette groups,
  sprite gotchas).
- [[map-connections]] — the map graph confirmed so far, and how it was
  confirmed.
- [[rom-and-repo-map]] — where a given fact lives, in both
  `roms/pokecrystal` (the ROM source) and this repo (the port).

For the two facts that come up over and over (a map's connections, and
whether an event flag is force-set on a new save — see [[conventions]]'s
SET=hidden section), don't re-grep `roms/pokecrystal` by hand: run
`python3 tools/crystal_index.py --pokecrystal roms/pokecrystal` once (or
whenever the checkout changes) and query the JSON it writes instead —
`tools/crystal_index.py`'s own docstring has the exact query one-liners.
It covers every map/flag pret's source defines, not only the ones this
project has ported, so it stays useful as the roadmap advances. It's
gitignored (regenerate on demand, same prerequisite as
`tools/rom_manifest_crystal.json`) — nothing at runtime reads it, it's
purely a lookup aid for whoever's picking up this codebase next.

**Rule for adding to these notes:** only record something once it's been
verified against real ROM source or real code in this session's own work
(a grep result, a decoded byte, a test that passed) — never a guess. If a
later milestone finds one of these wrong, correct it in place and note
what changed, don't leave stale facts standing.
