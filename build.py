"""Builds dist/Skill Tree.zip for the Steam Workshop uploader.

The zip holds mods-unpacked/blard-SkillTree/ exactly as ModLoader expects. Keep the file name
"Skill Tree.zip": the uploader takes the Workshop title from it.

    python build.py
"""
import json
import os
import zipfile

HERE = os.path.dirname(os.path.abspath(__file__))
MOD_DIR = os.path.join("mods-unpacked", "blard-SkillTree")
OUT = os.path.join(HERE, "dist", "Skill Tree.zip")


def main():
    manifest = json.load(open(os.path.join(HERE, MOD_DIR, "manifest.json")))
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    if os.path.exists(OUT):
        os.remove(OUT)
    count = 0
    with zipfile.ZipFile(OUT, "w", zipfile.ZIP_DEFLATED) as z:
        for root, _, files in os.walk(os.path.join(HERE, MOD_DIR)):
            for name in sorted(files):
                path = os.path.join(root, name)
                arc = os.path.relpath(path, HERE).replace(os.sep, "/")
                z.write(path, arc)
                count += 1
    print("Built %s (version %s, %d files)" % (OUT, manifest["version_number"], count))


if __name__ == "__main__":
    main()
