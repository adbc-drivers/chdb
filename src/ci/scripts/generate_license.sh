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

# Emit the LICENSE text for the driver package on stdout. adbc-gen-package
# picks this script up in preference to a license.tpl, which is what the Go and
# Rust drivers use — neither applies to a driver whose payload is a prebuilt
# C++ library.
#
# The driver is libchdb, which is Apache-2.0, so that text plus the attribution
# in NOTICE.txt is the license for the package. Third-party components compiled
# into libchdb are enumerated separately by generate_notice.sh, which needs a
# chdb-core checkout.
#
#   ./ci/scripts/generate_license.sh            # writes to stdout

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
readonly REPO_ROOT

for f in "${REPO_ROOT}/LICENSE.txt" "${REPO_ROOT}/NOTICE.txt"; do
    [[ -f "${f}" ]] || { echo "[license][error] missing ${f}" >&2; exit 1; }
done

cat "${REPO_ROOT}/LICENSE.txt"
printf '\n%s\n%s\n%s\n\n' \
    "==============================================================================" \
    "Notices" \
    "=============================================================================="
cat "${REPO_ROOT}/NOTICE.txt"
