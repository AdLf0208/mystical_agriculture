//! The game glue: the crop's bone-meal Part and the loot hook.
//!
//! Both read the block state the game hands them and call [`crate::runtime`]; no rule is
//! decided here. The Part is attached to `mysticalagriculture:inferium_crop` alone, so the
//! game asks it only about this mod's crop and no id check is needed inside it — the retired
//! bundle's global `is_valid_bonemeal_target`/`is_bonemeal_success` helpers had to compare
//! the state's name themselves.

use std::sync::OnceLock;

use mod_api::{
    self, BlockKey, BlockMetadata, BlockPart, BlockState, Host, HostBlockStates,
    IsBonemealSuccessEvent, IsValidBonemealTargetEvent, ItemKey, ItemStack, LevelHost,
    LevelRandomHost, LevelRef, LevelSide, LootDropsEvent, RandomSource, Registrar, ServerHost,
};

use crate::runtime::{self, Ground};

/// The state property the crop's age is read from (vanilla `CropBlock.AGE`).
const AGE: &str = "age";

/// The ids the rules compare, resolved once at registration.
///
/// The runtime names blocks and items by id (`mysticalagriculture:inferium_essence`) while
/// the API identifies them by key; this is the translation table.
struct Ids {
    crop: BlockKey,
    essence: ItemKey,
    seeds: ItemKey,
}

static IDS: OnceLock<Ids> = OnceLock::new();

/// Resolve the content's ids and attach the crop's Part. Every id is declared by this same
/// package, and a requested key is checked after all declarations, so a missing one refuses
/// the mod at load instead of failing silently at the first harvest.
pub(super) fn register(r: &mut dyn Registrar) {
    let ids = Ids {
        crop: r.block_key(runtime::CROP),
        essence: r.item_key(runtime::ESSENCE),
        seeds: r.item_key(runtime::SEEDS),
    };
    r.block_part(ids.crop, Crop);
    let _ = IDS.set(ids);
}

/// `MysticalCropBlock`'s two bone-meal answers, attached to the inferium crop.
///
/// Horizon asks a mod block's own three questions ahead of the `BonemealableBlock` its
/// template would give it (`horizon-world/src/level/bonemeal.rs`, `grow_crop`), which is the
/// order the retired bundle injected at.
struct Crop;

#[mod_api::horizon_part]
impl BlockPart for Crop {
    /// `MysticalCropBlock.isValidBonemealTarget` (vanilla `CropBlock`'s `!isMaxAge`): a young
    /// crop takes the meal, a ripe one refuses it and the meal is kept. Asked on both sides,
    /// and the jar's answer does not depend on the side.
    fn is_valid_bonemeal_target(
        &self,
        level: LevelSide<'_>,
        event: &mut IsValidBonemealTargetEvent,
    ) -> Option<bool> {
        let age = age_of(level, event.state)?;
        Some(!runtime::is_ripe(age))
    }

    /// `MysticalCropBlock.isBonemealSuccess`: always false, so a meal spent on a young crop
    /// grows nothing, as in the jar.
    fn is_bonemeal_success(
        &self,
        _level: &mut dyn LevelRandomHost,
        event: &mut IsBonemealSuccessEvent,
    ) {
        event.success = false;
    }
}

/// The `age` of `state` when it is the inferium crop, else `None`.
///
/// The block's Part is only asked about this block, so the name check is a guard against a
/// state table that moved, not a decision.
fn age_of(level: LevelSide<'_>, state: BlockState) -> Option<u8> {
    let level: &dyn LevelHost = match level {
        LevelSide::Server(level) | LevelSide::Client(level) => level,
    };
    age_in(&level.state_string(state)?)
}

/// The `age` in a serialized state (`mysticalagriculture:inferium_crop[age=3]`).
fn age_in(text: &str) -> Option<u8> {
    let (name, properties) = text.split_once('[')?;
    if name != runtime::CROP {
        return None;
    }
    properties
        .strip_suffix(']')?
        .split(',')
        .find_map(|entry| entry.strip_prefix("age="))
        .and_then(|age| age.parse().ok())
}

/// `InferiumCropBlock.getDrops` for a broken crop: replace the rolled list with the jar's
/// own essence and seeds, read from the farmland under it (the content's loot table is the
/// plain-farmland fallback a game without this mod rolls).
pub(super) fn on_loot_drops(host: &mut dyn ServerHost, event: &mut LootDropsEvent<'_>) {
    let Some(ids) = IDS.get() else {
        return;
    };
    let Some((pos, state)) = event.context.block else {
        return;
    };
    if state.block() != ids.crop {
        return;
    }
    let Some(age) = age_of_state(host, state) else {
        return;
    };
    let Some(level) = host.level(event.context.dimension) else {
        return;
    };
    let ground = ground_below(host, level, pos);
    // A young crop draws nothing (the jar returns before either roll), so the level's stream
    // is only drawn from when the jar would draw: the extra-essence roll, then the seed's.
    let harvest = if runtime::is_ripe(age) {
        let harvest = level.with_random(host, |random| {
            runtime::harvest(age, ground, runtime::SECONDARY_SEED_DROPS, || {
                random.next_double()
            })
        });
        let Some(harvest) = harvest else {
            return;
        };
        harvest
    } else {
        runtime::harvest(age, ground, runtime::SECONDARY_SEED_DROPS, || 0.0)
    };

    let drops = &mut *event.drops;
    drops.clear();
    if harvest.essence > 0
        && let Some(stack) = ItemStack::new(ids.essence, harvest.essence)
    {
        drops.push(stack);
    }
    if harvest.seeds > 0
        && let Some(stack) = ItemStack::new(ids.seeds, harvest.seeds)
    {
        drops.push(stack);
    }
}

/// The crop's `age`, read from the host's own state table (the loot hook is given the state
/// itself, not a level to format it through).
fn age_of_state(host: &dyn Host, state: BlockState) -> Option<u8> {
    let metadata = host.block_states();
    let age = state.property(&metadata, AGE).ok().flatten()?;
    age.parse().ok()
}

/// The block under the crop, as the drop rules read it: an unloaded cell, an out-of-height
/// position or an unreadable state is plain ground.
fn ground_below(host: &dyn Host, level: LevelRef, [x, y, z]: [i32; 3]) -> Ground {
    let Some(state) = level.block_state(host, [x, y - 1, z]) else {
        return Ground::Plain;
    };
    let metadata = host.block_states();
    match metadata.name(state.block()) {
        Ok(name) => Ground::from_block(name),
        Err(_) => Ground::Plain,
    }
}
