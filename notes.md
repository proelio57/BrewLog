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
