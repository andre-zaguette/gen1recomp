-- Route 30, the path from Cherrygrove City north to Mr. Pokémon's House
-- (pret/pokecrystal maps/Route30.asm). Registering this map is what
-- closes the reachability gap the final Milestone 1 review flagged: it's
-- the only ROM map connecting Cherrygrove's own `connection north` to
-- Mr. Pokémon's House's incoming warp (`warp_event 17, 5,
-- MR_POKEMONS_HOUSE, 1`), so until now Task 6's whole errand chain
-- (Mystery Egg, rival hide, officer reveal, PokéDex) had no real map a
-- player could walk through to reach it.
--
-- Ported: the real-content objects (Route30YoungsterScript,
-- Route30CooltrainerFScript, the Antidote item ball) and all 5
-- def_bg_events (4 real signs + the hidden-item bg_event below).
--
-- Not ported (all stay hidden in the manifest -- see
-- tools/make_rom_manifest_crystal.py's ROUTE_30 entry for the full
-- reasoning behind each):
--   * ROUTE30_YOUNGSTER2/3, ROUTE30_BUG_CATCHER (TrainerYoungsterJoey,
--     TrainerYoungsterMikey, TrainerBugCatcherDon) -- real
--     OBJECTTYPE_TRAINER NPCs. This project has no OBJECTTYPE_TRAINER
--     sight-triggered auto-battle wiring in
--     src/world/OverworldController.lua (grepped: zero hits;
--     Commands.start_battle(ctx, "trainer", ...) exists but nothing
--     drives it from a trainer object's sight detection) and no Gen2
--     trainer-party data extracted at all (RomExtractorGen2.lua has no
--     trainer/party table). Building that wiring is its own future task,
--     not part of closing this reachability gap.
--   * ROUTE30_YOUNGSTER1 (YoungsterJoey_ImportantBattleScript) and its
--     two SPRITE_MONSTER companions, ROUTE30_MONSTER1/2 -- a purely
--     scripted, non-interactive "watch Joey and Mikey's Rattata fight"
--     cutscene (applymovement + playsound only, no startbattle), gated on
--     EVENT_ROUTE_30_BATTLE, which only ElmsLab.asm's (unbuilt)
--     errand-completion scene ever sets. Same unbuilt scene-state gap as
--     CHERRYGROVECITY_RIVAL (crystal_cherrygrove_city.lua) -- no
--     coord_event/scene-state mechanism exists here at all.
--   * ROUTE30_FRUIT_TREE1/2 (Route30FruitTree1/2) -- no shake-a-tree
--     mechanic exists in this project, matching the precedent
--     crystal_route29.lua's ROUTE29_FRUIT_TREE already set for the exact
--     same gap (rather than inventing new fruit-tree behavior here).
--
-- Also out of scope for this task: ROUTE_30_BERRY_HOUSE, the destination
-- of Route30's OTHER warp (`warp_event 7, 39, ROUTE_30_BERRY_HOUSE, 1`).
-- It's a genuinely tiny, self-contained side room (1 NPC giving a single
-- Berry, 2 bg_events both pointing at the same generic
-- MagazineBookshelfScript, 2 warps both landing back on Route 30's own
-- warp #1) with no bearing on the Mr. Pokémon's House reachability gap
-- this task exists to close -- registering it is a real, separable
-- follow-up task, not folded in here. Leaving it unregistered is safe,
-- not a latent crash: RomExtractorGen2.lua's extractMap() skips (not
-- asserts on) a warp_event whose destination map isn't registered, so
-- Route30's own warp cell at (7,39) simply won't produce a warp entry at
-- all -- stepping onto it is a silent no-op, the same behavior this
-- project already relied on for every other not-yet-registered
-- destination (e.g. Route 29's own ROUTE_46 connection before this
-- session).

return {
  talk = {
    -- ROM: Route30YoungsterScript. checkevent
    -- EVENT_GAVE_MYSTERY_EGG_TO_ELM is never set anywhere in this project
    -- (the mystery-egg-to-Elm handoff hasn't been built -- same gap Task
    -- 5 confirmed for Route 29's own catch tutorial), so only the
    -- "directions to Mr. Pokémon's house" branch is currently reachable;
    -- both branches ported anyway, matching the
    -- ROUTE29_COOLTRAINER_M1/CHERRYGROVECITY_TEACHER precedent of porting
    -- dead branches too.
    TEXT_ROUTE30_YOUNGSTER = {
      { "face_player" },
      { "check_flag", "EVENT_GAVE_MYSTERY_EGG_TO_ELM" },
      { "jump_if_true", "egg_delivered" },
      { "show_text", "MR.POKéMON's\nhouse? It's a bit\vfarther ahead." },
      { "jump", "end" },

      { "label", "egg_delivered" },
      { "show_text", "Everyone's having\nfun battling!\vYou should too!" },
    },

    -- ROM: Route30CooltrainerFScript (`jumptextfaceplayer`).
    TEXT_ROUTE30_COOLTRAINER_F = {
      { "face_player" },
      { "show_text",
        "I'm not a trainer.\fBut if you look\none in the eyes,\vprepare to battle." },
    },

    -- ROM: Route30Antidote (`itemball ANTIDOTE`). Trailing flag
    -- EVENT_ROUTE_30_ANTIDOTE is not in InitializeEventsScript's
    -- force-set list, so it starts clear -- visible -- same
    -- give_item/set_flag/hide_object shape as Route 29's Potion ball.
    TEXT_ROUTE30_ANTIDOTE = {
      { "check_flag", "EVENT_ROUTE_30_ANTIDOTE" },
      { "jump_if_true", "end" },
      { "give_item", "ANTIDOTE", 1 },
      { "set_flag", "EVENT_ROUTE_30_ANTIDOTE" },
      { "hide_object", "ROUTE_30", "ROUTE30_POKE_BALL" },
    },

    Route30Sign = {
      { "show_text", "ROUTE 30\fVIOLET CITY -\nCHERRYGROVE CITY" },
    },
    MrPokemonsHouseDirectionsSign = {
      { "show_text", "MR.POKéMON'S HOUSE\nSTRAIGHT AHEAD!" },
    },
    MrPokemonsHouseSign = {
      { "show_text", "MR.POKéMON'S HOUSE" },
    },
    Route30TrainerTips = {
      { "show_text",
        "TRAINER TIPS\fNo stealing other\npeople's POKéMON!\fPOKé BALLS are to\nbe thrown only at\vwild POKéMON!" },
    },

    -- ROM: Route30HiddenPotion (`hiddenitem POTION,
    -- EVENT_ROUTE_30_HIDDEN_POTION`) -- a BGEVENT_ITEM bg_event, not a
    -- BGEVENT_READ sign (see tools/make_rom_manifest_crystal.py's
    -- ROUTE_30 sign-list comment). Its trailing flag is not in
    -- InitializeEventsScript's force-set list either, so it starts clear
    -- -- pickable -- same give_item/set_flag shape as the Antidote ball
    -- above, minus hide_object: there's no sprite here to hide (it's a
    -- plain ground tile, same as every other bg_event on this map), so
    -- the check_flag guard alone is what stops it from giving the Potion
    -- twice.
    Route30HiddenPotion = {
      { "check_flag", "EVENT_ROUTE_30_HIDDEN_POTION" },
      { "jump_if_true", "end" },
      { "give_item", "POTION", 1 },
      { "set_flag", "EVENT_ROUTE_30_HIDDEN_POTION" },
    },
  },
}
