#!/bin/bash
# db-backup.sh — dump a Supabase/Postgres project database to a local backup.
#
# Usage:  db-backup.sh <project-dir> [more-project-dirs...]
# Env:    DB_BACKUP_DIR   backup root    (default ~/db-backups)
#         DB_BACKUP_KEEP  dumps to keep per project (default 14)
# Needs:  psql + pg_dump. Prefers postgresql@17's pg_dump if installed (keg-only,
#         /opt/homebrew/opt/postgresql@17/bin/pg_dump) so newer Supabase servers
#         can be dumped even when the default pg_dump is older.
#
# Secrets: the connection URL is read from the project's .env into a shell
# variable and passed straight to psql/pg_dump. It is never echoed, logged,
# or printed — only key names appear in output.
#
# Backups are pg_dump custom format (compressed): public, auth and storage
# schemas included. Restore with:
#   pg_restore --clean --if-exists --no-owner --no-privileges \
#     -d "<connection-url>" <file>.dump
set -uo pipefail

BACKUP_ROOT="${DB_BACKUP_DIR:-$HOME/db-backups}"
KEEP="${DB_BACKUP_KEEP:-14}"
PG17_DUMP="/opt/homebrew/opt/postgresql@17/bin/pg_dump"
URL_KEYS=(NEXT_PUBLIC_SUPABASE_DB_URL SUPABASE_DB_URL DATABASE_URL)

mkdir -p "$BACKUP_ROOT"

slugify() {
    printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//'
}

human_size() {
    local bytes=$1
    if (( bytes >= 1073741824 )); then awk -v b="$bytes" 'BEGIN{printf "%.1fG", b/1073741824}'
    elif (( bytes >= 1048576 ));    then awk -v b="$bytes" 'BEGIN{printf "%.1fM", b/1048576}'
    else printf '%dK' $(( bytes / 1024 ))
    fi
}

major_of() {  # "17.2" or "pg_dump (PostgreSQL) 14.18 (Homebrew)" -> 17 / 14
    printf '%s' "$1" | grep -oE '[0-9]+\.[0-9]+' | head -1 | cut -d. -f1
}

pick_pg_dump() {
    if [[ -x "$PG17_DUMP" ]]; then printf '%s' "$PG17_DUMP"
    else command -v pg_dump || true
    fi
}

# Keep the newest $KEEP dumps for a slug, delete the rest.
rotate() {
    local slug=$1 old
    ls -t "$BACKUP_ROOT/${slug}-"*.dump 2>/dev/null | tail -n +$((KEEP + 1)) | while IFS= read -r old; do
        rm -f "$old"
    done
}

fail_count=0

for PROJECT_DIR in "$@"; do
    SLUG="$(slugify "$(basename "$PROJECT_DIR")")"

    if [[ ! -d "$PROJECT_DIR" ]]; then
        echo "FAIL $SLUG project directory not found: $PROJECT_DIR"
        fail_count=$((fail_count + 1)); continue
    fi

    # --- load the connection URL (value never printed) ---
    DB_URL=""
    ENV_FILE=""
    for f in "$PROJECT_DIR/.env" "$PROJECT_DIR/.env.local" "$PROJECT_DIR/supabase/.env"; do
        if [[ -f "$f" ]]; then ENV_FILE="$f"; break; fi
    done
    if [[ -n "$ENV_FILE" ]]; then
        for key in "${URL_KEYS[@]}"; do
            DB_URL="$(grep -E "^${key}=" "$ENV_FILE" | head -1 | cut -d= -f2- | tr -d '"' | tr -d "'")"
            [[ -n "$DB_URL" ]] && break
        done
    fi
    if [[ -z "$DB_URL" ]]; then
        echo "FAIL $SLUG no database URL key (${URL_KEYS[*]}) found in .env"
        fail_count=$((fail_count + 1)); continue
    fi

    # --- tooling preflight ---
    if ! command -v psql >/dev/null 2>&1; then
        echo "FAIL $SLUG psql not found — install with: brew install postgresql@17"
        fail_count=$((fail_count + 1)); continue
    fi
    PG_DUMP_BIN="$(pick_pg_dump)"
    if [[ -z "$PG_DUMP_BIN" ]]; then
        echo "FAIL $SLUG pg_dump not found — install with: brew install postgresql@17"
        fail_count=$((fail_count + 1)); continue
    fi

    SERVER_VERSION="$(psql "$DB_URL" -tAc 'show server_version' 2>/dev/null | head -1)"
    if [[ -z "$SERVER_VERSION" ]]; then
        echo "FAIL $SLUG could not reach the database (check .env URL / network / VPN)"
        fail_count=$((fail_count + 1)); continue
    fi
    SERVER_MAJOR="$(major_of "$SERVER_VERSION")"
    DUMP_MAJOR="$(major_of "$("$PG_DUMP_BIN" --version)")"
    if (( DUMP_MAJOR < SERVER_MAJOR )); then
        echo "FAIL $SLUG pg_dump $DUMP_MAJOR is older than server $SERVER_MAJOR — brew install postgresql@17 and retry"
        fail_count=$((fail_count + 1)); continue
    fi

    # --- dump ---
    STAMP="$(date +%Y%m%d-%H%M%S)"
    OUT_FILE="$BACKUP_ROOT/${SLUG}-${STAMP}.dump"
    ERR_FILE="$(mktemp)"
    if "$PG_DUMP_BIN" "$DB_URL" --format=custom --compress=9 --no-owner --no-privileges \
        --file="$OUT_FILE" 2>"$ERR_FILE"; then
        BYTES="$(stat -f%z "$OUT_FILE" 2>/dev/null || echo 0)"
        echo "OK $SLUG $OUT_FILE $(human_size "$BYTES") server=pg$SERVER_MAJOR"
        rotate "$SLUG"
    else
        rm -f "$OUT_FILE"
        # First line of the error, with any connection URL scrubbed.
        REASON="$(head -1 "$ERR_FILE" | sed -E 's#postgres(ql)?://[^ ]+#[connection-url]#g' | cut -c1-160)"
        echo "FAIL $SLUG pg_dump failed: ${REASON:-unknown error}"
        fail_count=$((fail_count + 1))
    fi
    rm -f "$ERR_FILE"
done

exit $(( fail_count > 0 ? 1 : 0 ))
