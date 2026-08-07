
return function(mod)
  mod.content.maps:patch("PALLET_TOWN", {
    width = 16,
    height = 9,
    blocks = {
       82,  79,  82,  82,  79,  11,  80,  82,  82,  80, 108, 108, 108, 108, 108,  54,
       78,   1,  56,  57,   1,   1,  56,  57,   1,  77,  10,  10,  10,  10,  10, 110,
       78,   8,  60,  61,   1,   8,  60,  61,   1,   1,   1,   1,   1,   1,   1, 110,
       78,   1,   1,   1,   1,   1,   1,   1,   1,  77,  26,  26,  26,  26,  26,  15,
       78,   1, 119,  86,   1,  12,  13,  14,   1,  77,   1,   1,   1,   1,   1, 110,
       78,   1, 116, 116,   1,  16,  58,   0,   1,  77,  26,  26,  26,  26,  26,  15,
       78,   1,   1,   1,   1, 119,  86, 119,  49,  77,   1,   1,   1,   1,   1, 110,
       78,  10,  29,  30,  49, 116, 116,  10,  49,  77,   1,   2,   3,   1,   1, 110,
       80,  10, 101, 100,  97,  97,  97,  97,  97,  79, 111, 111, 111, 111, 111,  15,
    },
    warps = {
      { x = 5, y = 5, destMap = "REDS_HOUSE_1F", destWarp = 1 },
      { x = 13, y = 5, destMap = "BLUES_HOUSE", destWarp = 1 },
      { x = 12, y = 11, destMap = "OAKS_LAB", destWarp = 2 },
      { x = 23, y = 15, destMap = "BOOKERS_HEAVEN", destWarp = 1 },
    },
    -- __append keeps the three vanilla objects (PALLETTOWN_OAK index 1,
    -- GIRL 2, FISHER 3); a bare list would replace them, since maps merge
    -- with record semantics.  Index 4 is the first free object slot.
    --
    -- This is deliberately NOT the vanilla PALLETTOWN_OAK: the intro
    -- cutscene (data/scripts/story2.lua) shows/hides/walks that one from
    -- (8,5), so borrowing it would leave the escort standing in the wrong
    -- place.  Ours is its own object, hidden until the gate scene runs and
    -- hidden again the moment it ends.  The def coordinates are only a
    -- spawn point -- the scene relocates him next to the player with
    -- place_npc, and show_object rebuilds the NPC from this def every
    -- time, so the relocation never sticks.
    objects = { __append = {
      {
        hidden = true,
        index = 4,
        movement = "STAY",
        name = "PALLETTOWN_OAK_GATE",
        range = "RIGHT",
        sprite = "SPRITE_OAK",
        text = "TEXT_PALLETTOWN_OAK_GATE",
        x = 18,
        y = 5,
      },
    } },
  })
end
