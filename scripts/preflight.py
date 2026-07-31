#!/usr/bin/env python3
"""Project-configuration preflight for JetSetter Pro.

Catches the class of defect that is invisible at compile time but breaks the app
on a real device:

  1. An AppSecrets.Key that the target never forwards into Info.plist. The build
     succeeds, the key silently reads nil, and the feature quietly falls back to
     mock data or an empty state.
  2. A privacy-gated API used in code with no matching usage description. The
     build succeeds and iOS kills the app the first time that code path runs.
  3. A missing shared scheme, which breaks `xcodebuild -scheme` and Xcode Cloud
     from a clean checkout.

Runs on Linux in seconds — no Xcode required.

    python3 scripts/preflight.py

After a build, `--app` additionally inspects the *built* Info.plist to confirm
the Secrets.xcconfig base-configuration step actually took. That step is the
single most common setup failure: miss it and every credential is present but
empty, the app silently serves mock data, and nothing in the build output says
so.

    python3 scripts/preflight.py --app "build/Debug-iphoneos/JetSetter Pro.app"
"""
from __future__ import annotations

import os
import re
import sys

PBX = "JetSetter Pro.xcodeproj/project.pbxproj"
SECRETS = "JetSetter Pro/Core/Configuration/AppSecrets.swift"
SCHEME = "JetSetter Pro.xcodeproj/xcshareddata/xcschemes/JetSetter Pro.xcscheme"
SRC = "JetSetter Pro"

# API marker in source -> Info.plist usage-description key it requires.
# Only markers that actually trigger a system permission prompt belong here.
PERMISSION_APIS = {
    "NSMicrophoneUsageDescription": [
        r"AVAudioApplication\.requestRecordPermission",
        r"\.requestRecordPermission\(",
    ],
    "NSSpeechRecognitionUsageDescription": [r"SFSpeechRecognizer\.requestAuthorization"],
    "NSMotionUsageDescription": [r"\bCMPedometer\b", r"\bCMAltimeter\b", r"\bCMMotionActivityManager\b"],
    "NSCameraUsageDescription": [r"AVCaptureDevice\.", r"\.sourceType\s*=\s*\.camera"],
    "NSPhotoLibraryUsageDescription": [r"PHPhotoLibrary\.", r"\bPhotosPicker\b"],
    "NSLocationWhenInUseUsageDescription": [r"requestWhenInUseAuthorization\(\)"],
    "NSLocationAlwaysAndWhenInUseUsageDescription": [r"requestAlwaysAuthorization\(\)"],
    "NSCalendarsFullAccessUsageDescription": [r"requestFullAccessToEvents"],
    "NSFaceIDUsageDescription": [r"\.deviceOwnerAuthenticationWithBiometrics"],
    "NSContactsUsageDescription": [r"\bCNContactStore\b"],
}

failures: list[str] = []
notes: list[str] = []


def read(path: str) -> str:
    with open(path, encoding="utf-8") as fh:
        return fh.read()


def swift_sources() -> list[tuple[str, str]]:
    out = []
    for root, _, files in os.walk(SRC):
        for fn in sorted(files):
            if fn.endswith(".swift"):
                p = os.path.join(root, fn)
                out.append((p, read(p)))
    return out


def check_secrets_forwarded() -> None:
    declared = set(re.findall(r'=\s*"(API_[A-Z0-9_]+)"', read(SECRETS)))
    forwarded = set(re.findall(r"INFOPLIST_KEY_(API_[A-Z0-9_]+)\s*=", read(PBX)))
    missing = sorted(declared - forwarded)
    if missing:
        failures.append(
            "AppSecrets keys never reach Info.plist (they will read nil at runtime):\n    "
            + "\n    ".join(missing)
            + "\n  Add INFOPLIST_KEY_<KEY> = \"$(<KEY>)\" to BOTH build configurations."
        )
    orphan = sorted(forwarded - declared)
    if orphan:
        notes.append("Forwarded but not declared in AppSecrets.Key: " + ", ".join(orphan))
    print(f"  secrets forwarded ... {len(declared & forwarded)}/{len(declared)}")


