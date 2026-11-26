"""Inspect, verify, and copy EncoreSheets library backups without extracting them."""

import argparse
import json
from pathlib import Path
import shutil
import sys
from zipfile import BadZipFile, ZipFile


def inspect_backup(path, verify=False):
    with ZipFile(path) as backup:
        members = backup.namelist()
        if len(members) != len(set(members)):
            raise ValueError("The backup contains duplicate archive entries.")
        manifest_info = backup.getinfo("manifest.json")
        if manifest_info.file_size > 64 * 1024 * 1024:
            raise ValueError("The backup manifest exceeds 64 MB.")
        manifest = json.loads(backup.read(manifest_info))
        if not isinstance(manifest, dict) or (
            manifest.get("format"), manifest.get("version")
        ) != ("EncoreSheetsLibrary", 1):
            raise ValueError("This is not a supported EncoreSheets library backup.")
        scores, setlists = manifest.get("scores"), manifest.get("setlists")
        if not isinstance(scores, list) or not isinstance(setlists, list):
            raise ValueError("The score or setlist catalog is invalid.")
        references = manifest.get("referencesOnly") is True
        if not references:
            available = set(members)
            for number in range(len(scores)):
                if f"scores/{number}.pdf" not in available:
                    raise ValueError(f"The PDF for catalog item {number + 1} is missing.")
        if verify:
            damaged = backup.testzip()
            if damaged is not None:
                raise ValueError(f"Damaged archive entry: {damaged}")
        return {
            "path": str(path),
            "type": "metadata-only" if references else "full library",
            "scores": len(scores),
            "setlists": len(setlists),
            "bytes": path.stat().st_size,
        }


def copy_backup(path, directory):
    directory = directory.resolve(strict=True)
    if not directory.is_dir():
        raise ValueError("Choose an existing destination directory.")
    target = directory / path.name
    with path.open("rb") as source, target.open("xb") as output:
        try:
            shutil.copyfileobj(source, output)
        except BaseException:
            output.close()
            target.unlink()
            raise
    try:
        inspect_backup(target, verify=True)
    except BaseException:
        target.unlink()
        raise
    return target


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    for name in ("inspect", "verify", "copy"):
        command = commands.add_parser(name)
        command.add_argument("backup", type=Path)
        if name == "copy":
            command.add_argument("directory", type=Path)
    args = parser.parse_args()
    try:
        if args.command == "copy":
            inspect_backup(args.backup)
            print(f"Copied and verified: {copy_backup(args.backup, args.directory)}")
        else:
            print(json.dumps(inspect_backup(args.backup, verify=args.command == "verify"), indent=2))
    except (OSError, ValueError, KeyError, BadZipFile, RuntimeError) as error:
        print(f"Backup error: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
