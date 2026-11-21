#!/usr/bin/env python3
"""Check that the data this package carries is in Minecraft 26.3's dialect.

The same idea as `ports/createaddition/tools/data_shape.py` and
`ports/modularrouters/tools/data_shape.py`, extended to the entry-level
condition this port's crop table uses. Every defect this checks for passes
`cargo horizon-mod check`, `fits` and the unit tests, and shows only when the
data is used in game:

* a **loot pool or entry condition** written the 1.21.1 way:

  - `"conditions": [ {…} ]` (an array) where 26.3 takes the singular
    `"condition": {…}` — on a pool and on an entry alike. `modularrouters`
    measured the result in game: the block dropped **0 of itself** beside a
    vanilla table that dropped 1.
  - `{"type": "minecraft:block_state_property", "properties": {…}}` where 26.3
    spells it `{"type": "minecraft:match_block", "blocks": "…", "state": {…}}`
    (every one of the 1201 block tables in the prepared 26.3 resources uses the
    latter; `minecraft:wheat` is the crop example).
  - `"bonus_rolls"` on a pool, which the 26.3 shape has no place for, and an
    integral `"rolls": 1.0` where 26.3 spells `1`.

* a **recipe ingredient** written as `{"item": "…"}` / `{"tag": "…"}` where 26.3
  takes a bare string (`"minecraft:iron_ingot"`, `"#minecraft:arrows"`).

    python3 tools/data_shape.py <package.hmod> [more.hmod]
    python3 tools/data_shape.py --data data [more dirs/files]

Exit 0 when every carried recipe and loot table is in the 26.3 dialect, 1
otherwise, printing each offender with the value it found.
"""
from __future__ import annotations

import json
import sys
import zipfile
from pathlib import Path

CRAFTING = ("minecraft:crafting_shaped", "minecraft:crafting_shapeless")

# The vanilla tables this file insists the shape of:
#   /home/adlf/Desktop/horizon/.local/horizon-client/26.3/data/minecraft/
#   loot_table/blocks/acacia_button.json   (a pool condition)
#   .../blocks/wheat.json                  (an entry condition, match_block)
VANILLA_EXAMPLE = (
    "data/minecraft/loot_table/blocks/{acacia_button,wheat}.json in the prepared 26.3 resources"
)

# A condition object at 26.3 uses `type`; a bare string is the shortcut spelling.
CONDITION_KEYS = {"survives_explosion", "tool/can_silk_touch", "tool/can_shear",
                  "killed_by_player", "random_chance"}


def recipe_offenders(recipe: dict) -> list[str]:
    """Every ingredient of one recipe that is not a bare item id / #tag string."""
    kind = recipe.get("type", "")
    if kind not in CRAFTING:
        return []
    if kind == "minecraft:crafting_shaped":
        values = list(recipe.get("key", {}).values())
    else:
        values = list(recipe.get("ingredients", []))
    return [json.dumps(value) for value in values if not isinstance(value, str)]


def condition_offenders(value, where: str) -> list[str]:
    """Problems with one condition value (the object under `condition`)."""
    problems: list[str] = []
    if isinstance(value, str):
        return problems
    if not isinstance(value, dict):
        return [f"{where}: condition {json.dumps(value)} is not an object or a string"]
    kind = value.get("type", "")
    if not kind:
        problems.append(f"{where}: condition {json.dumps(value)} has no \"type\" "
                        "(26.3 names it \"type\", not \"condition\")")
    elif kind == "minecraft:block_state_property":
        problems.append(f"{where}: \"type\": \"minecraft:block_state_property\" "
                        "(26.3 uses \"minecraft:match_block\" with \"blocks\" and \"state\")")
    elif kind == "minecraft:match_block" and "properties" in value:
        problems.append(f"{where}: match_block spells its state \"properties\" "
                        "(26.3 uses \"state\")")
    if "terms" in value:
        for index, term in enumerate(value["terms"]):
            problems += condition_offenders(term, f"{where}.terms[{index}]")
    if "term" in value:
        problems += condition_offenders(value["term"], f"{where}.term")
    return problems


