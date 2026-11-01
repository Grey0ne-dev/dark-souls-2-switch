#!/usr/bin/env python3
"""Extract the official devkitPro OCI toolchain locally; no Docker daemon needed."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import tarfile
import urllib.request

ROOT = Path(__file__).resolve().parents[1]
REPO = "devkitpro/devkita64"


def request(url, token=None, accept=None):
    headers = {}
    if token:
        headers["Authorization"] = "Bearer " + token
    if accept:
        headers["Accept"] = accept
    return urllib.request.urlopen(urllib.request.Request(url, headers=headers), timeout=120)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--install", action="store_true")
    args = parser.parse_args()
    downloads = ROOT / "_tools/downloads"
    downloads.mkdir(parents=True, exist_ok=True)
    token = json.load(request("https://auth.docker.io/token?service=registry.docker.io&scope=repository:" + REPO + ":pull"))["token"]
    base = "https://registry-1.docker.io/v2/" + REPO
    accept = ", ".join(["application/vnd.oci.image.index.v1+json", "application/vnd.docker.distribution.manifest.list.v2+json", "application/vnd.oci.image.manifest.v1+json", "application/vnd.docker.distribution.manifest.v2+json"])
    manifest = json.load(request(base + "/manifests/latest", token, accept))
    if "manifests" in manifest:
        chosen = next(m for m in manifest["manifests"] if m.get("platform", {}).get("architecture") == "amd64" and m["platform"].get("os") == "linux")
        manifest = json.load(request(base + "/manifests/" + chosen["digest"], token, accept))
    (downloads / "devkita64-manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    print("Official image:", REPO, flush=True)
    print("Download size: %.1f MiB" % (sum(l["size"] for l in manifest["layers"]) / 2**20), flush=True)
    if not args.install:
        return
    dest = ROOT / "_tools/devkitpro"
    dest.mkdir(parents=True, exist_ok=True)
    prefix = "opt/devkitpro/"
    for i, layer in enumerate(manifest["layers"]):
        digest = layer["digest"].split(":")[1]
        archive = downloads / (digest + ".tar.gz")
        print("Layer %d/%d: %.1f MiB" % (i + 1, len(manifest["layers"]), layer["size"] / 2**20), flush=True)
        if not archive.exists() or archive.stat().st_size != layer["size"]:
            with request(base + "/blobs/" + layer["digest"], token) as src, archive.open("wb") as out:
                shutil.copyfileobj(src, out, 1024 * 1024)
        with archive.open("rb") as src:
            actual = hashlib.file_digest(src, "sha256").hexdigest()
        if actual != digest:
            raise RuntimeError("OCI layer digest mismatch: " + str(archive))
        with tarfile.open(archive) as tar:
            count = 0
            for member in tar:
                name = member.name.removeprefix("./")
                if not name.startswith(prefix):
                    continue
                relative = name[len(prefix):]
                if not relative or any(p == ".." for p in Path(relative).parts):
                    continue
                if Path(relative).parts[0] not in {"devkitA64", "libnx", "portlibs", "tools", "cmake"}:
                    continue
                if Path(relative).name.startswith(".wh."):
                    raise RuntimeError("OCI whiteout needs handling: " + name)
                member.name = relative
                if member.islnk():
                    link = member.linkname.removeprefix("./")
                    if not link.startswith(prefix):
                        raise RuntimeError("Hardlink outside devkitPro: " + link)
                    member.linkname = link[len(prefix):]
                if member.issym() and member.linkname.startswith("/opt/devkitpro/"):
                    member.linkname = os.path.relpath(dest / member.linkname[len("/opt/devkitpro/"):], (dest / relative).parent)
                tar.extract(member, dest, filter="data")
                count += 1
        print("Extracted %d toolchain entries" % count, flush=True)
    print("Toolchain:", dest, flush=True)


if __name__ == "__main__":
    main()
