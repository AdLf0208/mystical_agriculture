#!/usr/bin/env bash
# In-game check for Mystical Agriculture slice 1: the inferium crop/essence
# loop, Minecraft 26.3 on the SDK nightly 0b14f8a.
#
# The mod is one flat `.hmod` now (the 2026-11-18 SDK format), so the game the
# scenario runs on is a **launcher-built** binary that already carries it:
#   horizon-launcher native-build ports/mysticalagriculture --instance <i> --trust-native-code
# and this script is given that binary as GAME. There is no `--dev-mod` path for
# a native package and no `content/` folder any more: `assets/` and `data/` sit
# at the package root beside `src/`.
#
#   1. the package loads and the crop binds age 0..7;
#   2. inferium seeds plant an age-0 crop on farmland (the item's
#      `block`); a stick on farmland places nothing;
#   3. growth is the pin's random tick: with `random_tick_speed 0` the same
#      crops do not change, then with the speed up they advance stages;
#   4. bone meal is refused on our crop (age stays, one meal spent) while the
#      vanilla wheat control grows (the differential);
#   5. a survival break of an age-7 crop drops 1 essence + 1 seed, an age-0
#      crop drops a seed and no essence, and vanilla wheat drops its own items;
#   6. the shaped seeds recipe and the shapeless ingot recipe craft in a real
#      table, with wrong-ingredient controls staying empty;
#   7. unknown ids are refused.
#
# NEGATIVE=1 keeps the scenario but expects the age-0 crop to drop essence:
# the run MUST fail, proving the drop assertion is not vacuous.
# SELFTEST=1 flips the ripe-crop drop assertion (it must FAIL).
# STOCK=<unmodified horizon-client>: first run the same scenario checks against a
# game with no mod, where every id must be unknown — the counterfactual that
# proves the ids came from this package (optional; skipped when unset).
#
# TABLE=1 is the carried loot table's own leg, and it needs the code to be
# **absent** (the mod's `loot_drops` hook replaces the rolled table for this
# crop, so a native game can never exercise it). The pin refuses a native
# package as a content candidate — `horizon-mod-package/src/selection.rs`:
# "Native packages are not content candidates, even through a development path"
# — so this leg mounts a content-only *copy* of the package (the same
# `assets/`/`data/` bytes, `[native]` dropped) as `--dev-mod` on the unmodded
# game (`CONTROL_GAME`, from `launcher-game.sh env`). It then breaks a ripe and
# a young crop and asserts the table's own drops. `SOURCE=` names the package
# copied (default `$PORT/mysticalagriculture.hmod`); pointing it at the previous
# package is the counterfactual: the 1.21.1 table drops nothing, so the leg must
# FAIL.
set -Eeuo pipefail

SELFTEST=${SELFTEST:-0}
TABLE=${TABLE:-0}
DEV_MOD=${DEV_MOD:-}

CLONE=/home/adlf/Desktop/all_the_mods_10_rust_rewrite
PORT=$CLONE/ports/mysticalagriculture
SHARED=$CLONE/ports/_shared/bin/horizon-1d63e0a5
CTL=${CTL:-$SHARED/horizon-ctl}
# A launcher-built game carrying the package; there is no dev-mod path for a native `.hmod`.
GAME=${GAME:-}
RES=${RES:-${HORIZON_RES:-/home/adlf/Desktop/horizon/.local/horizon-client/26.3}}
SOCK=${SOCK:-/tmp/opencode/mysticalagriculture-e2e.sock}
NEGATIVE=${NEGATIVE:-0}
MOD=mysticalagriculture
CROP=$MOD:inferium_crop
ESSENCE=$MOD:inferium_essence
SEEDS=$MOD:inferium_seeds
WORLD=MysticalAgricultureE2E

[ -n "$GAME" ] || {
    echo "GAME must be a launcher-built horizon-client carrying this mod:" >&2
    echo "  horizon-launcher native-build $PORT --instance <i> --trust-native-code" >&2
    exit 1
}
[ -x "$CTL" ] || { echo "missing horizon-ctl: $CTL" >&2; exit 1; }
[ -x "$GAME" ] || { echo "missing horizon-client: $GAME" >&2; exit 1; }
[ -d "$RES/assets" ] || { echo "missing prepared resources: $RES" >&2; exit 1; }
[ -f "$PORT/horizon-mod.toml" ] || { echo "missing manifest: $PORT/horizon-mod.toml" >&2; exit 1; }
[ -f "$PORT/$MOD.hmod" ] || { echo "missing package: $PORT/$MOD.hmod" >&2; exit 1; }

