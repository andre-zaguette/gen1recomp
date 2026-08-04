-- Pass-through "no starter selection" screen for total conversions that
-- have not extracted a starter-selection/naming intro (Task 10 of
-- docs/superpowers/plans/2026-08-03-gen2-crystal-extraction-skeleton.md:
-- Crystal's skeleton spawns straight into New Bark Town and has no
-- Oak-speech-equivalent content to run in its place yet).
--
-- Matches OakSpeech.new(game, onDone)'s contract: Game:makeTitleState's
-- onNewGame (src/core/Game.lua) already pushes OverworldState before
-- pushing field.boot.screens.newGame on top, so once this screen pops
-- itself and calls onDone(), the player is standing wherever field.boot
-- put them.  No dialogue, no naming, no other side effect.

local NoOpScreen = {}
NoOpScreen.__index = NoOpScreen

function NoOpScreen.new(game, onDone)
  local self = setmetatable({}, NoOpScreen)
  self.game = game
  self.onDone = onDone
  return self
end

-- StateStack:push calls enter() right after inserting this instance, so
-- it is already on top of the stack -- popping here pops itself, the same
-- moment OakSpeech:finish() does after its last step.
function NoOpScreen:enter()
  self.game.stack:pop()
  if self.onDone then self.onDone() end
end

return NoOpScreen
