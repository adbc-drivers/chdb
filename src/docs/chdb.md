<!--
  Copyright (c) 2026 ADBC Drivers Contributors

  Licensed under the Apache License, Version 2.0 (the "License");
  you may not use this file except in compliance with the License.
  You may obtain a copy of the License at

          http://www.apache.org/licenses/LICENSE-2.0

  Unless required by applicable law or agreed to in writing, software
  distributed under the License is distributed on an "AS IS" BASIS,
  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
  See the License for the specific language governing permissions and
  limitations under the License.
-->

# chDB ADBC Driver — Product & Build Design

How the shipped driver artifact — `libadbc_driver_chdb.{so,dylib}` — is
produced from the chDB / chdb-core object graph, and how it is identified,
exported, and packaged for distribution through
[`dbc`](https://docs.columnar.tech/dbc).

This document is build-only. It does **not** require compiling libchdb (a
multi-hour, high-memory ClickHouse build); the pipeline consumes prebuilt
libchdb release artifacts, driven by the scripts under
[`ci/scripts/`](../ci/scripts).

## 1. What the driver *is*

The ADBC driver for chDB is **libchdb itself**. chdb-core already implements the
ADBC contract in `programs/local/chdb-adbc.cpp` and compiles it into the same
object graph as libchdb, so no separate driver `.so` needs to be built. The two
ADBC entrypoints are defined and exported there:

```cpp
// programs/local/chdb-adbc.cpp
extern "C" CHDB_EXPORT AdbcStatusCode chdb_adbc_init(int version, void *raw_driver, AdbcError *error);
extern "C" CHDB_EXPORT AdbcStatusCode AdbcDriverInit(int version, void *raw_driver, AdbcError *error)
{
    return chdb_adbc_init(version, raw_driver, error);
}
```

`CHDB_EXPORT` is `__attribute__((visibility("default")))` (see
`programs/local/chdb.h`). `AdbcDriverInit` is the symbol the standard ADBC
driver manager resolves by default; `chdb_adbc_init` is chDB's stable alias.

Both symbols are already on chdb-core's public export lists, so a stock libchdb
release **is** a loadable ADBC driver:

- Linux version script `chdb/libchdb_export.map` — `global:` includes
  `chdb_adbc_init; AdbcDriverInit;`
- macOS exported-symbols list `chdb/libchdb_export_macos.txt` — includes
  `_chdb_adbc_init` and `_AdbcDriverInit`.

Contrast with the reference driver (adbc-drivers/clickhouse), which wraps a
standalone Rust crate (`ClickHouse/adbc_clickhouse`) and links a small
`libadbc_driver_clickhouse` via `cargo build -Fffi`. chDB does not have (or
need) a separate small driver library — the engine library is the driver.

## 2. Contract: URI and connection model

chDB is in-process; there is no host/port. The driver interprets the ADBC `uri`
option as the database location:

| URI                 | Meaning                                        |
|---------------------|------------------------------------------------|
| `chdb://`           | in-memory database (default)                   |
| `chdb:///abs/path`  | on-disk database rooted at `/abs/path`         |
| `chdb://./rel/path` | on-disk database rooted at a relative path     |

Exact URI parsing lives in `chdb-adbc.cpp`; the packaging repo only documents
it.

## 3. Obtaining the artifact: repackage a prebuilt libchdb

`ci/scripts/build.sh <config> <platform> <arch>` repackages a prebuilt libchdb.
This is the only supported path — the ClickHouse engine is never compiled here
(a from-source build is multi-hour and high-memory, unsuitable for per-release
CI). chdb-core owns compilation; this repo consumes its release artifacts.

chdb-core publishes a per-platform `{os}-{arch}-libchdb.tar.gz` release asset
for all four targets (linux x86_64/aarch64, macos x86_64/arm64). Because those
binaries already export the ADBC entrypoints, the packaging step is:

1. Resolve a libchdb for the target platform. In order:
   - `CHDB_LIBCHDB_PATH` — a local prebuilt library, used as-is.
   - `CHDB_LIBCHDB_URL` — direct download of a prebuilt library.
   - default — download and unpack the chdb-core release tarball
     `https://github.com/chdb-io/chdb-core/releases/download/${CHDB_CORE_VERSION}/{os}-{arch}-libchdb.tar.gz`
     (`CHDB_CORE_VERSION` pins the release; see §7).
2. Copy it to `build/libadbc_driver_chdb.<ext>`, where adbc-make and the
   packaging step look for it.
3. Set a stable library identity (SONAME / install name — §4).
4. Strip local/debug symbols (release only).
5. Verify `AdbcDriverInit` is exported (`ci/scripts/verify_exports.sh`).

This takes seconds instead of hours and reuses the exact binaries chDB already
tests and ships. The driver version is therefore coupled to whatever libchdb
release is pinned.

If a future need arises to relink specifically for ADBC and hide the rest of the
chDB C API, this repo carries minimal export lists that keep only the two
entrypoints: `ci/scripts/adbc_driver_chdb_export.map` (Linux) and
`ci/scripts/adbc_driver_chdb_export_macos.txt` (macOS). They are not used by the
default flow, which keeps the full chDB C API exported (§7 ⑤).

## 4. Library identity: SONAME, install name, exported entrypoint

The dbc package installs the file under the driver name and the driver manager
`dlopen`s it directly, so the on-disk filename (`libadbc_driver_chdb.<ext>`) is
what matters most. We still normalise the embedded identity for robustness:

- **Linux SONAME.** chdb-core does *not* currently set a SONAME on libchdb.so
  (the link line is a plain `-shared -o libchdb.so`). After copying,
  `ci/scripts/build.sh` sets one post-hoc:
  `patchelf --set-soname libadbc_driver_chdb.so <lib>`.
- **macOS install name.** `ci/scripts/build.sh` sets `LC_ID_DYLIB` to an
  `@rpath` name so the driver is relocatable wherever dbc installs it:
  `install_name_tool -id @rpath/libadbc_driver_chdb.dylib <lib>`. chdb-core's
  libchdb is already built with an `@rpath` install name.
- **Exported entrypoint.** Guaranteed by chdb-core's export lists; re-checked by
  `ci/scripts/verify_exports.sh` (`nm -D --defined-only` on Linux, `nm -gU` on
  macOS) so a bad repackage fails the build rather than shipping. The same
  script `dlopen`s the result — a symbol table looks correct either way — and
  asserts the portability floors ADBC packages target: no GLIBC above 2.17 and
  no GLIBCXX above 3.4.19 (manylinux2014, per PEP 599) on Linux, and a minimum
  macOS of 11.0.

## 5. Packaging for dbc

Identical mechanism to the clickhouse reference: the per-platform shared
libraries feed `adbc-gen-package` (from `adbc-drivers/dev`), which emits a dbc
`.tar.gz` + `manifest.yaml` per platform using [`manifest.toml`](../manifest.toml)
as the template. `dbc install chdb` then fetches the right tarball from the CDN.
See the `package` job in
[`script_test.yaml`](../../.github/workflows/script_test.yaml).
`manifest.toml` sets `license = "Apache-2.0"` (single license; the clickhouse
driver is `MIT OR Apache-2.0` because its Rust wrapper is MIT).

## 6. License & attribution

The driver binary embeds the entire ClickHouse engine and its `contrib/`
dependencies, so the package must carry those attributions:

- [`LICENSE.txt`](../../LICENSE.txt) — Apache-2.0 (chDB and ClickHouse are both
  Apache-2.0).
- [`NOTICE.txt`](../../NOTICE.txt) — attributes chDB, ClickHouse, and points at
  the generated third-party notices.
- `ci/scripts/generate_notice.sh` — harvests `LICENSE`/`COPYING`/`NOTICE` files
  from a chdb-core checkout's `contrib/` tree into `THIRD_PARTY_NOTICES.txt`.
  Set `CHDB_CORE_DIR` to reuse a checkout, or let it clone one. The Go and Rust
  drivers get this from go-licenses / cargo-about, neither of which applies to a
  prebuilt C++ library.

## 7. Decisions

1. **libchdb source.** Consume the chdb-core `{os}-{arch}-libchdb.tar.gz`
   release asset (the non-`static`, shared variant). Do not extract `_chdb*.so`
   from PyPI wheels and do not build from source.
2. **Version pin, no submodule.** `CHDB_CORE_VERSION` in
   `ci/scripts/build.sh` names the chdb-core release to download, and is bumped
   to the GA release when it ships. chdb-core is deliberately not a submodule:
   it is a ClickHouse tree with hundreds of nested submodules, and CI would
   clone it for every job while needing none of it. `generate_notice.sh` clones
   it on demand.
3. **macOS x86_64.** Kept in the build matrix; chdb-core publishes a
   `macos-x86_64-libchdb.tar.gz` asset.
4. **SONAME / install name.** Patched post-hoc in this repo by
   `ci/scripts/build.sh` (`patchelf` / `install_name_tool`); chdb-core's libchdb
   already ships with an `@rpath` install name.
5. **Export surface.** Ship the full chDB C API (the stock libchdb export set).
   The minimal ADBC-only export lists in `ci/scripts/` are reference-only and
   not applied.
6. **No build-from-source.** This repo only repackages prebuilt libchdb;
   per-release ClickHouse compilation stays entirely in chdb-core's pipeline.
7. **Workflows are generated.** `adbc-gen-workflow` (from `adbc-drivers/dev`)
   renders the workflows and `pixi.toml` from
   [`generate.toml`](../../.github/workflows/generate.toml); regenerate rather
   than editing them. One deviation is applied by hand afterwards: the platform
   matrices drop the generator's windows entries and add macos/amd64, because
   chDB has no Windows build and the generator cannot yet be told which
   platforms to target (adbc-drivers/dev#53).
8. **Validation suite.** `generate.toml` sets `validation.skip`, so no
   `validate` job is generated yet. The driver's behaviour is covered by
   `tests/test_adbc_driver.py` in chdb-core, where the driver is implemented;
   a suite here is still to be added.
9. **`adbc-make build`, not `adbc-make check`.** `check` requires a driver
   library to export only `Adbc*` symbols. That cannot hold here: the driver
   library is libchdb, and its ADBC implementation calls the chDB C API through
   the same dynamic symbol table, so hiding those exports would leave the
   library unable to resolve its own calls. `verify_exports.sh` covers what does
   apply — entrypoint exported, library loads, portability floors met (§4).
