#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SZCAST_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
REPOS_PARENT="$(cd "$SZCAST_ROOT/.." && pwd)"

MODE="audit"
TARGET="all"

usage() {
    cat <<'EOF'
Usage:
  ./Scripts/upstream-radar.sh [all|tinycast|enviouswispr|macparakeet]
  ./Scripts/upstream-radar.sh --mark-reviewed [all|tinycast|enviouswispr|macparakeet]
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --mark-reviewed|--mark)
            MODE="mark"
            ;;
        all|tinycast|enviouswispr|macparakeet)
            TARGET="$1"
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown argument: $1" >&2
            usage >&2
            exit 2
            ;;
    esac
    shift
done

resolve_repo() {
    case "$1" in
        tinycast)
            REPO_LABEL="Tinycast (abue-ammar/tinycast)"
            REPO_DIR="$SZCAST_ROOT"
            REMOTE_NAME="upstream"
            BRANCH_NAME="main"
            REMOTE_URL="https://github.com/abue-ammar/tinycast.git"
            TRACK_FILE="$SZCAST_ROOT/.upstream-synced"
            DEFAULT_BASE="6fa8ba1225be0777ef769f1816bffc7da213f91d"
            SHOW_PREFIX="git show"
            ;;
        enviouswispr)
            REPO_LABEL="EnviousWispr (saurabhav88/EnviousWispr)"
            REPO_DIR="$REPOS_PARENT/EnviousWispr"
            REMOTE_NAME="origin"
            BRANCH_NAME="main"
            REMOTE_URL="https://github.com/saurabhav88/EnviousWispr.git"
            TRACK_FILE="$SZCAST_ROOT/.enviouswispr-synced"
            DEFAULT_BASE="3beac2d7fa7a4d171be0ccbca8e5eea44f84a587"
            SHOW_PREFIX="git -C \"../EnviousWispr\" show"
            ;;
        macparakeet)
            REPO_LABEL="MacParakeet (moona3k/macparakeet)"
            REPO_DIR="$REPOS_PARENT/macparakeet"
            REMOTE_NAME="origin"
            BRANCH_NAME="main"
            REMOTE_URL="https://github.com/moona3k/macparakeet.git"
            TRACK_FILE="$SZCAST_ROOT/.macparakeet-synced"
            DEFAULT_BASE="2545f91c9e1fead7b29a85c2485ae899a8d506e4"
            SHOW_PREFIX="git -C \"../macparakeet\" show"
            ;;
    esac
}

ensure_repo_ready() {
    if [[ ! -d "$REPO_DIR/.git" ]]; then
        echo "Cloning $REPO_LABEL into $REPO_DIR..."
        git clone --depth=250 "$REMOTE_URL" "$REPO_DIR" --quiet
    fi
    if [[ ! -f "$TRACK_FILE" ]]; then
        echo "$DEFAULT_BASE" > "$TRACK_FILE"
    fi
}

fetch_with_baseline() {
    local last_synced="$1"
    git -C "$REPO_DIR" fetch "$REMOTE_NAME" "$BRANCH_NAME" --quiet
    # Deepen shallow clones if the reviewed baseline sits outside the fetched depth.
    if [[ -f "$REPO_DIR/.git/shallow" ]] && ! git -C "$REPO_DIR" cat-file -e "${last_synced}^{commit}" 2>/dev/null; then
        git -C "$REPO_DIR" fetch "$REMOTE_NAME" "$BRANCH_NAME" --deepen=250 --quiet || true
    fi
}

classify_file() {
    local repo_key="$1"
    local file_path="$2"
    case "$repo_key" in
        tinycast)
            if [[ "$file_path" =~ ^(Tinycast|szcast|Szcast)/ ]]; then
                echo "app"
            elif [[ "$file_path" =~ ^Tests/ ]]; then
                echo "test"
            elif [[ "$file_path" =~ ^(docs/|README\.md$) ]]; then
                echo "doc"
            elif [[ "$file_path" =~ ^(website|\.github)/ ]]; then
                echo "noise"
            else
                echo "other"
            fi
            ;;
        enviouswispr)
            if [[ "$file_path" =~ ^(Sources|workers|Vendor)/ ]]; then
                echo "app"
            elif [[ "$file_path" =~ ^Tests/ ]]; then
                echo "test"
            elif [[ "$file_path" =~ ^(docs/|README\.md$) ]]; then
                echo "doc"
            elif [[ "$file_path" =~ ^(website|\.github|assets|benchmark-results|\.validation|reference)/ ]]; then
                echo "noise"
            else
                echo "other"
            fi
            ;;
        macparakeet)
            if [[ "$file_path" =~ ^(Sources/|Package\.swift$) ]]; then
                echo "app"
            elif [[ "$file_path" =~ ^Tests/ ]]; then
                echo "test"
            elif [[ "$file_path" =~ ^(docs/|spec/|plans/|README\.md$|CLAUDE\.md$|AGENTS\.md$) ]]; then
                echo "doc"
            elif [[ "$file_path" =~ ^(diagnostics/|marketing/|screenshots/|brand-assets/|Assets/|benchmarks/|scripts/|\.github/|THIRD_PARTY_LICENSES\.md$|LICENSE$) ]]; then
                echo "noise"
            else
                echo "other"
            fi
            ;;
    esac
}

