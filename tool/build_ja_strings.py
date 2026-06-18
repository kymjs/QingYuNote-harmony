#!/usr/bin/env python3
"""Generate Harmony ja_JP string resources from en_US + ja translations."""

import json
import re
import sys
from pathlib import Path

FLUTTER_TOOL = Path(__file__).resolve().parent.parent.parent / "flutter" / "tool"
sys.path.insert(0, str(FLUTTER_TOOL))
from ja_translation_data import EN_JA, ZH_JA  # noqa: E402

HARMONY = Path(__file__).resolve().parent.parent.parent / "harmony"
EN_US = HARMONY / "entry/src/main/resources/en_US/element/string.json"
BASE = HARMONY / "entry/src/main/resources/base/element/string.json"
JA_OUT = HARMONY / "entry/src/main/resources/ja_JP/element/string.json"
APP_JA_OUT = HARMONY / "AppScope/resources/ja_JP/element/string.json"


def ja_for_en_value(en: str, name: str) -> str:
    if en in EN_JA:
        return EN_JA[en]
    # name-based hints
    name_hints = {
        "language_ja": "日本語",
        "language_zh": "简体中文",
        "language_en": "English",
        "app_name": "軽羽クラウドノート",
    }
    if name in name_hints:
        return name_hints[name]
    return en


def main() -> None:
    en_data = json.loads(EN_US.read_text(encoding="utf-8"))
    base_data = json.loads(BASE.read_text(encoding="utf-8"))
    base_names = {x["name"]: x["value"] for x in base_data["string"]}

    ja_strings = []
    for item in en_data["string"]:
        name = item["name"]
        en_val = item["value"]
        zh_val = base_names.get(name, "")
        ja_val = ZH_JA.get(zh_val)
        if ja_val is None and zh_val:
            from ja_translation_data import translate_ja_from_zh
            ja_val = translate_ja_from_zh(zh_val)
        if ja_val is None:
            ja_val = ja_for_en_value(en_val, name)
        ja_strings.append({"name": name, "value": ja_val})

    # add language_ja if missing
    names = {x["name"] for x in ja_strings}
    if "language_ja" not in names:
        ja_strings.append({"name": "language_ja", "value": "日本語"})

    JA_OUT.parent.mkdir(parents=True, exist_ok=True)
    JA_OUT.write_text(
        json.dumps({"string": ja_strings}, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )

    APP_JA_OUT.parent.mkdir(parents=True, exist_ok=True)
    APP_JA_OUT.write_text(
        json.dumps({"string": [{"name": "app_name", "value": "軽羽クラウドノート"}]}, ensure_ascii=False, indent=2)
        + "\n",
        encoding="utf-8",
    )

    still_en = 0
    en_by_name = {i["name"]: i["value"] for i in en_data["string"]}
    for x in ja_strings:
        en_val = en_by_name.get(x["name"], "")
        if x["value"] == en_val and not re.search(r"[\u3040-\u30ff\u4e00-\u9fff]", x["value"]):
            still_en += 1
    print(f"Wrote {JA_OUT} ({len(ja_strings)} strings, {still_en} still English)")


if __name__ == "__main__":
    main()
