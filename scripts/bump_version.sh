#!/usr/bin/env bash
# Usage: ./scripts/bump_version.sh <major|minor|patch>
# Bumps the version in pubspec.yaml and creates a git tag.
set -euo pipefail

BUMP_TYPE="${1:-patch}"
PUBSPEC="pubspec.yaml"

# Extract current version
CURRENT=$(grep '^version:' "$PUBSPEC" | sed 's/version: //')
IFS='+' read -r SEMVER BUILD <<< "$CURRENT"
IFS='.' read -r MAJOR MINOR PATCH <<< "$SEMVER"

case "$BUMP_TYPE" in
  major) MAJOR=$((MAJOR + 1)); MINOR=0; PATCH=0 ;;
  minor) MINOR=$((MINOR + 1)); PATCH=0 ;;
  patch) PATCH=$((PATCH + 1)) ;;
  *) echo "Usage: $0 <major|minor|patch>"; exit 1 ;;
esac

NEW_BUILD=$((BUILD + 1))
NEW_VERSION="$MAJOR.$MINOR.$PATCH+$NEW_BUILD"

# Update pubspec.yaml
sed -i "s/^version: .*/version: $NEW_VERSION/" "$PUBSPEC"

echo "Bumped version: $CURRENT -> $NEW_VERSION"
echo "Run: git add pubspec.yaml && git commit -m 'chore: bump version to $NEW_VERSION' && git tag v$MAJOR.$MINOR.$PATCH"