say() { echo "== $* =="; }
fail() { echo "FAIL: $*" >&2; exit 1; }

SCRATCH=$(mktemp -d "${E2E_TMP:-/tmp/opencode}"/mysticalagriculture-home.XXXXXX)
export HORIZON_HOME=$SCRATCH/game
export HORIZON_LAUNCHER_HOME=$SCRATCH/launcher
export XDG_DATA_HOME=$SCRATCH/data
export XDG_CONFIG_HOME=$SCRATCH/config
export HORIZON_NO_AUDIO=1
mkdir -p "$(dirname "$SOCK")"
rm -f "$SOCK"
cd "$SCRATCH"

ctl() { "$CTL" --socket "$SOCK" "$@"; }
end() { ctl command "execute in minecraft:the_end run $1"; }
block_state() { ctl block "$1" "$2" "$3" | jq -r '.state // "unknown"'; }
block_name() { ctl block "$1" "$2" "$3" | jq -r '.block // "unknown"'; }
prop() { echo "$1" | grep -o "$2=[A-Za-z0-9_]*" | head -1 | cut -d= -f2 || true; }
assert_prop() {
    local state=$1 key=$2 want=$3 got
    got=$(prop "$state" "$key")
    [ "$got" = "$want" ] || fail "$state: $key is '$got', expected '$want'"
}
settle() {
    local last=-1 cur pend i
    for i in $(seq 1 60); do
        cur=$(ctl state | jq -r '.chunks // 0')
        pend=$(ctl state | jq -r '.streaming.queued // 0')
        [ "$cur" = "$last" ] && [ "$pend" = 0 ] && return 0
        last=$cur
        ctl wait 10 >/dev/null
    done
}
readback() { # x y z expected-block-id
    local x=$1 y=$2 z=$3 want=$4 st i
    for i in 1 2 3 4 5 6 7 8; do
        st=$(block_state "$x" "$y" "$z")
        case "$st" in "$want"*) echo "$st"; return 0 ;; esac
        ctl wait 5 >/dev/null
    done
    echo "$st"
}
age_at() { prop "$(block_state "$1" "$2" "$3")" age; }

cleanup() {
    local status=$?
    ctl quit >/dev/null 2>&1 || true
    sleep 1
    if [ "${KEEP:-0}" = 1 ]; then
        echo "kept scratch: $SCRATCH" >&2
    else
        rm -rf "$SCRATCH" || true
    fi
    # Last line of every run: `check-e2e-logs.py` reads it as the verdict.
    echo "EXIT:$status"
}
trap cleanup EXIT

launch() { # launch [WORLD]
    local world=${1:-$WORLD}
    rm -f "$SOCK"
    # No `--dev-mod` for a native `.hmod`: it is compiled in by the launcher's native
    # build. The table leg sets DEV_MOD to a content-only copy.
    local args=(--game "$GAME" --world "$world" --seed 20261108 --creative --offscreen --wait
                --game-dir "$SCRATCH/game" --resources "$RES" --render-distance 4)
    [ -z "$DEV_MOD" ] || args+=(--dev-mod "$DEV_MOD")
    "$CTL" --socket "$SOCK" launch "${args[@]}"
    ctl wait-ready 180
    if ctl logs --lines 4000 2>/dev/null | grep -q "content mods not loaded"; then
        ctl logs --lines 4000 | grep "content mods not loaded" >&2
        fail "the package did not load"
    fi
    local pid cwd
    pid=$(ctl state | jq -r '.launch.pid // empty')
    cwd=$(readlink "/proc/$pid/cwd" 2>/dev/null || true)
    echo "the package is built into the game; pid $pid runs in ${cwd:-?}"
    ctl logs --lines 4000 2>/dev/null | grep -E "content from [0-9]+ mod" || true
}

