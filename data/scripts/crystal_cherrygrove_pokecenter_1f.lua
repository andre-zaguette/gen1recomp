return {
  talk = {
    TEXT_CHERRYGROVEPOKECENTER1F_NURSE = {
      { "face_player" },
      { "show_text",
        "Welcome to our\nPOKéMON CENTER!\fWe heal your\nPOKéMON back to\vperfect health." },
      { "heal_party" },
      { "show_text", "OK. Your POKéMON\nare fighting fit!" },
    },

    TEXT_CHERRYGROVEPOKECENTER1F_FISHER = {
      { "face_player" },
      { "show_text",
        "It's great. I can\nstore any number\nof POKéMON, and\nit's all free." },
    },

    TEXT_CHERRYGROVEPOKECENTER1F_GENTLEMAN = {
      { "face_player" },
      { "show_text",
        "That PC is free\nfor any trainer\nto use." },
    },

    TEXT_CHERRYGROVEPOKECENTER1F_TEACHER = {
      { "face_player" },
      { "check_flag", "EVENT_GAVE_MYSTERY_EGG_TO_ELM" },
      { "jump_if_true", "comm_center_open" },
      { "show_text",
        "The COMMUNICATION\nCENTER upstairs\nwas just built.\fBut they're still\nfinishing it up." },
      { "jump", "end" },

      { "label", "comm_center_open" },
      { "show_text",
        "The COMMUNICATION\nCENTER upstairs\nwas just built.\fI traded POKéMON\nthere already!" },
    },
  },
}
