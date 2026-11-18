# Mystical Agriculture — a Horizon port

**Mystical Agriculture** is a Minecraft mod. Adds Resource Crops, Armor, Tools, and other cool things!. This repository is a **port of it to [Horizon](https://github.com/horizon-rust/horizon)**, the Rust engine for Minecraft Java 26.3. It carries the complete source of the port plus the content files it ships, and installs as a single `.hmod` package.

Upstream: [BlakeBr0/MysticalAgriculture](https://github.com/BlakeBr0/MysticalAgriculture) — licence **MIT**.

| | |
|---|---|
| Upstream mod | Mystical Agriculture ([source](https://github.com/BlakeBr0/MysticalAgriculture)) |
| Ported to | Horizon 0b14f8a, Minecraft Java 26.3, mod API `0.2` |
| Package | `mysticalagriculture.hmod` (install it with the Horizon launcher) |
| Licence | **MIT** — the upstream mod's licence; see [Licence and credit](#licence-and-credit) |

## What this port implements

- The inferium crop and essence loop: grow crops on farmland, harvest essence, craft seeds a

## Not yet ported

- Tiers 2–5 (prudentium/tertium/imperium/supremium essence, essence farmland,
- Inferium farmland and essence farmland tiers (crafting, moisture,
- Machines: growth accelerators, seed reprocessor, infuser, reprocessor, soul
- Tools/armor/weapons, infusion/enchantment, mob soul collection, ore
- No creative tab, no villager planting, no block-colour tint registration for
- **The in-game e2e has not been re-run in the SDK format**: it needs a
- The drop hook **replaces** the rolled list, so a third mod's addition to the

## Installing

1. Install the [Horizon launcher](https://github.com/horizon-rust/horizon/releases) (0.2.70 or newer).
2. Add `mysticalagriculture.hmod` to the instance's mods.
3. The package is pinned to a specific Horizon build; the launcher checks that pin.

## Licence and credit

Mystical Agriculture was created by its upstream authors; the code, models and assets in the original mod
remain theirs and are used here under **MIT**. The Rust in this repository is a clean-room
rewrite for Horizon, not a translation of the original source.

- `LICENSE` — the upstream licence text.
- `LICENSE-NOTICE.md` — what this port carries and where it came from.
- The upstream project: https://github.com/BlakeBr0/MysticalAgriculture

## Technical details

```
horizon-mod.toml   package manifest (id, version, api, [native] pin)
Cargo.toml         the crate; depends on `horizon-mod-api` from the fetched SDK
src/               lib.rs (the one `impl Hooks`), runtime.rs (pure logic + tests), glue
assets/ data/      the content the package ships
tools/             content generators and the e2e scenario
```

- Build: `cargo horizon-mod build` (packages; it does not compile against the game).
- Test: `cargo test`, `cargo clippy --all-targets -- -D warnings`.
- In-game: `ports/tools/launcher-game.sh run mysticalagriculture` in the campaign tree, or install the
  `.hmod` and play; the harness scenario is `tools/e2e.sh`.

This repository is generated from the campaign's port at `ports/mysticalagriculture/`; the port's own
`notes.md` is the full record (decisions, traps, evidence).
