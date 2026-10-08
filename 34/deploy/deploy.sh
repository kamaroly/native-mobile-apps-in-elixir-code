#!/usr/bin/env bash
# deploy/deploy.sh: runs on the server, as the deploy user.
#
#   ~/deploy.sh ~/risiti-<commit>.tar.gz
#
# Unpacks the release next to the old ones, migrates, points
# /opt/risiti/current at it, and restarts the three instances one at a time.
set -euo pipefail

TARBALL="$1"
VERSION="$(basename "$TARBALL" .tar.gz)"
APP_DIR=/opt/risiti
RELEASE_DIR="$APP_DIR/releases/$VERSION"
PORTS=(4000 4001 4002)

echo "==> Unpacking $VERSION"
mkdir -p "$RELEASE_DIR"
tar -xzf "$TARBALL" -C "$RELEASE_DIR"
rm -f "$TARBALL"

echo "==> Migrating"
# The same variables the instances get from systemd.
set -a
source /etc/risiti/risiti.env
set +a
"$RELEASE_DIR/bin/migrate"

echo "==> Switching to $VERSION"
PREVIOUS="$(readlink -f "$APP_DIR/current" || true)"
ln -sfn "$RELEASE_DIR" "$APP_DIR/current"

# True once something answers HTTP on the port (any status will do).
answers() {
  for _ in $(seq 1 30); do
    curl -s -o /dev/null "http://127.0.0.1:$1/" && return 0
    sleep 1
  done
  return 1
}

for port in "${PORTS[@]}"; do
  echo "==> Restarting port $port"
  sudo systemctl restart "risiti@$port"

  if ! answers "$port"; then
    echo "!! Port $port didn't come back. The ports after it still run the old release." >&2
    echo "!! To go back: ln -sfn $PREVIOUS $APP_DIR/current, then restart risiti@$port" >&2
    exit 1
  fi
done

echo "==> Keeping the last five releases"
ls -1dt "$APP_DIR"/releases/*/ | tail -n +6 | xargs -r rm -rf

echo "==> $VERSION is live"
