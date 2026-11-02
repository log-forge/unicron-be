#!/usr/bin/env bash
set -euo pipefail
umask 077

fail() {
  printf 'LogForge setup stopped: %s\n' "$*" >&2
  exit 1
}

installer_lock_path() {
  local key
  key="$(printf '%s' "$1" | sha256sum)"
  printf '/run/lock/logforge-install-%s.lock\n' "${key%% *}"
}

require_install_host() {
  local root="$1"
  shift
  if [[ "${EUID}" -ne 0 ]]; then
    exec sudo -- bash "$root/install.sh" "$@"
  fi
  [[ "$#" -eq 0 ]] || fail 'Configure optional addresses and storage in .env, then run ./install.sh.'
  [[ "$(uname -s)" == Linux && "$(uname -m)" == x86_64 ]] || fail 'This installer currently qualifies native Linux AMD64 hosts.'
  command -v docker >/dev/null || fail 'Install Docker Engine and its Compose plugin first.'
  command -v realpath >/dev/null || fail 'The Linux realpath utility is required.'
  command -v flock >/dev/null || fail 'The Linux flock utility is required.'
  [[ -d /run/systemd/system ]] || fail 'Run on the Linux Docker host with systemd.'
  systemctl show-environment >/dev/null || fail 'The host administrator must have access to systemd.'
}

main() {
  local root data public_url key value resolved version work capsule exporter image_key image_ref image_tag image_config image_platform
  local installer_lock installer_fd operation_root operation_lock operation_fd
  root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
  require_install_host "$root" "$@"
  cd -- "$root"
  [[ -f compose.yaml && -f vendor-public.jwks.json ]] || fail 'Keep install.sh beside the public Compose file and independent vendor trust.'
  docker compose version >/dev/null
  docker info >/dev/null

  # Compose owns .env quoting and interpolation. Read only operator choices from
  # its resolved environment; never source .env as executable shell code.
  resolved="$(docker compose config --environment)"
  data="$root/data"
  public_url=https://localhost
  while IFS='=' read -r key value; do
    case "$key" in
      CENTRAL_OPERATOR_DATA_ROOT) [[ -z "$value" ]] || data="$value" ;;
      CENTRAL_PUBLIC_URL) [[ -z "$value" ]] || public_url="$value" ;;
    esac
  done <<< "$resolved"
  unset resolved
  [[ "$data" == /* && "$data" != / && "$(realpath -m -- "$data")" == "$data" ]] || fail 'Choose an absolute canonical data directory without aliases.'
  installer_lock="$(installer_lock_path "$data")"
  [[ ! -L "$installer_lock" && ( ! -e "$installer_lock" || -f "$installer_lock" ) ]] || fail 'The installation lock is not a regular local file.'
  exec {installer_fd}>>"$installer_lock"
  flock -n "$installer_fd" || fail 'Another installer is already preparing this data directory.'
  [[ ! -e "$data/operator-updates/current.json" && ! -L "$data/operator-updates/current.json" ]] || fail 'This deployment has recorded update/recovery state. Use its update screen or recorded start command; the existing data is preserved.'

  if [[ ! -e "$data/deployment.env" ]]; then
    mkdir -p -- "$data"
    printf 'Downloading the published bootstrap and initializing this deployment…\n'
    docker compose pull
    docker compose up --no-deps --exit-code-from storage-init storage-init
  fi
  [[ -f "$data/deployment.env" && ! -L "$data/deployment.env" ]] || fail 'Initialization did not produce a regular deployment environment.'
  [[ -f "$data/product-updates/deployment/compose.yaml" ]] || fail 'The signed runtime configuration is missing.'
  operation_root="$data/operator-updates"
  if [[ ! -e "$operation_root" ]]; then
    mkdir -m 700 -- "$operation_root"
  fi
  [[ -d "$operation_root" && ! -L "$operation_root" && "$(stat -c %a -- "$operation_root")" == 700 ]] || fail 'The existing operator state directory must remain private.'
  operation_lock="$operation_root/lock"
  [[ ! -L "$operation_lock" && ( ! -e "$operation_lock" || -f "$operation_lock" ) ]] || fail 'The operator lock is not a regular local file.'
  exec {operation_fd}>>"$operation_lock"
  flock -n "$operation_fd" || fail 'A product update or recovery action is active; finish it before setup.'
  [[ ! -e "$operation_root/current.json" && ! -L "$operation_root/current.json" ]] || fail 'A recorded product operation must be managed through its existing controls.'
  version="$(cat -- "$data/product-updates/deployment/VERSION")"
  [[ "$version" =~ ^[0-9]{4}\.[0-9]{2}\.[0-9]{2}\.[0-9]+$ ]] || fail 'The initialized release identity is invalid.'

  printf 'Starting the verified release %s…\n' "$version"
  docker compose --project-directory "$root" --env-file "$data/deployment.env" \
    -f "$data/product-updates/deployment/compose.yaml" up -d --wait --wait-timeout 180

  work="$(mktemp -d "$root/.logforge-setup.XXXXXXXX")"
  capsule="docker.io/junaidquraishi/unicron-business:release-$version-amd64"
  printf 'Obtaining the matching signed update package…\n'
  docker pull --platform linux/amd64 "$capsule"
  exporter="$(docker create --entrypoint /not-executed "$capsule")"
  if ! docker cp "$exporter:/unicron-release/." "$work/"; then
    docker rm "$exporter" >/dev/null
    fail "Package extraction failed; preserve $work for review."
  fi
  docker rm "$exporter" >/dev/null

  # setup-web verifies the complete registry projection, including IMAGE_LOCK,
  # before any inventory row is consumed. It retains its own private package copy.
  "$work/unicron-update" --data-root "$data" --installed-package "$work" \
    --trust "$root/vendor-public.jwks.json" setup-web
  "$work/unicron-update" --data-root "$data" --installed-package "$work" \
    --trust "$root/vendor-public.jwks.json" verify-platform

  printf 'Downloading the complete signed release inventory…\n'
  while IFS="$(printf '\t')" read -r image_key image_ref image_tag image_config; do
    case "$image_key" in
      *_ARM64_*) image_platform=linux/arm64 ;;
      *_AMD64_*) image_platform=linux/amd64 ;;
      *) image_platform=linux/amd64 ;;
    esac
    docker pull --platform "$image_platform" "$image_ref"
  done < "$work/IMAGE_LOCK"

  # Keep a predictable source package for later administrator start/recovery
  # commands, while preserving any package an earlier setup already retained.
  if [[ ! -e "$root/update-package" && ! -L "$root/update-package" ]]; then
    mv -- "$work" "$root/update-package"
    work="$root/update-package"
  fi

  printf '\nLogForge %s is installed and browser updates are configured.\n' "$version"
  printf 'Open %s to sign in or finish first Owner setup and add the Docker host.\n' "$public_url"
  printf 'Keep the data directory: %s\n' "$data"
  printf 'Keep this original source package for start/recovery commands: %s\n' "$work"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
