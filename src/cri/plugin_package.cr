require "digest/sha256"

module Cri
  class PluginPackage
    EXTENSION_ROOT               = ".config/cri/extensions"
    MAX_ARCHIVE_COMPRESSED_BYTES = 16_i64 * 1024_i64 * 1024_i64
    MAX_ARCHIVE_ENTRIES          = 1024
    MAX_ARCHIVE_BYTES            = 64_i64 * 1024_i64 * 1024_i64

    private struct ArchiveEntry
      getter name : String
      getter kind : Char
      getter size : Int64

      def initialize(@name : String, @kind : Char, @size : Int64)
      end
    end

    getter root : String

    def initialize(@root : String = Dir.current)
    end

    def pack(project : String, output : String? = nil) : Bool
      project = File.expand_path(project, root)
      manifest_path = File.join(project, "extension.toml")
      manifest = Extensions::Manifest.load(manifest_path)
      return fail_with(manifest.errors) unless manifest.valid?

      wasm = manifest.wasm_path
      return fail_with(["WASM artifact not found; run cri plugin build first"]) unless wasm && File.file?(wasm)
      conformance = Wasm::ConformanceChecker.new.check(wasm.not_nil!)
      return fail_with(conformance.errors) unless conformance.valid?

      destination = output || File.join(root, "#{manifest.name}.cri-plugin.tar.gz")
      destination = File.expand_path(destination, root)
      entries = ["extension.toml", "plugin.wasm"]
      entries << "README.md" if File.file?(File.join(project, "README.md"))
      entries << "prompts" if Dir.exists?(File.join(project, "prompts"))

      args = ["-czf", destination, "-C", project] + entries
      unless run_tar(args)
        STDERR.puts "could not create plugin package"
        return false
      end
      puts "created #{destination}"
      true
    rescue ex
      STDERR.puts "could not pack plugin: #{ex.message || ex.class.name}"
      false
    end

    def install(package : String, destination_root : String? = nil) : Bool
      temp : String? = nil
      begin
        package = File.expand_path(package, root)
        return fail_with(["package not found: #{package}"]) unless File.file?(package)
        return fail_with(["package is too large"]) if File.size(package) > MAX_ARCHIVE_COMPRESSED_BYTES
        package_digest = archive_digest(package)

        entries = archive_entries(package)
        return false unless entries && safe_entries?(entries.not_nil!)

        temp = File.join(Dir.tempdir, "cri-plugin-#{Random::Secure.hex(8)}")
        Dir.mkdir_p(temp)
        return false unless run_tar(["--no-same-owner", "--no-same-permissions", "-xzf", package, "-C", temp])
        return fail_with(["package changed during extraction"]) unless archive_digest(package) == package_digest

        manifest = Extensions::Manifest.load(File.join(temp, "extension.toml"))
        return fail_with(manifest.errors) unless manifest.valid?
        return fail_with(["invalid plugin name"]) unless safe_name?(manifest.name)

        target_root = destination_root || default_install_root
        destination = File.join(target_root, manifest.name)
        if Dir.exists?(destination)
          return fail_with(["plugin already installed: #{manifest.name}"])
        end

        Dir.mkdir_p(target_root)
        FileUtils.mv(temp, destination)
        temp = nil
        puts "installed #{manifest.name} to #{destination}"
        true
      rescue ex
        STDERR.puts "could not install plugin: #{ex.message || ex.class.name}"
        false
      ensure
        FileUtils.rm_rf(temp.not_nil!) if temp && Dir.exists?(temp.not_nil!)
      end
    end

    def remove(name : String, destination_root : String? = nil) : Bool
      return fail_with(["invalid plugin name"]) unless safe_name?(name)
      destination = File.join(destination_root || default_install_root, name)
      return fail_with(["plugin is not installed: #{name}"]) unless Dir.exists?(destination)
      FileUtils.rm_rf(destination)
      puts "removed #{name}"
      true
    rescue ex
      STDERR.puts "could not remove plugin: #{ex.message || ex.class.name}"
      false
    end

    private def archive_digest(package : String) : String
      Digest::SHA256.hexdigest(File.read(package))
    end

    private def archive_entries(package : String) : Array(ArchiveEntry)?
      names_output = IO::Memory.new
      names_status = Process.run("tar", args: ["-tzf", package], output: names_output, error: Process::Redirect::Inherit)
      return nil unless names_status.success?

      verbose_output = IO::Memory.new
      verbose_status = Process.run(
        "tar",
        args: ["-tvzf", package, "--quoting-style=escape"],
        output: verbose_output,
        error: Process::Redirect::Inherit
      )
      return nil unless verbose_status.success?

      names = names_output.to_s.lines.map(&.chomp).reject(&.empty?)
      details = verbose_output.to_s.lines.map(&.chomp).reject(&.empty?)
      return nil unless names.size == details.size

      entries = [] of ArchiveEntry
      index = 0
      while index < details.size
        line = details[index]
        fields = line.split
        return nil if fields.size < 3
        size = fields[2].to_i64?
        return nil unless size
        entries << ArchiveEntry.new(names[index], line[0], size.not_nil!)
        index += 1
      end
      entries
    rescue
      nil
    end

    private def safe_entries?(entries : Array(ArchiveEntry)) : Bool
      return fail_with(["package has no files"]) if entries.empty?
      return fail_with(["package has too many entries"]) if entries.size > MAX_ARCHIVE_ENTRIES

      total_size = 0_i64
      names = {} of String => Bool
      entries.each do |entry|
        clean = entry.name.sub(/^\.\//, "")
        if names[clean]?
          return fail_with(["duplicate path in package: #{entry.name}"])
        end
        names[clean] = true

        unless entry.kind == '-' || entry.kind == 'd'
          return fail_with(["unsupported entry type in package: #{entry.name}"])
        end

        path_segments = clean.split(File::SEPARATOR)
        if clean.includes?("\0") || clean.starts_with?("/") || path_segments.any? { |segment| segment == ".." }
          return fail_with(["unsafe path in package: #{entry.name}"])
        end

        total_size += entry.size
        if total_size > MAX_ARCHIVE_BYTES
          return fail_with(["package is too large"])
        end
      end
      true
    end

    private def safe_name?(name : String) : Bool
      !!(name =~ /^[A-Za-z0-9][A-Za-z0-9_.-]*$/)
    end

    private def default_install_root : String
      home = ENV["HOME"]? || root
      File.join(home, EXTENSION_ROOT)
    end

    private def run_tar(args : Array(String)) : Bool
      Process.run("tar", args: args, output: Process::Redirect::Inherit, error: Process::Redirect::Inherit).success?
    end

    private def fail_with(errors : Array(String)) : Bool
      errors.each { |error| STDERR.puts error }
      false
    end
  end
end
