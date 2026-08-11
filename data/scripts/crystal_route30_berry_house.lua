return {
  talk = {
    TEXT_ROUTE30BERRYHOUSE_POKEFAN_M = {
      { "face_player" },
      { "check_flag", "EVENT_GOT_BERRY_FROM_ROUTE_30_HOUSE" },
      { "jump_if_true", "got_berry" },
      { "show_text",
        "You know, POKéMON\neat BERRIES.\fWell, my POKéMON\ngot healthier by\neating a BERRY.\fHere. I'll share\none with you!" },
      { "give_item", "BERRY", 1, false },
      { "set_flag", "EVENT_GOT_BERRY_FROM_ROUTE_30_HOUSE" },

      { "label", "got_berry" },
      { "show_text",
        "Check trees for\nBERRIES. They just\ndrop right off." },
    },

    Route30BerryHouseBookshelf = {
      { "show_text", "It's packed with\nmagazines." },
    },
  },
}