arena() {
    say "The End arena: stone floor at 119, a 7x5 wet-farmland plot at 120, glowstone ceiling"
    end "forceload add 24 0 64 16"
    end "fill 24 119 0 64 119 16 minecraft:stone"
    end "fill 40 120 2 46 120 6 minecraft:farmland[moisture=7]"
    # A stone-ringed water source keeps every plot cell within farmland's 4-block
    # water scan, so a random tick never dries or reverts the farmland.
    end "setblock 43 120 4 minecraft:water"
    end "setblock 42 120 4 minecraft:stone"
    end "setblock 44 120 4 minecraft:stone"
    end "setblock 43 120 3 minecraft:stone"
    end "setblock 43 120 5 minecraft:stone"
    # The End has no skylight; wheat needs light 9, so a glowstone ceiling three
    # blocks up supplies 12 at every crop cell.
    end "fill 38 124 0 48 124 8 minecraft:glowstone"
    end "tp @s 43.5 121 12.5"
    end "difficulty peaceful"
    end "gamerule spawn_mobs false"
    end "gamerule random_tick_speed 0"
    for _ in $(seq 1 30); do
        [ "$(ctl state | jq -r '.dimension')" = minecraft:the_end ] && break
        ctl wait 10
    done
    [ "$(ctl state | jq -r '.dimension')" = minecraft:the_end ] \
        || fail "the player is in $(ctl state | jq -r '.dimension'), not The End"
    ctl wait-ready 180 >/dev/null
    ctl wait 20 >/dev/null
    settle
    echo "player in the_end at $(ctl state | jq -c '.player.position'), chunks settled"
}

# STOCK=<unmodified horizon-client>: the counterfactual. The same checks against a game
# with no mod must find the ids unknown, so a passing default run proves the crop and its
# items came from this package and not from the engine.
stock_leg() {
    echo "== control: the same checks on a game with no mod =="
    local mod_game=$GAME
    GAME=$STOCK
    launch MysticalAgricultureControl
    arena
    ctl command "item replace entity @s hotbar.0 with $SEEDS 1" >/dev/null || true
    ctl wait 4 >/dev/null
    ctl inventory | jq -e --arg i "$SEEDS" '[.hotbar[], .main[] | select(.item == $i)] | length == 0' >/dev/null \
        || fail "the stock game has the seed item, so the ids came from somewhere else: $(ctl inventory | jq -c '{hotbar,main}')"
    ctl command "execute in minecraft:the_end run setblock 44 121 2 $CROP" >/dev/null || true
    ctl wait 4 >/dev/null
    local name
    name=$(block_name 44 121 2)
    [ "$name" = "minecraft:air" ] || fail "the stock game holds $name, so the crop block id was known"
    echo "  without the mod: no seed item, the crop block stayed $name"
    ctl quit >/dev/null 2>&1 || true
    sleep 2
    GAME=$mod_game
    rm -f "$SOCK"
}


# A content-only copy of a package: the same `assets/`/`data/` bytes with `[native]`
# removed from the manifest. The pin refuses a native package as a content candidate
# (`horizon-mod-package/src/selection.rs`: "Native packages are not content candidates,
# even through a development path"), so this copy is how the carried loot table is
# rolled with the mod's code absent. `tree` (the port) is compared file by file, so the
# leg's claim is about the delivered bytes and not about a hand-edited copy.
stage_content_only() { # source(.hmod|dir) dest [tree]
    local source=$1 dest=$2 tree=${3:-}
    rm -rf "$dest"
    mkdir -p "$dest"
    python3 - "$source" "$dest" "$tree" <<'PY' || fail "cannot stage a content-only copy of $source"
import hashlib, sys, zipfile
from pathlib import Path

source, dest, tree = Path(sys.argv[1]), Path(sys.argv[2]), sys.argv[3]
if source.is_dir():
    def read(name: str) -> bytes:
        return (source / name).read_bytes()
    names = sorted(p.relative_to(source).as_posix() for p in source.rglob("*")
                   if p.is_file()
                   and p.relative_to(source).as_posix().split("/")[0] in ("assets", "data"))
else:
    archive = zipfile.ZipFile(source)
    names = sorted(n for n in archive.namelist()
                   if not n.endswith("/") and n.split("/")[0] in ("assets", "data"))

    def read(name: str) -> bytes:
        return archive.read(name)

text = read("horizon-mod.toml").decode()
head, sep, _native = text.partition("\n[native]")
if not sep:
    raise SystemExit(f"{source}: no [native] block to drop")
(dest / "horizon-mod.toml").write_text(head.rstrip("\n") + "\n")
digest = hashlib.sha256()
tree_digest = hashlib.sha256()
for name in names:
    data = read(name)
    (dest / name).parent.mkdir(parents=True, exist_ok=True)
    (dest / name).write_bytes(data)
    digest.update(name.encode() + b"\0" + hashlib.sha256(data).digest())
    if tree:
        tree_file = Path(tree) / name
        if not tree_file.is_file() or tree_file.read_bytes() != data:
            raise SystemExit(f"{name}: the package's bytes differ from {tree_file}")
        tree_digest.update(name.encode() + b"\0" + hashlib.sha256(data).digest())
print(f"content-only copy of {source}: {len(names)} file(s), data sha256 {digest.hexdigest()}")
if tree:
    print(f"  the tree's data/ is the same {len(names)} file(s): sha256 {tree_digest.hexdigest()}")
PY
}

