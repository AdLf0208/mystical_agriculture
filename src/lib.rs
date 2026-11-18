//! Mystical Agriculture for Horizon — slice 1: the inferium crop, its drops and its
//! bone-meal refusal.
//!
//! Upstream (see `FINDINGS.md`) is `MysticalCropBlock`/`InferiumCropBlock`: a crop on the
//! wheat template whose `getDrops` rolls its own essence and seeds from the farmland under
//! it, and whose `isBonemealSuccess` always says no. The rules — the harvest formula, the
//! secondary-seed chance per farmland tier, ripeness — live in [`runtime`], a plain module
//! with no `mod_api` types, so `cargo test` exercises them without the game. [`support`] is
//! the glue: the block Part and the loot hook, through typed hosts and events.
//!
//! # Where the retired container's hooks went
//!
//! The 2026-11-17 mod-API merge (#16941, launcher ≥ 0.2.70) retired `.hnmod`: the plan, the
//! injection points and the per-hook helper files are gone, and a hook is a typed method or,
//! for a moment that belongs to one block, a Part. The mapping is:
//!
//! | `.hnmod` hook (API) | here |
//! |---|---|
//! | `loot_drops` (75) HEAD helper `loot_drops.rs` | [`Hooks::loot_drops`] — a global hook: the broken block is `event.context.block`, the dimension `event.context.dimension` |
//! | `is_valid_bonemeal_target` (72) HEAD helper `bonemeal_target.rs` | [`BlockPart::is_valid_bonemeal_target`](mod_api::BlockPart::is_valid_bonemeal_target) on the crop's own Part, so no id check |
//! | `is_bonemeal_success` (72) HEAD helper `bonemeal_success.rs` | [`BlockPart::is_bonemeal_success`](mod_api::BlockPart::is_bonemeal_success) on the same Part |
//! | the `content_root` injection and `embedded_content.rs` | gone: one flat `.hmod` carries `assets/` and `data/` itself |
//! | `[[module]] runtime` | `pub mod runtime` |
//! | `[[module]] state` (`support.rs`) | `mod support` |
//!
//! The carried content is declared by this same package, so `register` resolves the crop,
//! the essence and the seeds by id and attaches the Part; a missing id refuses the mod at
//! load instead of failing silently at the first break.
pub mod runtime;
mod support;

use mod_api::{self, Hooks, LootDropsEvent, Registrar, RegistrationContext, ServerHost};

/// The mod has no settings: what it keeps is the content's own ids, resolved once.
#[derive(Default)]
struct Mod;

#[mod_api::horizon_mod]
impl Hooks for Mod {
    /// Resolve the ids the rules compare and attach the crop's bone-meal Part.
    fn register(&self, r: &mut dyn Registrar, _context: &RegistrationContext) {
        support::register(r);
    }

    /// A block broke: an inferium crop drops the jar's essence and seeds, rolled from the
    /// farmland under it, not the plain-farmland table the content ships as a fallback.
    fn loot_drops(&self, host: &mut dyn ServerHost, event: &mut LootDropsEvent<'_>) {
        support::on_loot_drops(host, event);
    }
}
