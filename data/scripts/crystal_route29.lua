-- Route 29, the path from New Bark Town toward Cherrygrove City / Mr.
-- Pokémon's house (pret/pokecrystal maps/Route29.asm).
--
-- Ported: the two route signs, and the NPCs whose dialogue doesn't depend
-- on content this project hasn't built (Youngster, Teacher1, Fisher, both
-- Cooltrainer Ms, the Potion item ball).
--
-- Not ported (all stay hidden in the manifest, see
-- tools/make_rom_manifest_crystal.py's ROUTE_29 entry for why each one
-- specifically): the fruit tree (no shake-a-tree mechanic exists),
-- Tuscany (day-of-week gated), and the catch tutorial coord_events
-- (SCENE_ROUTE29_CATCH_TUTORIAL is only ever set by the mystery-egg
-- chain's ElmAfterTheftScript, which this project hasn't built either --
-- CatchingTutorialDudeScript's own always-false EVENT_GAVE_MYSTERY_EGG_TO_ELM
-- check means only its "box full"-shaped fallback text is reachable, so
-- that's the only branch ported for ROUTE29_COOLTRAINER_M1 below).

return {
  talk = {
    TEXT_ROUTE29_COOLTRAINER_M1 = {
      { "face_player" },
      { "show_text", "POKéMON hide in\nthe grass. Who\fknows when they'll\npop out…" },
    },

    TEXT_ROUTE29_YOUNGSTER = {
      { "face_player" },
      { "show_text",
        "Yo. How are your\nPOKéMON?\fIf they're weak\nand not ready for\fbattle, keep out\nof the grass." },
    },

    TEXT_ROUTE29_TEACHER1 = {
      { "face_player" },
      { "show_text",
        "See those ledges?\nIt's scary to jump\voff them.\fBut you can go to\nNEW BARK without\fwalking through\nthe grass." },
    },

    TEXT_ROUTE29_FISHER = {
      { "face_player" },
      { "show_text",
        "I wanted to take a\nbreak, so I saved\fto record my\nprogress." },
    },

    -- ROM: Route29CooltrainerMScript checktime DAY/NITE, both leading to a
    -- "waiting for POKéMON" line -- no time-of-day command exists yet
    -- (same gap as PLAYERSHOUSE1F_POKEFAN_F), so this always shows the DAY
    -- branch's text (Route29CooltrainerMText_WaitingForNight).
    TEXT_ROUTE29_COOLTRAINER_M2 = {
      { "face_player" },
      { "show_text", "I'm waiting for\nPOKéMON that\fappear only at\nnight." },
    },

    -- ROM: Route29Potion (`itemball POTION`).
    TEXT_ROUTE29_POTION = {
      { "check_flag", "EVENT_ROUTE_29_POTION" },
      { "jump_if_true", "end" },
      { "give_item", "POTION", 1 },
      { "set_flag", "EVENT_ROUTE_29_POTION" },
      { "hide_object", "ROUTE_29", "ROUTE29_POKE_BALL" },
    },

    Route29Sign1 = {
      { "show_text", "ROUTE 29\fCHERRYGROVE CITY -\nNEW BARK TOWN" },
    },
    Route29Sign2 = {
      { "show_text", "ROUTE 29\fCHERRYGROVE CITY -\nNEW BARK TOWN" },
    },
  },
}
