# Mystical Agriculture 8.0.29 — upstream findings (slice 1: inferium)

Read from `BlakeBr0/MysticalAgriculture`, branch `1.21`, commit
`f38a092852538905de72a999f462936b71181554` (`Release 8.0.29`). Behaviour only;
the Rust is a clean-room rewrite (see `notes.md`).

## The crop is a vanilla `CropBlock` with a custom drop table

`MysticalCropBlock extends CropBlock` and copies `Blocks.WHEAT`'s properties
(`block/MysticalCropBlock.java:33`), so it has the wheat template's
`age` 0..7, `getGrowthSpeed` (farmland moisture and neighbours), the light-9
`canSurvive`, and vanilla's random-tick growth. Its own `randomTick`
(`:44-49`) only asks `canGrow` and then calls `super.randomTick`; `canGrow`
(`:136-160`) checks, in order: a crux block two below (only some crops), the
tier's effective farmland when `requiresEffectiveFarmland` is on (and the crop
is not inferium), and required biomes. For **inferium** none of these applies
(no crux, the config defaults to `false`, no biomes), so its growth is exactly
vanilla wheat's crop random tick. `getShape` (`:52-54`) returns one 4-pixel-high
box for every age (`SHAPE`, `:30`), unlike wheat's age-dependent outline.

Bone meal: `isBonemealSuccess` returns **false** (`:39-41`) and
`isValidBonemealTarget` (`:114-121`) is `canGrow && super` — true for a young
crop. Vanilla therefore spends the meal and grows nothing.

## Harvest drops (`MysticalCropBlock.getDrops` :62-104, `InferiumCropBlock.getDrops` :21-50)

Read at the mature age (`age == 7`); any younger age drops one seed and no
essence.

`InferiumCropBlock` (the block this slice ships) overrides the essence count:

| block under the crop | essence | extra |
|---|---:|---|
| vanilla farmland / anything not an essence farmland | 1 | — |
| essence farmland tier 1 (inferium) | 1 | — |
| tier 2 (prudentium) | 1 | tier > 1 and even: +1 on a `random < 0.5` |
| tier 3 (tertium) | 2 | — |
| tier 4 (imperium) | 2 | +1 on a `random < 0.5` |
| tier 5 (supremium) | 3 | — |

Formula: `(int)(0.5 * tier + 0.5)`, then `tier > 1 && tier % 2 == 0 && Math.random() < 0.5`
adds one (`InferiumCropBlock.java:33-39`). This override does **not** drop
fertilized essence (the base class does).

Seeds: one, plus a second when `secondarySeedDrops` (default true,
`config/ModConfigs.java:49-51`) and `Math.random() < getSecondaryChance(below)`.
`Crop.getSecondaryChance` (`api/crop/Crop.java:404-414`) is the tier's 0.1 base
on an essence farmland plus 0.1 when it is the tier's own effective farmland;
tier 1's effective farmland is inferium farmland
(`lib/ModCorePlugin.java:41`), so inferium reaches **0.2 on inferium farmland
and 0.0 on plain farmland**. Draw order: the even-tier essence roll first, then
the seed roll.

## Content and recipes (the jar's own files)

- Block `mysticalagriculture:inferium_crop`: blockstate age 0..6 uses the shared
  `mystical_resource_crop_<age>` cross models; age 7 uses `inferium_crop`
  (`mystical_resource_crop_7` with `block/flower/inferium_flower`).
- Items `inferium_seeds` (`item/seeds/inferium_seeds`), `inferium_essence`
  (`item/inferium_essence`), `inferium_ingot` (`item/inferium_ingot`).
- `inferium_seeds`: shaped `EEE/ESE/EEE` — 8 essence around a wheat seed.
- `inferium_ingot`: shapeless — one `prosperity_ingot` plus two essence.
  **The prosperity ingot is not craftable in this slice** (its recipe needs
  prosperity shards, whose ore/crop is a later slice), so the ingot item is
  carried as a prerequisite and given in the harness.
- No loot table JSON exists for the crop in the jar; drops are code.

Config defaults read but not carried (no config file system in this slice):
`secondarySeedDrops=true`, `fertilizedEssenceChance=0.1`,
`requiresEffectiveFarmland=false` (`config/ModConfigs.java:46-54`).

## Rest of the mod (next slices, not built)

Tiers 2–5 (essence, farmland, cruxes, seeds), the other ~120 crops and their
seed crafting, essence farmland blocks and their moisture/watering-can
behaviour, the machine set (growth accelerators, seed reprocessor, infuser,
reprocessor, soul jars), tools/armor/weapons, the infusion/enchantment system,
mob soul collection, ore worldgen, Patchouli guide, config, and the Jade/Curios
integrations. The jar also depends on BlakeBr0's `cucumber` library, which this
rewrite does not need.

## How the rewrite differs (and why)

- Growth is the pin's crop/wheat template random tick, not a native growth
  hook: the jar's inferium crop does nothing but call vanilla (above).
- The drop formula lives in `runtime.rs` and runs from `native_loot_drops`
  (API 75) so the farmland-dependent essence/seed counts are exact; the content
  loot table is the plain-farmland fallback (identical on vanilla farmland).
- The two draws use the server level's own random (`native_level_random`,
  API 43) instead of Java's `Math.random()`; the order is preserved.
- Bone meal is refused through API 72's three questions; `is_valid_bonemeal_target`
  must answer first or the template path runs and grows the crop (found in-game).
- The crop's 4-pixel outline is declared in content, with an explicit empty
  collision table (vanilla wheat's outline grows with age).
