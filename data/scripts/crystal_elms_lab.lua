-- Minimal Crystal Elm's Lab flow for the New Bark opening:
-- talk to Elm, unlock the three starter balls, choose one, then continue.
-- This intentionally scopes to the starter handoff path only.

local function starterBall(species, askText, choseFlag, ownBall)
  return {
    { "face_player" },
    { "check_flag", "EVENT_GOT_A_POKEMON_FROM_ELM" },
    { "jump_if_true", "already_got_one" },
    { "check_flag", "EVENT_FOLLOWED_OAK_INTO_LAB" },
    { "jump_if_false", "talk_to_elm_first" },
    { "ask", askText },
    { "jump_if_false", "end" },
    { "play_sound", "Get_Key_Item" },
    { "show_text", "You received\n{RAM:" .. species .. "}!", { RAM = species } },
    { "give_pokemon", species, 5 },
    { "set_flag", "EVENT_GOT_STARTER" },
    { "set_flag", "EVENT_GOT_A_POKEMON_FROM_ELM" },
    { "set_flag", choseFlag },
    { "hide_object", "ELMS_LAB", ownBall },
    { "show_text",
      "MR.POKéMON lives a\nlittle bit beyond\nCHERRYGROVE, the\nnext city.\fTake this POKéMON\nwith you." },
    { "jump", "end" },

    { "label", "talk_to_elm_first" },
    { "show_text",
      "PROF.ELM is looking\nfor someone to run\nan errand.\fYou should talk to\nhim first." },
    { "jump", "end" },

    { "label", "already_got_one" },
    { "show_text", "That's a POKé BALL.\nThere's a POKéMON\ninside!" },
  }
end

return {
  talk = {
    TEXT_ELMSLAB_ELM = {
      { "face_player" },
      { "check_flag", "EVENT_GOT_A_POKEMON_FROM_ELM" },
      { "jump_if_true", "after_starter" },
      { "check_flag", "EVENT_FOLLOWED_OAK_INTO_LAB" },
      { "jump_if_true", "repeat_intro" },
      { "show_text",
        "So this is it!\nMy latest experi-\nment.\fThanks to you, I\nmay finally solve\nthe mystery of\nPOKéMON!" },
      { "show_text",
        "Will you raise one\nof these POKéMON\nfor me?" },
      { "show_text",
        "You'll find one in\neach of those\nPOKé BALLS.\fGo ahead. Choose\none!" },
      { "set_flag", "EVENT_FOLLOWED_OAK_INTO_LAB" },
      { "jump", "end" },

      { "label", "repeat_intro" },
      { "show_text",
        "Go ahead. Choose\none of the POKéMON\nin the POKé BALLS." },
      { "jump", "end" },

      { "label", "after_starter" },
      { "show_text",
        "How is your POKéMON?\fIf it is hurt, you\nshould heal it with\nthe machine." },
    },

    TEXT_ELMSLAB_ELMS_AIDE = {
      { "face_player" },
      { "check_flag", "EVENT_GOT_A_POKEMON_FROM_ELM" },
      { "jump_if_true", "after_starter" },
      { "show_text",
        "PROF.ELM is always\nbusy with his\nresearch." },
      { "jump", "end" },

      { "label", "after_starter" },
      { "show_text",
        "When I grow up, I'm\ngoing to help PROF.\nELM, too." },
    },

    TEXT_ELMSLAB_OFFICER = {
      { "face_player" },
      { "show_text", "..." },
    },

    TEXT_ELMSLAB_CYNDAQUIL_POKE_BALL =
      starterBall("CYNDAQUIL", "Do you want\nCYNDAQUIL?", "EVENT_GOT_CYNDAQUIL_FROM_ELM",
        "ELMSLAB_POKE_BALL1"),
    TEXT_ELMSLAB_TOTODILE_POKE_BALL =
      starterBall("TOTODILE", "Do you want\nTOTODILE?", "EVENT_GOT_TOTODILE_FROM_ELM",
        "ELMSLAB_POKE_BALL2"),
    TEXT_ELMSLAB_CHIKORITA_POKE_BALL =
      starterBall("CHIKORITA", "Do you want\nCHIKORITA?", "EVENT_GOT_CHIKORITA_FROM_ELM",
        "ELMSLAB_POKE_BALL3"),
  },
}
