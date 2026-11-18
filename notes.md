# Mystical Agriculture → Horizon

Ported from **Mystical Agriculture 1.21.1-8.0.29** (`BlakeBr0/MysticalAgriculture`,
MIT), Minecraft Java 1.21.1 NeoForge, read from
`ports/_shared/upstream/mysticalagriculture` at commit
`f38a092852538905de72a999f462936b71181554` (`Release 8.0.29`). The upstream
source and the jar were read for behaviour and assets only; the Rust is a
clean-room rewrite. Local-only until publishing is approved
(ARCHITECTURE.md §8).

**Licence: MIT** (`license="MIT"` in the jar's `META-INF/neoforge.mods.toml`;
MIT text © 2018 BlakeBr0 from the upstream `LICENSE`) → **rank 0, permissive**,
publishable under MIT with this source once the maintainer approves. `LICENSE`
(both copyright lines) and `LICENSE-NOTICE.md` (provenance) travel **inside** the
package and are carried into the `.hmod`.

**Format: the SDK package (2026-11-18), version 0.2.0.** This port was migrated
from the retired `.hnmod` container (0.1.0, PR **#886**) to the flat SDK package;
see [`## Migration to the SDK format`](#migration-to-the-sdk-format) for the
recipe, the file map and the traps. `src/runtime.rs` is **byte-identical** to the
retired `mixins/mysticalagriculture/runtime.rs` (sha256
`555e64425477fa8cb63a203aa95e5b80455d39d9ac53c3a2598274d250eaf6b9`), including
the file inside the package.

## Approach (from the pin's `docs/modpacks.md`)

- **Class `content`, tier `machines`** (`ports/ledger.csv` row 331; provenance
  `ports/_shared/source-map/atm10-sources.csv`). This job is **slice 1 of the
  `content` half**: carried-over content (the crop block, its stages, its
  textures/models, the items, the recipes) + the logic half its jar's code
  needs (the drop formula and the bone-meal refusal). No block entity, menu,
  screen or capability is built here — those belong to the mod's machines and
  are listed as gaps.
- **Why now:** rank 0, core parent of `mysticalagradditions` (one pending mod
  depends on it), #3 by dependency weight in `port_queue.py`'s licence-first
  order.
- **Carry-over vs agent port:** the crop's assets, models, blockstate, lang
  keys, item models and the two recipes are carried (byte-identical from the
  exact ATM10 jar, see `tools/carry_content.py`); the drop rules and the
  bone-meal answer are the agent port.

## Slice 1 — the inferium crop/essence loop

- `mysticalagriculture:inferium_crop` on the `minecraft:wheat` template:
  `age` 0..7, vanilla crop growth on farmland, the jar's 4-pixel outline
  (declared, with an explicit empty collision table), light-9 survival.
- `mysticalagriculture:inferium_seeds` plants the crop on farmland through the
  item's `block` declaration (the crop block has `item: false`).
- `mysticalagriculture:inferium_essence` and `inferium_ingot` items;
  `prosperity_ingot` is carried only as the ingot recipe's other ingredient.
- Recipes: seeds = 8 essence + 1 wheat seed (shaped); ingot = 1 prosperity
  ingot + 2 essence (shapeless).
- Drops (the jar's `InferiumCropBlock.getDrops`, in `runtime::harvest`): a
  young crop gives 1 seed; a ripe one gives 1..2 seeds (0.2 on inferium
  farmland, 0 on plain) and 1..3 essence by the essence farmland's tier. The
  content loot table is the plain-farmland fallback; `loot_drops` replaces it
  with the farmland-aware result.
- Bone meal: the crop's Part answers `Some(age < 7)` and `success = false`, so a
  meal is spent and the crop does not grow, as upstream.

### Hooks → methods (the whole behaviour's surface)

| `.hnmod` (retired) | SDK package |
|---|---|
| `[[module]] runtime` (`runtime.rs`) | `pub mod runtime` |
| `[[module]] state` (`support.rs`) | `mod support` |
| `[[injection]] hook = "loot_drops"`, kind HEAD, `loot_drops.rs` → `support::on_loot_drops(game, context, drops)` | [`Hooks::loot_drops`]: `event.context` (a `LootDrops`) + `event.drops` (`&mut Vec<ItemStack>`) |
| `[[injection]] hook = "is_valid_bonemeal_target"`, HEAD, `bonemeal_target.rs` | [`BlockPart::is_valid_bonemeal_target`] on the crop's Part → `Option<bool>` |
| `[[injection]] hook = "is_bonemeal_success"`, HEAD, `bonemeal_success.rs` | [`BlockPart::is_bonemeal_success`] on the same Part → sets `event.success` |
| `[[injection]] target = "horizon_client::game::mods::content_root"` + `embedded_content.rs` | **gone**: `assets/` + `data/` are in the package |
| `game.native_level_random(dimension)` | `LevelRef::with_random(host, …)` + `RandomSource::next_double` |
| `game.pack.assets.registry.state(..)` / `world.block(..)` | `BlockState::property(&host.block_states(), "age")`, `LevelRef::block_state(host, pos)` and `BlockMetadata::name` |

The rules (age/ripeness, the farmland tiers, the draw order) stay in
`src/runtime.rs`, unit-tested there; `src/lib.rs` is the `impl Hooks` and
`src/support.rs` is the glue, with no number of its own.

### Deliberate deviations

- Growth is the pin's wheat-template random tick, not a native growth hook:
  the jar's `MysticalCropBlock.randomTick` does nothing but call
  `super.randomTick` (its `canGrow` is always true for inferium). The e2e
  proves the stage advance is random-tick driven (speed 0 holds, then ages
  0→7).
- The two RNG draws come from the level's own random
  (`LevelRef::with_random`) instead of Java's `Math.random()`; the jar's draw
  order is preserved and a young crop draws nothing at all.
- The seed item uses a plain item template plus `block` instead of
  `ItemNameBlockItem`: no vanilla seed behaviour, and the crop is not in
  `minecraft:villager_plantable_seeds`, so farmers do not plant it (gap).
- No config file: `secondarySeedDrops` is the default `true`; the inferium
  crop never drops fertilized essence (the jar's own override) and
  `requiresEffectiveFarmland` cannot matter for inferium.
- The `inferium_crop` item does not exist (the jar's seed item is the block's
  item); the crop block is not in a creative tab in this slice.
- The ingot's prosperity-ingot prerequisite has no acquisition path here
  (prosperity ore/worldgen is a later slice); the item and the recipe are
  carried so the chain is exact, and the harness gives the ingot.

### Gaps (next slices)

- Tiers 2–5 (prudentium/tertium/imperium/supremium essence, essence farmland,
  cruxes, seeds), the remaining ~120 crops and their seed-crafting recipes.
- Inferium farmland and essence farmland tiers (crafting, moisture,
  watering-can refill) — the drop formula already accepts them
  (`runtime::Ground`), and only the pure tests exercise the tiers today.
- Machines: growth accelerators, seed reprocessor, infuser, reprocessor, soul
  jars, essence vessel; their block entities, menus and screens.
- Tools/armor/weapons, infusion/enchantment, mob soul collection, ore
  worldgen, Patchouli guide, config, Jade/Curios integrations.
- No creative tab, no villager planting, no block-colour tint registration for
  the mature flower (the model's `tintindex` gets no mod colour).
- **The in-game e2e has not been re-run in the SDK format**: it needs a
  launcher-built game (`horizon-launcher native-build … --trust-native-code`)
  and `horizon-launcher` is not installed here. `tools/e2e.sh` is adapted to
  that shape (no `--dev-mod`, `GAME=` required, an optional `STOCK=` control)
  and its assertions are unchanged; the 0.1.0 run below stands as the
  behaviour's evidence.
- The drop hook **replaces** the rolled list, so a third mod's addition to the
  same crop's drops (a loot modifier) is dropped too — the retired hook did the
  same and the jar has no such interaction to copy.

## Migration to the SDK format

*Pins for this migration: SDK nightly
**`0b14f8acfd97fa2c750e42795249dcc981178ca4`** (2026-11-18), mixins
**`e59da9094f0c2fdda6c627fe9eff22dec6a906f0`**, launcher 0.2.78,
`cargo-horizon-mod` from `horizon-rust/horizon@main` (`448cd693`). The recipe's
origin is `ports/imfast/notes.md`; this port follows it for a **content + code**
package, which imfast (code only) did not exercise.*

### Why

Horizon's mod-API merge (#16941, launcher ≥ 0.2.70) retired `.hnmod`; the
registry closed every `.hnmod` submission on 2026-11-18, #886 among them, and an
`.hnmod` no longer loads. The new unit is **one flat `.hmod`** that may carry
content, code, or both — so this port's split halves (a content `.hmod` embedded
inside an `.hnmod` through the AE2 `content_root` pattern) collapse into one
archive with `assets/` and `data/` at the root.

### The file map (what the package holds)

| Path | What it is |
|---|---|
| `horizon-mod.toml` | the only manifest and the only identity: `id`, `version = 0.2.0`, `api = "0.2"`, `side = "both"`, `capabilities = ["registries"]`, `[native]` with the three exact pins |
| `Cargo.toml` | one crate (`mysticalagriculture`, 0.2.0, edition 2024); its only dependency is `horizon-mod-api` from `.horizon/sdk/` |
| `src/lib.rs` | the one `#[mod_api::horizon_mod] impl Hooks`: `register` + `loot_drops`, and the retired-hook table in its docs |
| `src/support.rs` | the glue: the id table, the `Crop` `BlockPart` (both bone-meal answers), the loot hook body |
| `src/runtime.rs` | the pure rules, **copied byte-for-byte** (`cp`, then `cmp`), 9 tests |
| `assets/mysticalagriculture/` | 32 carried files: blockstate, 13 models (9 block + 4 item), 13 textures, 4 item definitions, lang |
| `data/mysticalagriculture/` | the block and item declarations, the two recipes, the fallback loot table |
| `LICENSE`, `LICENSE-NOTICE.md`, `README.md` | the notices the licence requires in a distributed copy (the packer takes root files with these prefixes) |
| `.gitignore` | `/target`, `/.horizon`, `/Cargo.lock` (trap 5) |
| `tools/e2e.sh`, `tools/carry_content.py`, `tools/craft_check.py` | the scenario, the jar carry (`--check`) and its crafting cases |
| `mysticalagriculture.hmod` | the deliverable, 30,169 B, sha256 `0d6c7606…caee` |

`assets/` and `data/` are the **same bytes** as the retired `content/` tree
(`carry_content.py --check` → `40 files, 0 pending`, jar sha1 `4a774506…`): the
carry script now writes at the package root and no longer generates a second
manifest.

### Manifest field map

| old (`horizon-mixin.toml` + `content/horizon-mod.toml`) | new (`horizon-mod.toml`) |
|---|---|
| two manifests (code + content) | one |
| `[mod] id` / content `id` | `id` (also the resource namespace) |
| `[mod] version = "0.1.0"` | `version = "0.2.0"` (a resubmission is always a new version) |
| `[mod] priority = 100` | gone; ordering is `#[listener(priority = …)]` per hook |
| `[compatibility] horizon_revision = 1d63e0a5…` | `[native] horizon = 0b14f8ac…` |
| the bundle's mixins revision `5a64af93…` | `[native] mixins = e59da9094f0c…` |
| content `api = "0.2"`, `side`, `capabilities` | the same three fields, now for one package |
| `[[module]]` × 2, `[[injection]]` × 4 | `src/`, one `impl Hooks`, one `BlockPart` |
| — | `[native] game = "26.3"`, `license`, `homepage`, `issues`, `authors` |

### Build and check (the ladder for an SDK package)

`build-slot.sh` speaks the retired `horizon.py` ladder and does not apply; every
step runs **directly in the port** with `CARGO_INCREMENTAL=0`, no staging and no
`--target-dir`:

```sh
CARGO_INCREMENTAL=0 cargo test                             # 9 passed
CARGO_INCREMENTAL=0 cargo clippy --all-targets -- -D warnings
cargo fmt --check                                          # not `--all`
rm -f Cargo.lock                                           # trap 5
CARGO_INCREMENTAL=0 cargo horizon-mod build                 # -> target/horizon-mod/<id>.hmod
cp target/horizon-mod/<id>.hmod ./<id>.hmod
cargo horizon-mod check <id>.hmod [--uses|--json]
cargo horizon-mod fits <id>.hmod --build nightly
sha256sum <id>.hmod
```

### Traps this migration hit (and the next one must know)

1. **A leftover old path refuses the package.** The packer walks every root
   directory and refuses any `.rs` or `.toml` outside `src/` (imfast hit
   `unexpected package path: mixins/imfast/runtime.rs`; read
   `horizon-mod-package/src/manifest.rs`, `directory_files`). So
   `mixins/mysticalagriculture/*.rs`, `horizon-mixin.toml` and
   `tools/audit/{Cargo.toml,src/main.rs}` **would** have failed, and all of them
   (plus the retired `tools/*.py`) were moved out *before* the first build.
   `tools/*.py` and `*.sh` are ignored by the walk; `.rs`/`.toml` are not.
2. **The content schema moved with the SDK: an item's `place_block` is now
   `block`.** `data/…/horizon/item/inferium_seeds.json` was green at
   `1d63e0a5` and refused here with `unknown field 'place_block', expected one
   of 'template', 'max_stack_size', 'rarity', 'components',
   'crafting_remainder', 'block', 'arm_pose'`. Both the carried file and
   `carry_content.py` now write `block`; a port migrating a `place_block` item
   must expect this.
3. **`cargo horizon-mod check` with no file checks wasm** (imfast trap 3): use
   `check <file.hmod>`, and `cargo check`/`cargo test` for the crate.
4. **`cargo fmt --all --check` reports the SDK's files** (it is a path
   dependency): use `cargo fmt --check`.
5. **`Cargo.lock` is packed and changes the artifact.** `cargo test`/`clippy`
   write one; `rm -f Cargo.lock` right before the build, and keep `/Cargo.lock`
   in `.gitignore`.
6. **`side` is the installation side**: `"both"`, because an integrated server
   belongs to the client installation and the crop must work in single player.
7. **`capabilities = ["registries"]` is a schema requirement**, not a claim that
   a mod without content may drop it.
8. **A block-scoped hook is a `BlockPart`, not a global `Hooks` method.** Both
   bone-meal hooks are `scope = "block"`: as `Hooks` methods they compile and are
   **never called**. Attach the Part to the block (`r.block_part(r.block_key(…),
   Crop)`) and the game asks it only about that block.
9. **`is_valid_bonemeal_target` returns `Option<bool>` and `LevelSide`, while
   `is_bonemeal_success` takes `&mut dyn LevelRandomHost`.** A Part is asked
   *ahead of* the template's own bonemeal behaviour
   (`horizon-world/src/level/bonemeal.rs`, `grow_crop`), which is what makes
   `Some(false)`/`success = false` reproduce the jar on a wheat-template crop.
10. **Reading a state's properties inside a Part needs `LevelHost`, not
    `Host`.** `LevelSide::Server(level) | LevelSide::Client(level) => level` gives
    the `&dyn LevelHost`, and `state_string(state)` is the readable form; the
    `BlockMetadata` path (`state.property(...)`) is for a `Host`.
11. **Trait imports that look unused are required**: `HostBlockStates` for
    `host.block_states()` and `BlockMetadata` for `metadata.name(..)`/
    `property(..)`; `RandomSource` for `next_double`. Without them the calls do
    not resolve (`E0599`).
12. **`Hooks` is `Any + Send + Sync`**: any session state goes in a `Mutex`
    field or a `OnceLock`/`Mutex` static (this port keeps the id table in a
    `OnceLock`, resolved once in `register`).
13. **`runtime.rs` as a module**: declare `pub mod runtime;` (a private module
    makes every `pub` item a `dead_code` warning). The file itself stays
    byte-identical — no `#[allow(...)]` inside it.
14. **No `rust-toolchain.toml`**: the pin (and the launcher) decide the
    toolchain. `sdk.json` declares rust 1.99.1; this crate compiles with the
    local 1.97.0, edition 2024.
15. **The content is at the package root now.** `assets/<id>/` and `data/<id>/`
    are packed by `cargo horizon-mod build`; `content/`, `mixins/*/data/` and
    the `content_root` injection exist only in the retired format.
16. **The e2e needs a launcher-built game.** `horizon-launcher` is not installed
    in this environment, so `tools/e2e.sh` (adapted: `GAME=` required, no
    `--dev-mod`, optional `STOCK=` counterfactual) has not been re-run. Do not
    claim `ported` from the 0.1.0 evidence alone.

### What was retired, and where

`ports/_shared/evidence/mysticalagriculture/retired-hnmod-0.1.0/` holds the
whole 0.1.0 tree as evidence: `mixins/mysticalagriculture/` (the plan,
`runtime.rs`, `support.rs`, the three helpers, `embedded_content.rs`, the
embedded content `.hmod`), `mysticalagriculture.hnmod` (18,729 B, sha256
`316a13e6…469e`), `compatibility.json`, `rust-toolchain.toml`, the old
`Cargo.toml`/`Cargo.lock`, `content/horizon-mod.toml` and
`content/mysticalagriculture.hmod` (15,741 B, sha256 `622c873e…b456`), and the
retired tooling (`tools/horizon.py`, `package.py`, `package.sh`,
`embed_ladder.sh`, `e2e_embedded.sh`, `test_stage.py`, `test_template.py`,
`add-notices.py`, `tools/audit/`). Deleted rather than archived: `content/target/`
and `target/` (disposable), the old `.hnmod` copy under `target/` (identical to
the archived one).

## Verification

Pins: SDK nightly `0b14f8acfd97fa2c750e42795249dcc981178ca4`, mixins
`e59da9094f0c2fdda6c627fe9eff22dec6a906f0`, game 26.3. Every step ran directly
in the port with `CARGO_INCREMENTAL=0` (no `build-slot.sh`: it speaks the retired
ladder). Evidence: [`../_shared/evidence/mysticalagriculture/`](../_shared/evidence/mysticalagriculture/)
(`sdk-*.log`, `sdk-uses.json`, `sdk-sha256.txt`, plus the 0.1.0 logs).

| Check | Command | Result |
|---|---|---|
| Runtime unit tests | `cargo test` | **9 passed**, 0 failed (`sdk-test.log`) |
| Lints | `cargo clippy --all-targets -- -D warnings` | exit 0, **0 warnings** (`sdk-clippy.log`) |
| Formatting | `cargo fmt --check` | clean (`sdk-fmt.log`) |
| Package | `cargo horizon-mod build` | `target/horizon-mod/mysticalagriculture.hmod`, EXIT 0 (`sdk-build.log`) |
| Registry check | `cargo horizon-mod check mysticalagriculture.hmod` | `mysticalagriculture 0.2.0 (native-mod, format native-1/0b14f8a…/e59da90…, for 26.3)`, **30,169 B**, sha256 `0d6c7606…caee`, **EXIT 0** (`sdk-check.log`, `sdk-check-json.log`) |
| What it uses | `cargo horizon-mod check … --uses` | **110** surface entries (`sdk-uses.json`), EXIT 0 |
| Fits the pinned build | `cargo horizon-mod fits … --build nightly` | `0b14f8a  made for`, EXIT 0 (`sdk-fits.log`) |
| `runtime.rs` untouched | `unzip -p …hmod src/runtime.rs \| sha256sum` | `555e6442…f6b9` = the retired file, byte for byte (`cmp` too) |
| Carried content | `python3 tools/carry_content.py --check` | **40 files, 0 pending**, jar sha1 `4a774506…` (`sdk-carry-check.log`) |
| Skills line | `python3 ports/tools/check-skills.py --notes ports/mysticalagriculture` | `Skills line present`, **SKILLS GATE: PASS** |

The package's 49 entries: `horizon-mod.toml`, `Cargo.toml`, `LICENSE`,
`LICENSE-NOTICE.md`, `README.md`, `src/{lib,runtime,support}.rs`, `uses.json`
and the 40 carried content files. No `Cargo.lock` is packed.

### The 0.1.0 in-game evidence (still the behaviour's proof)

The retired run drove the same scenario through `horizon-ctl` on a game with the
content loaded as a dev mod; the transcript is in `e2e-default.log` and the
embedded one in `e2e-embedded.log`:

```
crop PASS: ages 0..7 read back
mysticalagriculture:inferium_seeds on farmland -> mysticalagriculture:inferium_crop[age=0]
seed planting PASS: inferium_crop[age=0] placed; a stick places nothing
control PASS: random_tick_speed 0 keeps ages 0 and 3 for 300 ticks
growth PASS after 60 ticks: age 0->1 and age 3->4
our crop PASS: age 0 after bone meal, meal 8 -> 7
wheat control PASS: bone meal grew vanilla wheat to age 4
{"scenario":"age=7","block_before":"mysticalagriculture:inferium_crop[age=7]","drops":{"mysticalagriculture:inferium_essence":1,"mysticalagriculture:inferium_seeds":1}}
{"scenario":"age=0","block_before":"mysticalagriculture:inferium_crop[age=0]","drops":{"mysticalagriculture:inferium_seeds":1}}
loot PASS: age 7 -> 1 essence + 1 seeds; age 0 -> 0 essence + 1 seeds; wheat -> 1
8 essence + 1 wheat seed -> inferium_seeds -> {"count": 1, "item": "mysticalagriculture:inferium_seeds", "slot": 200}
1 prosperity ingot + 2 essence -> inferium_ingot -> {"count": 1, "item": "mysticalagriculture:inferium_ingot", "slot": 200}
unknown ids refused
PASS: …
EXIT:0
```

Controls that make it fail-capable: the same crop with `random_tick_speed 0`
does not change; a stick on farmland places nothing; bone meal grows vanilla
wheat in the same plot but not ours; vanilla wheat drops its own loot; the
wrong-ingredient recipes stay empty; `NEGATIVE=1` (expecting essence from a
young crop) exits 1 and `SELFTEST=1` exits 1 on the ripe-crop assertion.

### Harness facts learned (useful for the next slice)

- A 4-pixel crop cannot be clicked through `ctl interact … up` reliably: the
  aim point is the block centre. `ctl look-at x y.1 z` + `ctl use-item` applies
  the meal; `ctl break` works (it tries every face).
- Horizon needs `is_valid_bonemeal_target` to answer before
  `is_bonemeal_success` is asked (the mod's three questions only run when the
  first answers).
- A stone-ringed water source at the farmland level keeps the 4-block water
  scan true, so random ticks never dry/revert the plot; `random_tick_speed 400`
  reaches age 7 in ~100 ticks at render distance 4.

Skills: superpowers/using-superpowers,brainstorming,writing-plans,test-driven-development,systematic-debugging,verification-before-completion; BeautifulRust/rust-best-practices,rust-port

## Review repairs (PR #570)

- *"Include the upstream MIT copyright and license notices in the distributed
  bundle"* — `LICENSE` and `LICENSE-NOTICE.md` sit at the package root and are
  packed into the `.hmod` (root files with `LICENSE`/`NOTICE` prefixes are
  package paths), and both were already at the embedded content archive's root
  in the retired format.
- *"Align the PR-body artifact hash (`da887f…`) with
  `mods/mysticalagriculture.toml:34`"* — the body is the orchestrator's; the
  entry now carries the SHA-256 of this repackaged artifact.

### Verification after the repairs

- **0.2.0 artifact:** `mysticalagriculture.hmod`, 30,169 B, SHA-256
  `0d6c760670641b4d6aa84e122e82c62e571e85cfaa4cf6e99957452fbe3bcaee`
  (rebuilt twice — the archive is deterministic; 49 entries, no `Cargo.lock`).
- **0.1.0 artifact (retired, in evidence):** `mysticalagriculture.hnmod`,
  18,729 B, SHA-256 `316a13e6d3a07108bb5c44e49c1c5ba998e7f9b09f668577135291b82476469e`.
- `python3 ports/tools/check-skills.py --notes ports/mysticalagriculture` → exit 0.

## Changelog / supersede text (for the resubmission)

> **0.2.0 — SDK package (supersedes PR #886, closed 2026-11-18).**
> Horizon retired `.hnmod` (mod-API merge #16941, launcher ≥ 0.2.70) and closed
> every `.hnmod` submission, this one included. The port is republished as the
> flat SDK package the new API asks for: one `.hmod` with `horizon-mod.toml`
> (`api = "0.2"`, `[native]` pinned to Horizon `0b14f8a…` / mixins `e59da90…`),
> the Rust in `src/`, and the crop, its items, models, textures, recipes and
> loot at the package root, so one file installs both halves — no embedded
> `content_root` bundle any more.
> The behaviour is unchanged and its rules are the same byte-identical
> `src/runtime.rs` (9 tests): ages 0..7 on random ticks, the jar's
> farmland-aware harvest, and bone meal spent but refused on every Mystical
> Agriculture crop (now a `BlockPart` on the crop, which is the SDK's shape for
> a block-scoped hook). Content schema follow-ups: an item's `place_block` field
> is `block` at this SDK. Still slice 1 — tiers 2–5, the essence farmlands, the
> other crops and the machines remain recorded gaps.
