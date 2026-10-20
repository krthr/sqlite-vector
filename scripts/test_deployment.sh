#!/bin/sh
set -eu

project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
smoke_dir=$(mktemp -d "${TMPDIR:-/tmp}/sqlite-vector-deployment.XXXXXX")
trap 'rm -rf "$smoke_dir"' EXIT
trap 'exit 1' HUP INT TERM

mkdir -p "$smoke_dir/shard" "$smoke_dir/consumer" "$smoke_dir/deploy"
cp "$project_dir/shard.yml" "$smoke_dir/shard/"
cp -R "$project_dir/src" "$project_dir/scripts" "$smoke_dir/shard/"

cat > "$smoke_dir/consumer/shard.yml" <<'YAML'
name: sqlite_vector_consumer
version: 0.1.0
dependencies:
  sqlite-vector:
    path: ../shard
YAML

cat > "$smoke_dir/consumer/main.cr" <<'CRYSTAL'
require "sqlite-vector"

if ARGV[0]? == "--extension-path"
  puts Sqlite::Vector.extension_path
  exit
end

DB.open("sqlite3::memory:") do |db|
  db.setup_connection do |connection|
    Sqlite::Vector.load(connection.as(SQLite3::Connection), path: ARGV[0])
  end
  version = db.scalar("SELECT vector_version()").as(String)
  raise "Unexpected vector version: #{version}" unless version == "1.1.2"
  puts "Deployed SQLite Vector #{version} loaded successfully"
end
CRYSTAL

cd "$smoke_dir/consumer"
shards install
crystal build main.cr -o "$smoke_dir/deploy/app"
extension_path=$("$smoke_dir/deploy/app" --extension-path)
extension_name=$(basename "$extension_path")
cp "$extension_path" "$smoke_dir/deploy/$extension_name"

cd "$smoke_dir/deploy"
rm -rf "$smoke_dir/consumer" "$smoke_dir/shard"
./app "$smoke_dir/deploy/$extension_name"
