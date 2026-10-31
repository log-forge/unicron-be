# Unicron Business Edition: connected Docker installation

Docker downloads the public product images without a LogForge registry login.
One-time host setup enables **Settings > Updates & releases**; routine updates
and restore then use its buttons. Online and offline delivery use the same images.

## Get the current installation

For a new installation, clone the public deployment repository:

```bash
git clone https://github.com/log-forge/unicron-be.git
cd unicron-be
```

The repository selects the current published bootstrap images. Initialization
verifies the signed release and records exact image digests for this deployment;
you do not build product source or choose image versions. Existing installations
use their supported update controls rather than pulling this repository into
their running deployment or restarting a newer bootstrap over retained data.

These commands use Bash on a Linux host with Docker Engine, Compose v2 and
systemd. Run them in a Linux administrator shell with access to that Docker
engine, from the folder containing `compose.yaml`. The public repository also
supplies independent vendor public signing trust as `vendor-public.jwks.json`.
If you received only a connected package, obtain that public trust independently
from LogForge and save it beside the Compose file. Keep it separate from
downloaded update payloads. Native AMD64 Docker operation is qualified; ARM64 hardware
qualification remains deferred.

## 1. Choose the installation address and data location

The defaults use `https://localhost`, ports 443/9443 and `./data`. To change
addresses, ports, data location or the initial Owner name, copy `.env.example`
to `.env` and edit those operator choices before startup. Use an absolute path
for a different data directory. Keep public URLs, host ports and certificate
DNS/IP names aligned. Image versions and generated secrets are not operator
choices.

For another installation on the same Docker host, choose a different
`CENTRAL_COMPOSE_PROJECT_NAME` and data directory. Running installations also
need different host ports.

For a local browser with remote Echo hosts, use a loopback Central URL,
`CENTRAL_OPERATOR_LOCALHOST_ENABLED=true` and explicit non-loopback Echo HTTPS
URLs. Certificate names must cover those hosts. Echo URLs do not become trusted
browser origins.

In the commands below, set `DATA` to that same data directory:

```bash
DATA="$PWD/data"
mkdir -p "$DATA"
```

## 2. Initialize, then start the verified release

```bash
docker compose pull
docker compose up --no-deps --exit-code-from storage-init storage-init
```

Continue only after initialization exits successfully. It verifies the signed
release, generates private secrets and writes the exact runtime configuration
under the data directory. Start with that generated configuration:

```bash
docker compose --project-directory "$PWD" \
  --env-file "$DATA/deployment.env" \
  -f "$DATA/product-updates/deployment/compose.yaml" up -d
```

Expected result: Central starts on the configured HTTPS address. Do not print,
publish or edit `deployment.env`; it contains generated credentials. Keep the
original installation directory and data in place.

## 3. Enable browser updates once

Download the updater payload for the installed version. The following copies
files from its public registry artifact without executing that artifact:

```bash
case "$(uname -m)" in
  x86_64) CPU=amd64 ;;
  aarch64|arm64) CPU=arm64 ;;
  *) echo "Unsupported Linux CPU" >&2; exit 1 ;;
esac
VERSION="$(cat "$DATA/product-updates/deployment/VERSION")"
CAPSULE="docker.io/junaidquraishi/unicron-business:release-$VERSION-$CPU"
docker pull --platform "linux/$CPU" "$CAPSULE"
EXPORTER="$(docker create --entrypoint /not-executed "$CAPSULE")"
mkdir -p update-package
docker cp "$EXPORTER:/unicron-release/." ./update-package/
docker rm "$EXPORTER"
```

Use a new, empty `update-package` directory. Leave its files, including
`operator.env`, unchanged. This is an update payload; it is not the initial
connected installer and does not contain offline image layers.

```bash
"$PWD/update-package/unicron-update" \
  --data-root "$DATA" \
  --installed-package "$PWD/update-package" \
  --trust "$PWD/vendor-public.jwks.json" setup-web
```

Expected result: setup reports configured and installs the native host update
service. It verifies the package and the running release before registration.
Keep the data, trust file and extracted package. Central does not receive a
Docker socket.

## 4. Sign in and use the update screen

Trust the installation's public CA at `data/pki/trust/root_ca.crt` through your
normal operating-system trust process, after checking it belongs to this
installation. Open the configured HTTPS address and set the first `owner`
password. Adjust that CA path if you chose another data directory.

Open **Settings > Updates & releases** as Owner:

- **Check for updates** downloads and verifies the signed release from Docker
  Hub. **No update is currently available** is the expected result when current.
- **Upload update file** accepts a complete vendor-signed offline tar. It uses
  the same update engine and image identities.
- When a verified successor is available, select **Update this installation**,
  read the notice and select **Update now**. Follow progress at the same address.
- Connect each Docker Echo updater once using its **Connect updater** action,
  then use **Update eligible agents** after Central completes. An unreachable
  agent remains unfinished.

After an interruption, reopen the recovery page or select **Open update
recovery**. Use **Resume update** for the recorded operation. **Restore previous
version** restores the saved PostgreSQL checkpoint after a data-loss
confirmation: database changes since that checkpoint are lost. Retained
telemetry, certificates and Echo identity/queued data are not rewound. Verify
the installed version, sign-in and telemetry after recovery.

## Startup and troubleshooting

Before the first product update, start an existing fresh installation with the
same generated runtime command from step 2:

```bash
docker compose --project-directory "$PWD" \
  --env-file "$DATA/deployment.env" \
  -f "$DATA/product-updates/deployment/compose.yaml" up -d
```

After a product update has created an operation journal, the host update engine
retains the active release and recovery state. Use its start command:

```bash
"$PWD/update-package/unicron-update" \
  --data-root "$DATA" \
  --installed-package "$PWD/update-package" \
  --trust "$PWD/vendor-public.jwks.json" start
```

Do not select product versions with `docker compose pull`, rerun the starter
Compose on an updated deployment, or delete containers, data or update journals
to resolve a failed operation. Keep the existing recovery point and use its
resume/restore controls. If setup says an image reference differs, finish step
2 with the generated Compose file. If it reports an edited package, use a fresh
untouched payload matching the installed version; do not bypass verification.

These are host commands, not automatic boot configuration. If you arrange host
startup, keep its command aligned with the installed release and update state.

### Verify readiness after startup or recovery

Set `ORIGIN` to the HTTPS address configured for this installation, including a
non-default port when used. This check uses the installation's CA without
bypassing certificate verification:

```bash
ORIGIN=https://localhost
curl --fail --show-error --cacert "$DATA/pki/trust/root_ca.crt" \
  "$ORIGIN/api/v1/health"
```

HTTP 200 means the health response was received; inspect its readiness result.
Before an Echo is enrolled, `readiness.profiles.setup.state` can be `ready`
while operator readiness is still blocked. Use **Add Remote Agent** to enroll
the intended Echo, then verify current inventory and fresh workload logs or
metrics in Central.

For normal operation, `readiness.profiles.operator.state` must be `ready` or
`ready_with_advisories`, and `readiness.requiredEcho.state` must be `current`.
Read the profile's `reasons` and `nextActions` for anything pending, degraded
or blocked. Keep visible advisories, such as a manual CA backup responsibility,
in the operating record. After a restart or restore, also verify the installed
version and sign-in, and confirm the existing Echo identities and retained
telemetry are still present. A running host or successful health request alone
does not establish those facts.

This is proprietary LogForge software. See `LICENSE` for applicable terms.
