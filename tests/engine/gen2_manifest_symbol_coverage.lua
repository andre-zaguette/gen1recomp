-- Regression guard for extractor<->manifest symbol agreement.
--
-- Root problem this pins: nothing in the committed suite ever calls an
-- extractXMusic() (or any other extract*) function against a real ROM, and
-- nothing checks that every symbol name RomExtractorCrystal.lua references via
-- self:symbol("...") actually exists in tools/rom_manifest_crystal.json's
-- symbols table. That gap let Tasks 4 and 5 (see
-- docs/superpowers/plans/2026-08-06-gen2-crystal-milestone2-music.md's
-- progress notes) land extractor code whose manifest entries were
-- incomplete or got silently dropped on a later regeneration, and it let
-- extractTitleMusic ship for an entire earlier plan missing a real Ch3
-- symbol nobody caught until the final whole-branch review.
--
-- This is a ROM-free static check: tools/rom_manifest_crystal.json is
-- committed (only raw ROM *bytes* are gitignored, see /roms/ in
-- .gitignore), so it can be read directly like
-- tests/engine/gen2_map_songs.lua already does, and RomExtractorCrystal.lua
-- is read as plain text and pattern-matched for self:symbol("literal")
-- call sites -- no ROM, no love stub, no live extraction required.
--
-- Pattern-extraction scope, verified by hand against every self:symbol(
-- call site in src/import/RomExtractorCrystal.lua before writing this test:
--   self:symbol%("([%w_%.]+)"%) matches all 75 call sites whose argument
--   is a plain double-quoted string literal (covers every music/title/
--   font/cry/sprite symbol lookup in the file). It naturally SKIPS the
--   handful of call sites whose argument is not a plain string literal,
--   because they never start with a quote right after the paren:
--     - self:symbol(spec.gfx) / self:symbol(spec.meta) /
--       self:symbol(spec.coll) -- built from MAP_SPECS/tileset spec
--       tables at runtime (extractTileset)
--     - self:symbol(expected.label .. "_MapAttributes") -- string
--       concatenation, not a bare literal (extractMap)
--     - self:symbol(label) -- a loop variable over INTRO_TEXT_LABELS
--       (extractIntroText)
--   These "dynamic" sites aren't testable via literal pattern matching;
--   that's an accepted gap, not a bug in this test.
--
-- One further, deliberate exception: extractIntroText's guarded
-- _OakText3 lookup (RomExtractorCrystal.lua:1311-1313) reads:
--   local oakText3 = self.symbols and rawget(self.symbols, "_OakText3")
--   if oakText3 then
--     out._OakText3 = self:decodeTextCommands(self:symbol("_OakText3"))
--   end
-- The self:symbol("_OakText3") call on line 1313 IS a plain string
-- literal, so the pattern above still extracts it -- but it is only ever
-- reached after the rawget guard above it confirms the symbol exists, so
-- older/incomplete manifests (this project's own committed manifest
-- included -- Crystal's OakText3 is an older-manifest-optional prompt
-- beat, see extractIntroText's own doc comment) are expected to lack it.
-- _OakText3 is therefore excluded from this test's required-symbol set by
-- name, not silently -- see EXCLUDED_SYMBOLS below.
--   luajit tests/engine/gen2_manifest_symbol_coverage.lua

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check = T.check

local Json = require("src.link.Json")

local EXCLUDED_SYMBOLS = {
  -- Guarded by a rawget check before use (RomExtractorCrystal.lua:1311-1313);
  -- absent from older/incomplete manifests by design. See header comment.
  _OakText3 = true,
}

local function readFile(path)
  local f = assert(io.open(path, "r"), "cannot open " .. path)
  local data = f:read("*a")
  f:close()
  return data
end

local manifest = Json.decode(readFile("tools/rom_manifest_crystal.json"))
local extractorSource = readFile("src/import/RomExtractorCrystal.lua")

-- Extract every self:symbol("literal") call site's argument, in file
-- order, with a 1-based line number for readable failure messages.
local referenced = {}
local lineNum = 0
for line in (extractorSource .. "\n"):gmatch("([^\n]*)\n") do
  lineNum = lineNum + 1
  for name in line:gmatch('self:symbol%("([%w_%.]+)"%)') do
    referenced[#referenced + 1] = { name = name, line = lineNum }
  end
end

check(#referenced > 0,
  "self:symbol(\"literal\") pattern matched at least one call site " ..
  "in RomExtractorCrystal.lua (sanity check that the pattern itself works)")

local manifestSymbols = manifest.symbols or {}
local checkedCount, skippedCount = 0, 0

for _, ref in ipairs(referenced) do
  if EXCLUDED_SYMBOLS[ref.name] then
    skippedCount = skippedCount + 1
  else
    checkedCount = checkedCount + 1
    check(manifestSymbols[ref.name] ~= nil,
      ("RomExtractorCrystal.lua:%d references self:symbol(\"%s\"), which " ..
       "must exist in tools/rom_manifest_crystal.json's symbols table")
        :format(ref.line, ref.name))
  end
end

print(("(checked %d literal symbol references, skipped %d documented " ..
  "exception(s))"):format(checkedCount, skippedCount))

T.finish("Gen2 extractor<->manifest symbol coverage")
