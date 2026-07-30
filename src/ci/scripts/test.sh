#!/bin/bash
# Copyright (c) 2026 ADBC Drivers Contributors
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#         http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# Smoke test the freshly built driver: confirm the ADBC entrypoint is exported
# and, if the ADBC driver manager is available, load the library and open a
# throwaway in-memory connection.
#
#   ./ci/scripts/test.sh <linux|macos> <amd64|arm64>
#
# This is a packaging check, not a conformance suite. The driver's behaviour is
# covered by tests/test_adbc_driver.py in chdb-io/chdb-core, which is where the
# driver is implemented; a src/validation suite like the clickhouse driver's is
# still to be added here.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
SRC_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
readonly SRC_DIR
readonly PLATFORM="${1:?usage: test.sh <linux|macos> <amd64|arm64>}"
# shellcheck disable=SC2034
readonly ARCH="${2:?missing arch}"

case "${PLATFORM}" in
    linux) ext="so" ;;
    macos) ext="dylib" ;;
    *) echo "unsupported platform '${PLATFORM}'" >&2; exit 1 ;;
esac

readonly LIB="${SRC_DIR}/build/libadbc_driver_chdb.${ext}"
[[ -f "${LIB}" ]] || { echo "driver not built: ${LIB} (run build.sh first)" >&2; exit 1; }

# 1. Static check: the entrypoint is exported.
"${SCRIPT_DIR}/verify_exports.sh" "${LIB}" "${PLATFORM}"

# 2. Dynamic check: load the driver if the ADBC manager is importable.
if python -c "import adbc_driver_manager" >/dev/null 2>&1; then
    echo "[test] loading driver via adbc_driver_manager"
    CHDB_ADBC_DRIVER_PATH="${LIB}" python - <<'PY'
import os
from adbc_driver_manager import dbapi

lib = os.environ["CHDB_ADBC_DRIVER_PATH"]
with dbapi.connect(driver=lib, entrypoint="AdbcDriverInit", uri="chdb://") as conn:
    with conn.cursor() as cur:
        cur.execute("SELECT 1")
        assert cur.fetchone() == (1,)
print("[test] OK: driver loaded and SELECT 1 returned 1")
PY
else
    echo "[test] adbc_driver_manager not installed; skipping dynamic load test"
fi
