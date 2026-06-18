#!/usr/bin/env python3
"""Export Flutter zhToJa map to Harmony LocaleJaStrings.ets."""

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent.parent
JA_DART = ROOT / "flutter/lib/l10n/translations_map_ja.dart"
OUT = ROOT / "harmony/entry/src/main/ets/common/utils/LocaleJaStrings.ets"


def parse_map(text: str) -> dict[str, str]:
    pairs = re.findall(r"  '((?:\\'|[^'])*)': '((?:\\'|[^'])*)',", text)
    out: dict[str, str] = {}
    for zh, ja in pairs:
        zh_u = zh.replace("\\n", "\n").replace("\\'", "'").replace("\\$", "$")
        ja_u = ja.replace("\\n", "\n").replace("\\'", "'").replace("\\$", "$")
        out[zh_u] = ja_u
    return out


def esc(s: str) -> str:
    return s.replace("\\", "\\\\").replace("'", "\\'").replace("\n", "\\n")


def main() -> None:
    data = parse_map(JA_DART.read_text(encoding="utf-8"))
    lines = [
        "/** Auto-generated from flutter/lib/l10n/translations_map_ja.dart */",
        "export const LOCALE_JA_MAP: Record<string, string> = {",
    ]
    for zh, ja in sorted(data.items()):
        lines.append(f"  '{esc(zh)}': '{esc(ja)}',")
    lines.append("}")
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(f"Wrote {OUT} ({len(data)} entries)")


if __name__ == "__main__":
    main()
