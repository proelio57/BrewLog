# Updates via SideStore (GitHub Actions)

Every push to `main` that changes the iOS app builds a new unsigned `BrewLog.ipa` on a GitHub macOS runner,
runs the unit tests and publishes it as a SideStore source. SideStore shows the update, you tap **Update**,
and SideStore signs the app with your own Apple ID. No Mac, no paid developer account, no Codemagic.

Changing only `Shared/recipes.json` doesn't need an app update at all: the **Recipes** workflow publishes the
list in a few seconds and the app picks it up within a few hours (or right away via
**Gear → Settings → Recipes → Check now**).

```
push to main ──► .github/workflows/ios.yml ──► GitHub release v1.0.<run>  (BrewLog.ipa)
                                          └─► branch "sidestore": source.json, recipes.json, icon.png
                .github/workflows/recipes.yml ─► branch "sidestore": recipes.json
SideStore ◄── https://raw.githubusercontent.com/proelio57/BrewLog/sidestore/source.json
BrewLog app ◄── https://raw.githubusercontent.com/proelio57/BrewLog/sidestore/recipes.json
```

## Setup

The workflows publish to this repository, `proelio57/BrewLog` (public on GitHub). They need
Settings → Actions → General → Workflow permissions: **Read and write permissions**. Then every push to `main`
builds and publishes.

## In SideStore

SideStore needs **[LocalDevVPN](https://apps.apple.com/us/app/localdevvpn/id6755608044)** from the App Store
([GitHub](https://github.com/jkcoxson/LocalDevVPN)): open it, tap **Connect** and allow the VPN profile (the iPhone
needs a passcode). Keep it connected when installing or refreshing apps, otherwise the 7-day re-signing fails.

1. **Sources → +** and enter `https://raw.githubusercontent.com/proelio57/BrewLog/sidestore/source.json`.
2. Install BrewLog from the source once. If you sideloaded BrewLog before, back up your data first
   (e.g. export your recipes), in case SideStore installs it as a separate app.
3. New builds then show up under **My Apps → Update**. `raw.githubusercontent.com` caches for about 5 minutes.

## Good to know

- **Widgets** need an App Group shared by the app and the widget extension. The CI build writes the entitlement
  into the unsigned IPA with `ldid` (`scripts/build-ipa.sh`); SideStore registers the group for your Apple ID and
  updates `ALTAppGroups` in Info.plist, which the app reads. If the widgets only say "Open BrewLog once", the
  group is missing: reinstall from the source, then open the app once.
- **Version numbers**: `MARKETING_VERSION` from `project.yml` plus the run number, e.g. `0.1.42`. Raise
  `MARKETING_VERSION` (e.g. to `0.2`) for bigger releases; the run number keeps every build unique.
- **Changelog**: the message of the last commit is shown in SideStore.
- **Free Apple ID**: apps have to be refreshed every 7 days, at most 3 apps (SideStore counts as one) and
  10 app IDs per week. The Live Activity is an app extension and needs its own app ID, so BrewLog uses two.
  If you run out, remove the extension when SideStore asks; BrewLog then works without the Lock Screen view.
- **Pull requests** are built and tested, and the `.ipa` is attached to the run as an artifact, but nothing is
  published.
- **Manual run**: Actions → iOS → *Run workflow*.
- **Test the publishing locally**: `scripts/sidestore-publish.sh` takes `RELEASE_GIT_URL` to push to a local
  repository instead of GitHub.
