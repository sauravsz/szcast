#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TRACK_FILE="$REPO_ROOT/.upstream-synced"

cd "$REPO_ROOT"

if [[ ! -f "$TRACK_FILE" ]]; then
    echo "6fa8ba1225be0777ef769f1816bffc7da213f91d" > "$TRACK_FILE"
fi

LAST_SYNCED=$(cat "$TRACK_FILE" | tr -d '[:space:]')

if [[ "${1:-}" == "--mark-reviewed" ]] || [[ "${1:-}" == "--mark" ]]; then
    git fetch upstream main --quiet
    NEW_HEAD=$(git rev-parse upstream/main)
    echo "$NEW_HEAD" > "$TRACK_FILE"
    echo "Marked upstream reviewed up to $NEW_HEAD ($(git log -1 --format='%s' "$NEW_HEAD"))."
    exit 0
fi

echo "Fetching latest from upstream..."
git fetch upstream main --quiet

UPSTREAM_HEAD=$(git rev-parse upstream/main)

if [[ "$LAST_SYNCED" == "$UPSTREAM_HEAD" ]]; then
    echo "szcast is up to date with upstream."
    echo "Last reviewed commit: $LAST_SYNCED ($(git log -1 --format='%h %s (%cr)' "$LAST_SYNCED"))"
    echo "New commits: 0"
    exit 0
fi

NEW_COUNT=$(git rev-list --count "$LAST_SYNCED..upstream/main")
echo "Found $NEW_COUNT new upstream commit(s) since $(git log -1 --format='%h (%cr)' "$LAST_SYNCED"):"
echo ""

while IFS= read -r commit_hash; do
    SUBJECT=$(git log -1 --format='%s' "$commit_hash")
    AUTHOR=$(git log -1 --format='%an' "$commit_hash")
    DATE=$(git log -1 --format='%cr' "$commit_hash")
    FILES=$(git diff-tree --no-commit-id --name-only -r "$commit_hash")

    IS_APP=false
    IS_TEST=false
    IS_DOC=false
    IS_NOISE=true

    while IFS= read -r f; do
        if [[ -z "$f" ]]; then continue; fi
        if [[ "$f" =~ ^(Tinycast|szcast)/ ]]; then
            IS_APP=true
            IS_NOISE=false
        elif [[ "$f" =~ ^Tests/ ]]; then
            IS_TEST=true
            IS_NOISE=false
        elif [[ "$f" =~ ^docs/ ]]; then
            IS_DOC=true
            IS_NOISE=false
        elif [[ "$f" =~ ^(website|\.github)/ ]]; then
            :
        else
            IS_NOISE=false
        fi
    done <<< "$FILES"

    TAG="[OTHER]"
    if $IS_APP; then
        TAG="[APP CODE - REVIEW]"
    elif $IS_TEST; then
        TAG="[TESTS ONLY]"
    elif $IS_DOC; then
        TAG="[DOCS ONLY]"
    elif $IS_NOISE; then
        TAG="[NOISE - SKIP]"
    fi

    printf "%-22s %-10s %s (%s, %s)\n" "$TAG" "$(git rev-parse --short "$commit_hash")" "$SUBJECT" "$AUTHOR" "$DATE"
done < <(git rev-list --reverse "$LAST_SYNCED..upstream/main")

echo ""
echo "To inspect a commit:  git show <commit-hash>"
echo "To mark current upstream as reviewed: ./Scripts/upstream-radar.sh --mark-reviewed"
