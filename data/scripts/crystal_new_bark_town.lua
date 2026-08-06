-- New Bark Town's three reachable NPCs (pret/pokecrystal maps/NewBarkTown.asm:
-- NewBarkTownTeacherScript, NewBarkTownFisherScript, NewBarkTownRivalScript).
--
-- NEWBARKTOWN_RIVAL is visible from the very start of the game (his flag,
-- EVENT_RIVAL_NEW_BARK_TOWN, is clear on a fresh save -- unlike
-- ELMSLAB_OFFICER's, it is not in InitializeEventsScript's force-set list),
-- caught spying by the lab before the player has even met Elm. ROM: he only
-- disappears from here once MrPokemonsHouse.asm's errand-return script sets
-- that flag, right before the player crosses paths with him elsewhere on
-- the way back -- that whole errand doesn't exist in this project yet, so
-- for now he just stays put rather than vanishing with nothing to replace
-- him.

-- object index within NEW_BARK_TOWN's object list (object_const_def order
-- in NewBarkTown.asm: NEWBARKTOWN_TEACHER, _FISHER, _RIVAL)
local RIVAL = 3

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

    -- ROM: NewBarkTownRivalScript. After the two lines of dialogue the real
    -- script shoves the player one tile south (playsound SFX_TACKLE) and
    -- retreats the rival one tile east before he vanishes for good (his
    -- flag gets set at Mr. Pokémon's house right after). This project has
    -- no trigger to make him vanish yet (#8's known gap), so he stays put
    -- and stays interactable -- retreating him a permanent tile every talk
    -- would walk him off his post a little further each time.
    TEXT_NEWBARKTOWN_RIVAL = {
      { "show_text", "…\fSo this is the\nfamous ELM POKéMON\vLAB…" },
      { "show_text", "…What are you\nstaring at?" },
      { "move_player", "down", 1 },
      { "face_object", RIVAL, "down" },
      { "move_player", "down", 1 },
    },

    NewBarkTownSign = {
      { "show_text", "NEW BARK TOWN\fThe Town Where the\nWinds of a New\vBeginning Blow" },
    },
    NewBarkTownPlayersHouseSign = {
      { "show_text", "{PLAYER}'s House" },
    },
    NewBarkTownElmsLabSign = {
      { "show_text", "ELM POKéMON LAB" },
    },
    NewBarkTownElmsHouseSign = {
      { "show_text", "ELM'S HOUSE" },
    },
  },
}
