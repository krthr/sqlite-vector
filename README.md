# sqlite-vector

A Crystal shard that installs and loads [SQLite Vector](https://github.com/sqliteai/sqlite-vector)
using the official [crystal-sqlite3](https://github.com/crystal-lang/crystal-sqlite3)
adapter. Vector operations remain ordinary SQL.

## Installation

Requires Crystal 1.21.1 or newer and a system SQLite library with runtime extension
loading enabled. The shard uses `crystal-sqlite3 ~> 0.24.0`; it does not replace
SQLite or require an adapter fork.

On macOS, Apple's SQLite may omit the extension-loading entry point. Install
Homebrew SQLite and tell Crystal's linker where to find it before compiling:

```sh
brew install sqlite
export CRYSTAL_LIBRARY_PATH="$(brew --prefix sqlite)/lib:$(crystal env CRYSTAL_LIBRARY_PATH)"
```

Without a SQLite library that exports `sqlite3_load_extension`, compilation can
fail with an undefined-symbol error. On Linux, install the SQLite development
package for your distribution (`libsqlite3-dev` on Debian/Ubuntu, `sqlite-dev`
on Alpine).

Add the dependency to `shard.yml`:

```yaml
dependencies:
  sqlite-vector:
    github: krthr/sqlite-vector
```

Run `shards install`. Its postinstall hook downloads SQLite Vector **1.1.2** from
the upstream release, verifies its pinned SHA-256 checksum, and installs the
shared library under `lib/sqlite-vector/native/`. Installation needs `curl`,
`tar`, and `sha256sum` or `shasum`; Linux also needs `ldd` to identify libc.

Supported native platforms:

| OS | Architectures | Library |
| --- | --- | --- |
| macOS | ARM64, x86_64 | `vector.dylib` |
| Linux, glibc | ARM64, x86_64 | `vector.so` |
| Linux, musl (including Alpine) | ARM64, x86_64 | `vector.so` |

If you use `shards install --skip-postinstall`, run the installer yourself:

```sh
sh lib/sqlite-vector/scripts/install.sh
```

Installation requires network access; running the application does not download
anything. Unsupported platforms and installation failures produce errors.

## Usage

```crystal
require "sqlite-vector"

DB.open("sqlite3://./app.db") do |db|
  db.setup_connection do |connection|
    Sqlite::Vector.load(connection.as(SQLite3::Connection))
  end

  puts db.scalar("SELECT vector_version()")
end
```

Load the extension before running vector queries. `setup_connection` initializes
both existing connections and connections created later by the pool. If your
application already has a setup block, add the loader there: registering another
block replaces the previous one.

The public methods are:

```crystal
Sqlite::Vector.extension_path : String
Sqlite::Vector.load(connection : SQLite3::Connection,
                   path : String = extension_path) : Nil
```

`extension_path` returns the installed library's absolute path. `load` uses
SQLite's C loading API and disables extension loading after a native load
attempt, including on failure. Invalid inputs are rejected before changing the
connection. It does not enable SQL's `load_extension()` function. Failures raise
`Sqlite::Vector::Error`, with SQLite's return code in `code` when available.
Only load libraries you trust.

Loading failures raise `Sqlite::Vector::Error`, a `DB::Error` subclass. Its `code`
property contains SQLite's return code when the failure came from SQLite.

### Vector queries

Create the table first, then call `vector_init` in the setup block for every
connection that will use it:

```crystal
require "sqlite-vector"

DB.open("sqlite3://./app.db") do |db|
  db.using_connection do |connection|
    connection.exec "CREATE TABLE IF NOT EXISTS documents (id INTEGER PRIMARY KEY, embedding BLOB)"
  end

  db.setup_connection do |connection|
    Sqlite::Vector.load(connection.as(SQLite3::Connection))
    connection.scalar "SELECT vector_init('documents', 'embedding', 'type=FLOAT32,dimension=3')"
  end

  db.exec "INSERT OR REPLACE INTO documents VALUES (1, vector_as_f32(?))", "[1,0,0]"
  db.exec "INSERT OR REPLACE INTO documents VALUES (2, vector_as_f32(?))", "[0,1,0]"
  ids = db.query_all(
    "SELECT rowid FROM vector_full_scan('documents', 'embedding', vector_as_f32(?), 1)",
    "[1,0,0]", as: Int64
  )
  puts ids # => [1]
end
```

Table initialization is connection-local; loading the extension alone does not
initialize your tables. Register setup before starting application queries, and
keep schema creation in `using_connection` as shown. See the
[upstream SQL API](https://github.com/sqliteai/sqlite-vector/blob/1.1.2/API.md)
for distances, quantization, and other vector operations.

## Deployment

The compiled Crystal executable does **not** embed the downloaded library. Copy
the appropriate file from `lib/sqlite-vector/native/<platform>/` into your
deployment and pass its runtime path:

```crystal
Sqlite::Vector.load(connection.as(SQLite3::Connection),
  path: "/opt/my-app/lib/vector.so")
```

Use `vector.dylib` on macOS. The default path points into the source checkout;
an explicit deployment path lets the executable run without that checkout.
Ship the [upstream license](LICENSE-SQLITE-VECTOR) and
[third-party notice](THIRD-PARTY-NOTICES.md) with the library.

Build and install on the target OS, CPU architecture, and libc. Cross-compilation,
Windows, fully static executables, and embedding the extension are not supported
by this shard. A matching extension binary still requires a compatible system
SQLite build; builds with `SQLITE_OMIT_LOAD_EXTENSION` cannot load it.

## Development

```sh
shards install
sh scripts/install.sh
sh scripts/test_install.sh
crystal spec
sh scripts/test_deployment.sh
crystal tool format --check
```

The root project's postinstall hook is not run by `shards install`, so development
requires the explicit installer command. Integration specs use the real extension.
The deployment smoke test installs a fresh downstream project, compiles it, and
runs it with a copied library after removing its temporary source checkout.

CI is configured for all six OS/architecture/libc combinations above.

## License

The Crystal wrapper is [MIT licensed](LICENSE). SQLite Vector is separately
[Apache-2.0 licensed](LICENSE-SQLITE-VECTOR), copyright SQLite Cloud, Inc.
