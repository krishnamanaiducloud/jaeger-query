#!/bin/sh
# apk-install [--upgrade] PACKAGE...
# `apk add` for networks where some downloads stall: apk otherwise waits ~15 minutes on a
# stalled package. Runs apk with a package cache under a timeout and retries; packages already
# downloaded stay in the cache, so each attempt only fetches what is missing. Packages are
# verified against the signed repository index as usual. The cache is removed afterwards.
set -eu

upgrade=
if [ "${1:-}" = "--upgrade" ]; then
  upgrade=1
  shift
fi

# Packages come from the public Wolfi repository (the base image trusts its key); large
# downloads redirected from apk.cgr.dev stalled repeatedly on some networks.
echo https://packages.wolfi.dev/os > /etc/apk/repositories

mkdir -p /var/cache/apk
ln -sfn /var/cache/apk /etc/apk/cache
cleanup() { rm -f /etc/apk/cache; rm -rf /var/cache/apk/*; }
trap cleanup EXIT

# run SECONDS COMMAND...: retry COMMAND, killing it outright when it runs too long.
run() {
  limit=$1
  shift
  attempt=1
  until timeout -s KILL "$limit" "$@"; do
    if [ "$attempt" -ge 40 ]; then
      echo "apk-install: '$*' still failing after $attempt attempts" >&2
      return 1
    fi
    attempt=$((attempt + 1))
    echo "apk-install: retrying '$*' (attempt $attempt)" >&2
    sleep 2
  done
}

run 60 apk update -q
[ "$#" -eq 0 ] || run 150 apk add "$@"
[ -z "$upgrade" ] || run 150 apk upgrade
