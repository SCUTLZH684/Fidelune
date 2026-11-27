"""Fetch, SHA-256 verify, and extract pinned official Un4seen BASS iOS XCFrameworks."""

from __future__ import annotations

import argparse
import hashlib
import io
import json
from pathlib import Path
import shutil
import sys
import urllib.request
import zipfile


ROOT = Path(__file__).resolve().parents[1]
DEPS_FILE = Path(__file__).resolve().with_name("bass_deps.json")


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def load_manifest(path: Path = DEPS_FILE) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def download_or_read_cached(pkg: dict, cache_dir: Path | None) -> bytes:
    archive = pkg["archive"]
    expected = pkg["sha256"]
    if cache_dir is not None:
        cache_dir.mkdir(parents=True, exist_ok=True)
        cached = cache_dir / archive
        if cached.is_file():
            data = cached.read_bytes()
            if sha256_bytes(data) == expected:
                return data
            print(f"[warn] Cached {archive} failed SHA-256; re-downloading", file=sys.stderr)

    req = urllib.request.Request(pkg["url"], headers={"User-Agent": "Fidelune-CI/1.0"})
    with urllib.request.urlopen(req, timeout=45) as resp:
        data = resp.read()

    actual = sha256_bytes(data)
    if actual != expected:
        raise RuntimeError(
            f"SHA-256 mismatch for {archive}: expected {expected}, got {actual}"
        )

    if cache_dir is not None:
        (cache_dir / archive).write_bytes(data)
    return data


def extract_package(pkg: dict, archive_bytes: bytes, frameworks_dir: Path, headers_dir: Path) -> None:
    xcf_prefix = pkg["xcframework"] + "/"
    header_name = pkg["header"]
    target_xcf = frameworks_dir / pkg["xcframework"]
    if target_xcf.exists():
        shutil.rmtree(target_xcf)

    found_header = False
    found_xcf_files = 0
    with zipfile.ZipFile(io.BytesIO(archive_bytes)) as zf:
        for info in zf.infolist():
            name = info.filename
            if info.is_dir():
                continue
            if name == header_name or name.endswith("/" + header_name):
                if name.count("/") == 0:
                    (headers_dir / header_name).write_bytes(zf.read(name))
                    found_header = True
            elif name.startswith(xcf_prefix):
                dest = frameworks_dir / name
                dest.parent.mkdir(parents=True, exist_ok=True)
                # Preserve symlinks inside .framework bundles if present in zip
                is_symlink = ((info.external_attr >> 16) & 0o170000) == 0o120000
                if is_symlink:
                    link_target = zf.read(name).decode("utf-8")
                    if dest.exists() or dest.is_symlink():
                        dest.unlink()
                    dest.symlink_to(link_target)
                else:
                    dest.write_bytes(zf.read(name))
                    mode = (info.external_attr >> 16) & 0o777
                    if mode:
                        dest.chmod(mode)
                found_xcf_files += 1

    if not found_header:
        raise RuntimeError(f"Header {header_name} not found in {pkg['archive']}")
    if found_xcf_files == 0:
        raise RuntimeError(f"XCFramework {pkg['xcframework']} not found in {pkg['archive']}")


def fetch_all(
    frameworks_dir: Path,
    headers_dir: Path,
    cache_dir: Path | None = None,
    manifest_path: Path = DEPS_FILE,
) -> list[dict]:
    manifest = load_manifest(manifest_path)
    frameworks_dir.mkdir(parents=True, exist_ok=True)
    headers_dir.mkdir(parents=True, exist_ok=True)

    installed = []
    for pkg in manifest["packages"]:
        data = download_or_read_cached(pkg, cache_dir)
        extract_package(pkg, data, frameworks_dir, headers_dir)
        installed.append({
            "name": pkg["name"],
            "version": pkg["version"],
            "archive": pkg["archive"],
            "sha256": pkg["sha256"],
            "bytes": len(data),
        })
        print(f"Verified & extracted {pkg['name']} {pkg['version']} ({len(data)} bytes)")
    return installed


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--cache-dir",
        type=Path,
        default=ROOT / ".bass_cache",
        help="Optional zip cache directory",
    )
    parser.add_argument(
        "--frameworks-dir",
        type=Path,
        default=ROOT / "ios" / "Frameworks",
    )
    parser.add_argument(
        "--headers-dir",
        type=Path,
        default=ROOT / "ios" / "BASS_Headers",
    )
    args = parser.parse_args()
    installed = fetch_all(args.frameworks_dir, args.headers_dir, args.cache_dir)
    out_manifest = args.frameworks_dir / "bass_verified.json"
    out_manifest.write_text(json.dumps({"packages": installed}, indent=2) + "\n", encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
