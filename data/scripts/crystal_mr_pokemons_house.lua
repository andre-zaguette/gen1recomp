-- Mr. Pokémon's House (pret/pokecrystal maps/MrPokemonsHouse.asm) -- the
-- payoff for the whole New Bark Town opening. In the ROM this is really
-- two chained scripts that auto-run the moment the room loads
-- (`sdefer MrPokemonsHouseMrPokemonEventScript`, itself ending with
-- `sjump MrPokemonsHouse_OakScript`): Mr. Pokémon hands over the MYSTERY
-- EGG, PROF.OAK cameos to give the PokéDex and heal the party, and then
-- the errand-completion tail sets every flag the rest of this milestone's
-- maps are gated on. This project has no auto-run-on-entry/scene-state
-- mechanism (same gap noted in crystal_elms_lab.lua's onEnter/onStep
-- comments), so the whole thing is collapsed into one talk-to-Mr.-Pokémon
-- script instead, gated on EVENT_ELM_CALLED_ABOUT_STOLEN_POKEMON (the very
-- last flag the real chain sets) so it only plays once.
--
-- Not ported: the cosmetic `turnobject`/`applymovement` beats between the
-- two halves (Mr. Pokémon and Oak facing each other, Oak walking over,
-- Oak walking back out and `disappear`ing through the door) -- purely
-- blocking/facing animation with no gameplay effect, same "skip the
-- pure-movement beats" precedent as elsewhere in this session. Also not
-- ported: `MrPokemonsHouse_MrPokemonScript`'s RED_SCALE/EXP_SHARE trade
-- branch (`checkitem RED_SCALE` / `.RedScale`) -- RED_SCALE is a Lake of
-- Rage fishing reward (way past this milestone, no fishing/Lake of Rage
-- content exists yet) and EXP_SHARE isn't in this project's item data
-- either, so that whole sub-flow is unreachable this early regardless of
-- how it's wired; left out rather than faked.
--
-- The theft phone call itself (`specialphonecall SPECIALCALL_ROBBED` ->
-- engine/phone/scripts/elm.asm's ElmPhoneCallerScript -> `.disaster` ->
-- `setevent EVENT_ELM_CALLED_ABOUT_STOLEN_POKEMON`) is a real Pokégear
-- call that arrives some time after this scene in vanilla Crystal, not
-- immediately -- this project has no Pokégear/phone system at all yet
-- (Milestone 4), so per the task brief this sets that flag directly here
-- instead of modeling the call.

