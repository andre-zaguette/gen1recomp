-- The player's neighbors' house (pret/pokecrystal
-- maps/PlayersNeighborsHouse.asm: PlayersNeighborsDaughterScript,
-- PlayersNeighborScript). Both are single-text jumptextfaceplayer scripts
-- in the ROM, no branching. The radio (PlayersNeighborsHouseRadioScript)
-- and its EVENT_LISTENED_TO_INITIAL_RADIO flow are out of scope here.

return {
  talk = {
    TEXT_PLAYERSNEIGHBORSHOUSE_COOLTRAINER_F = {
      { "face_player" },
      { "show_text",
        "PIKACHU is an\nevolved POKéMON.\fI was amazed by\nPROF.ELM's find-\vings.\fHe's so famous for\nhis research on\vPOKéMON evolution.\f…sigh…\fI wish I could be\na researcher like\vhim…" },
    },

    TEXT_PLAYERSNEIGHBORSHOUSE_POKEFAN_F = {
      { "face_player" },
      { "show_text",
        "My daughter is\nadamant about\fbecoming PROF.\nELM's assistant.\fShe really loves\nPOKéMON!\fBut then, so do I!" },
    },
  },
}
