#!/usr/bin/env python3
"""Export Flutter zhToZhTw map to Harmony LocaleZhTwStrings.ets."""

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent.parent
ZH_TW_DART = ROOT / "flutter/lib/l10n/translations_map_zh_tw.dart"
OUT = ROOT / "harmony/entry/src/main/ets/common/utils/LocaleZhTwStrings.ets"


def parse_map(text: str) -> dict[str, str]:
    pairs = re.findall(r"  '((?:\\'|[^'])*)': '((?:\\'|[^'])*)',", text)
    out: dict[str, str] = {}
    for zh, tw in pairs:
        zh_u = zh.replace("\\n", "\n").replace("\\'", "'").replace("\\$", "$")
        tw_u = tw.replace("\\n", "\n").replace("\\'", "'").replace("\\$", "$")
        out[zh_u] = tw_u
    return out


def esc(s: str) -> str:
    return s.replace("\\", "\\\\").replace("'", "\\'").replace("\n", "\\n")


def main() -> None:
    if not ZH_TW_DART.exists():
        raise SystemExit(f"Missing {ZH_TW_DART}")
    data = parse_map(ZH_TW_DART.read_text(encoding="utf-8"))
    lines = [
        "/** Auto-generated from flutter/lib/l10n/translations_map_zh_tw.dart */",
        "export const LOCALE_ZH_TW_MAP: Record<string, string> = {",
    ]
    for zh, tw in sorted(data.items()):
        lines.append(f"  '{esc(zh)}': '{esc(tw)}',")
    lines.append("}")
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(f"Wrote {OUT} ({len(data)} entries)")


if __name__ == "__main__":
    main()
