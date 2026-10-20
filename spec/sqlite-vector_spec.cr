require "./spec_helper"

describe Sqlite::Vector do
  it "finds an absolute path to the installed native library" do
    path = Sqlite::Vector.extension_path
    Path[path].absolute?.should be_true
    File.file?(path).should be_true
  end

  it "loads the pinned vector extension and disables further loading" do
    with_connection do |connection|
      Sqlite::Vector.load(connection)
      connection.scalar("SELECT vector_version()").should eq(Sqlite::Vector::EXTENSION_VERSION)
      assert_loading_disabled(connection)
    end
  end

  it "supports a real nearest-neighbor query using ordinary SQL" do
    with_connection do |connection|
      Sqlite::Vector.load(connection)
      connection.exec("CREATE TABLE items (id INTEGER PRIMARY KEY, embedding BLOB)")
      connection.exec("INSERT INTO items VALUES (1, vector_as_f32('[1, 0]')), (2, vector_as_f32('[0, 1]'))")
      connection.scalar("SELECT vector_init('items', 'embedding', 'type=FLOAT32,dimension=2,distance=L2')")

      id, distance = connection.query_one(
        "SELECT rowid, distance FROM vector_full_scan('items', 'embedding', vector_as_f32(?), 1)",
        "[1, 0]", as: {Int64, Float64}
      )
      id.should eq(1)
      distance.should eq(0.0)
    end
  end

  it "loads existing and future pooled connections alongside application setup" do
    DB.open("sqlite3://%3Amemory%3A?initial_pool_size=1&max_pool_size=2") do |db|
      initialized = [] of SQLite3::Connection
      db.setup_connection do |connection|
        sqlite = connection.as(SQLite3::Connection)
        Sqlite::Vector.load(sqlite)
        connection.exec("PRAGMA foreign_keys = ON")
        initialized << sqlite
      end

      initialized.size.should eq(1)
      db.using_connection do |first|
        db.using_connection do |second|
          first.should_not be(second)
          initialized.size.should eq(2)
          [first, second].each do |connection|
            connection.scalar("SELECT vector_version()").should eq(Sqlite::Vector::EXTENSION_VERSION)
            connection.scalar("PRAGMA foreign_keys").should eq(1)
            assert_loading_disabled(connection.as(SQLite3::Connection))
          end
        end
      end
    end
  end

  it "can be loaded more than once on a connection" do
    with_connection do |connection|
      2.times { Sqlite::Vector.load(connection) }
      connection.scalar("SELECT vector_version()").should eq(Sqlite::Vector::EXTENSION_VERSION)
      assert_loading_disabled(connection)
    end
  end

  it "supports an explicit library path" do
    with_connection do |connection|
      Sqlite::Vector.load(connection, path: Sqlite::Vector.extension_path)
      connection.scalar("SELECT vector_version()").should eq(Sqlite::Vector::EXTENSION_VERSION)
    end
  end

  it "rejects closed connections before using their native handle" do
    with_connection do |connection|
      connection.close
      expect_raises(Sqlite::Vector::Error, /closed connection/) do
        Sqlite::Vector.load(connection)
      end
    end
  end

  it "rejects empty paths and embedded NULs" do
    with_connection do |connection|
      initial_state = extension_loading_state(connection)
      ["", "#{Sqlite::Vector.extension_path}\0ignored"].each do |path|
        expect_raises(Sqlite::Vector::Error, /empty or contain NUL/) do
          Sqlite::Vector.load(connection, path: path)
        end
      end
      extension_loading_state(connection).should eq(initial_state)
      assert_sql_loading_disabled(connection)
    end
  end

  it "rejects missing files and directories" do
    with_connection do |connection|
      initial_state = extension_loading_state(connection)
      [File.join(Sqlite::Vector.extension_path, "missing"), __DIR__].each do |path|
        expect_raises(Sqlite::Vector::Error, /binary not found/) do
          Sqlite::Vector.load(connection, path: path)
        end
      end
      extension_loading_state(connection).should eq(initial_state)
      assert_sql_loading_disabled(connection)
    end
  end

  it "preserves native load errors and disables loading after failure" do
    with_connection do |connection|
      error = expect_raises(Sqlite::Vector::Error, /Cannot load SQLite Vector/) do
        Sqlite::Vector.load(connection, path: __FILE__)
      end
      error.code.should eq(1)
      error.message.not_nil!.should contain(__FILE__)
      error.message.not_nil!.should_not contain("no error message provided")
      assert_loading_disabled(connection)

      Sqlite::Vector.load(connection)
      connection.scalar("SELECT vector_version()").should eq(Sqlite::Vector::EXTENSION_VERSION)
    end
  end
end
