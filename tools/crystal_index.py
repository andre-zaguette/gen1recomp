#!/usr/bin/env python3
"""Builds a lightweight, queryable index of a pret/pokecrystal checkout.

Not part of the shipped extraction pipeline (that's
make_rom_manifest_crystal.py, scoped to the maps this project has actually
registered). This is a development aid: instead of re-grepping the whole
roms/pokecrystal tree every time a session needs "does this map connect to
that one" or "is this event flag set on a new save", it reads two facts
once and writes them to a small JSON file that a later `jq`/`python -c`
one-liner can query in place of a fresh grep pass.

Indexes, for every map/flag pret's source defines -- not just the ones
this project has ported yet, so it stays useful as the roadmap advances:

  - maps: label, dimensions, group/number, connections (data/maps/
    attributes.asm), tileset id
  - event_flags: declaration index, and whether InitializeEventsScript
    force-sets it on a new save (engine/events/std_scripts.asm) -- the
    SET=hidden convention documented in
    docs/superpowers/crystal-notes/conventions.md depends on knowing this
    per flag, and re-deriving it by hand (grep the flag, grep
    InitializeEventsScript, cross-reference) is exactly the repeated cost
    this script exists to cut.

Usage:
    python3 tools/crystal_index.py --pokecrystal roms/pokecrystal \\
        --out tools/crystal_index.json

Query examples once built:
    python3 -c "import json; d=json.load(open('tools/crystal_index.json'));
      print(d['event_flags']['EVENT_COP_IN_ELMS_LAB'])"
    jq '.maps.ROUTE_29.connections' tools/crystal_index.json
    jq '.event_flags | to_entries[] | select(.value.force_set_at_boot) | .key' \\
      tools/crystal_index.json   # every flag hidden-by-default at boot

This index does NOT replace reading the actual .asm when a task needs a
script body, text, or object list -- it only answers the two questions
above without a fresh grep. Regenerate after pulling a newer pokecrystal
checkout; nothing here is committed as project data (see AGENT_HANDOFF.md
-- no ROM bytes, and this carries none: it's derived from the public
pokecrystal disassembly source, same as tools/rom_manifest_crystal.json).
"""

import argparse
import json
import os
import re


def read_lines(path):
    with open(path, "r", encoding="utf-8", errors="replace") as f:
        return f.readlines()


def index_event_flags(pokecrystal):
    """name -> {index, force_set_at_boot}."""
    path = os.path.join(pokecrystal, "constants/event_flags.asm")
    flags = {}
    index = 0
    for line in read_lines(path):
        s = line.strip()
        if s == "const_def":
            index = 0
            continue
        m = re.match(r"const\s+(EVENT_[A-Z0-9_]+)", s)
        if m:
            flags[m.group(1)] = {"index": index, "force_set_at_boot": False}
            index += 1

    init_path = os.path.join(pokecrystal, "engine/events/std_scripts.asm")
    in_init = False
    for line in read_lines(init_path):
        s = line.strip()
        if s == "InitializeEventsScript:":
            in_init = True
            continue
        if in_init:
            if s == "end" or (s.endswith(":") and not s.startswith(".")):
                # next label after the script body ends it
                if s != "end":
                    break
            m = re.match(r"setevent\s+(EVENT_[A-Z0-9_]+)", s)
            if m and m.group(1) in flags:
                flags[m.group(1)]["force_set_at_boot"] = True
    return flags


def parse_map_constants(pokecrystal):
    path = os.path.join(pokecrystal, "constants/map_constants.asm")
    out = {}
    group = 0
    number = 0
    for line in read_lines(path):
        s = line.strip()
        if s.startswith("newgroup"):
            group += 1
            number = 0
            continue
        if s.startswith("endgroup"):
            number = 0
            continue
        m = re.match(r"map_const\s+([A-Z0-9_]+),\s*(\d+),\s*(\d+)", s)
        if not m:
            continue
        number += 1
        out[m.group(1)] = {
            "width": int(m.group(2)), "height": int(m.group(3)),
            "group": group, "number": number,
        }
    return out


def index_maps(pokecrystal):
    dims = parse_map_constants(pokecrystal)
    path = os.path.join(pokecrystal, "data/maps/attributes.asm")
    maps = {}
    current = None
    for line in read_lines(path):
        s = line.strip()
        m = re.match(r"map_attributes\s+(\w+),\s+([A-Z0-9_]+),\s*(\S+)", s)
        if m:
            label, const_name, tileset_id = m.group(1), m.group(2), m.group(3)
            current = const_name
            d = dims.get(const_name, {})
            maps[current] = {
                "label": label,
                "asm": "maps/%s.asm" % label,
                "tileset_id": tileset_id,
                "width": d.get("width"), "height": d.get("height"),
                "group": d.get("group"), "number": d.get("number"),
                "connections": {},
            }
            continue
        m = re.match(
            r"connection\s+(north|south|west|east),\s+(\w+),\s+([A-Z0-9_]+),\s*(-?\d+)",
            s)
        if m and current:
            maps[current]["connections"][m.group(1)] = {
                "map": m.group(3), "offset": int(m.group(4)),
            }
    return maps


def main():
    parser = argparse.ArgumentParser(description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--pokecrystal", required=True)
    parser.add_argument("--out",
        default=os.path.join(os.path.dirname(__file__), "crystal_index.json"))
    args = parser.parse_args()

    pokecrystal = os.path.abspath(args.pokecrystal)
    if not os.path.isfile(os.path.join(pokecrystal, "main.asm")):
        raise SystemExit("%s is not a pokecrystal checkout" % pokecrystal)

    data = {
        "source": "derived from a local pret/pokecrystal checkout (public "
                   "disassembly source, not ROM bytes) -- see docstring",
        "maps": index_maps(pokecrystal),
        "event_flags": index_event_flags(pokecrystal),
    }
    with open(args.out, "w", encoding="utf-8", newline="\n") as f:
        json.dump(data, f, ensure_ascii=False, indent=2, sort_keys=True)
    print("wrote %s: %d maps, %d event flags" % (
        args.out, len(data["maps"]), len(data["event_flags"])))


if __name__ == "__main__":
    main()
