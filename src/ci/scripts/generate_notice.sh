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

# Generate THIRD_PARTY_NOTICES.txt for the driver package.
#
# libchdb embeds ClickHouse's C/C++ `contrib/` dependencies, and there is no
# package manifest enumerating them (the Go and Rust drivers get this from
# go-licenses / cargo-about), so harvest the license files out of a chdb-core
# checkout. Point CHDB_CORE_DIR at one, or let the script clone it.
#
#   ./ci/scripts/generate_notice.sh [output_file]
#
# Best-effort harvester (see docs/chdb.md, "License & attribution").

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
SRC_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
readonly SRC_DIR
REPO_ROOT="$(cd "${SRC_DIR}/.." && pwd)"
readonly REPO_ROOT
readonly OUT="${1:-${SRC_DIR}/build/THIRD_PARTY_NOTICES.txt}"

# Keep this in step with CHDB_CORE_VERSION in build.sh.
readonly CHDB_CORE_VERSION="${CHDB_CORE_VERSION:-v26.5.1-rc.3}"

mkdir -p "$(dirname "${OUT}")"

{
    cat "${REPO_ROOT}/NOTICE.txt"
    echo
    echo "================================================================================"
    echo "Embedded third-party components (via the ClickHouse engine in libchdb)"
    echo "================================================================================"
    echo
} > "${OUT}"

if [[ -n "${CHDB_CORE_DIR:-}" ]]; then
    CONTRIB="${CHDB_CORE_DIR}/contrib"
else
    # A shallow clone is enough: only contrib/ license files are read. It is not
    # a submodule because chdb-core is a ClickHouse tree with hundreds of nested
    # submodules, which every CI job would then pay for.
    CHECKOUT="${SRC_DIR}/build/chdb-core"
    if [[ ! -d "${CHECKOUT}/.git" ]]; then
        echo "[notice] cloning chdb-core ${CHDB_CORE_VERSION}" >&2
        git clone --depth 1 --branch "${CHDB_CORE_VERSION}" \
            https://github.com/chdb-io/chdb-core "${CHECKOUT}" >&2
    fi
    CONTRIB="${CHECKOUT}/contrib"
fi
readonly CONTRIB

if [[ ! -d "${CONTRIB}" ]]; then
    echo "[notice][warn] ${CONTRIB} not found" >&2
    echo "(Third-party license texts unavailable.)" >> "${OUT}"
    exit 0
fi

# Harvest each contrib's license file.
find "${CONTRIB}" -maxdepth 2 -type f \
    \( -iname 'LICENSE*' -o -iname 'COPYING*' -o -iname 'NOTICE*' \) \
    | sort | while read -r lic; do
        component="$(basename "$(dirname "${lic}")")"
        {
            echo "--------------------------------------------------------------------------------"
            echo "${component} -- $(basename "${lic}")"
            echo "--------------------------------------------------------------------------------"
            cat "${lic}"
            echo
        } >> "${OUT}"
    done

echo "[notice] wrote ${OUT}" >&2