return {
  talk = {
    -- ROM: MrPokemonsHouse_MrPokemonScript is actually the REPEAT-visit
    -- script (the very first visit is scene-triggered, not talk-triggered)
    -- -- but per this project's collapse-into-one-talk approach, the first
    -- talk plays the whole errand instead, and only later talks fall
    -- through to the real repeat-visit lines.
    TEXT_MRPOKEMONSHOUSE_GENTLEMAN = {
      { "face_player" },
      { "check_flag", "EVENT_ELM_CALLED_ABOUT_STOLEN_POKEMON" },
      { "jump_if_true", "repeat_visit" },

      -- MrPokemonsHouseMrPokemonEventScript: the MYSTERY EGG handoff.
      { "show_text", "Hello, hello! You\nmust be {PLAYER}.\fPROF.ELM said that\nyou would visit." },
      { "move_player", "right", 1 },
      { "move_player", "up", 1 },
      { "show_text", "This is what I\nwant PROF.ELM to\nexamine." },
      { "play_sound", "Get_Key_Item" },
      { "show_text", "{PLAYER} received\nMYSTERY EGG." },
      { "give_item", "MYSTERY_EGG", 1, false },
      { "set_flag", "EVENT_GOT_MYSTERY_EGG_FROM_MR_POKEMON" },
      { "show_text",
        "I know a couple\nwho run a POKéMON\vDAY-CARE service.\fThey gave me that\nEGG.\fI was intrigued,\nso I sent mail to\vPROF.ELM.\fFor POKéMON evolu-\ntion, PROF.ELM is\vthe authority." },
      { "show_text", "Even PROF.OAK here\nrecognizes that." },
      { "show_text",
        "If my assumption\nis correct, PROF.\vELM will know it." },

      -- MrPokemonsHouse_OakScript: PROF.OAK's cameo -- PokéDex, healing,
      -- then the errand-completion tail.
      { "show_text",
        "OAK: Aha! So\nyou're {PLAYER}!\fI'm OAK! A POKéMON\nresearcher.\fI was just visit-\ning my old friend\vMR.POKéMON.\fI heard you were\nrunning an errand\ffor PROF.ELM, so I\nwaited here.\fOh! What's this?\nA rare POKéMON!\fLet's see…\fHm, I see!\fI understand why\nPROF.ELM gave you\fa POKéMON for this\nerrand.\fTo researchers\nlike PROF.ELM and\fI, POKéMON are our\nfriends.\fHe saw that you\nwould treat your\fPOKéMON with love\nand care.\f…Ah!\fYou seem to be\ndependable.\fHow would you like\nto help me out?\fSee? This is the\nlatest version of\vPOKéDEX.\fIt automatically\nrecords data on\fPOKéMON you've\nseen or caught.\fIt's a hi-tech\nencyclopedia!" },
      { "play_sound", "Get_Item1" },
      { "show_text", "{PLAYER} received\nPOKéDEX!" },
      { "set_flag", "ENGINE_POKEDEX" },
      { "show_text",
        "Go meet many kinds\nof POKéMON and\fcomplete that\nPOKéDEX!\fBut I've stayed\ntoo long.\fI have to get to\nGOLDENROD for my\vusual radio show.\f{PLAYER}, I'm\ncounting on you!" },
      { "hide_object", "MR_POKEMONS_HOUSE", "MRPOKEMONSHOUSE_OAK" },
      { "show_text", "You are returning\nto PROF.ELM?\fHere. Your POKéMON\nshould have some\vrest." },
      { "heal_party" },
      { "show_text", "I'm depending on\nyou!" },

      -- Errand-completion flags: MrPokemonsHouse_OakScript's tail.
      { "set_flag", "EVENT_RIVAL_NEW_BARK_TOWN" },
      { "hide_object", "NEW_BARK_TOWN", "NEWBARKTOWN_RIVAL" },
      { "set_flag", "EVENT_PLAYERS_HOUSE_1F_NEIGHBOR" },
      { "clear_flag", "EVENT_PLAYERS_NEIGHBORS_HOUSE_NEIGHBOR" },
      { "clear_flag", "EVENT_COP_IN_ELMS_LAB" },
      { "show_object", "ELMS_LAB", "ELMSLAB_OFFICER" },
      { "set_flag", "EVENT_ELM_CALLED_ABOUT_STOLEN_POKEMON" },

      -- Which starter the rival stole: of the two Poké Balls the player
      -- didn't take, this flags the one that's now empty (the ROM's own
      -- three-way branch, keyed on the same EVENT_GOT_*_FROM_ELM flags
      -- crystal_elms_lab.lua's starterBall already sets when the player
      -- picks). Set for narrative-state parity with the ROM; this
      -- project's ELMS_LAB poke balls aren't wired to react to it (no
      -- "ball's pokémon is now missing" visual exists there), out of scope
      -- for this task.
      { "check_flag", "EVENT_GOT_TOTODILE_FROM_ELM" },
      { "jump_if_true", "rival_took_chikorita" },
      { "check_flag", "EVENT_GOT_CHIKORITA_FROM_ELM" },
      { "jump_if_true", "rival_took_cyndaquil" },
      { "set_flag", "EVENT_TOTODILE_POKEBALL_IN_ELMS_LAB" },
      { "jump", "end" },

      { "label", "rival_took_chikorita" },
      { "set_flag", "EVENT_CHIKORITA_POKEBALL_IN_ELMS_LAB" },
      { "jump", "end" },

      { "label", "rival_took_cyndaquil" },
      { "set_flag", "EVENT_CYNDAQUIL_POKEBALL_IN_ELMS_LAB" },
      { "jump", "end" },

      -- ROM: MrPokemonsHouse_MrPokemonScript, the real repeat-visit
      -- script. `checkitem RED_SCALE` branch not ported (see file header).
      -- Both remaining branches ARE ported even though
      -- EVENT_GAVE_MYSTERY_EGG_TO_ELM (handing the egg to Elm) is a later
      -- milestone's content and can never be true yet -- same "port both
      -- even though one is currently dead" precedent as
      -- crystal_cherrygrove_city.lua's CHERRYGROVECITY_TEACHER/_YOUNGSTER.
      { "label", "repeat_visit" },
      { "check_flag", "EVENT_GAVE_MYSTERY_EGG_TO_ELM" },
      { "jump_if_true", "always_new_discoveries" },
      { "show_text", "I'm depending on\nyou!" },
      { "jump", "end" },

      { "label", "always_new_discoveries" },
      { "show_text", "Life is delight-\nful! Always, new\vdiscoveries to be\nmade!" },
    },

    -- ROM: OAK's object here (`ObjectEvent`, home/map.asm) has no custom
    -- script of its own -- talking to him falls through to the engine's
    -- generic placeholder, `_ObjectEventText` (data/text/common_3.asm):
    -- literally "Object event". Ported verbatim rather than inventing
    -- dialogue Oak never has in the ROM; he disappears for good once the
    -- Gentleman's errand-completion script above runs.
    TEXT_MRPOKEMONSHOUSE_OAK = {
      { "face_player" },
      { "show_text", "Object event" },
    },

    MrPokemonsHouse_ForeignMagazines = {
      { "show_text", "It's packed with\nforeign magazines.\fCan't even read\ntheir titles…" },
    },
    MrPokemonsHouse_BrokenComputer = {
      { "show_text", "It's a big com-\nputer. Hmm. It's\vbroken." },
    },
    MrPokemonsHouse_StrangeCoins = {
      { "show_text",
        "A whole pile of\nstrange coins!\fMaybe they're from\nanother country…" },
    },
  },
}
