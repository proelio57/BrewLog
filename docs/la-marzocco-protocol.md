# La Marzocco cloud protocol (as BrewLog uses it)

Source: pylamarzocco **v2.5.6** (GitHub zweckj/pylamarzocco, commit 4c639ee, 2026-11-05), the library behind the Home
Assistant `lamarzocco` integration. Files: `src/pylamarzocco/const.py`, `clients/_cloud.py`,
`util/_authentication.py`, `util/_websocket.py`, `models/_config.py`, `models/_general.py`, fixtures in
`tests/fixtures/machine/dashboard_*.json`. La Marzocco publishes no API; it has changed before (2025 firmware/app
switch, local API on port 8081 removed) and may change again.

The local WebSocket (`ws://<ip>:8081/api/v1/streaming`) is gone on current firmware. Bluetooth needs a token that also
comes from the cloud. So BrewLog talks to La Marzocco's servers with the user's own La Marzocco account (opt-in).

## Hosts

- REST: `https://lion.lamarzocco.io/api/customer-app`
- WebSocket: `wss://lion.lamarzocco.io/ws/connect` (STOMP over WebSocket)

## Installation key (once per BrewLog install)

- `installationId`: random UUID, lower-case.
- Key pair: ECDSA P-256 (`SECP256R1`). Public key as DER SubjectPublicKeyInfo (91 bytes), base64 = `pk`.
- `secret` (32 bytes) = SHA-256 of the UTF-8 string `"<installationId>.<base64(pubDER)>.<base64(SHA-256(installationId))>"`.
- `baseString` = `"<installationId>.<base64(SHA-256(pubDER))>"`.
- Kept in the Keychain (private key raw representation, secret, id). Losing it only means registering again.

### Request proof (La Marzocco's own algorithm)

```
work = copy of secret (32 bytes)
for each byte b of the UTF-8 input:
    i = b % 32
    s = work[(i + 1) % 32] & 7
    x = b ^ work[i]
    work[i] = ((x << s) | (x >> (8 - s))) & 0xFF      // rotate left by s
proof = base64(SHA-256(work))
```

Test vectors (computed with the library's own function):
- input `"abc"`, secret 32 × `0x00` → `P5ynD3LZU7oRYIN0D2ZtOlbpepJdBXQH9vdqJGOfq/o=`
- installationId `3f2504e0-4f89-41d3-9a0c-0305e82c3301`, pubDER = bytes 0…90:
  secret `EUWj84o7RXt611rkgsprs36qybfa0ZjAUFSQFvJJ2co=`,
  baseString `3f2504e0-4f89-41d3-9a0c-0305e82c3301.WNKUWbITCi4VElLUCLlebaxCTFZAYuuRHMdkQMuSbKA=`,
  proof(baseString) `/gmx2S9P5KtTvJ4RScjIgp96zl4CSPsaVaLcuukpVLs=`,
  proof(`"<id>.00000000-0000-4000-8000-000000000000.1762358400000"`) `4rXwI3Qpk0PhDlJu+HH5iSckHEm4F9GknCUIx3iNarg=`

## Requests

- **Register** (once per installation key): `POST /auth/init`, headers `X-App-Installation-Id: <id>`,
  `X-Request-Proof: proof(baseString)`, JSON body `{"pk": "<base64 pubDER>"}`.
- **Every other request** (sign-in included) carries signed headers, new for each request:
  - `X-App-Installation-Id: <id>`
  - `X-Timestamp: <ms since 1970>`
  - `X-Nonce: <random UUID, lower-case>`
  - `X-Request-Signature: base64(ECDSA-P256-SHA256-DER(sign("<id>.<nonce>.<timestamp>.<proof(\"<id>.<nonce>.<timestamp>\")>")))`
- **Sign in**: `POST /auth/signin` `{"username", "password"}` → `{"accessToken", "refreshToken"}`. The token is valid
  about 1 h; refresh 10 min before: `POST /auth/refreshtoken` `{"username", "refreshToken"}`.
- Authenticated calls add `Authorization: Bearer <accessToken>`.
- `401` → wrong login. `403` with `{"code": "USER_MUST_ACCEPT_POLICY"}` → the user has to accept La Marzocco's privacy
  policy in their app (`PUT /users/policy` exists, but BrewLog leaves that decision to the user and their app).
- **Machines**: `GET /things` → `[{serialNumber, type ("CoffeeMachine" …), name, modelName, connected, …}]`.
- **Dashboard**: `GET /things/<serial>/dashboard` → `{connected, widgets: [{code, index, output}], …}`.
- **Commands**: `POST /things/<serial>/command/<Command>` → `[{id, status}]`; the result arrives later in the
  WebSocket's `commands` (`status`: `Success`, `Error`, `Failed`, `Timeout`).
  - Power: `CoffeeMachineChangeMode` `{"mode": "BrewingMode" | "StandBy"}`.
  - Brew temperature: `CoffeeMachineSettingCoffeeBoilerTargetTemperature` `{"boilerIndex": 1, "targetTemperature": 93.5}`
    (rounded to 0.1).

## Widgets BrewLog reads

- `CMMachineStatus.output`: `status` (`StandBy`, `PoweredOn`, `Brewing`, `EcoMode`, `Off`), `mode`
  (`BrewingMode`, `EcoMode`, `StandBy`), `availableModes`, `brewingStartTime` (ms or null).
- `CMCoffeeBoiler.output`: `status` (`StandBy`, `HeatingUp`, `Ready`, `NoWater`, `EcoMode`, `Off`), `targetTemperature`,
  `targetTemperatureMin`/`Max`/`Step`, `readyStartTime`.
- No pressure, flow or live temperature on Micra / Mini / GS3: BrewLog keeps offering the BOOKOO pressure sensor.

## WebSocket (STOMP)

Open `wss://lion.lamarzocco.io/ws/connect` with the signed headers, then send text frames (`\0` ends a frame):

```
CONNECT
host:lion.lamarzocco.io
accept-version:1.2,1.1,1.0
heart-beat:0,0
Authorization:Bearer <accessToken>

\0
```
Wait for `CONNECTED`, then
```
SUBSCRIBE
destination:/ws/sn/<serial>/dashboard
ack:auto
id:<random UUID>
content-length:0

\0
```
Each `MESSAGE` frame's body is a dashboard JSON (`connected`, `widgets`, `removedWidgets`, `commands`). The library
pings every 15 s at WebSocket level. On close: reconnect with a fresh token.
