-- Regression guard for the "naming screen letter grid is missing the row
-- containing R" playtest report (Task 3,
-- docs/superpowers/plans/2026-08-06-gen2-crystal-roadmap.md).
--
-- Root cause, verified directly against roms/pokecrystal (gitignored, not
-- committed -- see the report for the full derivation): the charmap is
-- fine ("R" -> code $91, contiguous with A-Z at $80-$99, constants/
-- charmap.asm) and RomExtractorGen2:extractFont's tile-sheet decode is
-- fine. The bug was purely a NamingScreen.lua drawing-position bug in its
-- "crystal" layout branch: every grid cell drew at
-- `16 + c * 16, 48 + r * 16` (c, r 1-indexed column/row). Crystal's real
-- naming screen (engine/menus/naming_screen.asm's .row/.col copy loop,
-- placing data/text/name_input_chars.asm's NameInputUpper starting at
-- hlcoord 2,8 with one blank BG tile between letters) puts letter c at BG
-- tile column 2c, i.e. pixel 16c -- no extra +16. That extra offset
-- pushed the 9th (last) column of every row 16px past the 160px-wide
-- canvas: "I" (row 1), "R" (row 2 -- the reported bug), the row-3 blank,
-- "<MN>" (row 4) and, worse, "ED" itself (row 5, the confirm cell) all
-- drew completely off-screen.
--
-- ROM-free by construction: stubs Font.draw to record where
-- NamingScreen:draw() actually places each grid cell (the same technique
-- tests/engine/menu_row_offset_bug564.lua uses for boxed-menu rows), then
-- checks by LABEL (not by assumed position) that every row 1-5 cell's real
-- draw call lands fully inside the 160x144 canvas -- so this fails the same
-- way against the pre-fix formula whether or not the fix's own math is
-- reused to compute the expectation.
--   luajit tests/engine/gen2_naming_screen_layout.lua

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
love = love or require("tests.love_stub")

local Font = require("src.render.Font")
local NamingScreen = require("src.ui.NamingScreen")

local CANVAS_W, CANVAS_H, GLYPH = 160, 144, 8

local fakeGame = { data = {}, save = { player = {} } }

-- Draw the naming screen with Font.draw stubbed out and report, in pixels,
-- the LAST position each distinct label actually drew at (PlaceString-style
-- screens never repeat a grid label within rows 1-5, so "last" == "only").
local function drawnPositions(screen)
  local realDraw = Font.draw
  local at = {}
  Font.draw = function(text, x, y)
    at[text] = { x = x, y = y }
    return GLYPH
  end
  local ok, err = pcall(screen.draw, screen)
  Font.draw = realDraw
  if not ok then error(err, 0) end
  return at
end

local function onCanvas(x, y)
  return x >= 0 and y >= 0 and x + GLYPH <= CANVAS_W and y + GLYPH <= CANVAS_H
end

-- --------------------------------------------------------- player naming
-- The exact CrystalIntro.lua call shape (layout="crystal", a maxLen and a
-- title, no presets so :enter() does not push a name-picker menu first).
local screen = NamingScreen.new(fakeGame, {
  layout = "crystal", title = "YOUR NAME?", maxLen = 7,
})

local at = drawnPositions(screen)

-- Rows 1-5 (letters and symbols, including the ED confirm cell). Row 6
-- (the case-switch cell) is a separate, still-open layout gap -- see the
-- report's follow-ups -- and is deliberately not asserted here.
local grid = screen:grid()
local checked = 0
for r = 1, 5 do
  local row = grid[r]
  for c, cell in ipairs(row) do
    local drawn = at[cell]
    check(drawn ~= nil,
      ("naming screen: row %d col %d (%q) actually calls Font.draw at all")
        :format(r, c, tostring(cell)))
    if drawn then
      check(onCanvas(drawn.x, drawn.y),
        ("naming screen: row %d col %d (%q) draws fully on the 160x144 canvas "
          .. "(got x=%d y=%d)"):format(r, c, tostring(cell), drawn.x, drawn.y))
    end
    checked = checked + 1
  end
end
eq(checked, 45, "naming screen: checked every cell across rows 1-5 (9 cells each)")

-- Specifically pin the originally reported letter and the confirm cell, by
-- name, so a future grid-shape edit that regresses only one cell still
-- fails loudly and legibly rather than just moving the checked-count total.
check(at["R"] ~= nil and onCanvas(at["R"].x, at["R"].y),
  "naming screen: R draws on-screen -- this is the exact letter the "
  .. "playtest screenshot reported missing")
check(at["ED"] ~= nil and onCanvas(at["ED"].x, at["ED"].y),
  "naming screen: ED (the confirm cell) draws on-screen -- was clipped off-"
  .. "canvas by the same bug, which would have silently blocked name entry")

T.finish("Gen2 naming screen crystal-layout grid")
