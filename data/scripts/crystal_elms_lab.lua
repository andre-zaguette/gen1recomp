-- Minimal Crystal Elm's Lab flow for the New Bark opening:
-- talk to Elm, unlock the three starter balls, choose one, then continue.
-- This intentionally scopes to the starter handoff path only.

local function concatRows(...)
  local out = {}
  for _, rows in ipairs({ ... }) do
    for _, row in ipairs(rows) do out[#out + 1] = row end
  end
  return out
end

-- ROM: ElmsLabWalkUpToElmScript, the full first-conversation text this
-- project's earlier pass skipped past. `yesorno`/.MustSayYes is a forced
-- loop -- refusing just re-shows the same prompt, there is no way out but
-- yes -- so `ask` (which shows its own multi-page text, then pops the
-- yes/no choice once the last page has typed out) loops right back to
-- itself on a "no". Ends by setting EVENT_FOLLOWED_OAK_INTO_LAB, the same
-- flag ElmsLabMoveElmCallback's stand-in (this file's onEnter, below) reads
-- to know whether Elm is still supposed to be waiting at the PC.
local function elmIntroRows()
  return {
    { "label", "elm_ask_loop" },
    { "ask",
      "ELM: {PLAYER}!\nThere you are!\fI needed to ask\nyou a favor.\fI'm conducting new\nPOKéMON research\fright now. I was\nwondering if you\fcould help me with\nit, {PLAYER}.\fYou see…\fI'm writing a\npaper that I want\fto present at a\nconference.\fBut there are some\nthings I don't\fquite understand\nyet.\fSo!\fI'd like you to\nraise a POKéMON\fthat I recently\ncaught." },
    { "jump_if_true", "elm_gets_email" },
    { "show_text", "But… Please, I\nneed your help!" },
    { "jump", "elm_ask_loop" },

    { "label", "elm_gets_email" },
    { "show_text", "Thanks, {PLAYER}!\fYou're a great\nhelp!" },
    { "show_text",
      "When I announce my\nfindings, I'm sure\fwe'll delve a bit\ndeeper into the\fmany mysteries of\nPOKéMON.\fYou can count on\nit!" },
    { "show_text", "Oh, hey! I got an\ne-mail!\f………\nHm… Uh-huh…\fOkay…" },
    { "show_text",
      "Hey, listen.\fI have an acquain-\ntance called MR.\vPOKéMON.\fHe keeps finding\nweird things and\fraving about his\ndiscoveries.\fAnyway, I just got\nan e-mail from him\fsaying that this\ntime it's real.\fIt is intriguing,\nbut we're busy\fwith our POKéMON\nresearch…\fWait!\fI know!\f{PLAYER}, can you\ngo in our place?" },
    { "show_text",
      "I want you to\nraise one of the\fPOKéMON contained\nin these BALLS.\fYou'll be that\nPOKéMON's first\vpartner, {PLAYER}!\fGo on. Pick one!" },
    { "set_flag", "EVENT_FOLLOWED_OAK_INTO_LAB" },
  }
