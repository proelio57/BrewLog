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
SideStore ◄── https://raw.githubusercontent.com/<RELEASE_REPO>/sidestore/source.json
BrewLog app ◄── https://raw.githubusercontent.com/<RELEASE_REPO>/sidestore/recipes.json
```

## Setup

SideStore and the app download without logging in, so the files have to be in a **public** GitHub repository.
Pick one of these:

### A: the code repository itself is public (simplest)

1. Push this repository to GitHub, e.g. `you/brewlog` (public).
2. Settings → Actions → General → Workflow permissions: **Read and write permissions**.
3. Push to `main`. Done. macOS minutes are free for public repositories.

### B: code stays private, releases go to a second, public repository

1. Create an **empty public** repository, e.g. `you/brewlog-releases`.
2. Create a fine-grained token (GitHub → Settings → Developer settings → Fine-grained tokens):
   repository access only `you/brewlog-releases`, permission **Contents: Read and write**.
3. In the private code repository (Settings → Secrets and variables → Actions):
   - secret `RELEASE_TOKEN` = the token
   - variable `RELEASE_REPO` = `you/brewlog-releases`
4. Push to `main`.

Private repositories get 2,000 free Actions minutes per month, and macOS minutes count 10×. A build with tests
takes roughly 8–12 minutes, so that's about 15–25 builds a month. To save minutes, set the variable
`SKIP_TESTS` = `true` (the build itself still has to compile), or only push to `main` when you want a release.

### Code on GitLab?

GitLab's hosted macOS runners are only available on paid plans. Keep GitLab as the main repository and mirror
it to GitHub: GitLab → Settings → Repository → **Mirroring repositories** → Git repository URL
`https://github.com/you/brewlog.git`, direction **Push**, password = a GitHub token with *Contents: Read and
write* on that repository. Every push to GitLab then reaches GitHub within minutes and starts the build.

## In SideStore

1. **Sources → +** and enter `https://raw.githubusercontent.com/<RELEASE_REPO>/sidestore/source.json`.
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
