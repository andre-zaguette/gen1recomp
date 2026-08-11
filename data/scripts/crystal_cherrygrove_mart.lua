return {
  talk = {
    TEXT_CHERRYGROVEMART_CLERK = {
      { "face_player" },
      { "show_text", "Hi there!\nMay I help you?" },
      { "check_flag", "EVENT_GAVE_MYSTERY_EGG_TO_ELM" },
      { "jump_if_true", "dex_stock" },
      { "push_screen", "ShopMenu", { "POTION", "ANTIDOTE", "PARLYZ_HEAL", "AWAKENING" } },
      { "jump", "end" },

      { "label", "dex_stock" },
      { "push_screen", "ShopMenu", { "POKE_BALL", "POTION", "ANTIDOTE", "PARLYZ_HEAL", "AWAKENING" } },
    },

    TEXT_CHERRYGROVEMART_COOLTRAINER_M = {
      { "face_player" },
      { "check_flag", "EVENT_GAVE_MYSTERY_EGG_TO_ELM" },
      { "jump_if_true", "balls_in_stock" },
      { "show_text",
        "They're fresh out\nof POKé BALLS!\fWhen will they get\nmore of them?" },
      { "jump", "end" },

      { "label", "balls_in_stock" },
      { "show_text",
        "POKé BALLS are in\nstock! Now I can\ncatch POKéMON!" },
    },

    TEXT_CHERRYGROVEMART_YOUNGSTER = {
      { "face_player" },
      { "show_text",
        "When I was walking\nin the grass, a\fbug POKéMON poi-\nsoned my POKéMON!\fI just kept going,\nbut then my\fPOKéMON fainted.\fYou should keep an\nANTIDOTE with you." },
    },
  },
}
