# Incident & Error Log

## 2026-10-09: Cloudflare Build Failure (ENOENT: package.json missing)

### Symptoms
During Cloudflare Pages / Workers build:
```
Executing user build command: npm run build
npm error code ENOENT
npm error syscall open
npm error path /opt/buildhome/repo/package.json
npm error enoent Could not read package.json: Error: ENOENT: no such file or directory, open '/opt/buildhome/repo/package.json'
```

### Root Cause
1. Cloudflare was pointing to the root directory `/` (or mistakenly `/dist`), whereas the web frontend lives in `web/`.
2. No `package.json` was present in the repository root for monorepo build delegation.
3. `wrangler.json` was missing for Cloudflare's `npx wrangler deploy` execution with static assets.

### Resolution
1. Added root `package.json` delegating `build` and `test` to `web/` (`npm --prefix web ci && npm --prefix web run build`).
2. Added `wrangler.json` both at root and in `web/` with static asset directory bindings (`./web/dist` and `./dist`).
3. Added automated unit tests in `web/tests/deployment-config.test.ts` to validate presence and schema of all deployment configuration files before compilation.

## 2026-10-09: Cloudflare Build Failure (sh: 1: tsc: not found)

### Symptoms
During root-level CI execution:
```
> build
> npm --prefix web run build
> brewlog-web@1.0.0 build
> tsc --noEmit && vite build
sh: 1: tsc: not found
Failed: error occurred while running build command
```

### Root Cause
Cloudflare ran `npm install` at root where no packages were declared (`No packages! Deleted empty lockfile`), so `web/node_modules` was never populated during CI setup. When `npm run build` ran inside `web`, binary dependencies like `tsc` were absent.

### Resolution
Updated the root `package.json` build command to `npm --prefix web ci && npm --prefix web run build`, guaranteeing that all web packages and CLI tools (`tsc`, `vite`) are installed in the container prior to invoking build scripts. Added corresponding regression tests.
## 2026-10-14: Android Local Build Failure (SDK location not found & licenses not accepted)

### Symptoms
When running `./android/gradlew testDebugUnitTest`:
```
FAILURE: Build failed with an exception.
* What went wrong:
Could not determine the dependencies of task ':app:testDebugUnitTest'.
> SDK location not found. Define a valid SDK location with an ANDROID_HOME environment variable or by setting the sdk.dir path in your project's local properties file at 'android/local.properties'.
```
And upon creating `local.properties`:
```
Warning: License for package Android SDK Build-Tools 36 not accepted.
Warning: License for package Android SDK Platform 37.0 not accepted.
```

### Root Cause
1. `local.properties` was missing on the Linux environment, so Gradle could not locate the Android SDK directory.
2. The Android SDK license hashes for build-tools and platform 37 had not been accepted in `licenses/android-sdk-license`.

### Resolution
1. Created `android/local.properties` pointing to `~/Android/Sdk`.
2. Created the license files in `~/Android/Sdk/licenses/` with accepted standard license digests.
3. Created `scripts/build-apk.sh` to automatically detect or configure `ANDROID_HOME` and run tests before compilation.
4. Added Android build/CI workflow tests in unit tests to ensure configurations are validated before compilation.

## 2026-10-14: Android AGP JdkImageTransform Failure (jlink missing in JBR)

### Symptoms
During compilation with PyCharm's bundled JBR as `JAVA_HOME`:
```
Execution failed for JdkImageTransform: .../platforms/android-37.0/core-for-system-modules.jar.
> jlink executable /usr/share/pycharm/jbr/bin/jlink does not exist.
```

### Root Cause
The PyCharm JetBrains Runtime (JBR) distribution omits `jlink` to reduce binary size, but AGP (Android Gradle Plugin) 9.4 requires `jlink` to build runtime image modules for Java 17+.

### Resolution
Installed full Eclipse Temurin OpenJDK 17 with complete JDK tools (including `jlink`) in `~/.local/share/jdk-17` and set `JAVA_HOME` accordingly. Documented and tested JDK toolchain presence.

## 2026-10-14: Android Unit Test Compilation Failure (Recipe & RecipeStep Model Parameter Mismatches)

### Symptoms
During `testDebugUnitTest`:
```
Execution failed for task ':app:compileDebugUnitTestKotlin'.
> Kotlin compiler: NO_VALUE_FOR_PARAMETER
  No value passed for parameter 'author'.
  Argument type mismatch: actual type is 'Double', but 'StepKind' was expected.
```

### Root Cause
In unit tests, `Recipe` and `RecipeStep` objects were instantiated with an older or abbreviated parameter list (`RecipeStep(time, target, kind)` instead of `RecipeStep(kind, time, target)` and `Recipe` missing required fields such as `author`, `summary`, `tasteNotes`, `taste`, etc.).

### Resolution
Introduced a typed `testRecipe(...)` test factory with sensible defaults that conforms to the domain model contracts, and added explicit assertions verifying full domain model parameter construction and serialization stability.
