return {
  talk = {
    TEXT_ROUTE31_FISHER = {
      { "face_player" },
      { "show_text",
        "… Hnuurg… Huh?\fI walked too far\ntoday looking for\nPOKéMON.\fMy feet hurt and\nI'm sleepy…\fIf I were a wild\nPOKéMON, I'd be\neasy to catch…\f…Zzzz…" },
    },

    TEXT_ROUTE31_YOUNGSTER = {
      { "face_player" },
      { "show_text",
        "I found a good\nPOKéMON in DARK\nCAVE.\fI'm going to raise\nit to take on\nFALKNER.\fHe's the leader of\nVIOLET CITY's GYM." },
    },

    TEXT_ROUTE31_COOLTRAINER_M = {
      { "face_player" },
      { "show_text",
        "DARK CAVE…\fIf POKéMON could\nlight it up, I'd\nexplore it." },
    },

    TEXT_ROUTE31_POTION = {
      { "check_flag", "EVENT_ROUTE_31_POTION" },
      { "jump_if_true", "end" },
      { "give_item", "POTION", 1 },
      { "set_flag", "EVENT_ROUTE_31_POTION" },
      { "hide_object", "ROUTE_31", "ROUTE31_POKE_BALL1" },
    },

    TEXT_ROUTE31_POKE_BALL = {
      { "check_flag", "EVENT_ROUTE_31_POKE_BALL" },
      { "jump_if_true", "end" },
      { "give_item", "POKE_BALL", 1 },
      { "set_flag", "EVENT_ROUTE_31_POKE_BALL" },
      { "hide_object", "ROUTE_31", "ROUTE31_POKE_BALL2" },
    },

    Route31Sign = {
      { "show_text", "ROUTE 31\fVIOLET CITY -\nCHERRYGROVE CITY" },
    },

    DarkCaveSign = {
      { "show_text", "DARK CAVE" },
    },
  },
}