# TABLE=1: break a ripe and a young crop on the unmodded game with the package's data
# mounted as content, and assert the table's own drops. The mod's `loot_drops` hook is
# absent here (no code), which is the only way the rolled table is reachable.
break_crop() { # x z — clears the hand, holds the hoe, stands on the crop and mines it
    ctl command "clear @s" >/dev/null
    ctl give minecraft:iron_hoe 1 >/dev/null || fail "give hoe"
    ctl wait 3 >/dev/null
    ctl select minecraft:iron_hoe >/dev/null
    ctl tp "$1.5" 121 "$2.5" >/dev/null
    ctl wait 4 >/dev/null
    ctl break "$1" 121 "$2"
}

table_leg() {
    local ripe ripe_seeds young young_seeds wheat_item broken
    say "launch (unmodded game, the package's data as --dev-mod: the table is what rolls)"
    launch MysticalAgricultureTable
    arena
    ctl command "gamemode survival @s" >/dev/null
    ctl setblock 42 121 3 "$CROP[age=7]" >/dev/null || fail "setblock ripe crop"
    ctl setblock 44 121 5 "$CROP[age=0]" >/dev/null || fail "setblock young crop"
    ctl wait 6
    [ "$(block_name 42 121 3)" = "$CROP" ] || fail "the table leg's ripe crop did not place"
    [ "$(block_name 44 121 5)" = "$CROP" ] || fail "the table leg's young crop did not place"
    broken=$(break_crop 42 3) || fail "cannot break the ripe crop"
    echo "$broken" | jq -c '{scenario:"table age=7",block,block_before,drops}'
    ripe=$(echo "$broken" | jq -r --arg i "$ESSENCE" '.drops[$i] // 0')
    ripe_seeds=$(echo "$broken" | jq -r --arg i "$SEEDS" '.drops[$i] // 0')
    if [ "$SELFTEST" = 1 ]; then
        echo "(selftest: asserting the table's age-7 crop dropped no essence)"
        [ "$ripe" = 0 ] || fail "the table's age-7 crop dropped $ripe essence (selftest expects 0)"
    else
        [ "$ripe" -ge 1 ] || fail "the table's age-7 crop dropped $ripe essence"
    fi
    [ "$ripe_seeds" -ge 1 ] || fail "the table's age-7 crop dropped $ripe_seeds seeds"
    broken=$(break_crop 44 5) || fail "cannot break the young crop"
    echo "$broken" | jq -c '{scenario:"table age=0",block,block_before,drops}'
    young=$(echo "$broken" | jq -r --arg i "$ESSENCE" '.drops[$i] // 0')
    young_seeds=$(echo "$broken" | jq -r --arg i "$SEEDS" '.drops[$i] // 0')
    [ "$young" = 0 ] || fail "the table's age-0 crop dropped $young essence, expected 0"
    [ "$young_seeds" -ge 1 ] || fail "the table's age-0 crop dropped $young_seeds seeds"
    # The differential: vanilla wheat's own table rolls 1 item beside ours.
    ctl setblock 45 121 5 "minecraft:wheat[age=7]" >/dev/null || fail "setblock wheat control"
    ctl wait 6
    broken=$(break_crop 45 5) || fail "cannot break the wheat control"
    echo "$broken" | jq -c '{scenario:"table wheat age=7",block,block_before,drops}'
    wheat_item=$(echo "$broken" | jq -r '.drops["minecraft:wheat"] // 0')
    [ "$wheat_item" -ge 1 ] || fail "the vanilla wheat control dropped $wheat_item wheat"
    ctl command "gamemode creative @s" >/dev/null
    echo "PASS: the carried table rolled by itself — age 7 -> $ripe essence + $ripe_seeds seeds, age 0 -> $young essence + $young_seeds seeds, and vanilla wheat beside it dropped $wheat_item wheat"
}


