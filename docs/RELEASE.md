# SmartScribe release checklist

## Branch

```text
main
```

Repository: `https://github.com/Pavan-Gopa/SmartScribe`.

## Build signed DMG

```bash
APP_VERSION=1.0.1 APP_BUILD=2 ./script/build_release_dmg.sh
# or with notarization in one step:
APP_VERSION=1.0.1 APP_BUILD=2 NOTARIZE=1 ./script/build_release_dmg.sh
```

Outputs:

- `dist/SmartScribe.dmg` — signed (and optionally notarized) disk image  
- `dist/release/SmartScribe.app` — app bundle  
- `dist/handoff/` — DMG + `install.sh` + `SHA256SUMS.txt`

Signing identity (preferred):

```text
Developer ID Application: Stichting Kadamba Foundation (438UQRF7JV)
```

## Notarize with Apple

Credentials are **not** stored in the repo. Configure once on the build machine:

```bash
xcrun notarytool store-credentials "SmartScribe-Notary" \
  --apple-id "YOUR_APPLE_ID" \
  --team-id "438UQRF7JV" \
  --password "APP_SPECIFIC_PASSWORD"
```

Then:

```bash
./script/notarize_dmg.sh dist/SmartScribe.dmg
# or as part of the build:
NOTARIZE=1 ./script/build_release_dmg.sh
```

Verify:

```bash
spctl -a -vv -t install dist/SmartScribe.dmg
xcrun stapler validate dist/SmartScribe.dmg
```

## CLI install for recipients

```bash
./script/install.sh /path/to/SmartScribe.dmg
./script/install.sh --from-github   # needs gh auth + private repo access
```

## GitHub release (published)

```bash
# Ensure remote stays private until you choose otherwise
gh repo view Pavan-Gopa/SmartScribe --json isPrivate

# Push branch
git push -u origin HEAD

# Create / update a normal Latest release
gh release create v1.0.1 \
  dist/SmartScribe.dmg \
  --title "SmartScribe 1.0.1" \
  --notes-file docs/RELEASE_NOTES.md \
  --target main \
  --latest

# If the release already exists as a draft:
gh release edit v1.0.1 \
  --notes-file docs/RELEASE_NOTES.md \
  --draft=false \
  --prerelease=false \
  --latest=true
```

Do **not** run `gh repo edit --visibility public` unless you intend to open the repo.

## Smoke checks after install

1. Launch `/Applications/SmartScribe.app`  
2. Onboarding / Help → Replay onboarding  
3. Settings → Local Models — list loads  
4. Record a short clip → Raw text appears  
5. Option+S HUD appears over another app  
6. With ≥2 polishing providers: scroll HUD → provider list; right-click provider → model menu  
7. API Providers — keys remain local; no keys pre-bundled in the app  
