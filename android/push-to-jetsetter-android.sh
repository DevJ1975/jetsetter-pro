#!/usr/bin/env bash
#
# Export this android/ scaffold to the standalone JetSetter_Android repository, making the
# android/ folder the repo ROOT. Run it from anywhere:
#
#   ./push-to-jetsetter-android.sh [TARGET_REPO_URL] [BRANCH]
#
# Defaults: TARGET_REPO_URL=https://github.com/DevJ1975/JetSetter_Android.git  BRANCH=main
#
# Requirements: git, rsync. This creates a fresh history (clean root) — ideal for an empty
# target repo. For a history-preserving export instead, see the git-subtree note at the end.
set -euo pipefail

TARGET_REPO="${1:-https://github.com/DevJ1975/JetSetter_Android.git}"
BRANCH="${2:-main}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"   # the android/ directory
WORK="$(mktemp -d)"

echo "▶ Staging scaffold: $HERE  →  $WORK"
rsync -a \
  --exclude='.gradle/' \
  --exclude='build/' \
  --exclude='app/build/' \
  --exclude='local.properties' \
  --exclude='.idea/' \
  "$HERE/" "$WORK/"

cd "$WORK"
git init -q
git checkout -q -b "$BRANCH"
git add .
git -c user.name="JetSetter Bot" -c user.email="dev@trainovate.com" \
    commit -q -m "Initial Android scaffold (exported from jetsetter-pro)"
git remote add origin "$TARGET_REPO"

echo "▶ Pushing to $TARGET_REPO ($BRANCH)…"
git push -u origin "$BRANCH"

echo "✅ Done. Open the repo in Android Studio (File → Open → the repo root)."
echo "   Temp staging dir: $WORK (safe to delete)."

# ── History-preserving alternative (run from the jetsetter-pro repo root) ───────────────
#   git subtree split --prefix=android -b _jsa_export
#   git push https://github.com/DevJ1975/JetSetter_Android.git _jsa_export:main
#   git branch -D _jsa_export
