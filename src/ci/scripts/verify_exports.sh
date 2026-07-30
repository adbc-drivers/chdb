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

# Verify that a driver shared library is fit to ship: it exports the ADBC
# entrypoint that dbc / the ADBC driver manager looks up, it actually loads,
# and it does not require a newer platform than ADBC packages target.
#
# The standard manager entrypoint is `AdbcDriverInit`; chDB also exports the
# historical `chdb_adbc_init` alias.
#
#   ./ci/scripts/verify_exports.sh <path/to/lib> <linux|macos>

set -euo pipefail

readonly LIB="${1:?usage: verify_exports.sh <lib> <linux|macos>}"
readonly PLATFORM="${2:?missing platform}"
readonly WANT="AdbcDriverInit"

case "${PLATFORM}" in
    linux)
        # Exported (defined, global) dynamic symbols only.
        if nm -D --defined-only "${LIB}" 2>/dev/null | grep -qw "${WANT}"; then
            echo "[verify] OK: ${WANT} exported by ${LIB}"
        else
            echo "[verify][error] ${WANT} not exported by ${LIB}" >&2
            exit 1
        fi
        ;;
    macos)
        # Mach-O prefixes C symbols with an underscore.
        if nm -gU "${LIB}" 2>/dev/null | grep -qw "_${WANT}"; then
            echo "[verify] OK: _${WANT} exported by ${LIB}"
        else
            echo "[verify][error] _${WANT} not exported by ${LIB}" >&2
            exit 1
        fi
        ;;
    *)
        echo "[verify][error] unsupported platform '${PLATFORM}'" >&2
        exit 1
        ;;
esac

# A symbol table can look right on a library that still refuses to load: a
# stale code signature on macOS, for one, takes the loading process down with
# SIGKILL. So load it for real and resolve the entrypoint.
if command -v python3 >/dev/null 2>&1; then
    if python3 -c '
import ctypes, sys
getattr(ctypes.CDLL(sys.argv[1]), sys.argv[2])
' "${LIB}" "${WANT}"; then
        echo "[verify] OK: ${LIB} loads and resolves ${WANT}"
    else
        echo "[verify][error] ${LIB} failed to load or resolve ${WANT}" >&2
        exit 1
    fi
else
    echo "[verify][warn] python3 not found; skipped the load check" >&2
fi

# Portability floors, matching what ADBC packages target: manylinux2014 on
# Linux and macOS 11 on macOS. A library that needs more than this loads on the
# build machine and fails on a user's.
readonly MAX_GLIBC="2.17"      # manylinux2014, per PEP 599
readonly MAX_GLIBCXX="3.4.19"  # manylinux2014, per PEP 599
readonly MAX_MACOS="11.0"

at_most() {
    # at_most <value> <limit> -> true when value <= limit
    [[ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | tail -n1)" == "$2" ]]
}

case "${PLATFORM}" in
    linux)
        # Read the symbol table once. Empty means nm could not read it, which is
        # not the same as a library that needs nothing.
        symbols="$(nm --dynamic "${LIB}" 2>/dev/null || true)"
        if [[ -z "${symbols}" ]]; then
            echo "[verify][error] could not read the dynamic symbols of ${LIB}" >&2
            exit 1
        fi
        for pair in "GLIBC:${MAX_GLIBC}" "GLIBCXX:${MAX_GLIBCXX}"; do
            prefix="${pair%%:*}"
            limit="${pair##*:}"
            # Highest version among `symbol@<prefix>_<version>` references.
            # A library needing none of them greps nothing, hence `|| true`.
            found="$(printf '%s\n' "${symbols}" \
                | grep -o "@${prefix}_[0-9][0-9.]*" \
                | sed "s/@${prefix}_//" | sort -V | tail -n1 || true)"
            if [[ -z "${found}" ]]; then
                echo "[verify] OK: no ${prefix} version references"
            elif at_most "${found}" "${limit}"; then
                echo "[verify] OK: needs ${prefix} ${found} (limit ${limit})"
            else
                echo "[verify][error] ${LIB} needs ${prefix} ${found}, above the ${limit} limit" >&2
                exit 1
            fi
        done
        ;;
    macos)
        minos="$(otool -l "${LIB}" 2>/dev/null \
            | awk '$1 == "minos" { print $2; exit }' || true)"
        if [[ -z "${minos}" ]]; then
            echo "[verify][error] could not read the minimum macOS version of ${LIB}" >&2
            exit 1
        elif at_most "${minos}" "${MAX_MACOS}"; then
            echo "[verify] OK: needs macOS ${minos} (limit ${MAX_MACOS})"
        else
            echo "[verify][error] ${LIB} needs macOS ${minos}, above the ${MAX_MACOS} limit" >&2
            exit 1
        fi
        ;;
esac
