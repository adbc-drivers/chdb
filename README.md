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

## Where can I find the ADBC driver for chDB?

**The ADBC Driver for chDB is maintained by ClickHouse.**

[chDB](https://clickhouse.com/chdb) is an embedded SQL engine powered by
ClickHouse: an in-process OLAP database with no server to run. This driver
exposes chDB through the [ADBC](https://arrow.apache.org/adbc/) API, so any
ADBC-aware tool can query local files, DataFrames, and remote sources with
ClickHouse SQL in-process.

Because chDB is embedded, the driver and the engine are the same artifact:
`libchdb` implements the ADBC entrypoints and exports them directly, so there is
no separate driver library to build. The driver is therefore developed, built,
and released in the engine repository, and this repository holds no source code.

The driver is provided for **Linux and macOS only** — chDB embeds the full
ClickHouse engine and does not ship native Windows binaries; Windows users run
it through WSL2.

> [!NOTE]
> **chDB and chdb-core.** chDB is published as two repositories.
> [`chdb-io/chdb`](https://github.com/chdb-io/chdb) is the user-facing project
> — the `chdb` PyPI package with the Python DataStore / DataFrame API.
> [`chdb-io/chdb-core`](https://github.com/chdb-io/chdb-core) is the
> engine-and-driver core that `chdb` builds on — the `chdb-core` package
> shipping `libchdb` and the `_chdb` module — and is where the ADBC driver
> lives (`programs/local/chdb-adbc.cpp`).

> [!NOTE]
> Driver packages have not been published yet. When they are, prerelease
> versions come first, so installing them will need `--pre` with dbc 0.2.0 or
> newer.

---

📥 To install it with [dbc](https://docs.columnar.tech/dbc), run `dbc install --pre chdb`.

🐛 To report an issue, go to [github.com/chdb-io/chdb-core/issues](https://github.com/chdb-io/chdb-core/issues). Specify clearly that it's about ADBC.

📚 To browse the documentation, go to [clickhouse.com/docs/chdb](https://clickhouse.com/docs/chdb).

⌨️ To see the source code, go to [github.com/chdb-io/chdb-core](https://github.com/chdb-io/chdb-core) (`programs/local/chdb-adbc.cpp`).

💬 To ask questions, email hello@adbc-drivers.org or chat with us on the [Columnar Community Slack](https://join.slack.com/t/columnar-community/shared_invite/zt-3gt5cb69i-KRjJj~mjUZv5doVmpcVa4w).

## Connecting

chDB is embedded, so there is no host or port. The `uri` selects the on-disk
data directory (or an in-memory database):

```python
from adbc_driver_manager import dbapi

# On-disk, persistent database rooted at ./my_data
with dbapi.connect(driver="chdb", uri="chdb:///my_data") as conn:
    with conn.cursor() as cur:
        cur.execute("SELECT count(*) FROM file('data.parquet', 'Parquet')")
        print(cur.fetchall())

# In-memory (default when the path is empty)
with dbapi.connect(driver="chdb", uri="chdb://") as conn:
    ...
```
