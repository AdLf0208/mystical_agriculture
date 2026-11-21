# Validation

Slice 2 of the port, validated on Linux with rustc 1.97.0 at the campaign pin
**SDK nightly `0a875da91dbb0fdcb7ba8c42c11341aa229af51a`** / horizon-mixins
`e59da9094f0c2fdda6c627fe9eff22dec6a906f0` (`[native]` in `horizon-mod.toml`),
game 26.3, launcher 0.2.92.

- Cargo steps: `ports/tools/build-slot.sh run --job W1-mysticalagriculture
  --port ports/mysticalagriculture --step test|check|build -- …`, with
  `CARGO_INCREMENTAL=0` and no `--target-dir`.
- In-game legs: the game was built and exported by
  `ports/tools/launcher-game.sh build mysticalagriculture` (the campaign pin's
  Nightly, `horizon-launcher` 0.2.92), then each leg ran inside a
  `--step e2e` lease with `GAME`/`CTL`/`CONTROL_GAME`/`RES` exported by
  `eval "$(ports/tools/launcher-game.sh env mysticalagriculture)"`.

Evidence: `../_shared/evidence/mysticalagriculture/` (`sdk-*`, `loot-*`) and
`../_shared/evidence/mysticalagriculture-e2e/` (`e2e-*`, `launcher-build.log`).
The full record with commands is `notes.md` §Slice 2 and §Verification.

| Check | Result |
|---|---|
| `cargo fmt --check` | pass |
| `cargo clippy --all-targets -- -D warnings` | pass, 0 warnings |
| `cargo test` | **9** runtime tests pass |
| `cargo horizon-mod build` (twice, `rm -f Cargo.lock` each) | exit 0, the two archives `cmp`-identical |
| `cargo horizon-mod check mysticalagriculture.hmod` | exit 0 — `0.2.1`, `native-1/0a875da…/e59da90…`, for 26.3, **30,400 B**, sha256 `bdb1fb31…38d1`, 49 entries |
| `cargo horizon-mod fits … --build 0a875da` | exit 0 — `0a875da  made for` (sha printed) |
| `cargo horizon-mod fits … --build 0b14f8a` | exit 0 — `0b14f8a  fits` (sha printed) |
| `python3 ports/tools/verify-sdk-package.py mysticalagriculture` | **1/1** (8 checks; `src/runtime.rs` byte-identical `555e6442…f6b9`; no packed `Cargo.lock`) |
| `python3 tools/carry_content.py --check` | 40 files, 0 pending (jar sha1 `4a774506…`) |
| `python3 tools/data_shape.py --data data` | red 6 problems before the fix, green after |
| `tools/e2e.sh` (native, launcher game at the pin) | **PASS** + `EXIT:0` |
| `SELFTEST=1 tools/e2e.sh` | `FAIL:` + `EXIT:1` (the drop assertion can fail) |
| `TABLE=1 tools/e2e.sh` (content-only mount, code absent) | **PASS** + `EXIT:0` — the carried table's own drops |
| `TABLE=1 SELFTEST=1 tools/e2e.sh` | `FAIL:` + `EXIT:1` |
| `TABLE=1 SOURCE=<0.2.0 package>` (legacy dialect) | PASS — the finding recorded in `notes.md` §Slice 2: at this pin the 1.21.1 spelling still rolls |
| `python3 ports/tools/check-e2e-logs.py mysticalagriculture-e2e --strict` | 5 logs, 5 ok, exit 0 |
| `python3 ports/tools/check-skills.py --notes ports/mysticalagriculture --strict` | `Skills line present`, PASS |

This is a partial port on purpose: slice 1 is the inferium crop/essence loop and
slice 2 put its carried loot table in 26.3's dialect and ran the package in game
at the pin. The remaining tiers, farmland, machines, tools, mob souls, worldgen
and the guide are the gap list in `notes.md`. Publishing needs the maintainer's
approval (ARCHITECTURE.md §8).
