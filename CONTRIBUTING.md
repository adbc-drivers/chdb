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

# How to Contribute

All contributors are expected to follow the [Code of
Conduct](https://github.com/adbc-drivers/chdb?tab=coc-ov-file#readme).

## Reporting Issues and Making Feature Requests

Please file issues and feature requests on the GitHub issue tracker:
https://github.com/adbc-drivers/chdb/issues

Potential security vulnerabilities should be reported to
[security@adbc-drivers.org](mailto:security@adbc-drivers.org) instead. See the
[Security Policy](https://github.com/adbc-drivers/chdb?tab=security-ov-file#readme).

## Build and Test

Most likely, you want to contribute to the upstream driver at
https://github.com/chdb-io/chdb-core (`programs/local/chdb-adbc.cpp`) — the
engine-and-driver core that the user-facing `chdb-io/chdb` project builds on.
This repository only holds the build, packaging and test scripts for the ADBC
Driver Foundry.

The driver product (`libadbc_driver_chdb.{so,dylib}`) is the chDB shared
library (`libchdb`) with the ADBC entrypoint exported. Because building
`libchdb` from source compiles the full ClickHouse engine (multi-hour, high
memory), CI does **not** compile it here; instead `ci/scripts/build.sh`
resolves a prebuilt `libchdb` for the target platform and repackages it. See
[`src/docs/chdb.md`](./src/docs/chdb.md).

```shell
$ cd src/
# ./ci/scripts/build.sh <test|release> <linux|macos> <amd64|arm64>
# For example:
$ ./ci/scripts/build.sh test linux amd64
```

This produces a shared library in `src/build/`.

## Opening a Pull Request

Before opening a pull request:

- Review your changes and make sure no stray files are included.
- Ensure the Apache license header is at the top of all files.
- Check if there is an existing issue. If not, please file one, unless the
  change is trivial.
- Assign the issue to yourself by commenting just the word `take`.
- Run the static checks by installing [pre-commit](https://pre-commit.com/),
  then running `pre-commit run --all-files` from inside the repository.

When writing the pull request description:

- Ensure the title follows [Conventional
  Commits](https://www.conventionalcommits.org/en/v1.0.0/) format. The
  component can generally be omitted. Example titles:

  - `feat: pin chdb-core v26.5.1`
  - `chore: update action versions`
  - `fix!: set SONAME on the Linux driver`

  Ensure breaking changes are flagged with a `!`.
- Make sure the description ends with `Closes #NNN`, `Fixes #NNN`, or similar,
  so the issue is linked to your pull request.
