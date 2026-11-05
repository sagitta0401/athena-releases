#!/bin/bash
# Removes Athena from this Mac: the app and everything it keeps outside your vaults (README, "Uninstalling";
# release.md, "Data locations"). Your notes, books and chats are never touched: they are files in your vault.
#
#   uninstall.sh [--dry-run] [--yes] [--vault-state]
#
# Moved to the Trash (so a mistake can be undone until the Trash is emptied):
#   - Athena.app in /Applications;
#   - ~/Library/Application Support/Athena: each vault's search index and caches, the keymap, the model lists;
#   - ~/Library/Caches/com.sagitta0401.Athena (downloaded updates), ~/Library/HTTPStorages/com.sagitta0401.Athena*,
#     ~/Library/WebKit/com.sagitta0401.Athena and ~/Library/Saved Application State/com.sagitta0401.Athena.savedState;
#   - Athena's crash reports in ~/Library/Logs/DiagnosticReports.
# Deleted (they cannot go to the Trash):
#   - the settings, the defaults domain com.sagitta0401.Athena;
#   - the Keychain items Athena wrote: the AI keys ("Athena ANTHROPIC_API_KEY", "Athena OPENROUTER_API_KEY") and the
#     passwords of protected PDFs ("Athena PDF password").
# Asked separately, and kept unless you answer y (or pass --vault-state): the hidden .athena folder in each vault
# Athena remembers (the open tabs, the graph's layout, the vault's id). Without it the vault is plain Markdown again.
# Never touched: everything else in a vault (notes, books, chats, templates, its .trash), the diagnostics zips you
# saved, macOS's own log (it expires by itself), and a developer's Sparkle signing key.
#
# --dry-run lists what would go and changes nothing; --yes answers y to the main question. Quit Athena first.
# Needs only the tools every macOS has, so it runs with the app gone or not starting:
#   curl -fsSL https://raw.githubusercontent.com/sagitta0401/athena-releases/main/uninstall.sh | bash
# Environment: DESTINATION (where Athena.app is; default /Applications).
set -u

DESTINATION="${DESTINATION:-/Applications}"
BUNDLE_ID="com.sagitta0401.Athena"
KEYCHAIN_SERVICES=("Athena ANTHROPIC_API_KEY" "Athena OPENROUTER_API_KEY" "Athena PDF password")
dry_run=0
assume_yes=0
vault_state=0
while [ $# -gt 0 ]; do
    case "$1" in
        --dry-run) dry_run=1 ;;
        --yes) assume_yes=1 ;;
        --vault-state) vault_state=1 ;;
        -h|--help) awk 'NR > 1 && /^#/ { sub(/^# ?/, ""); print; next } NR > 1 { exit }' "$0"; exit 0 ;;
        *) echo "error: unknown argument $1" >&2; exit 64 ;;
    esac
    shift
done

die() { echo "error: $*" >&2; exit 1; }
ask() {  # ask <question> [yes-flag]: true on y; reads the terminal, so it works under `curl | bash`
    [ "${2:-0}" -eq 1 ] && return 0
    printf '%s [y/N] ' "$1"
    local answer=""
    read -r answer </dev/tty || true
    [ "$answer" = y ] || [ "$answer" = Y ]
}
size_of() { du -sh "$1" 2>/dev/null | cut -f1 | tr -d ' '; }

[ -n "${HOME:-}" ] && [ -d "$HOME" ] || die "no home folder"
trash="$HOME/.Trash"
library="$HOME/Library"
if pgrep -x Athena >/dev/null 2>&1; then die "Athena is running: quit it, then run this again"; fi

# What there is to move to the Trash.
items=()
add() { [ -e "$1" ] && items+=("$1"); }
add "$DESTINATION/Athena.app"
add "$library/Application Support/Athena"
add "$library/Caches/$BUNDLE_ID"
for item in "$library/HTTPStorages/$BUNDLE_ID" "$library/HTTPStorages/$BUNDLE_ID".*; do add "$item"; done
add "$library/WebKit/$BUNDLE_ID"
add "$library/Saved Application State/$BUNDLE_ID.savedState"
for item in "$library/Logs/DiagnosticReports"/Athena-*.ips "$library/Logs/DiagnosticReports"/Athena_*.diag; do add "$item"; done

# The settings, and the vaults they remember (`recentVaults`: JSON entries with an absolute `path`).
settings="$(defaults export "$BUNDLE_ID" - 2>/dev/null || true)"
has_settings=0
case "$settings" in *"<key>"*) has_settings=1 ;; esac
vaults=()
if [ $has_settings -eq 1 ]; then
    encoded="$(printf '%s' "$settings" | plutil -extract recentVaults raw -o - - 2>/dev/null || true)"
    if [ -n "$encoded" ]; then
        json="$(printf '%s' "$encoded" | base64 --decode 2>/dev/null || true)"
        i=0
        while path="$(printf '%s' "$json" | plutil -extract "$i.path" raw -o - - 2>/dev/null)"; do
            [ -d "$path/.athena" ] && vaults+=("$path")
            i=$((i + 1))
            [ $i -lt 100 ] || break
        done
    fi
