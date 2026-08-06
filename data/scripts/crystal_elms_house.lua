-- Elm's House's two NPCs (pret/pokecrystal maps/ElmsHouse.asm: ElmsWife,
-- ElmsSon). Both are single-text jumptextfaceplayer scripts in the ROM, no
-- branching.

return {
  talk = {
    TEXT_ELMSHOUSE_ELMS_WIFE = {
      { "face_player" },
      { "show_text",
        "Hi, {PLAYER}! My\nhusband's always\fso busy--I hope\nhe's OK.\fWhen he's caught\nup in his POKéMON\fresearch, he even\nforgets to eat." },
    },

    TEXT_ELMSHOUSE_ELMS_SON = {
      { "face_player" },
      { "show_text",
        "When I grow up,\nI'm going to help\vmy dad!\fI'm going to be a\ngreat POKéMON\vprofessor!" },
    },
  },
}
