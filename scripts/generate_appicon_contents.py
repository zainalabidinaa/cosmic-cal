#!/usr/bin/env python3

import json
import sys
from pathlib import Path

appiconset_dir = Path(sys.argv[1])

images = [
    # iPhone
    {"idiom": "iphone", "size": "20x20", "scale": "2x", "filename": "icon-20@2x.png"},
    {"idiom": "iphone", "size": "20x20", "scale": "3x", "filename": "icon-20@3x.png"},
    {"idiom": "iphone", "size": "29x29", "scale": "2x", "filename": "icon-29@2x.png"},
    {"idiom": "iphone", "size": "29x29", "scale": "3x", "filename": "icon-29@3x.png"},
    {"idiom": "iphone", "size": "40x40", "scale": "2x", "filename": "icon-40@2x.png"},
    {"idiom": "iphone", "size": "40x40", "scale": "3x", "filename": "icon-40@3x.png"},
    {"idiom": "iphone", "size": "60x60", "scale": "2x", "filename": "icon-60@2x.png"},
    {"idiom": "iphone", "size": "60x60", "scale": "3x", "filename": "icon-60@3x.png"},

    # App Store
    {"idiom": "ios-marketing", "size": "1024x1024", "scale": "1x", "filename": "icon-1024.png"},
]

contents = {
    "images": images,
    "info": {"author": "xcode", "version": 1},
}

(appiconset_dir / "Contents.json").write_text(json.dumps(contents, indent=2) + "\n")