fi

# The Keychain items: `security` finds them by service, one call per item.
keychain=()
for service in "${KEYCHAIN_SERVICES[@]}"; do
    security find-generic-password -s "$service" >/dev/null 2>&1 && keychain+=("$service")
done

if [ ${#items[@]} -eq 0 ] && [ $has_settings -eq 0 ] && [ ${#keychain[@]} -eq 0 ] && [ ${#vaults[@]} -eq 0 ]; then
    echo "Athena is not on this Mac: nothing to remove."
    exit 0
fi

echo "== Athena on this Mac"
if [ ${#items[@]} -gt 0 ]; then
    echo "To the Trash:"
    reports=0
    for item in "${items[@]}"; do
        case "$item" in "$library/Logs/DiagnosticReports"/*) reports=$((reports + 1)); continue ;; esac
        echo "  $item ($(size_of "$item"))"
    done
    [ $reports -gt 0 ] && echo "  $reports crash reports of Athena in $library/Logs/DiagnosticReports"
fi
if [ $has_settings -eq 1 ] || [ ${#keychain[@]} -gt 0 ]; then
    echo "Deleted:"
    [ $has_settings -eq 1 ] && echo "  the settings (defaults domain $BUNDLE_ID)"
    for service in ${keychain[@]+"${keychain[@]}"}; do echo "  the Keychain item \"$service\""; done
fi
if [ ${#vaults[@]} -gt 0 ]; then
    echo "Asked separately (kept unless you say y):"
    for vault in "${vaults[@]}"; do echo "  $vault/.athena ($(size_of "$vault/.athena"))"; done
fi
echo "Your notes, books and chats stay where they are."

if [ $dry_run -eq 1 ]; then
    echo "dry run: nothing changed"
    exit 0
fi
ask "Remove Athena from this Mac?" $assume_yes || { echo "nothing changed"; exit 0; }

[ -d "$trash" ] || die "no Trash at $trash"
stamp="$(date +%Y-%m-%d-%H%M%S)"
failed=0
to_trash() {  # to_trash <path> [name]: moves it into the Trash as <name> (its own by default), unique there
    local name="${2:-$(basename "$1")}" base ext target n=1
    case "$name" in
        *.app|*.ips|*.diag|*.savedState) base="${name%.*}"; ext=".${name##*.}" ;;
        *) base="$name"; ext="" ;;
    esac
    target="$trash/$name"
    while [ -e "$target" ]; do
        [ $n -eq 1 ] && target="$trash/$base $stamp$ext" || target="$trash/$base $stamp $n$ext"
        n=$((n + 1))
    done
    if mv "$1" "$target" 2>/dev/null; then return 0; fi
    echo "  could not move $1 to the Trash" >&2
    failed=1
    return 1
}

for item in ${items[@]+"${items[@]}"}; do to_trash "$item"; done
[ ${#items[@]} -gt 0 ] && echo "moved ${#items[@]} items to the Trash"
if [ $has_settings -eq 1 ]; then
    if defaults delete "$BUNDLE_ID" >/dev/null 2>&1; then echo "deleted the settings"; else echo "  could not delete the settings" >&2; failed=1; fi
fi
for service in ${keychain[@]+"${keychain[@]}"}; do
    # One item per call; the PDF passwords are one item per book.
    count=0
    while security delete-generic-password -s "$service" >/dev/null 2>&1; do
        count=$((count + 1))
        [ $count -lt 1000 ] || break
    done
    if security find-generic-password -s "$service" >/dev/null 2>&1; then
        echo "  could not delete the Keychain item \"$service\"" >&2
        failed=1
    else
        echo "deleted the Keychain item \"$service\" ($count)"
    fi
done
for vault in ${vaults[@]+"${vaults[@]}"}; do
    if ask "Move $vault/.athena to the Trash too?" $vault_state; then
        # Named after its vault: a folder whose name starts with a dot would not show in the Trash.
        to_trash "$vault/.athena" "$(basename "$vault") (.athena)" && echo "moved $vault/.athena to the Trash"
    else
        echo "kept $vault/.athena"
    fi
done

if [ $failed -eq 1 ]; then
    echo "Athena is mostly removed; the lines above say what is left."
    exit 1
fi
echo "Athena is removed from this Mac. Empty the Trash to free the space for good."
