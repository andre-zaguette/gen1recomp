-- The player's house, 1F (pret/pokecrystal maps/PlayersHouse1F.asm:
-- MeetMomScript, MomScript, NeighborScript).
--
-- ROM: the very first time you reach Mom, a coord_event at the stairs
-- (MeetMomLeftScript/MeetMomRightScript, x=8/9 y=4) fires automatically as
-- you walk onto it -- talking to her directly instead lands in the same
-- place (MomScript's `checkscene / iffalse MeetMomTalkedScript`). Either
-- way she relays that PROF.ELM is looking for you and hands over the
-- POKéGEAR, before any of the regular branches below ever run. onStep below
-- covers the walk-in trigger; the talk entry covers talking to her
-- directly, both gated on ENGINE_POKEGEAR (the real flag MeetMomScript
-- itself sets, so nothing new is invented here) rather than a scene id,
-- since this engine's objects don't carry per-map scene state. The
-- day-of-week/DST setup wizard that follows in the ROM (special
-- SetDayOfWeek et al.) has no clock system here to configure, so it's
-- dropped along with the last paragraph of MomGivesPokegearText that leads
-- into it.
--
-- Mom's ROM script also branches into `special BankOfMom` once the
-- mystery-egg errand is done -- not built in this project, so only the two
-- reachable early branches are ported (before/after getting the starter,
-- same EVENT_GOT_A_POKEMON_FROM_ELM check as the New Bark Town teacher).
-- The visiting neighbor's time-of-day greeting (checktime) collapses to her
-- DAY line -- there is no script command for time-of-day text yet, and the
-- substance of what she says doesn't change with it.

return {
  onStep = function(game, ow, x, y)
    if game.save.flags and game.save.flags.ENGINE_POKEGEAR then return end
    if not ((x == 8 and y == 4) or (x == 9 and y == 4)) then return end
    ow:queueScript({
      { "show_text",
        "Oh, {PLAYER}…! Our\nneighbor, PROF.\fELM, was looking\nfor you.\fHe said he wanted\nyou to do some-\vthing for him.\fOh! I almost for-\ngot! Your POKéMON\fGEAR is back from\nthe repair shop.\fHere you go!" },
      { "show_text",
        "POKéMON GEAR, or\njust POKéGEAR.\fIt's essential if\nyou want to be a\vgood trainer." },
      { "set_flag", "ENGINE_POKEGEAR" },
    })
  end,

  talk = {
    TEXT_PLAYERSHOUSE1F_MOM1 = {
      { "face_player" },
      { "check_flag", "ENGINE_POKEGEAR" },
      { "jump_if_true", "regular" },
      { "show_text",
        "Oh, {PLAYER}…! Our\nneighbor, PROF.\fELM, was looking\nfor you.\fHe said he wanted\nyou to do some-\vthing for him.\fOh! I almost for-\ngot! Your POKéMON\fGEAR is back from\nthe repair shop.\fHere you go!" },
      { "show_text",
        "POKéMON GEAR, or\njust POKéGEAR.\fIt's essential if\nyou want to be a\vgood trainer." },
      { "set_flag", "ENGINE_POKEGEAR" },
      { "jump", "end" },

      { "label", "regular" },
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

    PlayersHouse1FStoveScript = {
      { "show_text", "Mom's specialty!\fCINNABAR VOLCANO\nBURGER!" },
    },
    PlayersHouse1FSinkScript = {
      { "show_text", "The sink is spot-\nless. Mom likes it\vclean." },
    },
    PlayersHouse1FFridgeScript = {
      { "show_text", "Let's see what's\nin the fridge…\fFRESH WATER and\ntasty LEMONADE!" },
    },
    PlayersHouse1FTVScript = {
      { "show_text",
        "There's a movie on\nTV: Stars dot the\fsky as two boys\nride on a train…\fI'd better get\nrolling too!" },
    },
  },
}