end

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
    -- The auto-trigger below (onEnter) handles the very first meeting on
    -- its own -- this is the fallback for a save that reaches Elm by
    -- talking to him directly instead (e.g. the queued script hasn't run
    -- yet), plus the ordinary repeat/after-starter branches.
    TEXT_ELMSLAB_ELM = concatRows(
      {
        { "face_player" },
        { "check_flag", "EVENT_GOT_A_POKEMON_FROM_ELM" },
        { "jump_if_true", "after_starter" },
        { "check_flag", "EVENT_FOLLOWED_OAK_INTO_LAB" },
        { "jump_if_true", "repeat_intro" },
      },
      elmIntroRows(),
      {
        { "jump", "end" },

        { "label", "repeat_intro" },
        { "show_text",
          "Go ahead. Choose\none of the POKéMON\nin the POKé BALLS." },
        { "jump", "end" },

        { "label", "after_starter" },
        { "show_text",
          "How is your POKéMON?\fIf it is hurt, you\nshould heal it with\nthe machine." },
      }
    ),

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

    -- ROM: ElmsLabHealingMachine / ElmsLabHealingMachine_HealParty
    -- (maps/ElmsLab.asm). The real script also fades to black, plays
    -- MUSIC_HEAL and runs HealMachineAnim before fading back in -- none of
    -- that exists for Crystal yet (no Crystal heal jingle has been
    -- extracted), so this keeps the yes/no gate and the actual heal, just
    -- without the animation/music beat.
    ElmsLabHealingMachine = {
      { "check_flag", "EVENT_GOT_A_POKEMON_FROM_ELM" },
      { "jump_if_false", "not_yet" },
      { "ask", "Would you like to\nheal your POKéMON?" },
      { "jump_if_false", "end" },
      { "heal_party" },
      { "show_text", "Your POKéMON are\nfully healed!" },
      { "jump", "end" },

      { "label", "not_yet" },
      { "show_text", "I wonder what this\ndoes?" },
    },

    -- ROM: ElmsLabBookshelf -> jumpstd DifficultBookshelfScript, shared by
    -- all 8 bookshelf tiles (both rows) -- the ROM shows the same generic
    -- line for every one of them, not per-shelf flavor text.
    ElmsLabBookshelf = {
      { "show_text", "It's full of\ndifficult books." },
    },

    ElmsLabTravelTip1 = {
      { "show_text",
        "{PLAYER} opened a\nbook.\fTravel Tip 1:\fPress START to\nopen the MENU." },
    },
    ElmsLabTravelTip2 = {
      { "show_text",
        "{PLAYER} opened a\nbook.\fTravel Tip 2:\fRecord your trip\nwith SAVE!" },
    },
    ElmsLabTravelTip3 = {
      { "show_text",
        "{PLAYER} opened a\nbook.\fTravel Tip 3:\fOpen your PACK and\npress SELECT to\vmove items." },
    },
    ElmsLabTravelTip4 = {
      { "show_text",
        "{PLAYER} opened a\nbook.\fTravel Tip 4:\fCheck your POKéMON\nmoves. Press the\fA Button to switch\nmoves." },
    },

    ElmsLabTrashcan = {
      { "show_text", "The wrapper from\nthe snack PROF.ELM\vate is in there…" },
    },

    -- ROM: ElmsLabWindow. `checkflag ENGINE_FLYPOINT_VIOLET iftrue .Normal`
    -- -- always false this early (Violet City/flying is Milestone 3+, no
    -- ENGINE_FLYPOINT_VIOLET setter exists yet) -- then
    -- `checkevent EVENT_ELM_CALLED_ABOUT_STOLEN_POKEMON iftrue .BreakIn`
    -- else `.Normal`. That event is now reachable (data/scripts/
    -- crystal_mr_pokemons_house.lua's errand-completion script sets it),
    -- so both branches are wired; ENGINE_FLYPOINT_VIOLET's check is ported
    -- too even though its "always show Normal once you can fly to Violet"
    -- short-circuit can't fire yet, for the same reason
    -- EVENT_GAVE_MYSTERY_EGG_TO_ELM's branch is ported in Mr. Pokémon's
    -- House despite being currently dead.
    ElmsLabWindow = {
      { "check_flag", "ENGINE_FLYPOINT_VIOLET" },
      { "jump_if_true", "normal" },
      { "check_flag", "EVENT_ELM_CALLED_ABOUT_STOLEN_POKEMON" },
      { "jump_if_true", "break_in" },

      { "label", "normal" },
      { "show_text", "The window's open.\fA pleasant breeze\nis blowing in." },
      { "jump", "end" },

      { "label", "break_in" },
      { "show_text", "He broke in\nthrough here!" },
    },

    ElmsLabPC = {
      { "show_text", "OBSERVATIONS ON\nPOKéMON EVOLUTION\f…It says on the\nscreen…" },
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

  -- ROM: ElmsLabMoveElmCallback (a MAPCALLBACK_OBJECTS, reapplied on every
  -- load) moves ELMSLAB_ELM from his object_event default (5,2) to (3,4,
  -- right by the PC) for as long as the scene is still SCENE_ELMSLAB_MEET_ELM
  -- -- i.e. before the player has been through the "will you raise one of
  -- these POKéMON" conversation once. This engine's objects have no scene
  -- state or per-map callback, so the same "before the first real talk"
  -- condition is approximated with the flag TEXT_ELMSLAB_ELM itself sets at
  -- the end of that conversation (EVENT_FOLLOWED_OAK_INTO_LAB), and the
  -- reposition is done directly on the pooled NPC instance rather than
  -- object.x/y (that field is read once at NPC construction, which already
  -- happened by the time onEnter runs -- see OverworldController.lua's
  -- setMap/enter ordering).
  --
  onEnter = function(game, ow)
    if game.save.flags and game.save.flags.EVENT_FOLLOWED_OAK_INTO_LAB then
      return
    end
    local elm = ow:npcByIndex(1) -- ELMSLAB_ELM
    if elm then
      elm.cellX, elm.cellY = 3, 4
      elm.px, elm.py = 3 * 16, 4 * 16
    end
  end,

  -- ROM also runs ElmsLabMeetElmScene (`sdefer ElmsLabWalkUpToElmScript`)
  -- automatically on entry while the scene is still SCENE_ELMSLAB_MEET_ELM,
  -- which opens with `applymovement PLAYER, ElmsLab_WalkUpToElmMovement` --
  -- the game auto-walks the player right next to Elm before the intro
  -- starts, rather than firing the instant the room loads. That walk
  -- animation itself isn't ported (purely cosmetic), but the "next to him"
  -- timing matters, so this triggers on proximity instead of on entry: any
  -- of the four cells touching (3,4), where onEnter above keeps him
  -- parked, counts as walked up to him.
  onStep = function(game, ow, x, y)
    if game.save.flags and game.save.flags.EVENT_FOLLOWED_OAK_INTO_LAB then
      return
    end
    if math.abs(x - 3) + math.abs(y - 4) ~= 1 then return end
    ow:queueScript(elmIntroRows())
    return true
  end,
}
