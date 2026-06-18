#!/usr/bin/env python3
"""Generate Harmony zh_TW string resources from base (Simplified) via OpenCC."""

import json
import re
import subprocess
import sys
from pathlib import Path

HARMONY = Path(__file__).resolve().parent.parent
BASE = HARMONY / "entry/src/main/resources/base/element/string.json"
ZH_TW_OUT = HARMONY / "entry/src/main/resources/zh_TW/element/string.json"
APP_ZH_TW_OUT = HARMONY / "AppScope/resources/zh_TW/element/string.json"

MANUAL: dict[str, str] = {
    "app_name": "輕羽雲筆記",
    "language_zh": "简体中文",
    "language_zh_tw": "繁體中文",
    "language_en": "English",
    "language_ja": "日本語",
}


def opencc_s2t(text: str) -> str:
    script = "from opencc import OpenCC; import sys; print(OpenCC('s2t').convert(sys.stdin.read()), end='')"
    for py in ("/usr/bin/python3", sys.executable):
        try:
            proc = subprocess.run([py, "-c", script], input=text, text=True, capture_output=True, check=True)
            return proc.stdout
        except (subprocess.CalledProcessError, FileNotFoundError):
            continue
    return text


def main() -> None:
    base_data = json.loads(BASE.read_text(encoding="utf-8"))
    zh_tw_strings = []
    for item in base_data["string"]:
        name = item["name"]
        zh_val = item["value"]
        if name in MANUAL:
            tw_val = MANUAL[name]
        else:
            tw_val = opencc_s2t(zh_val)
        zh_tw_strings.append({"name": name, "value": tw_val})

    names = {x["name"] for x in zh_tw_strings}
    if "language_zh_tw" not in names:
        zh_tw_strings.append({"name": "language_zh_tw", "value": "繁體中文"})

    ZH_TW_OUT.parent.mkdir(parents=True, exist_ok=True)
    ZH_TW_OUT.write_text(
        json.dumps({"string": zh_tw_strings}, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )

    APP_ZH_TW_OUT.parent.mkdir(parents=True, exist_ok=True)
    APP_ZH_TW_OUT.write_text(
        json.dumps({"string": [{"name": "app_name", "value": "輕羽雲筆記"}]}, ensure_ascii=False, indent=2)
        + "\n",
        encoding="utf-8",
    )

    still_simp = 0
    base_by_name = {i["name"]: i["value"] for i in base_data["string"]}
    for x in zh_tw_strings:
        base_val = base_by_name.get(x["name"])
        if (
            base_val is not None
            and x["value"] == base_val
            and re.search(r"[\u4e00-\u9fff]", x["value"])
            and x["name"] not in MANUAL
        ):
            still_simp += 1
    print(f"Wrote {ZH_TW_OUT} ({len(zh_tw_strings)} strings, {still_simp} unchanged han)")


if __name__ == "__main__":
    main()
