return {
  onInteract = function(game, overworld, fx, fy)
    if overworld.player.facing == "up"
       and fx >= 0 and fx <= 1
       and fy >= 1 and fy <= 2 then
      overworld:openPC()
      return true
    end
    return false
  end,
  talk = {
    TEXT_CHERRYGROVEPOKECENTER1F_NURSE = function(game, overworld, npc, onDone)
      npc:facePlayer(overworld.player)
      overworld:nurseHeal(onDone, npc)
    end,

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
