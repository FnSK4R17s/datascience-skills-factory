#!/usr/bin/env python3
"""Build references/emoji-folders.json from a local clone of microsoft/fluentui-emoji.

Output shape (per glyph):
  {
    "<emoji>": {
      "folder": "<Folder Name>",
      "variant": "Default" | "Light" | "Medium-Light" | "Medium" | "Medium-Dark" | "Dark" | null,
      "asset_path": "<Folder Name>/[<Variant>/]3D/<slug>_3d[_<variant-lower>].png"
    }
  }

Paths are relative to `assets/` on GitHub
(https://raw.githubusercontent.com/microsoft/fluentui-emoji/main/assets/<asset_path>).

Usage:
  build-emoji-map.py --clone /tmp/fluentui-emoji --out references/emoji-folders.json
"""
import argparse
import json
from pathlib import Path

SKIN_TONE_ORDER = [
    # (variant folder,       filename suffix, unicode modifier hex)
    ("Default",              "default",       None),
    ("Light",                "light",         "1f3fb"),
    ("Medium-Light",         "medium-light",  "1f3fc"),
    ("Medium",               "medium",        "1f3fd"),
    ("Medium-Dark",          "medium-dark",   "1f3fe"),
    ("Dark",                 "dark",          "1f3ff"),
]

# Folder-name → filename-slug overrides for Microsoft data quirks.
# Keep minimal; add an entry only after verifying against the actual repo tree.
SLUG_OVERRIDES = {
    "O button blood type": "o_button_(blood_type)",
}


def folder_slug(folder_name: str) -> str:
    if folder_name in SLUG_OVERRIDES:
        return SLUG_OVERRIDES[folder_name]
    return folder_name.replace(" ", "_").lower()


def unicode_seq_to_glyph(seq: str) -> str:
    """Convert '1f9d9 200d 2642 fe0f' → actual glyph string."""
    return "".join(chr(int(p, 16)) for p in seq.split())


def build(clone_dir: Path) -> dict:
    out: dict[str, dict] = {}
    assets = clone_dir / "assets"
    for folder in sorted(assets.iterdir()):
        if not folder.is_dir():
            continue
        meta_path = folder / "metadata.json"
        if not meta_path.exists():
            continue
        meta = json.loads(meta_path.read_text())
        slug = folder_slug(folder.name)
        skin_seqs = meta.get("unicodeSkintones")

        if not skin_seqs:
            glyph = meta["glyph"]
            out[glyph] = {
                "folder": folder.name,
                "variant": None,
                "asset_path": f"{folder.name}/3D/{slug}_3d.png",
            }
            continue

        # Skin-toned family. Six variants in fixed order.
        if len(skin_seqs) != len(SKIN_TONE_ORDER):
            raise RuntimeError(
                f"Unexpected unicodeSkintones length for {folder.name}: "
                f"{len(skin_seqs)} (expected {len(SKIN_TONE_ORDER)})"
            )
        for seq, (variant_folder, suffix, _) in zip(skin_seqs, SKIN_TONE_ORDER):
            glyph = unicode_seq_to_glyph(seq)
            out[glyph] = {
                "folder": folder.name,
                "variant": variant_folder,
                "asset_path": f"{folder.name}/{variant_folder}/3D/{slug}_3d_{suffix}.png",
            }
    return out


def verify_on_disk(mapping: dict, clone_dir: Path) -> list[str]:
    assets = clone_dir / "assets"
    missing = []
    for glyph, entry in mapping.items():
        if not (assets / entry["asset_path"]).exists():
            missing.append(f"{glyph!r}: {entry['asset_path']}")
    return missing


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--clone", required=True, type=Path,
                    help="Path to local clone of microsoft/fluentui-emoji")
    ap.add_argument("--out", required=True, type=Path,
                    help="Path to write emoji-folders.json")
    ap.add_argument("--verify", action="store_true",
                    help="Verify each asset_path exists on disk before writing")
    args = ap.parse_args()

    mapping = build(args.clone)
    print(f"Built {len(mapping)} entries from {args.clone}")

    if args.verify:
        missing = verify_on_disk(mapping, args.clone)
        if missing:
            print(f"ERROR: {len(missing)} asset paths do not exist on disk:")
            for m in missing[:10]:
                print(f"  {m}")
            raise SystemExit(1)
        print(f"Verified all {len(mapping)} asset paths exist on disk.")

    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps(mapping, ensure_ascii=False, indent=2, sort_keys=True) + "\n")
    print(f"Wrote {args.out}")


if __name__ == "__main__":
    main()
