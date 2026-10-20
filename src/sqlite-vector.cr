require "sqlite3"

# Installs SQLite Vector's SQL functions on an official SQLite3 connection.
module Sqlite::Vector
  VERSION           = "0.1.0"
  EXTENSION_VERSION = "1.1.2"

  # A loading failure, including SQLite's return code when available.
  class Error < DB::Error
    getter code : Int32?

    def initialize(message : String, @code : Int32? = nil)
      super(code ? "#{message} (SQLite code #{code})" : message)
    end
  end

  # :nodoc:
  private lib LibExtension
    fun db_config = sqlite3_db_config(db : LibSQLite3::SQLite3, option : Int32, ...) : Int32
    fun load_extension = sqlite3_load_extension(db : LibSQLite3::SQLite3, path : UInt8*, entry_point : UInt8*, error : UInt8**) : Int32
    fun free = sqlite3_free(pointer : Void*) : Void
  end

  # Returns the installed binary's absolute path in the shard's source tree.
  # Deployed applications should copy the binary and pass its location to `.load`.
  def self.extension_path : String
    platform = {% if flag?(:darwin) %}
                 "macos"
               {% elsif flag?(:linux) && flag?(:musl) %}
                 "linux-musl"
               {% elsif flag?(:linux) %}
                 "linux"
               {% else %}
                 {% raise "SQLite Vector supports only macOS and Linux" %}
               {% end %}
    architecture = {% if flag?(:aarch64) %}
                     "arm64"
                   {% elsif flag?(:x86_64) %}
                     "x86_64"
                   {% else %}
                     {% raise "SQLite Vector supports only ARM64 and x86_64" %}
                   {% end %}
    filename = {% if flag?(:darwin) %} "vector.dylib" {% else %} "vector.so" {% end %}
    path = File.expand_path("../native/#{platform}-#{architecture}/#{filename}", __DIR__)
    unless File.file?(path)
      raise Error.new("SQLite Vector binary not found at #{path}. Run the shard's scripts/install.sh or pass path: when deploying.")
    end
    path
  end

  # Loads the extension on this connection. Call inside `DB::Database#setup_connection`
  # to initialize both existing and future pooled connections.
  def self.load(connection : SQLite3::Connection, path : String = extension_path) : Nil
    raise Error.new("Cannot load SQLite Vector on a closed connection") if connection.closed?
    raise Error.new("SQLite Vector path must not be empty or contain NUL") if path.empty? || path.includes?('\0')

    path = File.expand_path(path)
    raise Error.new("SQLite Vector binary not found at #{path}") unless File.file?(path)

    handle = connection.to_unsafe
    # Enable only the C API; SQL load_extension() must stay disabled.
    code = LibExtension.db_config(handle, 1005, 1, Pointer(Int32).null)
    unless code == 0
      raise Error.new("Cannot enable SQLite extension loading; use a SQLite library with extension loading support", code)
    end

    error = Pointer(UInt8).null
    message = nil
    disable_code = 0
    begin
      code = LibExtension.load_extension(handle, path, "sqlite3_vector_init", pointerof(error))
      message = String.new(error) unless error.null?
    ensure
      LibExtension.free(error.as(Void*)) unless error.null?
      disable_code = LibExtension.db_config(handle, 1005, 0, Pointer(Int32).null)
    end

    unless code == 0
      detail = message || "no error message provided"
      detail += "; disabling extension loading also failed (SQLite code #{disable_code})" unless disable_code == 0
      raise Error.new("Cannot load SQLite Vector from #{path}: #{detail}", code)
    end
    unless disable_code == 0
      raise Error.new("SQLite Vector loaded but disabling extension loading failed", disable_code)
    end
  end
end
