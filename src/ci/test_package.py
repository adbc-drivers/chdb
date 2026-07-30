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

"""Post-install check: a dbc-installed chDB driver loads and answers a query.

Mirrors adbc-drivers/clickhouse:src/ci/test_package.py, but chDB is embedded so
there is no network endpoint -- we open an in-memory database instead.
"""

import adbc_driver_manager.dbapi


def test_package() -> None:
    # dbc registers the driver under the package name ("chdb").
    with adbc_driver_manager.dbapi.connect(
        driver="chdb", uri="chdb://", autocommit=True
    ) as conn:
        with conn.cursor() as cursor:
            cursor.execute("SELECT 1")
            assert cursor.fetchone() == (1,)
