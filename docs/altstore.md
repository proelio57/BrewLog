# Updates via AltStore (GitHub Actions)

Every push to `main` that changes the iOS app builds a new unsigned `BrewLog.ipa` on a GitHub macOS runner,
publishes it as a GitHub release and updates an AltStore source. AltStore shows the update, you tap **Update**,
and AltStore signs the app with your own Apple ID. No paid developer account and no Codemagic.

Changing only `Shared/recipes.json` doesn't need an app update at all: the **Recipes** workflow publishes the
list in a few seconds and the app picks it up within a few hours (or right away via
**Settings → Recipes, backup & data → Check now**).

```
push to main ──► .github/workflows/ios.yml ──► GitHub release v<version>  (BrewLog.ipa, BrewLog.apk)
                                          └─► branch "sidestore": source.json, recipes.json, icon.png
                .github/workflows/recipes.yml ─► branch "sidestore": recipes.json
AltStore ◄── https://raw.githubusercontent.com/proelio57/BrewLog/sidestore/source.json
BrewLog app ◄── https://raw.githubusercontent.com/proelio57/BrewLog/sidestore/recipes.json
```

The branch keeps its old name `sidestore`: the source URL and the recipe list URL in the app point to it.

## Setup

The workflows publish to this repository, `proelio57/BrewLog` (public on GitHub). They need
Settings → Actions → General → Workflow permissions: **Read and write permissions**. Then every push to `main`
builds and publishes.

## On the iPhone

You need **AltStore Classic** and an **AltServer** that signs and refreshes the apps. That is either a computer
(Mac or Windows PC) in the same Wi-Fi, or, without a computer, the **Remote AltServer** below.

> **AltStore PAL is not enough.** The EU marketplace version of AltStore only installs apps that Apple has
> notarized (each app needs a `marketplaceID`). BrewLog is signed with your own free Apple ID, so it needs
> AltStore Classic. If AltStore says "missing a marketplaceID", you have PAL.

1. Install AltServer on the computer and AltStore Classic on the iPhone ([altstore.io](https://altstore.io)),
   signing in with your Apple ID (a free one is enough).
2. Add the source: open `altstore://source?url=https://raw.githubusercontent.com/proelio57/BrewLog/sidestore/source.json`
   on the iPhone, or in AltStore **Browse → Sources → +** and enter
   `https://raw.githubusercontent.com/proelio57/BrewLog/sidestore/source.json`.
3. Install **BrewLog** from the source once. If you installed BrewLog another way before, export your recipes first,
   in case it installs as a separate app.
4. New builds then show up under **My Apps → Update**. `raw.githubusercontent.com` caches for about 5 minutes.

### Without a computer: Remote AltServer (LocalDevVPN)

AltStore Classic can refresh and install apps without a computer in the same Wi-Fi by using a **Remote AltServer**.
It works with a free Apple ID.

1. Install **[LocalDevVPN](https://apps.apple.com/us/app/localdevvpn/id6755608044)** from the App Store
   ([source on GitHub](https://github.com/jkcoxson/LocalDevVPN)). Open it, tap **Connect** and allow the VPN
   profile (the iPhone needs a passcode). Keep it connected while AltStore installs or refreshes apps, otherwise the
   Remote AltServer can't be reached.
2. In AltStore Classic open **Settings → Set up Remote AltServer** and follow the steps in the app.
3. Sign in with your (free) Apple ID, then add the source and install BrewLog as above.

This feature is still in beta and the steps may change; AltStore's own guide has the current ones:
[faq.altstore.io/altstore-classic/no-computer-instructions](https://faq.altstore.io/altstore-classic/no-computer-instructions).
AltStore Classic itself is installed once the usual way (AltServer on a computer).

Without a source you can also install a release's `BrewLog.ipa` directly (GitHub → Releases) with AltStore's
**My Apps → +** or with Sideloadly; then every update is a new install of the newer `.ipa`.

## Good to know

- **Widgets** need an App Group shared by the app and the widget extension. The CI build writes the entitlement
  into the unsigned IPA with `ldid` (`scripts/build-ipa.sh`); AltStore registers the group for your Apple ID and
  updates `ALTAppGroups` in Info.plist, which the app reads. If the widgets only say "Open BrewLog once", the
  group is missing: reinstall from the source, then open the app once.
- **Version numbers**: semantic versioning from the Conventional Commits of the merge (`scripts/next-version.sh`):
  a `fix` raises the patch (2.12.0 → 2.12.1), a `feat` the minor (→ 2.13.0), a breaking change the major. iOS and
  Android publish the same version into one release, and a re-run of a release keeps its version. The GitHub run
  number is the build number.
- **Changelog**: the notes of the release (`RELEASE_NOTES.md`, grouped by platform, a line that is the same for several platforms appears once under "iOS & Android" or "All platforms"; otherwise the commit subjects)
  are the update description in AltStore.
- **Free Apple ID**: apps have to be refreshed every 7 days, at most 3 apps are active at once and 10 app IDs
  can be created per week. The Live Activity is an app extension and needs its own app ID, so BrewLog uses two.
  If you run out, remove the extension when AltStore asks; BrewLog then works without the Lock Screen view.
- **Refreshing**: AltServer renews the signature in the background while the computer is on and in the same
  Wi-Fi; with the Remote AltServer, LocalDevVPN has to be connected. Otherwise open AltStore and tap
  **Refresh All** before the 7 days are over.
- **Pull requests** are built and tested, and the `.ipa` is attached to the run as an artifact, but nothing is
  published.
- **Manual run**: Actions → iOS → *Run workflow*.
- **Test the publishing locally**: `scripts/sidestore-publish.sh` takes `RELEASE_GIT_URL` to push to a local
  repository instead of GitHub.