def entry_offenders(entry, where: str) -> list[str]:
    """Problems inside one loot entry (or function), recursion included."""
    if not isinstance(entry, dict):
        return []
    problems: list[str] = []
    if "conditions" in entry:
        problems.append(f"{where}: \"conditions\": {json.dumps(entry['conditions'])} "
                        "(26.3 uses \"condition\": {...})")
    if "condition" in entry:
        problems += condition_offenders(entry["condition"], where)
    for index, child in enumerate(entry.get("children", [])):
        problems += entry_offenders(child, f"{where}.children[{index}]")
    for index, function in enumerate(entry.get("functions", [])):
        problems += entry_offenders(function, f"{where}.functions[{index}]")
    return problems


def loot_offenders(table: dict) -> list[str]:
    """Every 1.21.1 piece of one loot table: conditions, key names, roll spelling."""
    problems: list[str] = []
    for index, pool in enumerate(table.get("pools", [])):
        where = f"pool {index}"
        if "conditions" in pool:
            problems.append(f"{where}: \"conditions\": {json.dumps(pool['conditions'])} "
                            "(26.3 uses \"condition\": {...})")
        if "condition" in pool:
            problems += condition_offenders(pool["condition"], where)
        if "bonus_rolls" in pool:
            problems.append(f"{where}: \"bonus_rolls\": {json.dumps(pool['bonus_rolls'])} "
                            "(26.3 has no such key)")
        rolls = pool.get("rolls")
        if isinstance(rolls, float) and rolls.is_integer():
            problems.append(f"{where}: \"rolls\": {rolls} (26.3 spells an integral roll 1)")
        for index, entry in enumerate(pool.get("entries", [])):
            problems += entry_offenders(entry, f"{where}.entries[{index}]")
        for index, function in enumerate(pool.get("functions", [])):
            problems += entry_offenders(function, f"{where}.functions[{index}]")
    # A table-level condition has the same shape as a pool's.
    if "condition" in table:
        problems += condition_offenders(table["condition"], "table")
    if "conditions" in table:
        problems.append(f"table: \"conditions\": {json.dumps(table['conditions'])} "
                        "(26.3 uses \"condition\": {...})")
    return problems


def check_recipe(name: str, parsed, bad: list[str]) -> None:
    for recipe in parsed if isinstance(parsed, list) else [parsed]:
        wrong = recipe_offenders(recipe)
        if wrong:
            bad.append(f"{name}: {recipe.get('type', '?')} ingredient(s) in the 1.21.1 "
                       "object form: " + ", ".join(wrong))
        elif recipe.get("type", "") in CRAFTING:
            print(f"  ok   {name}: {recipe['type'].split(':')[1]}, bare item/tag strings")


def check_loot(name: str, parsed, bad: list[str]) -> None:
    wrong = loot_offenders(parsed)
    if wrong:
        for problem in wrong:
            bad.append(f"{name}: 1.21.1 loot table — {problem}")
    else:
        print(f"  ok   {name}: 26.3 loot table (singular condition, match_block, rolls 1)")


def read(name: str) -> list[tuple[str, str]]:
    """(path, text) for every recipe and loot table under a package or a data dir."""
    found: list[tuple[str, str]] = []
    if name.endswith(".hmod"):
        with zipfile.ZipFile(name) as archive:
            for entry in sorted(archive.namelist()):
                if entry.startswith("data/") and entry.endswith(".json") \
                        and ("/recipe/" in entry or "/loot_table/" in entry):
                    found.append((f"{Path(name).name}:{entry}", archive.read(entry).decode()))
        return found
    root = Path(name)
    files = sorted(root.rglob("*.json")) if root.is_dir() else [root]
    for path in files:
        text = str(path).replace("\\", "/")
        if "/recipe/" in text or "/loot_table/" in text:
            found.append((str(path), path.read_text()))
    return found


def main(argv: list[str]) -> int:
    if not argv:
        print(__doc__.strip(), file=sys.stderr)
        return 2
    names = argv
    if argv[0] == "--data":
        names = argv[1:]
    bad: list[str] = []
    files = 0
    for name in names:
        for path, text in read(name):
            files += 1
            try:
                parsed = json.loads(text)
            except json.JSONDecodeError as error:
                bad.append(f"{path}: not JSON: {error}")
                continue
            if "/loot_table/" in path:
                check_loot(path, parsed, bad)
            else:
                check_recipe(path, parsed, bad)
    if bad:
        for problem in bad:
            print(f"  FAIL {problem}")
        print(f"data shape: {files} file(s) checked, {len(bad)} 1.21.1 problem(s); "
              f"the shape to copy is {VANILLA_EXAMPLE}")
        return 1
    print(f"data shape: {files} recipe/loot file(s), every one in the 26.3 dialect")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