def check_permission_strings() -> None:
    pbx = read(PBX)
    sources = swift_sources()
    checked = 0
    for key, patterns in PERMISSION_APIS.items():
        users = []
        for path, text in sources:
            body = re.sub(r"//.*", "", text)
            if any(re.search(p, body) for p in patterns):
                users.append(path.replace(SRC + "/", ""))
        if not users:
            continue
        checked += 1
        if f"INFOPLIST_KEY_{key}" not in pbx:
            failures.append(
                f"{key} is missing, but the API it guards is used in:\n    "
                + "\n    ".join(users)
                + "\n  iOS terminates the app the first time this runs on a device."
            )
    print(f"  permission strings . {checked} privacy API(s) in use, all declared"
          if not failures else f"  permission strings . {checked} privacy API(s) in use")


def check_shared_scheme() -> None:
    if not os.path.exists(SCHEME):
        failures.append(
            f"No shared scheme at {SCHEME}.\n"
            "  `xcodebuild -scheme` and Xcode Cloud cannot resolve one from a clean checkout."
        )
        return
    scheme = read(SCHEME)
    defined = set(re.findall(r"^\t\t([0-9A-F]{24}) ", read(PBX), re.M))
    for bid in set(re.findall(r'BlueprintIdentifier\s*=\s*"([0-9A-F]{24})"', scheme)):
        if bid not in defined:
            failures.append(f"Scheme references target {bid}, which does not exist in the project.")
    print("  shared scheme ...... present, all blueprint ids resolve")


def check_built_app(app_path: str) -> None:
    """Confirm the Secrets.xcconfig base-config step took, by reading the built plist.

    Keys are always *present* (the target forwards them unconditionally); the
    tell is whether they expanded to a value or to an empty string.
    """
    import plistlib
    import subprocess

    plist_path = os.path.join(app_path, "Info.plist")
    if not os.path.exists(plist_path):
        failures.append(f"No Info.plist at {plist_path} — is that a built .app bundle?")
        return
    with open(plist_path, "rb") as fh:
        raw = fh.read()
    if raw[:8] == b"bplist00":
        try:  # binary plist written by the build; plistlib handles it directly
            plist = plistlib.loads(raw)
        except Exception:
            out = subprocess.run(["plutil", "-convert", "xml1", "-o", "-", plist_path],
                                 capture_output=True)
            plist = plistlib.loads(out.stdout)
    else:
        plist = plistlib.loads(raw)

    declared = sorted(set(re.findall(r'=\s*"(API_[A-Z0-9_]+)"', read(SECRETS))))
    absent = [k for k in declared if k not in plist]
    empty = [k for k in declared if k in plist and not str(plist[k]).strip()]
    populated = [k for k in declared if k in plist and str(plist[k]).strip()]

    print(f"\n  built app .......... {os.path.basename(app_path)}")
    print(f"  credentials set .... {len(populated)}/{len(declared)}")
    if absent:
        failures.append("Keys missing from the built Info.plist entirely (the target is not "
                        "forwarding them):\n    " + "\n    ".join(absent))
    if populated:
        print("    configured: " + ", ".join(populated))
    if not populated:
        notes.append(
            "No credential has a value in the built app. If you expected live services, the\n"
            "  Secrets.xcconfig base-configuration step did not take — see SETUP.md §1.\n"
            "  (If you meant to run on demo data, this is fine.)")
    elif empty:
        notes.append(f"{len(empty)} credential(s) still blank — those features stay on mock data: "
                     + ", ".join(empty))


def main() -> int:
    args = sys.argv[1:]
    app_path = None
    if "--app" in args:
        i = args.index("--app")
        if i + 1 >= len(args):
            print("error: --app needs a path to a built .app bundle", file=sys.stderr)
            return 2
        app_path = args[i + 1]

    print("JetSetter Pro — project-configuration preflight\n")
    check_secrets_forwarded()
    check_permission_strings()
    check_shared_scheme()
    if app_path:
        check_built_app(app_path)

    for note in notes:
        print(f"\nnote: {note}")

    if failures:
        print("\nFAILED\n")
        for i, f in enumerate(failures, 1):
            print(f"{i}. {f}\n")
        return 1
    print("\nOK — nothing here will silently break on a device.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
