-- Cherrygrove City, Route 29's west neighbor and the first full town on
-- the story path (pret/pokecrystal maps/CherrygroveCity.asm).
--
-- Ported: both generic-flavor signs, the two mart/pokecenter std_text.asm
-- signs, and the three NPCs whose dialogue doesn't depend on content this
-- project hasn't built (Teacher, Youngster, the Mystic Water fisher).
--
-- Not ported (both stay hidden in the manifest -- see
-- tools/make_rom_manifest_crystal.py's CHERRYGROVE_CITY entry for the full
-- reasoning behind each):
--   * CHERRYGROVECITY_GRAMPS (the Guide Gent) -- his `yesorno`-gated
--     walking tour depends on a PokéGear/Town Map item system that does
--     not exist in this project at all, and on a "player follows a
--     leading NPC through several scripted stops" primitive this engine's
--     script commands have no equivalent of.
--   * CHERRYGROVECITY_RIVAL -- the rival encounter here needs scene
--     state this engine doesn't model (SCENE_CHERRYGROVECITY_MEET_RIVAL,
--     set by the not-yet-built Mr. Pokémon errand's return trip) and real
--     Crystal RIVAL1 trainer-party data keyed to the player/rival starter
--     matchup, neither of which exists -- src/script/Commands.lua's
--     rival_battle is Gen1/Yellow-shaped only.

return {
  talk = {
    -- ROM: CherrygroveTeacherScript. checkflag ENGINE_MAP_CARD is only
    -- ever set true by the Guide Gent (deferred above), so only the
    -- "no map card" branch is reachable right now -- both ported anyway,
    -- matching this session's ROUTE29_COOLTRAINER_M1 precedent.
    TEXT_CHERRYGROVECITY_TEACHER = {
      { "face_player" },
      { "check_flag", "ENGINE_MAP_CARD" },
      { "jump_if_true", "have_map_card" },
      { "show_text",
        "Did you talk to\nthe old man by the\vPOKéMON CENTER?\fHe'll put a MAP of\nJOHTO on your\vPOKéGEAR." },
      { "jump", "end" },

      { "label", "have_map_card" },
      { "show_text", "When you're with\nPOKéMON, going\vanywhere is fun." },
    },

    -- ROM: CherrygroveYoungsterScript. checkflag ENGINE_POKEDEX -- this
    -- project only tracks Gen1's EVENT_GOT_POKEDEX so far, not Crystal's
    -- own ENGINE_POKEDEX, so only the "no pokedex" branch is currently
    -- reachable; both ported.
    TEXT_CHERRYGROVECITY_YOUNGSTER = {
      { "face_player" },
      { "check_flag", "ENGINE_POKEDEX" },
      { "jump_if_true", "have_pokedex" },
      { "show_text", "MR.POKéMON's house\nis still farther\vup ahead." },
      { "jump", "end" },

      { "label", "have_pokedex" },
      { "show_text",
        "I battled the\ntrainers on the\vroad.\fMy POKéMON lost.\nThey're a mess! I\fmust take them to\na POKéMON CENTER." },
    },

    -- ROM: MysticWaterGuy. verbosegiveitem MYSTIC_WATER once, gated on
    -- EVENT_GOT_MYSTIC_WATER_IN_CHERRYGROVE -- same give_item/set_flag
    -- shape as Route 29's Potion ball (crystal_route29.lua's
    -- TEXT_ROUTE29_POTION).
    TEXT_CHERRYGROVECITY_FISHER = {
      { "face_player" },
      { "check_flag", "EVENT_GOT_MYSTIC_WATER_IN_CHERRYGROVE" },
      { "jump_if_true", "after" },
      { "show_text",
        "A POKéMON I caught\nhad an item.\fI think it's\nMYSTIC WATER.\fI don't need it,\nso do you want it?" },
      { "give_item", "MYSTIC_WATER", 1 },
      { "set_flag", "EVENT_GOT_MYSTIC_WATER_IN_CHERRYGROVE" },

      { "label", "after" },
      { "show_text", "Back to fishing\nfor me, then." },
    },

    CherrygroveCitySign = {
      { "show_text", "CHERRYGROVE CITY\fThe City of Cute,\nFragrant Flowers" },
    },
    GuideGentsHouseSign = {
      { "show_text", "GUIDE GENT'S HOUSE" },
    },
    -- ROM: jumpstd MartSignScript / PokecenterSignScript -- the generic
    -- data/text/std_text.asm sign text every town's mart/pokecenter sign
    -- shares, not map-specific flavor text.
    CherrygroveCityMartSign = {
      { "show_text", "For All Your\nPOKéMON Needs\fPOKéMON MART" },
    },
    CherrygroveCityPokecenterSign = {
      { "show_text", "Heal Your POKéMON!\nPOKéMON CENTER" },
    },
  },
}
