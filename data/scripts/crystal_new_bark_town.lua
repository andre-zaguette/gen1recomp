-- New Bark Town's three reachable NPCs (pret/pokecrystal maps/NewBarkTown.asm:
-- NewBarkTownTeacherScript, NewBarkTownFisherScript, NewBarkTownRivalScript).
--
-- NEWBARKTOWN_RIVAL is visible from the very start of the game (his flag,
-- EVENT_RIVAL_NEW_BARK_TOWN, is clear on a fresh save -- unlike
-- ELMSLAB_OFFICER's, it is not in InitializeEventsScript's force-set list),
-- caught spying by the lab before the player has even met Elm. ROM: he only
-- disappears from here once MrPokemonsHouse.asm's errand-return script sets
-- that flag, right before the player crosses paths with him elsewhere on
-- the way back. That errand now exists (data/scripts/crystal_mr_pokemons_
-- house.lua's TEXT_MRPOKEMONSHOUSE_GENTLEMAN, its completion tail) and is
-- what actually makes him vanish, via a cross-map
-- hide_object("NEW_BARK_TOWN", "NEWBARKTOWN_RIVAL") call from that script
-- (Commands.lua's toggleObject persists to save.objectToggles regardless
-- of which map is currently loaded, and OverworldController.lua:85 reads
-- it back when NEW_BARK_TOWN's NPC list is built) -- nothing needs wiring
-- here in his own file for that half of the behavior.

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
    -- flag gets set at Mr. Pokémon's house right after, not here). This
    -- talk script itself is unchanged by that -- he stays interactable
    -- exactly like this on every visit until the errand-completion script
    -- hides him for good; retreating him a permanent tile every talk would
    -- walk him off his post a little further each time, so that cosmetic
    -- shove/retreat still isn't ported.
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

  -- Not a ROM behavior: vanilla Crystal never stops the player from
  -- leaving New Bark Town without a starter (checked -- no coord_event or
  -- EVENT_GOT_A_POKEMON_FROM_ELM check exists anywhere near the Route
  -- 27/29 boundary in maps/NewBarkTown.asm or maps/Route29.asm). This
  -- project adds one anyway, at the west edge into Route 29 (the story
  -- path with wild encounters -- Route 27 stays open), the same shape
  -- Gen1's own data/scripts/oaks_lab.lua onStep guard already uses for the
  -- equivalent "don't wander off with an empty party" beat there: watch
  -- the boundary coordinate and push back one step before the connection
  -- crossing would actually fire, rather than reacting after the fact.
  onStep = function(game, ow, x, y)
    if game.save.flags and game.save.flags.EVENT_GOT_A_POKEMON_FROM_ELM then
      return
    end
    if x > 0 then return end
    ow.runner:run({
      { "show_text",
        "You shouldn't wan-\nder around without\va POKéMON!\fGo see PROF.ELM at\nhis lab!" },
      { "move_player", "right", 1 },
    }, {})
    return true
  end,
}
