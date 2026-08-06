-- Route 29/Route 46 Gate, the ledge-shortcut gate between Route 29 (south)
-- and Route 46 (north) (pret/pokecrystal maps/Route29Route46Gate.asm).
--
-- Ported: both NPCs. Both are simple `jumptextfaceplayer` scripts with no
-- branching, matching crystal_route29.lua's TEXT_ROUTE29_YOUNGSTER/
-- TEXT_ROUTE29_TEACHER1 style exactly.

return {
  talk = {
    TEXT_ROUTE29ROUTE46GATE_OFFICER = {
      { "face_player" },
      { "show_text",
        "You can't climb\nledges.\fBut you can jump\ndown from them to\vtake a shortcut." },
    },

    TEXT_ROUTE29ROUTE46GATE_YOUNGSTER = {
      { "face_player" },
      { "show_text",
        "Different kinds of\nPOKéMON appear\vpast here.\fIf you want to\ncatch them all,\fyou have to look\neverywhere." },
    },
  },
}