if [ "$TABLE" = 1 ]; then
    [ -n "${CONTROL_GAME:-}" ] \
        || fail "TABLE=1 needs CONTROL_GAME: an unmodded Nightly (launcher-game.sh env prints it)"
    [ -x "$CONTROL_GAME" ] || fail "CONTROL_GAME is not executable: $CONTROL_GAME"
    GAME=$CONTROL_GAME
    SOURCE=${SOURCE:-$PORT/$MOD.hmod}
    [ -f "$SOURCE" ] || fail "no package at $SOURCE"
    sha256sum "$SOURCE"
    if [ "$SOURCE" = "$PORT/$MOD.hmod" ]; then
        stage_content_only "$SOURCE" "$SCRATCH/content" "$PORT"
    else
        echo "(counterfactual: not the delivered package, so its bytes are not compared to the tree)"
        stage_content_only "$SOURCE" "$SCRATCH/content"
    fi
    DEV_MOD=$SCRATCH/content
    table_leg
    exit 0
fi

# --------------------------------------------------------------- launch
say "launch (offscreen renderer, The End, a launcher-built game carrying the package)"
if [ -n "${STOCK:-}" ]; then stock_leg; fi
launch
arena

# --------------------------------------------------------------- registry
say "the inferium crop binds every age 0..7"
# A second wet-farmland band for the age read-back (random ticks are off, so it
# only has to be support).
end "fill 28 120 8 35 120 8 minecraft:farmland[moisture=7]"
for age in 0 1 2 3 4 5 6 7; do
    x=$((28 + age))
    ctl setblock "$x" 121 8 "$CROP[age=$age]" >/dev/null || fail "setblock age $age"
done
ctl wait 5
for age in 0 1 2 3 4 5 6 7; do
    x=$((28 + age))
    assert_prop "$(readback "$x" 121 8 "$CROP")" age "$age"
done
echo "crop PASS: ages 0..7 read back"

# --------------------------------------------------------------- planting
say "inferium seeds plant an age-0 crop on farmland; a stick places nothing"
plant() { # x z item expected-block
    ctl command "clear @s" >/dev/null
    ctl give "$3" 4 >/dev/null || fail "cannot give $3"
    ctl wait 3 >/dev/null
    ctl select "$3" >/dev/null || fail "cannot select $3"
    ctl tp "$1.5" 121 "$2.5" >/dev/null
    ctl wait 4 >/dev/null
    ctl look 0 60 >/dev/null
    ctl wait 4 >/dev/null
    ctl interact "$1" 120 "$2" up >/dev/null || fail "cannot click farmland with $3"
    ctl wait 5 >/dev/null
    readback "$1" 121 "$2" "$4"
}
planted=$(plant 40 2 "$SEEDS" "$CROP")
echo "$SEEDS on farmland -> $planted"
case "$planted" in "$CROP"*) ;; *) fail "the seed did not place its crop: $planted" ;; esac
assert_prop "$planted" age 0
planted_stick=$(plant 41 2 minecraft:stick minecraft:air)
[ "$(block_name 41 121 2)" = minecraft:air ] || fail "a stick placed $(block_name 41 121 2)"
echo "seed planting PASS: inferium_crop[age=0] placed; a stick places nothing"

