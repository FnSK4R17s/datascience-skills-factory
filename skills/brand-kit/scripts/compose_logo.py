#!/usr/bin/env python3
"""Composite Fluent 3D emoji PNGs side-by-side into a transparent logo.

Usage:
    python compose_logo.py --images factory_3d.png magnifying_glass_3d.png --output logo.png
    python compose_logo.py --images factory_3d.png magnifying_glass_3d.png --output logo.png --height 168
"""

import argparse
from pathlib import Path

try:
    from PIL import Image
except ImportError:
    print("ERROR: Pillow is required. Install with: pip install Pillow")
    raise SystemExit(1)


def compose_logo(image_paths: list[str], output: str, height: int = 168, gap: int = 8):
    """Composite emoji PNGs side-by-side at equal height."""
    images = []
    for path in image_paths:
        img = Image.open(path).convert("RGBA")
        # Scale to target height, preserving aspect ratio
        scale = height / img.height
        new_width = int(img.width * scale)
        img = img.resize((new_width, height), Image.LANCZOS)
        images.append(img)

    # Calculate total canvas size
    total_width = sum(img.width for img in images) + gap * (len(images) - 1)
    canvas = Image.new("RGBA", (total_width, height), (0, 0, 0, 0))

    # Paste each emoji
    x = 0
    for img in images:
        canvas.paste(img, (x, 0), img)
        x += img.width + gap

    canvas.save(output, "PNG")
    print(f"Logo saved: {output} ({total_width}x{height})")


def main():
    parser = argparse.ArgumentParser(description="Composite Fluent 3D emoji PNGs into a logo")
    parser.add_argument("--images", nargs="+", required=True, help="Paths to emoji PNG files (in order)")
    parser.add_argument("--output", required=True, help="Output logo.png path")
    parser.add_argument("--height", type=int, default=168, help="Target height in pixels (default: 168)")
    parser.add_argument("--gap", type=int, default=8, help="Gap between emojis in pixels (default: 8)")
    args = parser.parse_args()

    for path in args.images:
        if not Path(path).exists():
            print(f"ERROR: Image not found: {path}")
            raise SystemExit(1)

    compose_logo(args.images, args.output, args.height, args.gap)


if __name__ == "__main__":
    main()
