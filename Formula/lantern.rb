class Lantern < Formula
  desc "Is a postgres extension that provides blazingly fast vector indexes"
  homepage "https://lantern.dev"
  url "https://github.com/lanterndata/lantern/releases/download/v0.5.0/lantern-v0.5.0-source.tar.gz"
  version "0.5.0"
  sha256 "d2fad427fc420fcbef87774bead6d8a4cc863cabd745b6fc161dedaa4383a037"

  license "MIT"

  depends_on "cmake" => :build
  depends_on "gcc" => :build
  depends_on "make" => :build

  def which(cmd)
    exts = ENV["PATHEXT"] ? ENV["PATHEXT"].split(";") : [""]
    ENV["PATH"].split(File::PATH_SEPARATOR).each do |path|
      exts.each do |ext|
        exe = File.join(path, "#{cmd}#{ext}")
        return exe if File.executable?(exe) && !File.directory?(exe)
      end
    end
    nil
  end

  def self.postgresql
    # Try to get the most recent postgres version first
    if File.exist?(Formula["postgresql@16"].opt_bin)
      Formula["postgresql@16"]
    elsif File.exist?(Formula["postgresql@15"].opt_bin)
      Formula["postgresql@15"]
    elsif File.exist?(Formula["postgresql@14"].opt_bin)
      Formula["postgresql@14"]
    elsif File.exist?(Formula["postgresql@13"].opt_bin)
      Formula["postgresql@13"]
    elsif File.exist?(Formula["postgresql@12"].opt_bin)
      Formula["postgresql@12"]
    elsif File.exist?(Formula["postgresql@11"].opt_bin)
      Formula["postgresql@11"]
    end
  end

  unless postgresql
    # Install postgres 15 if no version is found
    depends_on "postgresql@15" => :build
  end

  def pgconfig
    postgresql = self.class.postgresql
    pg_config = which("pg_config")
    if !pg_config.nil?
      # pg_config exists in path use that
      pg_config
    elsif File.file?("/usr/local/bin/pg_config")
      "/usr/local/bin/pg_config"
    else
      postgresql.opt_bin/"pg_config"
    end
  end

  def install
    pg_config = pgconfig

    ENV["C_INCLUDE_PATH"] = "/usr/local/include"
    ENV["CPLUS_INCLUDE_PATH"] = "/usr/local/include"
    ENV["PG_CONFIG"] = pg_config

    system "cmake", "-DBUILD_FOR_DISTRIBUTING=YES", "-S", "./lantern_hnsw", "-B", "build"
    system "make", "-C", "build", "-j"

    share.install "build/lantern.control"
    share.install Dir["build/lantern--*.sql"]

    sql_update_files = Dir["sql/updates/*.sql"]
    sql_update_files.each do |file|
      # Extract the base file name (e.g., 0.0.1-0.0.2.sql)
      basename = File.basename(file)

      # Rename the file and install it with the desired name
      renamed_file = "lantern--#{basename}"
      share.install(file => renamed_file)
    end

    libdir = `#{pg_config} --pkglibdir`
    sharedir = `#{pg_config} --sharedir`

    `touch lantern_install`
    `chmod +x lantern_install`

    `echo "#!/bin/bash" >> lantern_install`
    `echo "echo 'Moving lantern files into postgres extension folder...'" >> lantern_install`

    if File.file?("build/lantern.so")
      lib.install "build/lantern.so"
      `echo "/usr/bin/install -c -m 755 #{lib}/lantern.so #{libdir.strip}/" >> lantern_install`
    else
      lib.install "build/lantern.dylib"
      `echo "/usr/bin/install -c -m 755 #{lib}/lantern.dylib #{libdir.strip}/" >> lantern_install`
    end

    `echo "/usr/bin/install -c -m 644 #{share}/* #{sharedir.strip}/extension/" >> lantern_install`
    `echo "echo 'Success.'" >> lantern_install`

    bin.install "lantern_install"
  end

  def caveats
    <<~EOS
      Thank you for installing Lantern!

      Run `lantern_install` to finish installation on #{self.class.postgresql.name}

      After that you can enable Lantern extension from psql:
        CREATE EXTENSION lantern;
    EOS
  end

  test do
    postgresql = self.class.postgresql
    pg_ctl = postgresql.opt_bin/"pg_ctl"
    psql = postgresql.opt_bin/"psql"
    port = free_port

    ENV["LC_ALL"] = "en_US.UTF-8"
    ENV["LANG"] = "C"
    system pg_ctl, "initdb", "-D", testpath/"test"
    (testpath/"test/postgresql.conf").write <<~EOS, mode: "a+"
      shared_preload_libraries = 'lantern'
      port = #{port}
    EOS
    system pg_ctl, "start", "-D", testpath/"test", "-l", testpath/"log"
    system psql, "-p", port.to_s, "-c", "CREATE EXTENSION \"lantern\";", "postgres"
    system pg_ctl, "stop", "-D", testpath/"test"
  end
end