# ---------------------------------------------------------------- growth
say "growth is the random tick: speed 0 keeps the stages, then the crops advance"
ctl setblock 42 121 2 "$CROP[age=3]" >/dev/null || fail "setblock growth crop"
ctl wait 5
a0=$(age_at 40 121 2)
b0=$(age_at 42 121 2)
[ "$a0" = 0 ] && [ "$b0" = 3 ] || fail "growth crops start at $a0/$b0, expected 0/3"
for _ in $(seq 1 10); do ctl wait 20 >/dev/null; done
ctl wait 100 >/dev/null
a1=$(age_at 40 121 2)
b1=$(age_at 42 121 2)
[ "$a1" = 0 ] && [ "$b1" = 3 ] \
    || fail "with random_tick_speed 0 the crops changed: $a0->$a1, $b0->$b1"
echo "control PASS: random_tick_speed 0 keeps ages $a0 and $b0 for 300 ticks"
end "gamerule random_tick_speed 400"
grown=0
for i in $(seq 1 60); do
    ctl wait 20 >/dev/null
    # keep the plot wet even if the engine's drying differs from vanilla's
    end "fill 40 120 2 46 120 6 minecraft:farmland[moisture=7]" >/dev/null 2>&1 || true
    a2=$(age_at 40 121 2)
    b2=$(age_at 42 121 2)
    if [ -n "$a2" ] && [ -n "$b2" ] && [ "$a2" -gt "$a0" ] && [ "$b2" -gt "$b0" ]; then
        grown=$i; break
    fi
done
a2=$(age_at 40 121 2)
b2=$(age_at 42 121 2)
[ "$grown" -gt 0 ] || fail "the crops did not advance under random ticks ($a0->$a2, $b0->$b2)"
echo "growth PASS after $((grown * 20)) ticks: age 0->$a2 and age 3->$b2"
# Let the planted crop reach 7 so the harvest phase reads a real growth result.
for _ in $(seq 1 40); do
    a3=$(age_at 40 121 2)
    [ "$a3" = 7 ] && break
    ctl wait 20 >/dev/null
    end "fill 40 120 2 46 120 6 minecraft:farmland[moisture=7]" >/dev/null 2>&1 || true
done
a3=$(age_at 40 121 2)
echo "the planted crop reached age $a3 of 7 under random ticks"
end "gamerule random_tick_speed 0"

# --------------------------------------------------------------- bone meal
say "bone meal is refused on our crop; the vanilla wheat control grows"
ctl command "gamemode survival @s" >/dev/null
ctl setblock 40 121 3 "$CROP[age=0]" >/dev/null || fail "setblock meal crop"
ctl setblock 41 121 3 "minecraft:wheat[age=0]" >/dev/null || fail "setblock wheat control"
ctl wait 5
[ "$(block_name 40 121 3)" = "$CROP" ] || fail "the meal crop did not place"
[ "$(block_name 41 121 3)" = "minecraft:wheat" ] || fail "the wheat control did not place"
ctl command "clear @s" >/dev/null
ctl give minecraft:bone_meal 8 >/dev/null || fail "give bone meal"
ctl wait 3
ctl select minecraft:bone_meal >/dev/null || fail "select bone meal"
# A right-click at the crosshair (look-at the low part of the crop, then
# use-item) is how the probe applied the meal reliably to a short crop.
meal() { # x z
    ctl tp "$1.5" 121 "$2.5" >/dev/null
    ctl wait 4
    ctl look-at "$1.5" 121.1 "$2.5" >/dev/null
    ctl wait 3
    ctl use-item >/dev/null || fail "use-item on $1,$2 failed"
    ctl wait 10
}
before=$(ctl state | jq -r '.held.count // 0')
meal 40 3
after=$(ctl state | jq -r '.held.count // 0')
ours=$(age_at 40 121 3)
[ "$ours" = 0 ] || fail "bone meal grew our crop to age $ours"
[ "$after" -lt "$before" ] || fail "bone meal was not spent on our crop ($before -> $after)"
echo "our crop PASS: age 0 after bone meal, meal $before -> $after"
# The control: vanilla wheat on the same plot must grow, so the refusal is ours.
meal 41 3
wheat=$(age_at 41 121 3)
[ -n "$wheat" ] && [ "$wheat" -gt 0 ] || fail "the vanilla wheat control did not grow (age $wheat)"
echo "wheat control PASS: bone meal grew vanilla wheat to age $wheat"

