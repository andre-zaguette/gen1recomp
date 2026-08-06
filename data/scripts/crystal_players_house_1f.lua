-- The player's house, 1F (pret/pokecrystal maps/PlayersHouse1F.asm:
-- MomScript, NeighborScript). Mom's ROM script also branches into
-- `special BankOfMom` once the mystery-egg errand is done, and gives the
-- POKéGEAR after Elm's Lab -- neither exists in this project yet, so only
-- the two reachable early branches are ported (before/after getting the
-- starter, same EVENT_GOT_A_POKEMON_FROM_ELM check as the New Bark Town
-- teacher). The visiting neighbor's time-of-day greeting (checktime)
-- collapses to her DAY line -- there is no script command for
-- time-of-day text yet, and the substance of what she says doesn't
-- change with it.

return {
  talk = {
    TEXT_PLAYERSHOUSE1F_MOM1 = {
      { "face_player" },
      { "check_flag", "EVENT_GOT_A_POKEMON_FROM_ELM" },
      { "jump_if_true", "after_starter" },
      { "show_text", "PROF.ELM is wait-\ning for you.\fHurry up, baby!" },
      { "jump", "end" },

      { "label", "after_starter" },
      { "show_text",
        "So, what was PROF.\nELM's errand?\f…\fThat does sound\nchallenging.\fBut, you should be\nproud that people\vrely on you." },
    },

    TEXT_PLAYERSHOUSE1F_POKEFAN_F = {
      { "face_player" },
      { "show_text",
        "Hello, {PLAYER}!\nI'm visiting!\f{PLAYER}, have you\nheard?\fMy daughter is\nadamant about\fbecoming PROF.\nELM's assistant.\fShe really loves\nPOKéMON!" },
    },
  },
}
