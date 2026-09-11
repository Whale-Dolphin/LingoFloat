# Releasing LingoFloat

Cutting a new release is split across two surfaces: **GitHub Actions** creates the draft Release page and **your local Mac** builds the Apple Silicon `.dmg`. The default artifact is ad-hoc signed for integrity but is not Apple-notarized.

## TL;DR

```sh
# 1. Tag and push
git tag v1.1.0
git push origin v1.1.0

# 2. Build the ad-hoc signed .dmg locally
./scripts/build-release.sh 1.1.0

# 3. Upload it to the draft release that GitHub Actions just created
gh release upload v1.1.0 build/LingoFloat-1.1.0.dmg build/LingoFloat-1.1.0.dmg.sha256

# 4. Publish
gh release edit v1.1.0 --draft=false
```

## Step-by-step

### Pre-flight

- [ ] All work for this version is merged to `main`.
- [ ] CI for the repository that will host LingoFloat is green on the head commit.
- [ ] Any machine-local notes or configs are ignored — sanity-check with `git status` (nothing personal in **Untracked files**) and `git check-ignore -v <path>` on each file you intentionally keep out of the repo.
- [ ] `LingoFloat/Local.xcconfig` is ignored. The release script creates it from the committed template when missing.
- [ ] Release notes state that the prebuilt app is arm64, ad-hoc signed, and not notarized.

### 1. Tag and push

Tags must follow **SemVer with a `v` prefix**: `v1.0.0`, `v1.2.3`, `v2.0.0-rc.1`.

```sh
git tag v1.1.0
git push origin v1.1.0
```

The push triggers `.github/workflows/release.yml`, which creates a **draft** GitHub Release with an auto-generated changelog from commits since the previous tag.

### 2. Build the ad-hoc signed `.dmg` locally

```sh
./scripts/build-release.sh 1.1.0
```

What this does:
1. Builds `Release` for arm64 with the pinned SwiftPM packages.
2. Applies an ad-hoc hardened-runtime signature with the app's audio entitlement.
3. Verifies the app signature and embedded marketing version.
4. Packages the app, Applications shortcut, and first-launch guide into `build/LingoFloat-1.1.0.dmg`.
5. Verifies the DMG and writes `build/LingoFloat-1.1.0.dmg.sha256`.

### 3. Upload the `.dmg` to the draft release

```sh
gh release upload v1.1.0 build/LingoFloat-1.1.0.dmg build/LingoFloat-1.1.0.dmg.sha256
```

If `gh` is not installed: `brew install gh && gh auth login`. Alternatively, drag-and-drop the `.dmg` onto the draft Release page in GitHub's web UI.

### 4. Publish

Open the draft release in the web UI to double-check the changelog text reads cleanly, then:

```sh
gh release edit v1.1.0 --draft=false
```

This flips the release from draft to published. Subscribers get notified and the README Release badge updates.

## What CI does (and doesn't) do

**Does:**
- Verifies that every push to `main` and every pull request **builds clean and passes tests** on a fresh `macos-15` runner.
- On every tag push matching `v*`, **creates a draft GitHub Release with a generated changelog**.

**Does NOT:**
- Build the `.dmg`.
- Produce or sign the downloadable app.
- Notarize the downloadable app — no Apple Developer credentials are stored in GitHub.

## Versioning policy

LingoFloat uses [Semantic Versioning](https://semver.org/) (`MAJOR.MINOR.PATCH`):

| Bump | When |
|-|-|
| `PATCH` (`1.0.0` → `1.0.1`) | Bug fixes, no user-visible behaviour changes |
| `MINOR` (`1.0.x` → `1.1.0`) | New features, settings, engines — backward-compatible for existing users |
| `MAJOR` (`1.x.x` → `2.0.0`) | Breaking changes: removed settings, breaking changes to chat-history file format, etc. |

`MARKETING_VERSION` is set by the build script via `xcodebuild MARKETING_VERSION=`, so what shows in **About → LingoFloat** matches the tag.

## Yanking a bad release

If a release has a critical issue and you want to take it offline before users see it:

```sh
gh release delete v1.0.0 --yes
git push --delete origin v1.0.0
git tag -d v1.0.0
```

Then fix, re-tag with a bumped patch (`v1.0.1`), and ship the fix. Don't reuse a tag — even if `git push --delete` removes it from the remote, mirrors and clones still hold it.
