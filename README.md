# The code, chapter by chapter

Each folder holds the Risiti app as it stands **at the end of** that chapter:
`03/` after Chapter 3, `15/` after Chapter 15. Chapters 1, 2 and 16 have no code
of their own.

This is Part I's Risiti: the real app's screens, schema and components,
grown one chapter at a time. Parts II to V add the rest (receipt reading,
claims, accounts, the server and sync) on top of `15/`.

Only the files we write are here: `lib/`, `test/`, `priv/`, `config/`,
`mix.exs`, `mob.exs` and `.formatter.exs`. The native `android/` folder is
whatever `mix mob.new` generated for you and never changes in Part I.

## Using a checkpoint

Generate a project once, then copy a checkpoint over it:

```
mix archive.install hex mob_new
mix mob.new risiti_app --android --blank
cp -r path/to/book/code/08/. risiti_app/
cd risiti_app
mix deps.get
mix test
```

Every checkpoint's tests pass on a computer with no phone attached, against
Mob 0.9.12:

| Chapter | Tests |
|---|---|
| 03 | 3 |
| 04 | 6 |
| 05 | 8 |
| 06 | 8 |
| 07 | 8 |
| 08 | 10 |
| 09 | 14 |
| 10 | 22 |
| 11 | 25 |
| 12 | 28 |
| 13 | 35 |
| 14 | 40 |
| 15 | 45 |
| 17 | 59 (3 of them doctests) |
| 18 | 88 (15 of them doctests) |
| 19 | 105 (15 of them doctests) |
| 20 | 131 (17 of them doctests) |
| 21 | 152 (21 of them doctests) |

`mix test` prints a warning that `mob_nif.so` can't be loaded. That's
expected: the NIF is built for the phone, and the tests don't need it.

Chapter 14 adds the `mob_camera` plugin, Chapter 15 `mob_biometric` and
Chapter 19 `mob_ocr` (in `plugins/`, copied with the rest), Chapter 20
`mob_scanner`, so deploy those
checkpoints with `--native` the first time.
