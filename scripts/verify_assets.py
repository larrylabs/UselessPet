"""Verify the complete native resource set. Use --update for intentional art changes."""

import argparse
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
RESOURCES = ROOT / "overlay/Sources/UselessPet/Resources"
MANIFEST = ROOT / "docs/assets-manifest.json"


def inventory():
    result = []
    for path in sorted(RESOURCES.rglob("*")):
        if path.is_symlink():
            raise ValueError(f"Symlink is not permitted: {path.relative_to(ROOT)}")
        if path.is_file():
            data = path.read_bytes()
            result.append(
                {
                    "path": path.relative_to(ROOT).as_posix(),
                    "bytes": len(data),
                    "sha256": hashlib.sha256(data).hexdigest(),
                }
            )
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--update", action="store_true")
    args = parser.parse_args()
    actual = inventory()
    names = {Path(item["path"]).name for item in actual}
    for species in ("nara", "mochi", "pando", "lumi"):
        prefix = "nara_hybrid" if species == "nara" else species
        for clip in ("idle", "eat", "play", "celebrate", "sad", "sleep"):
            assert f"{prefix}_{clip}.usdz" in names, (species, clip)
        assert f"{species}_portrait.png" in names, species
    for locale in ("en", "es", "ja", "zh-Hans", "zh-Hant"):
        assert (RESOURCES / f"{locale}.lproj/Localizable.strings").is_file(), locale
    assert actual and all(item["bytes"] < 100 * 1024 * 1024 for item in actual)
    if args.update:
        MANIFEST.write_text(json.dumps({"assets": actual}, indent=2) + "\n")
    else:
        assert json.loads(MANIFEST.read_text())["assets"] == actual, "Resource manifest differs"
    print(f"Verified {len(actual)} resources; {sum(item['bytes'] for item in actual):,} bytes")


if __name__ == "__main__":
    main()
