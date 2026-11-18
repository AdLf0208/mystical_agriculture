# Validation

Slice 1 of the port, validated on Linux with rustc 1.97.0 at **SDK nightly
`0b14f8acfd97fa2c750e42795249dcc981178ca4`** / horizon-mixins
`e59da9094f0c2fdda6c627fe9eff22dec6a906f0` (`[native]` in `horizon-mod.toml`),
game 26.3. Every step ran **directly in the port** with `CARGO_INCREMENTAL=0`:
`build-slot.sh` (and `tools/horizon.py`) speak the retired `.hnmod` ladder and do
not apply to a flat SDK package. The evidence logs are in
`../_shared/evidence/mysticalagriculture/` (`sdk-*`) and the full record with
commands is `notes.md` §Verification.

| Check | Result |
|---|---|
| `cargo fmt --check` | pass |
| `cargo clippy --all-targets -- -D warnings` | pass, 0 warnings |
| `cargo test` | **9** runtime tests pass |
| `cargo horizon-mod build` | `target/horizon-mod/mysticalagriculture.hmod`, exit 0 |
| `cargo horizon-mod check mysticalagriculture.hmod` | exit 0 — `native-mod`, format `native-1/0b14f8a…/e59da90…`, for 26.3, 30,169 B, sha256 `0d6c7606…caee`, 49 entries |
| `cargo horizon-mod check … --uses` | exit 0, 110 surface entries |
| `cargo horizon-mod fits … --build nightly` | exit 0 — `0b14f8a made for` |
| `unzip -p …hmod src/runtime.rs \| sha256sum` | `555e6442…f6b9`, the retired file byte for byte |
| `python3 tools/carry_content.py --check` | 40 files, 0 pending (jar sha1 `4a774506…`) |
| `tools/e2e.sh` | **not re-run**: needs a launcher-built game, `horizon-launcher` is not installed here. The 0.1.0 run (`e2e-default.log`, `e2e-embedded.log`, `PASS` + `EXIT:0`, `NEGATIVE=1`/`SELFTEST=1` exit 1) is the behaviour's evidence. |
| `python3 ports/tools/check-e2e-logs.py mysticalagriculture --strict` | the four 0.1.0 logs, all with a matching `EXIT:` |
| `python3 ports/tools/check-skills.py --notes ports/mysticalagriculture` | `Skills line present`, PASS |

This is a partial port on purpose: slice 1 is the inferium crop/essence loop.
The remaining tiers, farmland, machines, tools, mob souls, worldgen and the
guide are the gap list in `notes.md`. Publishing needs the maintainer's approval
(ARCHITECTURE.md §8).
