
#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT="${1:-}"
COMP="$HOME/esp/extra_components/micro_ros_espidf_component"
TOOLCHAIN="$COMP/esp32_toolchain.cmake"

# Validate project argument
if [[ -z "$PROJECT" ]]; then
    echo "Usage: $0 /path/to/esp-idf-project"
    exit 1
fi

PROJECT="$(realpath "$PROJECT")"

# Validate host architecture
if [[ "$(uname -m)" != "aarch64" ]]; then
    echo "ERROR: Ubuntu ARM64 (aarch64) is required."
    exit 1
fi

# Validate ESP-IDF project
if [[ ! -f "$PROJECT/CMakeLists.txt" ||
      ! -f "$PROJECT/sdkconfig" ]]; then
    echo "ERROR: Invalid ESP-IDF project."
    exit 1
fi

# Validate target
if ! grep -q '^CONFIG_IDF_TARGET="esp32s3"$' "$PROJECT/sdkconfig"; then
    echo "ERROR: Project is not configured for ESP32-S3."
    exit 1
fi

# Check micro-ROS dependencies
if [[ ! -s "$COMP/libmicroros.a" ||
      ! -f "$TOOLCHAIN" ]]; then
    echo "ERROR: Missing micro-ROS components."
    exit 1
fi

# Back up the shared toolchain
BACKUP="$(mktemp "$COMP/.toolchain-backup.XXXXXX")"
cp -p "$TOOLCHAIN" "$BACKUP"

# Restore the toolchain when the script exits
restore() {
    cp -p "$BACKUP" "$TOOLCHAIN"
    rm -f "$BACKUP"
}
trap restore EXIT

# Activate ESP-IDF
source "$HOME/esp/esp-idf/export.sh"

# Limit build resource usage
export CMAKE_BUILD_PARALLEL_LEVEL=2
export MAKEFLAGS="-j2"
export COLCON_DEFAULTS_FILE=/dev/null

# Adapt the shared toolchain to the selected project
python3 - "$TOOLCHAIN" "$PROJECT" <<'PY'
from pathlib import Path
import re
import sys

file = Path(sys.argv[1])
project = Path(sys.argv[2])
text = file.read_text()

pattern = r'"/home/yahboom/esp/tests_arm64/[^"]+/build/config"'
replacement = f'"{project}/build/config"'

updated, count = re.subn(
    pattern,
    replacement,
    text,
    count=1
)

if count != 1:
    raise SystemExit(
        "ERROR: Shared toolchain configuration path not found."
    )

file.write_text(updated)

print("Toolchain configured for:", project)
PY

# Build the firmware
cd "$PROJECT"

echo "=== BUILDING ESP32-S3 FIRMWARE ==="
idf.py build

# Display generated firmware
echo "=== GENERATED FIRMWARE ==="
ls -lh build/*.bin
sha256sum build/*.bin

echo "=== BUILD COMPLETED SUCCESSFULLY ==="
