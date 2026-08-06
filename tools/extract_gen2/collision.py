# tools/extract_gen2/collision.py
LAND_TILE, WATER_TILE, WALL_TILE, TALK = 0x00, 0x01, 0x0F, 0x10
# Not a pokecrystal COLL_* base value -- an extra flag bit this project
# adds on the LAND_TILE base, the same way TALK flags a WALL/WATER tile.
# constants/collision_constants.asm's COLL_LONG_GRASS ($14) and
# COLL_TALL_GRASS ($18) are the two real wild-encounter grass values; both
# stay walkable (bits 0-3 are still LAND_TILE) once flagged, matching Map
# .lua's own isGrassCell needing "walkable AND grass" to be true together.
GRASS = 0x20

_WALL = (
    0x07, 0x0F, 0x27, 0x2F, 0x62, 0x6A,
    *range(0x80, 0x85), *range(0x88, 0x8D), *range(0x90, 0xA0),
    0xFF,
)
_WALL_TALK = (0x12, 0x15, 0x1A, 0x1D)
_WATER = (
    0x20, 0x21, 0x25, 0x26, 0x28, 0x29, 0x2D, 0x2E,
    *range(0x30, 0x40), *range(0xC0, 0xD0),
)
_WATER_TALK = (0x22, 0x24, 0x2A, 0x2C)
_GRASS = (0x14, 0x18)

COLLISION_PERMISSION_TABLE = [LAND_TILE] * 256
for _index in _WALL:
    COLLISION_PERMISSION_TABLE[_index] = WALL_TILE
for _index in _WALL_TALK:
    COLLISION_PERMISSION_TABLE[_index] = WALL_TILE | TALK
for _index in _WATER:
    COLLISION_PERMISSION_TABLE[_index] = WATER_TILE
for _index in _WATER_TALK:
    COLLISION_PERMISSION_TABLE[_index] = WATER_TILE | TALK
for _index in _GRASS:
    COLLISION_PERMISSION_TABLE[_index] = LAND_TILE | GRASS

assert len(COLLISION_PERMISSION_TABLE) == 256
