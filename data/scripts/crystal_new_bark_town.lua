-- New Bark Town's two reachable NPCs (pret/pokecrystal maps/NewBarkTown.asm:
-- NewBarkTownTeacherScript, NewBarkTownFisherScript). The rival's object
-- (NEWBARKTOWN_RIVAL) stays hidden in the manifest -- his real flag,
-- EVENT_RIVAL_NEW_BARK_TOWN, is only set from MrPokemonsHouse.asm's
-- errand-return script, which this project hasn't built yet -- so there is
-- no talk entry for him here.

return {
  talk = {
    TEXT_NEWBARKTOWN_TEACHER = {
      { "face_player" },
      { "check_flag", "EVENT_GOT_A_POKEMON_FROM_ELM" },
      { "jump_if_true", "adorable" },
      { "show_text", "Wow, your POKéGEAR\nis impressive!\fDid your mom get\nit for you?" },
      { "jump", "end" },

      { "label", "adorable" },
      { "show_text", "Oh! Your POKéMON\nis adorable!\vI wish I had one!" },
    },

    TEXT_NEWBARKTOWN_FISHER = {
      { "face_player" },
      { "show_text", "Yo, {PLAYER}!\fI hear PROF.ELM\ndiscovered some\vnew POKéMON." },
    },
  },
}
