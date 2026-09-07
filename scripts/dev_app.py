"""Build and atomically install a self-contained local macOS Dev application."""

import argparse
import hashlib
import importlib.metadata
import json
import os
import plistlib
import shutil
import subprocess
import sys
import tempfile
from datetime import datetime
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
BUILD = ROOT / "build" / "dev-app"
APP_NAME = "UselessPet Dev.app"
BUNDLE_ID = "io.github.LarryZYN.UselessPet.Dev"


def command(*args, **kwargs):
    return subprocess.run(args, check=True, **kwargs)


def validate(app):
    info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
    if info.get("CFBundleIdentifier") != BUNDLE_ID or not info.get("UselessPetDev"):
        raise RuntimeError(f"Refusing to replace a different application: {app}")
    manifest = json.loads((app / "Contents/Resources/dev-manifest.json").read_text())
    for relative, digest in manifest["files"].items():
        path = app / relative
        if not path.is_file() or hashlib.sha256(path.read_bytes()).hexdigest() != digest:
            raise RuntimeError(f"Dev app verification failed: {relative}")
    command("/usr/bin/codesign", "--verify", "--deep", "--strict", str(app))
    print(f"Verified {len(manifest['files'])} bundled files: {info['UselessPetDevBuild']}")
    return info


def package(binary_dir):
    BUILD.mkdir(parents=True, exist_ok=True)
    app = BUILD / APP_NAME
    if app.exists():
        shutil.rmtree(app)
    macos = app / "Contents/MacOS"
    resources = app / "Contents/Resources"
    macos.mkdir(parents=True)
    resources.mkdir()
    shutil.copy2(binary_dir / "UselessPet", macos / "UselessPet")
    shutil.copytree(
        binary_dir / "UselessPet_UselessPet.bundle", resources / "UselessPet_UselessPet.bundle"
    )
    ignore = shutil.ignore_patterns("__pycache__", "*.pyc", "*.pyo")
    backend = resources / "Backend"
    backend.mkdir()
    shutil.copytree(ROOT / "backend/uselesspet", backend / "uselesspet", ignore=ignore)
    shutil.copy2(ROOT / "scripts/dev_bootstrap.py", backend / "dev_bootstrap.py")
    distribution = importlib.metadata.distribution("websockets")
    shutil.copytree(distribution.locate_file("websockets"), backend / "websockets", ignore=ignore)
    for item in distribution.files or []:
        if ".dist-info/" in str(item):
            source = distribution.locate_file(item)
            target = backend / str(item)
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source, target)
    # uv's relocatable CPython distribution includes its standard library and licenses.
    runtime = resources / "Python"
    shutil.copytree(Path(sys.base_prefix).resolve(), runtime, symlinks=True, ignore=ignore)
    python_name = Path(sys.executable).resolve().name
    python = runtime / "bin" / python_name
    if not python.is_file():
        raise RuntimeError("The uv Python distribution does not contain the expected interpreter")
    command(
        str(python),
        "-I",
        "-S",
        "-B",
        "-c",
        "import ssl, sqlite3, sys; print('Bundled Python:', sys.version.split()[0])",
    )
    iconset = BUILD / "Dev.iconset"
    iconset.mkdir(exist_ok=True)
    portrait = ROOT / "overlay/Sources/UselessPet/Resources/nara_portrait.png"
    for points in (16, 32, 128, 256, 512):
        for scale in (1, 2):
            pixels = str(points * scale)
            name = f"icon_{points}x{points}{'@2x' if scale == 2 else ''}.png"
            command(
                "/usr/bin/sips",
                "--resampleHeightWidth",
                pixels,
                pixels,
                str(portrait),
                "--out",
                str(iconset / name),
                stdout=subprocess.DEVNULL,
            )
    command(
        "/usr/bin/iconutil", "-c", "icns", str(iconset), "-o", str(resources / "UselessPetDev.icns")
    )
    now = datetime.now().astimezone()
    revision = subprocess.check_output(
        ["git", "rev-parse", "--short=12", "HEAD"], cwd=ROOT, text=True
    ).strip()
    dirty = bool(subprocess.check_output(["git", "status", "--porcelain"], cwd=ROOT))
    label = f"{now:%Y-%m-%d %H:%M %Z} · {revision}{' + local changes' if dirty else ''}"
    info = plistlib.loads((ROOT / "overlay/Support/Info.plist").read_bytes())
    info.update(
        CFBundleIdentifier=BUNDLE_ID,
        CFBundleName="UselessPet Dev",
        CFBundleDisplayName="UselessPet Dev",
        CFBundleExecutable="UselessPet",
        CFBundlePackageType="APPL",
        CFBundleInfoDictionaryVersion="6.0",
        CFBundleVersion=now.strftime("%Y%m%d%H%M%S"),
        LSMinimumSystemVersion="15.0",
        CFBundleIconFile="UselessPetDev.icns",
        UselessPetDev=True,
        UselessPetDevBuild=label,
        UselessPetPython=f"Python/bin/{python_name}",
    )
    (app / "Contents/Info.plist").write_bytes(plistlib.dumps(info))
    for name in ("LICENSE", "THIRD_PARTY_NOTICES.md", "ASSET_LICENSE.md"):
        shutil.copy2(ROOT / name, resources / name)
    # Sign copied native libraries first; never modify the developer's uv interpreter.
    native = {
        python.resolve(),
        *(runtime.rglob("*.dylib")),
        *(runtime.rglob("*.so")),
        *(backend.rglob("*.so")),
    }
    for file in sorted(native):
        if file.is_file():
            command(
                "/usr/bin/codesign", "--force", "--sign", "-", str(file), stderr=subprocess.DEVNULL
            )
    command(
        "/usr/bin/codesign",
        "--force",
        "--sign",
        "-",
        str(macos / "UselessPet"),
        stderr=subprocess.DEVNULL,
    )
    # The app signature covers the executable. Including its signed hash here would
    # create a cycle, because the executable signature also seals this manifest.
    files = {
        str(path.relative_to(app)): hashlib.sha256(path.read_bytes()).hexdigest()
        for path in sorted(app.rglob("*"))
        if path.is_file() and path != macos / "UselessPet" and "_CodeSignature" not in path.parts
    }
    (resources / "dev-manifest.json").write_text(
        json.dumps({"build": label, "files": files}, indent=2) + "\n"
    )
    command(
        "/usr/bin/codesign", "--force", "--deep", "--sign", "-", str(app), stderr=subprocess.DEVNULL
    )
    validate(app)
    print(f"Built {app}")


