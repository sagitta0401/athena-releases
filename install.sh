#!/bin/bash
# Installs the latest Athena release on this Mac (README, "Installing"; release.md "Installing on a
# fresh Mac", steps 1 and 2): downloads the zip and its checksum from GitHub Releases, checks the
# checksum and the code signature, puts Athena.app into /Applications and removes the quarantine
# attribute once, so that Gatekeeper opens the app, which is not notarized.
#
#   scripts/install.sh [--beta] [--version <x.y.z>] [--yes]
#
# --beta takes the newest release including pre-releases; --version a given one. An Athena.app already
# in /Applications is moved to the Trash first (asks unless --yes; quit Athena before). Needs only
# curl and the tools every macOS has (no Xcode, git, Python or gh), so it runs on a fresh Mac:
#   curl -fsSL https://raw.githubusercontent.com/sagitta0401/athena-releases/main/install.sh | bash
# Environment: RELEASE_REPO (owner/name; default sagitta0401/athena-releases), DESTINATION
# (default /Applications).
set -eu

RELEASE_REPO="${RELEASE_REPO:-sagitta0401/athena-releases}"
DESTINATION="${DESTINATION:-/Applications}"
beta=0
version=""
assume_yes=0
while [ $# -gt 0 ]; do
    case "$1" in
        --beta) beta=1 ;;
        --version) version="${2:?--version needs a version}"; shift ;;
        --yes) assume_yes=1 ;;
        -h|--help) awk 'NR > 1 && /^#/ { sub(/^# ?/, ""); print; next } NR > 1 { exit }' "$0"; exit 0 ;;
        *) echo "error: unknown argument $1" >&2; exit 64 ;;
    esac
    shift
done

die() { echo "error: $*" >&2; exit 1; }
ask() {  # ask <question>: true on y; reads the terminal, so it works under `curl | bash`
    [ $assume_yes -eq 1 ] && return 0
    printf '%s [y/N] ' "$1"
    local answer=""
    read -r answer </dev/tty || true
    [ "$answer" = y ] || [ "$answer" = Y ]
}

[ "$(uname -m)" = arm64 ] || die "Athena runs on Apple Silicon Macs only (this one is $(uname -m))"
major="$(sw_vers -productVersion | cut -d. -f1)"
[ "$major" -ge 26 ] || die "Athena needs macOS 26 or newer (this Mac has $(sw_vers -productVersion))"

work="$(mktemp -d "${TMPDIR:-/tmp}/athena-install.XXXXXX")"
trap 'rm -rf "$work"' EXIT

if [ -z "$version" ]; then
    if [ $beta -eq 1 ]; then
        curl -fsSL "https://api.github.com/repos/$RELEASE_REPO/releases?per_page=1" -o "$work/releases.json" ||
            die "cannot read the releases of $RELEASE_REPO"
        tag="$(plutil -extract 0.tag_name raw -o - "$work/releases.json" 2>/dev/null)" || die "no release found"
    else
        # /releases/latest redirects to the newest release that is not a pre-release.
        latest="$(curl -fsSLI -o /dev/null -w '%{url_effective}' "https://github.com/$RELEASE_REPO/releases/latest")" ||
            die "cannot reach https://github.com/$RELEASE_REPO/releases"
        tag="${latest##*/}"
        case "$tag" in v*) ;; *) die "no release found at https://github.com/$RELEASE_REPO/releases" ;; esac
    fi
    version="${tag#v}"
fi
name="Athena-$version"
base="https://github.com/$RELEASE_REPO/releases/download/v$version"

echo "== Athena $version from $RELEASE_REPO"
curl -fL --progress-bar "$base/$name.zip" -o "$work/$name.zip" || die "download failed: $base/$name.zip"
curl -fsSL "$base/$name.zip.sha256" -o "$work/$name.zip.sha256" || die "download failed: $base/$name.zip.sha256"
expected="$(cut -d' ' -f1 "$work/$name.zip.sha256")"
actual="$(openssl dgst -sha256 -r "$work/$name.zip" | cut -d' ' -f1)"
[ -n "$expected" ] && [ "$expected" = "$actual" ] || die "the checksum does not match (expected $expected, got $actual)"
echo "checksum ok"

ditto -x -k "$work/$name.zip" "$work/unzipped" || die "the zip does not extract"
app="$work/unzipped/Athena.app"
[ -d "$app" ] || die "the zip holds no Athena.app"
codesign --verify --deep --strict "$app" 2>/dev/null || die "the app's code signature does not verify"
echo "signature ok ($(codesign -dv "$app" 2>&1 | sed -n 's/^Authority=//p' | head -1 || true))"

target="$DESTINATION/Athena.app"
if [ -e "$target" ]; then
    if pgrep -x Athena >/dev/null 2>&1; then die "Athena is running: quit it, then run this again"; fi
    ask "Move the Athena.app in $DESTINATION to the Trash and install $version?" || die "nothing changed"
    mv "$target" "$HOME/.Trash/Athena $(date +%Y-%m-%d-%H%M%S).app" || die "could not move the old app to the Trash"
fi
ditto "$app" "$target" || die "could not copy Athena.app to $DESTINATION"
# Once per install: Gatekeeper would refuse the unnotarized app that a browser downloaded.
xattr -dr com.apple.quarantine "$target" 2>/dev/null || true
echo "installed $target"
echo "open it with: open \"$target\""