mark_repo() {
    local repo_key="$1"
    resolve_repo "$repo_key"
    ensure_repo_ready
    git -C "$REPO_DIR" fetch "$REMOTE_NAME" "$BRANCH_NAME" --quiet
    local new_head
    new_head="$(git -C "$REPO_DIR" rev-parse "$REMOTE_NAME/$BRANCH_NAME")"
    echo "$new_head" > "$TRACK_FILE"
    echo "Marked $REPO_LABEL reviewed up to $new_head ($(git -C "$REPO_DIR" log -1 --format='%s' "$new_head"))."
}

audit_repo() {
    local repo_key="$1"
    resolve_repo "$repo_key"
    ensure_repo_ready

    local last_synced
    last_synced="$(tr -d '[:space:]' < "$TRACK_FILE")"

    echo "================================================================================"
    echo "$REPO_LABEL"
    echo "================================================================================"
    echo "Fetching latest from $REMOTE_NAME/$BRANCH_NAME..."
    fetch_with_baseline "$last_synced"

    local remote_head
    remote_head="$(git -C "$REPO_DIR" rev-parse "$REMOTE_NAME/$BRANCH_NAME")"

    if [[ "$last_synced" == "$remote_head" ]]; then
        echo "Up to date ($repo_key)."
        echo "Last reviewed commit: $last_synced ($(git -C "$REPO_DIR" log -1 --format='%h %s (%cr)' "$last_synced"))"
        echo "New commits: 0"
        echo ""
        return 0
    fi

    if ! git -C "$REPO_DIR" cat-file -e "${last_synced}^{commit}" 2>/dev/null; then
        echo "Baseline $last_synced is not present locally after shallow fetch; showing latest 30 commits instead."
        git -C "$REPO_DIR" log -n 30 --oneline "$REMOTE_NAME/$BRANCH_NAME"
        echo ""
        return 0
    fi

    local new_count
    new_count="$(git -C "$REPO_DIR" rev-list --count "$last_synced..$REMOTE_NAME/$BRANCH_NAME")"
    echo "Found $new_count new commit(s) since $(git -C "$REPO_DIR" log -1 --format='%h (%cr)' "$last_synced"):"
    echo ""

    while IFS= read -r commit_hash; do
        local subject author date files
        subject="$(git -C "$REPO_DIR" log -1 --format='%s' "$commit_hash")"
        author="$(git -C "$REPO_DIR" log -1 --format='%an' "$commit_hash")"
        date="$(git -C "$REPO_DIR" log -1 --format='%cr' "$commit_hash")"
        files="$(git -C "$REPO_DIR" diff-tree -m --first-parent --no-commit-id --name-only -r "$commit_hash")"

        local is_app=false is_test=false is_doc=false is_noise=true
        while IFS= read -r f; do
            if [[ -z "$f" ]]; then continue; fi
            case "$(classify_file "$repo_key" "$f")" in
                app)   is_app=true;  is_noise=false ;;
                test)  is_test=true; is_noise=false ;;
                doc)   is_doc=true;  is_noise=false ;;
                noise) ;;
                other) is_noise=false ;;
            esac
        done <<< "$files"

        local tag="[OTHER]"
        if $is_app; then
            tag="[APP CODE - REVIEW]"
        elif $is_test; then
            tag="[TESTS ONLY]"
        elif $is_doc; then
            tag="[DOCS ONLY]"
        elif $is_noise; then
            tag="[NOISE - SKIP]"
        fi

        printf "%-22s %-10s %s (%s, %s)\n" "$tag" "$(git -C "$REPO_DIR" rev-parse --short "$commit_hash")" "$subject" "$author" "$date"
    done < <(git -C "$REPO_DIR" rev-list --reverse "$last_synced..$REMOTE_NAME/$BRANCH_NAME")

    echo ""
    echo "Inspect: $SHOW_PREFIX <commit-hash>"
    echo "Mark reviewed: ./Scripts/upstream-radar.sh --mark-reviewed $repo_key"
    echo ""
}

targets=()
if [[ "$TARGET" == "all" ]]; then
    targets=("tinycast" "enviouswispr" "macparakeet")
else
    targets=("$TARGET")
fi

for key in "${targets[@]}"; do
    if [[ "$MODE" == "mark" ]]; then
        mark_repo "$key"
    else
        audit_repo "$key"
    fi
done