def install(destination):
    source = BUILD / APP_NAME
    validate(source)
    destination = destination.expanduser().resolve()
    destination.mkdir(parents=True, exist_ok=True)
    target = destination / APP_NAME
    if target.exists():
        validate(target)
    command(str(BUILD / "dev-control"))
    with tempfile.TemporaryDirectory(
        prefix=".UselessPetDev-install-", dir=destination
    ) as temporary:
        temporary = Path(temporary)
        incoming = temporary / APP_NAME
        previous = temporary / "previous.app"
        command("/usr/bin/ditto", str(source), str(incoming))
        validate(incoming)
        existed = target.exists()
        if existed:
            os.rename(target, previous)
        try:
            os.rename(incoming, target)
            validate(target)
        except BaseException:
            if target.exists():
                shutil.rmtree(target)
            if existed:
                os.rename(previous, target)
            raise
    command("/usr/bin/open", str(target))
    print(f"Installed and opened {target}")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("action", choices=["package", "install", "verify"])
    parser.add_argument("--binary-dir", type=Path)
    parser.add_argument("--applications-dir", type=Path, default=Path("/Applications"))
    parser.add_argument("--app", type=Path, default=BUILD / APP_NAME)
    args = parser.parse_args()
    if args.action == "package":
        if args.binary_dir is None:
            parser.error("--binary-dir is required to package")
        package(args.binary_dir)
    elif args.action == "install":
        install(args.applications_dir)
    else:
        validate(args.app)


if __name__ == "__main__":
    main()