# ---------------------------------------------------------------- harvest
say "a survival break drops the jar's loot: ripe = essence + seed, young = seed only"
ctl command "gamemode survival @s" >/dev/null
ctl setblock 42 121 3 "$CROP[age=7]" >/dev/null || fail "setblock ripe crop"
ctl setblock 44 121 5 "$CROP[age=0]" >/dev/null || fail "setblock young crop"
ctl wait 6
broken=$(break_crop 42 3) || fail "cannot break the ripe crop"
echo "$broken" | jq -c '{scenario:"age=7",block,block_before,drops}'
ripe=$(echo "$broken" | jq -r --arg i "$ESSENCE" '.drops[$i] // 0')
ripe_seeds=$(echo "$broken" | jq -r --arg i "$SEEDS" '.drops[$i] // 0')
if [ "$SELFTEST" = 1 ]; then
    echo "(selftest: asserting the age-7 crop dropped no essence)"
    [ "$ripe" = 0 ] || fail "the age-7 crop dropped $ripe essence (selftest expects 0)"
else
    [ "$ripe" -ge 1 ] || fail "the age-7 crop dropped $ripe essence"
fi
[ "$ripe_seeds" -ge 1 ] || fail "the age-7 crop dropped $ripe_seeds seeds"
broken=$(break_crop 44 5) || fail "cannot break the young crop"
echo "$broken" | jq -c '{scenario:"age=0",block,block_before,drops}'
young=$(echo "$broken" | jq -r --arg i "$ESSENCE" '.drops[$i] // 0')
young_seeds=$(echo "$broken" | jq -r --arg i "$SEEDS" '.drops[$i] // 0')
want_young=0
[ "$NEGATIVE" = 1 ] && want_young=1
[ "$young" = "$want_young" ] || fail "the age-0 crop dropped $young essence, expected $want_young"
[ "$young_seeds" -ge 1 ] || fail "the age-0 crop dropped $young_seeds seeds"
# The differential: vanilla wheat on the same plot drops wheat + seeds.
ctl setblock 45 121 5 "minecraft:wheat[age=7]" >/dev/null || fail "setblock wheat harvest"
ctl wait 6
broken=$(break_crop 45 5) || fail "cannot break the wheat control"
echo "$broken" | jq -c '{scenario:"wheat age=7",block,block_before,drops}'
wheat_item=$(echo "$broken" | jq -r '.drops["minecraft:wheat"] // 0')
[ "$wheat_item" -ge 1 ] || fail "the vanilla wheat control dropped $wheat_item wheat"
ctl command "gamemode creative @s" >/dev/null
echo "loot PASS: age 7 -> $ripe essence + $ripe_seeds seeds; age 0 -> $young essence + $young_seeds seeds; wheat -> $wheat_item"

# ---------------------------------------------------------------- recipes
say "crafting: inferium seeds (shaped) and inferium ingot (shapeless)"
python3 "$PORT/tools/craft_check.py" "$SOCK" "$CTL" 30 120 14 || fail "craft_check.py failed"

# ---------------------------------------------------------------- controls
say "unknown ids are refused"
if ctl give "$MOD:not_an_item" 1 >/dev/null 2>&1; then
    fail "give $MOD:not_an_item succeeded"
fi
ctl setblock 60 121 12 "$MOD:not_a_block" >/dev/null 2>&1 || true
[ "$(block_name 60 121 12)" = minecraft:air ] \
    || fail "$MOD:not_a_block became $(block_name 60 121 12)"
echo "unknown ids refused"

echo "PASS: the inferium crop binds ages 0..7; seeds planted an age-0 crop and a stick did not; random_tick_speed 0 held the stages while random ticks advanced 0->$a2 and 3->$b2 (and the planted crop to age $a3); bone meal was refused on our crop but grew vanilla wheat; a ripe crop dropped $ripe essence + $ripe_seeds seeds and a young one $young essence + $young_seeds seeds while vanilla wheat dropped $wheat_item wheat; the shaped seeds recipe and shapeless ingot recipe crafted with empty wrong-ingredient controls; unknown ids were refused"
exit 0
