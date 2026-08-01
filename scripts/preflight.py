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
  4. An app icon with an alpha channel. Everything builds, archives and signs;
     App Store Connect then rejects the upload with ITMS-90717.
  5. A UIBackgroundModes entry nothing implements (App Review rejects it under
     Guideline 2.5.4), or a BGTaskScheduler identifier missing from
     BGTaskSchedulerPermittedIdentifiers, which raises at launch on a device.
  6. A StoreKit product id in code that the .storekit config does not define.
     Product.products(for:) omits unknown ids without erroring, so the paywall
     renders empty on an otherwise healthy build.

The common thread: every one of these passes `xcodebuild` and fails later — at
upload, at review, or in the user's hand.

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
INFO_PLIST = "Config/Info.plist"
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


# Background mode -> the API that actually implements it. App Review rejects a
# build declaring a mode it never uses (Guideline 2.5.4).
BACKGROUND_MODE_APIS = {
    "fetch": [r"BGAppRefreshTaskRequest"],
    "processing": [r"BGProcessingTaskRequest"],
    "location": [r"allowsBackgroundLocationUpdates", r"startMonitoringSignificantLocationChanges"],
    "audio": [r"AVAudioSession.*\.playback", r"AVAudioSession.*\.playAndRecord"],
    "voip": [r"\bPKPushRegistry\b"],
    "remote-notification": [r"didReceiveRemoteNotification"],
    "bluetooth-central": [r"\bCBCentralManager\b"],
    "bluetooth-peripheral": [r"\bCBPeripheralManager\b"],
}


def swift_blob() -> str:
    """All Swift sources concatenated, comments stripped."""
    return "\n".join(re.sub(r"//.*", "", text) for _, text in swift_sources())


def registered_bgtask_ids(blob: str) -> set:
    """Every identifier handed to BGTaskScheduler, following one level of
    `Type.constant` indirection."""
    wanted = set()
    for expr in re.findall(
            r'(?:forTaskWithIdentifier:|BGAppRefreshTaskRequest\(identifier:|'
            r'BGProcessingTaskRequest\(identifier:)\s*([^,)\n]+)', blob):
        expr = expr.strip()
        if expr.startswith('"'):
            wanted.add(expr.strip('"'))
            continue
        name = expr.split(".")[-1]
        for lit in re.findall(r'\b%s\s*(?::\s*String)?\s*=\s*"([^"]+)"' % re.escape(name), blob):
            wanted.add(lit)
    return wanted


