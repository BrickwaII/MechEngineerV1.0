# data/

Region files and tuning tables. Hand-edited, no code.

- `bot_data/tuning.json`: draft size, squad size, augment slot count, stat ranges,
  starting personality range, starting skills and generation, bot names.
- `bot_data/skills.json`: the starting skill catalog (name, effect id, energy cost).
- `regions/`: the act maps and their variants, built from public-domain outlines
  (see `regions/README.md`), and the placeholder maps the tests use.
- `tuning/acts.json`: the acts, their map variants and the zoom between them.
- `tuning/overworld.json`: every overworld number; `tuning/act1.json` to
  `act3.json` lay each act's pacing over it (countdown, action costs, pressure).
