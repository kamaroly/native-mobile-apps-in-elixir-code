# Native Mobile Apps in Elixir: the code

The code for the book
**[Native Mobile Apps in Elixir](https://leanpub.com/elixir-native-mobile-apps)**,
chapter by chapter.

Each folder holds Risiti as it stands **at the end of** that chapter:
`03/` after Chapter 3, `15/` after Chapter 15. Chapters 1, 2, 16 and 35
have no code of their own.

Clone it next to your own projects, as `code`, so the paths match the book:

```
git clone https://github.com/kamaroly/native-mobile-apps-in-elixir-code.git code
```

- **`03/` to `23/`** are the phone app, `risiti_app` (Parts I and II).
- **`24/` to `29/`** are the server, `risiti`, a Phoenix and Ash app
  (Part III).
- **`30/` to `32/`** are the phone app again, joined to the server
  (Part IV).
- **`33/`** and **`34/`** are the phone app and the server made ready to
  ship (Part V).

For the phone app, only the files we write are here: `lib/`, `test/`,
`priv/`, `config/`, `plugins/`, `mix.exs`, `mob.exs` and `.formatter.exs`.
The native `android/` folder is whatever `mix mob.new` generated for you.

## Using a checkpoint

Generate a project once, then copy a checkpoint over it:

```
mix archive.install hex mob_new
mix mob.new risiti_app --android --blank
cp -r code/08/. risiti_app/
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
| 22 | 155 (21 of them doctests) |
| 23 | 167 (22 of them doctests) |

`mix test` prints a warning that `mob_nif.so` can't be loaded. That's
expected: the NIF is built for the phone, and the tests don't need it.

Chapter 14 adds the `mob_camera` plugin, Chapter 15 `mob_biometric` and
Chapter 19 `mob_ocr` (in `plugins/`, copied with the rest), Chapter 20
`mob_scanner`, Chapter 22 `mob_google` and Chapter 23 `mob_viewer` (also in
`plugins/`), so deploy those checkpoints with `--native` the first time.

## The server

`24/` to `29/` and `34/` are complete Phoenix projects. Their tests need
PostgreSQL:

```
cd code/29
mix setup
mix test
```

## Part V

- **`33/`** is the phone app from `32/` made ready for release: `inets` in
  `mix.exs`, the server named by `RISITI_API_URL` at build time, and
  `scripts/release_apk.sh`. Its `android/` folder holds only the files
  Chapter 33 writes in full (R8 rules, splash, styles, adaptive icons);
  copy them over a generated project's `android/`, then make the
  `build.gradle`, manifest and `MainActivity.kt` edits the chapter shows.
  181 tests and 26 doctests pass.
- **`34/`** is the server from `29/` made ready to deploy:
  `Risiti.Release.migrate_all/0`, `rel/overlays/bin/`, the production
  services in `config/runtime.exs`, and `deploy/` (script, systemd unit,
  nginx, the secrets file's example) with `.github/workflows/deploy.yml`.
  Its tests need Postgres, like `24/` to `29/`: 121 tests and 8 doctests
  pass.

## License

The code is released under the [MIT License](LICENSE). The book itself is
not: it is sold on [Leanpub](https://leanpub.com/elixir-native-mobile-apps).
