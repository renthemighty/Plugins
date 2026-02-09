# Releasing Kira

## Versioning Policy

Kira follows **Semantic Versioning** with a build number:

```
MAJOR.MINOR.PATCH+BUILD
```

| Segment | When to bump |
|---------|-------------|
| MAJOR   | Breaking changes, major redesigns, incompatible data migrations |
| MINOR   | New features, new storage-provider support, non-breaking additions |
| PATCH   | Bug fixes, performance improvements, copy/translation updates |
| BUILD   | Auto-incremented on every bump (used by app stores) |

## Bumping the Version

Run from the project root:

```bash
./scripts/bump_version.sh patch   # 1.0.0+1 -> 1.0.1+2
./scripts/bump_version.sh minor   # 1.0.1+2 -> 1.1.0+3
./scripts/bump_version.sh major   # 1.1.0+3 -> 2.0.0+4
```

The script updates `pubspec.yaml` and prints the git commands to commit and tag.

## Release Checklist

1. **Ensure all tests pass**
   ```bash
   flutter test
   ```

2. **Bump the version**
   ```bash
   ./scripts/bump_version.sh <major|minor|patch>
   ```

3. **Commit and tag**
   ```bash
   git add pubspec.yaml
   git commit -m "chore: bump version to <NEW_VERSION>"
   git tag v<MAJOR.MINOR.PATCH>
   ```

4. **Build for Android**
   ```bash
   flutter build appbundle --release
   ```
   Output: `build/app/outputs/bundle/release/app-release.aab`

5. **Build for iOS**
   ```bash
   flutter build ipa --release
   ```
   Output: `build/ios/ipa/Kira.ipa`

6. **Push the commit and tag**
   ```bash
   git push origin HEAD
   git push origin v<MAJOR.MINOR.PATCH>
   ```

7. **Upload builds** to Google Play Console and App Store Connect.

## Notes

- The build number (`+N`) must always increase for store submissions.
- Never reuse a git tag. If a release is reverted, bump to the next patch.
- Run `flutter clean` before release builds if switching between debug and release.