def check_background_modes() -> None:
    """Two device/review failures the compiler cannot see.

    1. A UIBackgroundModes entry with no implementing API — App Review rejects
       the build under Guideline 2.5.4.
    2. A BGTaskScheduler identifier missing from BGTaskSchedulerPermittedIdentifiers
       — `register(forTaskWithIdentifier:)` raises at launch on a real device.
    """
    pbx = read(PBX)
    blob = swift_blob()

    m = re.search(r'INFOPLIST_KEY_UIBackgroundModes\s*=\s*"?([^";]+)"?;', pbx)
    declared = m.group(1).split() if m else []
    for mode in declared:
        patterns = BACKGROUND_MODE_APIS.get(mode)
        if patterns is None:
            notes.append(f"UIBackgroundModes declares '{mode}', which this check does not know "
                         "how to verify — confirm by hand that it is implemented.")
            continue
        if not any(re.search(p, blob) for p in patterns):
            failures.append(
                f"UIBackgroundModes declares '{mode}' but nothing implements it "
                f"(looked for {', '.join(patterns)}).\n"
                "  App Review rejects a background mode the app never uses (Guideline 2.5.4).")

    wanted = registered_bgtask_ids(blob)

    # How the identifiers reach the bundle, and why not the obvious way.
    #
    # NOT via INFOPLIST_KEY_BGTaskSchedulerPermittedIdentifiers. Xcode does not
    # recognise that suffix, so the setting reads as correct in the project and
    # the key never ships. Confirmed in CI against the built plist: no such key,
    # and BGTaskScheduler rejected registration at every launch.
    #
    # The type is the reason no build setting can carry this. INFOPLIST_KEY_
    # values are strings, and Xcode only widens a known key to an array
    # (UIBackgroundModes, LSApplicationQueriesSchemes). This key is not on that
    # list, and a string here is invisible to BGTaskScheduler.
    #
    # So the identifiers live in a real Info.plist file, as a real <array>, and
    # INFOPLIST_FILE points the target at it. GENERATE_INFOPLIST_FILE stays YES:
    # the file is the base that generation merges into, not a replacement for it.
    # An earlier attempt here concluded INFOPLIST_FILE *replaces* the generated
    # plist, having watched the 29 credential forwarders vanish from the bundle.
    # That was a misread — the credentials were already absent the commit before,
    # because Xcode omits an INFOPLIST_KEY_ that expands to empty and CI has no
    # Secrets.xcconfig. The merge is verified for real now, in check_built_app().
    permitted = set()
    if not re.search(r'INFOPLIST_FILE = "%s"' % re.escape(INFO_PLIST), pbx):
        failures.append(
            f"The app target does not set INFOPLIST_FILE to \"{INFO_PLIST}\".\n"
            "  That file is the only thing that can carry BGTaskSchedulerPermittedIdentifiers\n"
            "  as an array; without it the identifiers never reach the bundle and background\n"
            "  flight monitoring never runs.")
    elif INFO_PLIST.split("/")[0] in ("JetSetter Pro", "JetSetter ProTests"):
        # Both of those are PBXFileSystemSynchronizedRootGroups, so every file
        # under them joins the target automatically — an Info.plist there is
        # picked up as a bundle resource *and* as the target's Info.plist, and
        # the build dies with "Multiple commands produce .../Info.plist". Config/
        # is a plain folder, which is the whole reason the file lives there.
        failures.append(
            f"{INFO_PLIST} is inside a synchronized group, so Xcode will also copy it as a\n"
            "  bundle resource and the build fails with \"Multiple commands produce\n"
            "  .../Info.plist\". Keep it in Config/ or another non-synchronized folder.")
    elif re.search(r'INFOPLIST_KEY_BGTaskSchedulerPermittedIdentifiers', pbx):
        # Regression guard. This looks like the natural place to declare it and
        # is silently ineffective, so re-adding it means someone is about to
        # believe a key ships when it does not.
        failures.append(
            "INFOPLIST_KEY_BGTaskSchedulerPermittedIdentifiers is back in the project.\n"
            f"  Xcode drops it — declare the identifiers in \"{INFO_PLIST}\" instead,\n"
            "  which is already wired up via INFOPLIST_FILE.")
    else:
        import plistlib
        try:
            with open(INFO_PLIST, "rb") as fh:
                value = plistlib.load(fh).get("BGTaskSchedulerPermittedIdentifiers")
        except (OSError, plistlib.InvalidFileException) as exc:
            failures.append(f"Cannot read {INFO_PLIST}: {exc}")
            value = None
        if isinstance(value, list):
            permitted = set(value)
        elif value is not None:
            failures.append(
                f"BGTaskSchedulerPermittedIdentifiers in {INFO_PLIST} is a "
                f"{type(value).__name__}, and must be an <array> of <string>.")

    missing = sorted(wanted - permitted)
    if missing:
        failures.append(
            "BGTaskScheduler identifiers not in BGTaskSchedulerPermittedIdentifiers:\n    "
            + "\n    ".join(missing)
            + "\n  register(forTaskWithIdentifier:) raises at launch on a device.")

    modes = ", ".join(declared) or "none"
    state = "PROBLEM" if missing else f"{len(wanted)} BGTask id(s), all permitted"
    print(f"  background modes ... {modes}; {state}")


STOREKIT = "Config/Products.storekit"
SUBS = "JetSetter Pro/Core/Services/SubscriptionManager.swift"


