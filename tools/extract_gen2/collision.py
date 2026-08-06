# tools/extract_gen2/collision.py
LAND_TILE, WATER_TILE, WALL_TILE, TALK = 0x00, 0x01, 0x0F, 0x10

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

COLLISION_PERMISSION_TABLE = [LAND_TILE] * 256
for _index in _WALL:
    COLLISION_PERMISSION_TABLE[_index] = WALL_TILE
for _index in _WALL_TALK:
    COLLISION_PERMISSION_TABLE[_index] = WALL_TILE | TALK
for _index in _WATER:
    COLLISION_PERMISSION_TABLE[_index] = WATER_TILE
for _index in _WATER_TALK:
    COLLISION_PERMISSION_TABLE[_index] = WATER_TILE | TALK

assert len(COLLISION_PERMISSION_TABLE) == 256
