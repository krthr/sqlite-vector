require "spec"
require "../src/sqlite-vector"

lib VectorSpecSQLite
  fun db_config = sqlite3_db_config(db : LibSQLite3::SQLite3, option : Int32, ...) : Int32
end

def with_connection(&)
  DB.connect("sqlite3://%3Amemory%3A") do |connection|
    yield connection.as(SQLite3::Connection)
  end
end

def extension_loading_state(connection : SQLite3::Connection)
  enabled = -1
  VectorSpecSQLite.db_config(connection.to_unsafe, 1005, -1, pointerof(enabled)).should eq(0)
  enabled
end

def assert_sql_loading_disabled(connection : SQLite3::Connection)
  expect_raises(SQLite3::Exception, /not authorized/) do
    connection.scalar("SELECT load_extension(?)", Sqlite::Vector.extension_path)
  end
end

def assert_loading_disabled(connection : SQLite3::Connection)
  extension_loading_state(connection).should eq(0)
  assert_sql_loading_disabled(connection)
end