def check_storekit_products() -> None:
    """Product ids in code must match the local StoreKit config exactly.

    `Product.products(for:)` does not error on an unknown id — it just omits it.
    Drift here means the paywall renders with no products and no message, on a
    build that is otherwise completely healthy.
    """
    import json

    if not (os.path.exists(STOREKIT) and os.path.exists(SUBS)):
        notes.append("StoreKit config or SubscriptionManager not found; skipping product check.")
        return

    def product_ids(node, out):
        if isinstance(node, dict):
            if "productID" in node:
                out.add(node["productID"])
            for v in node.values():
                product_ids(v, out)
        elif isinstance(node, list):
            for v in node:
                product_ids(v, out)

    configured = set()
    with open(STOREKIT) as fh:
        product_ids(json.load(fh), configured)

    src = re.sub(r"//.*", "", read(SUBS))
    in_code = set(re.findall(r'\b\w*ID\w*\s*(?::\s*String)?\s*=\s*"([\w.\-]+\.subscription\.[\w.\-]+)"', src))

    if not in_code:
        notes.append(f"No subscription product ids found in {os.path.basename(SUBS)}.")
        return

    missing = sorted(in_code - configured)
    unused = sorted(configured - in_code)
    if missing:
        failures.append(
            f"Product ids used in code but absent from {STOREKIT}:\n    "
            + "\n    ".join(missing)
            + "\n  Product.products(for:) silently omits unknown ids — the paywall renders empty.")
    if unused:
        notes.append(f"In {STOREKIT} but never requested in code: " + ", ".join(unused))

    print(f"  storekit products .. {len(in_code)} id(s), matching {os.path.basename(STOREKIT)}"
          if not missing else f"  storekit products .. {len(in_code)} id(s), MISMATCH")


ICONSET = "JetSetter Pro/Assets.xcassets/AppIcon.appiconset"


