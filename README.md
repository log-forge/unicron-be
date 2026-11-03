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

Use native Linux AMD64 with Git, Docker Engine, Compose v2 and systemd.
The public repository includes `install.sh` and independent vendor signing trust.
Leave update headroom: the native updater requires at least 4 GiB of available
memory and 4 GiB of free disk, beyond resources used by running services.
Also allow storage for downloads and the database checkpoint. These free-resource
checks are separate from workload-specific total machine sizing.
For this normal online path, choose optional settings below, then run:

```bash
sudo bash ./install.sh
```

The installer verifies the published release, starts its generated runtime,
configures the native updater and downloads the complete signed image inventory.
It keeps the original source package at `update-package` on first success and
prints its path. Preserve that package and the data directory. If setup finds
recorded update/recovery state, it stops without replacing that deployment;
use its existing update controls instead. Open the configured HTTPS address to
finish Owner setup, then enroll your Docker host. No product source build or
manual image pulls are required.

The detailed commands below are also available for administrators who received
the four-file connected package without `install.sh`. Use a Linux administrator
shell (`sudo -s`), from the folder containing `compose.yaml`. Obtain independent
vendor public signing trust from LogForge if the package does not include it;
keep trust separate from downloaded payloads. ARM64 hardware qualification
remains deferred.

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

For the manual fallback and later checks, set `DATA` to that same data directory:

```bash
DATA="$PWD/data"
mkdir -p "$DATA"
```

## 2. Manual fallback: initialize and start

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

## 3. Manual fallback: enable browser updates once

Download the updater payload for the installed version. The following copies
files from its public registry artifact without executing that artifact:

Run the following block only after step 2 succeeds. `update-package` must not
already exist: preserve an existing directory and check your earlier setup
before retrying. The block stops on a failed command.

```bash
(
  set -e
  mkdir update-package
  case "$(uname -m)" in
    x86_64) CPU=amd64 ;;
    aarch64|arm64) CPU=arm64 ;;
    *) echo "Unsupported Linux CPU" >&2; exit 1 ;;
  esac
  VERSION="$(cat "$DATA/product-updates/deployment/VERSION")"
  CAPSULE="docker.io/junaidquraishi/unicron-business:release-$VERSION-$CPU"
  docker pull --platform "linux/$CPU" "$CAPSULE"
  EXPORTER="$(docker create --entrypoint /not-executed "$CAPSULE")"
  docker cp "$EXPORTER:/unicron-release/." ./update-package/
  docker rm "$EXPORTER"
)
```

Leave the extracted files, including `operator.env`, unchanged. This is an update
payload; it is not the initial connected installer and does not contain offline
image layers.

Register the native update service and download the installed release's complete
signed image inventory in the same preparation block. `setup-web` verifies the
package, including `IMAGE_LOCK`, against independent vendor trust before the
inventory is read. The CPU check follows that complete verification.

```bash
(
  set -e
  "$PWD/update-package/unicron-update" \
    --data-root "$DATA" \
    --installed-package "$PWD/update-package" \
    --trust "$PWD/vendor-public.jwks.json" setup-web
  "$PWD/update-package/unicron-update" \
    --data-root "$DATA" \
    --installed-package "$PWD/update-package" \
    --trust "$PWD/vendor-public.jwks.json" verify-platform
  case "$(uname -m)" in
    x86_64) SOURCE_PLATFORM=linux/amd64 ;;
    aarch64|arm64) SOURCE_PLATFORM=linux/arm64 ;;
    *) echo "Unsupported Linux CPU" >&2; exit 1 ;;
  esac
  while IFS="$(printf '\t')" read -r IMAGE_KEY IMAGE_REF IMAGE_TAG IMAGE_CONFIG; do
    case "$IMAGE_KEY" in
      *_ARM64_*) IMAGE_PLATFORM=linux/arm64 ;;
      *_AMD64_*) IMAGE_PLATFORM=linux/amd64 ;;
      *) IMAGE_PLATFORM="$SOURCE_PLATFORM" ;;
    esac
    docker pull --platform "$IMAGE_PLATFORM" "$IMAGE_REF"
  done < "$PWD/update-package/IMAGE_LOCK"
)
```

Continue only after setup and every download succeeds. Keep the extracted package
and its `IMAGE_LOCK` unchanged. Helper and agent images are part of the release
inventory even when its running services have not downloaded them.

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

Keep `DATA` set to the retained data directory. If the automatic installer
reported a different source-package path, use it instead of `update-package`
in administrator commands. Re-running `install.sh` is for interrupted initial
setup; it refuses deployments with a recorded product operation.


Before the first product update, start an existing fresh installation with the
same generated runtime command from step 2:

```bash
docker compose --project-directory "$PWD" \
  --env-file "$DATA/deployment.env" \
  -f "$DATA/product-updates/deployment/compose.yaml" up -d
```

After a product update has created an operation journal, the host update engine
retains the active release and recovery state. With `DATA` set to the original
absolute data directory and Python 3.9 or newer installed, use the installed native executor.
Its executable may be newer than the original source package; preserve both:

```bash
sudo python3 - "$DATA" <<'PY'
import json
import os
from pathlib import Path
import sys

data = Path(sys.argv[1])
if not data.is_absolute() or data == Path("/") or data.resolve(strict=True) != data:
    raise SystemExit("Use the original absolute data directory without aliases.")
root = data / "operator-web"
config = json.loads((root / "config.json").read_text())
if config["dataRoot"] != str(data):
    raise SystemExit("The updater belongs to another data directory.")
receipt = root / "executor.json"
transition = json.loads(receipt.read_text()) if receipt.exists() else {}
if transition.get("pendingPackage"):
    raise SystemExit("Finish the interrupted updater refresh: repeat its same setup-web --executor-package command before starting.")
executor = transition.get("currentPackage", config["installedPackage"])
binary = Path(executor) / "unicron-update"
if not binary.is_relative_to(root / "packages") or binary.resolve(strict=True) != binary:
    raise SystemExit("The installed native updater path is unavailable or aliased.")
os.execv(str(binary), [str(binary), "--data-root", str(data),
    "--installed-package", config["installedPackage"], "--trust", config["trustPath"], "start"])
PY
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
