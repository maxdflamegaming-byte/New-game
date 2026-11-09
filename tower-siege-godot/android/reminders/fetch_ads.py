#!/usr/bin/env python3
"""Fetches the Google Mobile Ads library's classes, to compile Ads.java against (the app itself
gets the library through Gradle, from the dependency addons/reminders adds).
Usage: fetch_ads.py OUT_DIR  ->  OUT_DIR/*.jar and OUT_DIR/version.txt (the version used).
The newest 24.x release is used (the API this game uses has been stable for years); if there is
none, the newest release."""
import io
import re
import sys
import urllib.request
import xml.etree.ElementTree as ET
import zipfile

MAVEN = "https://dl.google.com/dl/android/maven2"
GROUP = "com.google.android.gms"
WANTED = re.compile(r"^play-services-(ads.*|basement|tasks)$")


def get(url):
    with urllib.request.urlopen(url, timeout=60) as r:
        return r.read()


def path(artifact, version, ext):
    return f"{MAVEN}/{GROUP.replace('.', '/')}/{artifact}/{version}/{artifact}-{version}.{ext}"


def pick_version():
    meta = ET.fromstring(get(f"{MAVEN}/{GROUP.replace('.', '/')}/play-services-ads/maven-metadata.xml"))
    versions = [v.text for v in meta.iter("version") if re.fullmatch(r"\d+\.\d+\.\d+", v.text or "")]
    key = lambda v: tuple(int(x) for x in v.split("."))
    v24 = [v for v in versions if v.startswith("24.")]
    return max(v24 or versions, key=key)


def deps(artifact, version):
    pom = ET.fromstring(get(path(artifact, version, "pom")))
    ns = {"m": "http://maven.apache.org/POM/4.0.0"}
    out = []
    for d in pom.findall(".//m:dependencies/m:dependency", ns):
        g = d.findtext("m:groupId", "", ns)
        a = d.findtext("m:artifactId", "", ns)
        v = d.findtext("m:version", "", ns).strip("[]()")
        if g == GROUP and WANTED.match(a) and v:
            out.append((a, v.split(",")[0]))
    return out


def main(out):
    version = pick_version()
    todo, seen = [("play-services-ads", version)], set()
    while todo:
        a, v = todo.pop()
        if a in seen:
            continue
        seen.add(a)
        try:
            aar = zipfile.ZipFile(io.BytesIO(get(path(a, v, "aar"))))
            with open(f"{out}/{a}.jar", "wb") as f:
                f.write(aar.read("classes.jar"))
        except Exception as e:  # an artifact with no classes (or no aar) adds nothing to compile against
            print(f"  ({a} {v}: {e})")
        todo += deps(a, v)
    with open(f"{out}/version.txt", "w") as f:
        f.write(version)
    print(f"Google Mobile Ads {version}: {', '.join(sorted(seen))}")


if __name__ == "__main__":
    main(sys.argv[1])