def check_app_icon() -> None:
    """Catch ITMS-90717 before App Store Connect does.

    The App Store icon must not carry an alpha channel — an upload with one is
    rejected after the archive, export, and notarisation have all succeeded,
    which is an expensive place to find out. The dark and tinted variants are
    different: Apple composites those over a system-provided background, so the
    tinted one is *supposed* to be transparent.
    """
    import json
    import struct

    contents = os.path.join(ICONSET, "Contents.json")
    if not os.path.exists(contents):
        failures.append(f"No app icon set at {ICONSET}")
        return

    with open(contents) as fh:
        images = json.load(fh).get("images", [])

    def appearance(entry):
        for a in entry.get("appearances", []):
            if a.get("key", a.get("appearance")) == "luminosity":
                return a.get("value")
        return "default"

    seen = 0
    before = len(failures)
    for entry in images:
        name = entry.get("filename")
        if not name:
            continue
        path = os.path.join(ICONSET, name)
        if not os.path.exists(path):
            failures.append(f"{ICONSET}/Contents.json references missing file {name}")
            continue
        with open(path, "rb") as fh:
            head = fh.read(4096)
        if head[:8] != b"\x89PNG\r\n\x1a\n":
            failures.append(f"{name} is not a PNG")
            continue
        w, h, _depth, ctype = struct.unpack(">IIBB", head[16:26])
        has_alpha = ctype in (4, 6) or b"tRNS" in head
        kind = appearance(entry)
        seen += 1

        if (w, h) != (1024, 1024):
            failures.append(f"{name} is {w}x{h}; the icon must be 1024x1024")
        # Only the default (App Store) icon is rejected for transparency.
        if kind in ("default", "dark") and has_alpha:
            failures.append(
                f"{name} ({kind}) has an alpha channel. App Store Connect rejects this\n"
                f"    with ITMS-90717 at upload. Flatten it to RGB — if the alpha is fully\n"
                f"    opaque, dropping the channel is lossless.")
        if kind == "tinted" and not has_alpha:
            notes.append(f"{name} is the tinted variant but is fully opaque; Apple expects a "
                         "transparent mask it can tint over a system background.")

    if not seen:
        failures.append(f"{ICONSET}/Contents.json declares no icon images")
        print("  app icon ........... none declared")
    elif len(failures) > before:
        print(f"  app icon ........... {seen} variant(s), PROBLEM (see below)")
    else:
        print(f"  app icon ........... {seen} variant(s), 1024x1024, no App Store alpha issue")


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
    populated = [k for k in declared if str(plist.get(k, "")).strip()]

    print(f"\n  built app .......... {os.path.basename(app_path)}")
    print(f"  credentials set .... {len(populated)}/{len(declared)}")
    if populated:
        print("    configured: " + ", ".join(populated))
    else:
        # Absent is normal, not a failure. Xcode omits an INFOPLIST_KEY_ whose
        # value expands to empty, so with no Secrets.xcconfig the keys are gone
        # from the bundle rather than present-and-blank. An earlier version of
        # this check called that "the target is not forwarding them" and failed
        # every CI build — the forwarding is verified at project level above.
        notes.append(
            "No credential has a value in the built app. Expected when Secrets.xcconfig\n"
            "  is absent, as in CI. If you expected live services on a local build, the\n"
            "  base-configuration step did not take — see SETUP.md §1.")

    # Privacy usage descriptions are literal, non-empty strings, so unlike the
    # credentials they MUST survive into the bundle. If one goes missing iOS
    # terminates the app the first time that API is touched — the exact crash
    # this branch fixed. Any change to how Info.plist is produced has to be
    # checked against this, not assumed.
    want_usage = sorted(set(re.findall(r'INFOPLIST_KEY_(NS[A-Za-z]*UsageDescription)\s*=', read(PBX))))
    lost = [k for k in want_usage if not str(plist.get(k, "")).strip()]
    if lost:
        failures.append(
            "Privacy usage descriptions missing from the built Info.plist:\n    "
            + "\n    ".join(lost)
            + "\n  iOS terminates the app the first time the matching API runs.")
    elif want_usage:
        print(f"  usage strings ...... {len(want_usage)} present in the bundle")

    # The target sets INFOPLIST_FILE *and* GENERATE_INFOPLIST_FILE, on the
    # understanding that the file is a base which generation merges into. If that
    # is wrong and the file replaces the generated plist, these two keys are what
    # goes missing: neither can be expressed as INFOPLIST_KEY_ (they come from
    # UILaunchScreen_Generation / UIApplicationSceneManifest_Generation), so
    # neither is in the file, and losing them letterboxes the app on modern
    # screens or stops it launching at all. Both are silent at build time and
    # obvious only on a device, which is precisely the failure this check exists
    # to catch. The privacy strings above cover the same risk from the other end.
    for key, symptom in (
        ("UILaunchScreen",
         "the app letterboxes to a legacy screen size on every device"),
        ("UIApplicationSceneManifest",
         "the app has no scene configuration and will not launch"),
    ):
        if key not in plist:
            failures.append(
                f"{key} is missing from the built Info.plist — {symptom}.\n"
                "  It comes from GENERATE_INFOPLIST_FILE, so this means INFOPLIST_FILE\n"
                "  replaced the generated plist instead of being merged into it. Revert to\n"
                "  generation-only and find another way to ship the BGTask identifiers.")
    if "UILaunchScreen" in plist and "UIApplicationSceneManifest" in plist:
        print("  generated keys ..... UILaunchScreen + UIApplicationSceneManifest survived the merge")

    # BGTaskSchedulerPermittedIdentifiers must be an ARRAY in the built plist.
    # The project-level check above only compares the build-setting *string*, and
    # cannot see what type Xcode actually emitted. Xcode writes INFOPLIST_KEY_
    # suffixes it does not recognise as plain strings, and a string here is
    # invisible to BGTaskScheduler: registration is rejected at launch with
    # "<id> is not advertised in the application's Info.plist", background work
    # silently never runs, and the build is green throughout.
    key = "BGTaskSchedulerPermittedIdentifiers"
    ids = registered_bgtask_ids(swift_blob())
    if ids:
        value = plist.get(key)
        if value is None:
            failures.append(
                f"{key} is absent from the built Info.plist, so BGTaskScheduler rejects "
                + ", ".join(sorted(ids))
                + "\n  at launch and background flight monitoring never runs. It is declared as an\n"
                f"  array in {INFO_PLIST}, so the build did not merge that file into the\n"
                "  generated plist — check INFOPLIST_FILE on the app target.")
        elif isinstance(value, str):
            failures.append(
                f"{key} is a STRING in the built Info.plist ({value!r}), and must be an array.\n"
                "  BGTaskScheduler ignores it, so registration is rejected at launch and\n"
                "  background refresh never runs. Xcode emits INFOPLIST_KEY_ settings it does\n"
                f"  not recognise as strings — declare this key in {INFO_PLIST} instead.")
        elif isinstance(value, list):
            gap = sorted(ids - set(value))
            if gap:
                failures.append(f"{key} array is missing registered id(s): " + ", ".join(gap))
            else:
                print(f"  bgtask ids ......... {len(ids)} registered, all present as an array")


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
    check_app_icon()
    check_background_modes()
    check_storekit_products()
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
