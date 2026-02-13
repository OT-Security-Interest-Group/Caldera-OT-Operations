#!/usr/bin/env bash
set -euo pipefail

# -------- helpers ----------
die() { echo "[!] $*" >&2; exit 1; }
warn() { echo "[!] $*" >&2; }
info() { echo "[*] $*"; }

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Missing required command: $1"
}

cleanup() {
  if [[ -n "${TMP_FILE:-}" && -f "${TMP_FILE:-}" ]]; then rm -f "$TMP_FILE"; fi
}
trap cleanup EXIT
# --------------------------

need_cmd git
need_cmd awk
need_cmd grep
need_cmd cp
need_cmd find

echo "=== Caldera OT Plugin Installer (all protocols) ==="
echo ""

read -r -p "Path to your Caldera directory (the folder that contains plugins/ and conf/): " CALDERA_DIR
[[ -d "$CALDERA_DIR" ]] || die "Directory does not exist: $CALDERA_DIR"
[[ -d "$CALDERA_DIR/plugins" ]] || die "Missing: $CALDERA_DIR/plugins"
[[ -d "$CALDERA_DIR/conf" ]] || die "Missing: $CALDERA_DIR/conf"

echo ""
echo "Config choice:"
echo "  1) conf/default.yml  (common if you run: python3 server.py --insecure)"
echo "  2) conf/local.yml    (common for non-insecure setups)"
read -r -p "Pick 1 or 2 [1]: " CONF_PICK
CONF_PICK="${CONF_PICK:-1}"

if [[ "$CONF_PICK" == "2" ]]; then
  CONF_FILE="$CALDERA_DIR/conf/local.yml"
else
  CONF_FILE="$CALDERA_DIR/conf/default.yml"
fi

[[ -f "$CONF_FILE" ]] || die "Config file not found: $CONF_FILE"

OT_REPO_DIR="${OT_REPO_DIR:-$HOME/caldera-ot}"
OT_REPO_URL="https://github.com/mitre/caldera-ot.git"

echo ""
info "Using Caldera dir : $CALDERA_DIR"
info "Using config file : $CONF_FILE"
info "Using OT repo dir : $OT_REPO_DIR"

# Clone or update repo
if [[ -d "$OT_REPO_DIR/.git" ]]; then
  info "Updating caldera-ot..."
  git -C "$OT_REPO_DIR" pull --recurse-submodules
  git -C "$OT_REPO_DIR" submodule update --init --recursive
else
  info "Cloning caldera-ot..."
  git clone "$OT_REPO_URL" --recursive "$OT_REPO_DIR"
fi

# Discover plugin folders by presence of plugin.yml
mapfile -t PLUGIN_DIRS < <(find "$OT_REPO_DIR" -mindepth 1 -maxdepth 1 -type d -exec test -f "{}/plugin.yml" \; -print)

[[ "${#PLUGIN_DIRS[@]}" -gt 0 ]] || die "No plugins found in $OT_REPO_DIR (expected folders with plugin.yml)."

info "Found ${#PLUGIN_DIRS[@]} OT plugins:"
for d in "${PLUGIN_DIRS[@]}"; do
  echo "    - $(basename "$d")"
done

# Backup config before editing
BACKUP="$CONF_FILE.bak.$(date +%Y%m%d-%H%M%S)"
cp "$CONF_FILE" "$BACKUP"
info "Backed up config to: $BACKUP"

# Copy plugins and add to config
TMP_FILE="$(mktemp)"

add_plugin_to_config() {
  local plugin="$1"

  # already present?
  if grep -qE "^\s*-\s*${plugin}\s*$" "$CONF_FILE"; then
    info "Config already includes: $plugin"
    return 0
  fi

  # Insert under first 'plugins:' key if present; otherwise append a new section.
  awk -v p="$plugin" '
    BEGIN { inserted=0; saw_plugins=0 }
    {
      print $0
      if (!inserted && $0 ~ /^plugins:\s*$/) {
        saw_plugins=1
        print "  - " p
        inserted=1
      }
    }
    END {
      if (!inserted && !saw_plugins) {
        print ""
        print "plugins:"
        print "  - " p
      }
    }
  ' "$CONF_FILE" > "$TMP_FILE" && mv "$TMP_FILE" "$CONF_FILE"
}

echo ""
info "Installing plugins into $CALDERA_DIR/plugins and enabling in config..."

for d in "${PLUGIN_DIRS[@]}"; do
  plugin="$(basename "$d")"

  # Copy (replace existing)
  if [[ -d "$CALDERA_DIR/plugins/$plugin" ]]; then
    info "Replacing existing plugin folder: $plugin"
    rm -rf "$CALDERA_DIR/plugins/$plugin"
  fi

  cp -r "$d" "$CALDERA_DIR/plugins/" || die "Failed to copy plugin: $plugin"

  add_plugin_to_config "$plugin"
done

echo ""
info "Done."
echo "Next: restart Caldera (and rebuild if needed). Examples:"
echo ""
echo "  cd \"$CALDERA_DIR\""
echo "  source .calderavenv/bin/activate  # if you use a venv"
echo "  python3 server.py --insecure --build"
echo ""
warn "Note: Some plugins (e.g., IEC 61850) may require extra payload steps per their docs."