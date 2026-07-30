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

# Produce the chDB ADBC driver shared library.
#
#   ./ci/scripts/build.sh <test|release> <linux|macos> <amd64|arm64>
#
# The driver product is libchdb itself: chdb-core compiles
# programs/local/chdb-adbc.cpp into libchdb, which already exports the ADBC
# entrypoints `AdbcDriverInit` and `chdb_adbc_init`. This script resolves a
# prebuilt libchdb for the target platform, normalises it into
# `libadbc_driver_chdb.<ext>` with a stable identity, and verifies the ADBC
# entrypoint is exported. See docs/chdb.md.
#
# libchdb source resolution, in order:
#   CHDB_LIBCHDB_PATH  local prebuilt library (used as-is)
#   CHDB_LIBCHDB_URL   direct download of a prebuilt library
#   default            chdb-core release tarball for the target platform

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
SRC_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
readonly SRC_DIR
readonly OUT_DIR="${SRC_DIR}/build"
readonly DL_DIR="${SRC_DIR}/build/downloads"

# chdb-core release to consume: the first one that carries the ADBC driver.
# Bump once a GA release ships.
readonly CHDB_CORE_VERSION="${CHDB_CORE_VERSION:-v26.5.1-rc.3}"

log() { echo "[build] $*" >&2; }
die() { echo "[build][error] $*" >&2; exit 1; }

resolve_libchdb() {
    # Prints the path to a libchdb shared library for the requested platform.
    # chdb-core ships the library as `libchdb.so` on both platforms (the macOS
    # one is a Mach-O dylib under that name), so both suffixes are accepted.
    local platform="$1" arch="$2"
    mkdir -p "${DL_DIR}"

    if [[ -n "${CHDB_LIBCHDB_PATH:-}" ]]; then
        log "Using CHDB_LIBCHDB_PATH=${CHDB_LIBCHDB_PATH}"
        printf '%s\n' "${CHDB_LIBCHDB_PATH}"
        return
    fi

    if [[ -n "${CHDB_LIBCHDB_URL:-}" ]]; then
        local dest="${DL_DIR}/libchdb-${platform}-${arch}"
        log "Downloading libchdb from ${CHDB_LIBCHDB_URL}"
        curl --fail --location --show-error --silent -o "${dest}" "${CHDB_LIBCHDB_URL}"
        printf '%s\n' "${dest}"
        return
    fi

    # Default: chdb-core publishes `{os}-{arch}-libchdb.tar.gz` release assets.
    local asset_arch
    case "${platform}-${arch}" in
        linux-amd64) asset_arch="x86_64" ;;
        linux-arm64) asset_arch="aarch64" ;;
        macos-amd64) asset_arch="x86_64" ;;
        macos-arm64) asset_arch="arm64" ;;
        *) die "unsupported platform/arch '${platform}/${arch}'" ;;
    esac
    local url="https://github.com/chdb-io/chdb-core/releases/download/${CHDB_CORE_VERSION}/${platform}-${asset_arch}-libchdb.tar.gz"

    local tarball="${DL_DIR}/${platform}-${asset_arch}-libchdb.tar.gz"
    local extract_dir="${DL_DIR}/${platform}-${arch}"
    log "Downloading libchdb from ${url}"
    curl --fail --location --show-error --silent -o "${tarball}" "${url}"
    rm -rf "${extract_dir}"
    mkdir -p "${extract_dir}"
    tar -xzf "${tarball}" -C "${extract_dir}"

    local lib
    lib="$(find "${extract_dir}" -type f \( -name "libchdb.so" -o -name "libchdb.dylib" \) \
        | head -n1)"
    [[ -n "${lib}" ]] || die "no libchdb.so/.dylib found in ${url}"
    printf '%s\n' "${lib}"
}

main() {
    local -r config="${1:?usage: build.sh <test|release> <linux|macos> <amd64|arm64>}"
    local -r platform="${2:?missing platform}"
    local -r arch="${3:?missing arch}"

    # Suffix of the driver this script produces (the source library's own name
    # is resolved separately — see resolve_libchdb).
    local ext
    case "${platform}" in
        linux) ext="so" ;;
        macos) ext="dylib" ;;
        *) die "unsupported platform '${platform}' (linux|macos only; chDB has no Windows build)" ;;
    esac

    mkdir -p "${OUT_DIR}"
    local -r out="${OUT_DIR}/libadbc_driver_chdb.${ext}"

    local src
    src="$(resolve_libchdb "${platform}" "${arch}")"
    [[ -f "${src}" ]] || die "resolved libchdb does not exist: ${src}"

    log "Copying ${src} -> ${out}"
    cp -f "${src}" "${out}"
    chmod u+w "${out}"

    # Normalise the shared-library identity so dbc and the driver manager see a
    # stable name regardless of what the source library was called.
    case "${platform}" in
        linux)
            if command -v patchelf >/dev/null 2>&1; then
                log "Setting SONAME=libadbc_driver_chdb.so"
                patchelf --set-soname "libadbc_driver_chdb.so" "${out}"
            else
                log "WARNING: patchelf not found; SONAME left as-is"
            fi
            ;;
        macos)
            log "Setting install name=@rpath/libadbc_driver_chdb.dylib"
            install_name_tool -id "@rpath/libadbc_driver_chdb.dylib" "${out}"
            ;;
    esac

    # Release builds strip local/debug symbols; exported ADBC symbols are kept.
    if [[ "${config}" == "release" ]]; then
        if [[ "${platform}" == "linux" ]]; then
            strip --strip-unneeded "${out}" 2>/dev/null || log "WARNING: strip failed (non-fatal)"
        else
            strip -x "${out}" 2>/dev/null || log "WARNING: strip failed (non-fatal)"
        fi
    fi

    # libchdb ships ad-hoc signed, and both install_name_tool and strip
    # invalidate that signature. macOS refuses to map a library whose signature
    # no longer matches — dlopen takes the process down with SIGKILL — so sign
    # again after the last edit.
    if [[ "${platform}" == "macos" ]]; then
        log "Re-signing (ad-hoc) after edits"
        codesign --force --sign - "${out}" \
            || die "codesign failed; the library would be unloadable"
        codesign --verify "${out}" || die "codesign --verify failed for ${out}"
    fi

    "${SCRIPT_DIR}/verify_exports.sh" "${out}" "${platform}"

    log "Built ${out}"
    ls -lh "${out}" >&2
}

main "$@"
