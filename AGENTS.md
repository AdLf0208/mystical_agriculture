# Working on this native Horizon mod (SDK format)

This port is one flat `.hmod` in the 2026-11-18 SDK layout: `horizon-mod.toml` +
`Cargo.toml` + `src/` + `assets/` + `data/`. `cargo horizon-mod` is the tool
(`new`, `hooks`, `build`, `check`, `fits`), and `.horizon/sdk/` is fetched by the
first such command — never edit or commit it.

Read `README.md`, `horizon-mod.toml` and `notes.md` before editing. Keep this
repository separate from Horizon and horizon-mixins; never modify the pin
checkout or player resources. Do not commit binaries, fetched SDKs or Minecraft
assets beyond the mod's own carried files.

## Commands (run directly in this folder; there is no staged tree any more)

```sh
CARGO_INCREMENTAL=0 cargo test                             # the pure runtime, 9 tests
CARGO_INCREMENTAL=0 cargo clippy --all-targets -- -D warnings
cargo fmt --check                                          # NOT `--all`: that reads the SDK
rm -f Cargo.lock                                           # a packed lock changes the artifact
CARGO_INCREMENTAL=0 cargo horizon-mod build                # -> target/horizon-mod/<id>.hmod
cp target/horizon-mod/<id>.hmod ./<id>.hmod                # the deliverable lives in the port
cargo horizon-mod check <id>.hmod                          # the registry's checks
cargo horizon-mod check <id>.hmod --uses                   # what it uses, from uses.json
cargo horizon-mod fits <id>.hmod --build nightly           # does it fit that build
sha256sum <id>.hmod
```

`build-slot.sh` speaks the retired `horizon.py` ladder and does not apply to this
layout, so these steps run directly (the port has no staged Horizon copy and no
shared cargo target any more). A launcher-built game is what an in-game check
needs: `horizon-launcher native-build . --instance <i> --trust-native-code`, then
`GAME=<that binary> tools/e2e.sh`.

Rules that cost runs (the full list is in `notes.md`, `## Migration to the SDK
format`): the package root may hold only package paths, so no `.rs`/`.toml` may
sit anywhere but `src/`; `side` is the installation side; and a `Cargo.lock` in
the root is packed into the archive.

The port keeps the campaign's rule: gameplay rules live in `src/runtime.rs`
(pure, unit-tested, no `mod_api` types) and everything here is glue.
