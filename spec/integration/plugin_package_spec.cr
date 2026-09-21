require "../spec_helper"

describe Cri::PluginPackage do
  it "packs, installs and removes a plugin" do
    package_path = "/tmp/cri-package-#{Process.pid}.cri-plugin.tar.gz"
    install_root = "/tmp/cri-install-#{Process.pid}"
    package = Cri::PluginPackage.new(Dir.current)

    package.pack("examples/extensions/zig_fetch", package_path).should be_true
    File.file?(package_path).should be_true
    package.install(package_path, install_root).should be_true
    File.file?(File.join(install_root, "zig_fetch", "plugin.wasm")).should be_true
    package.remove("zig_fetch", install_root).should be_true
    Dir.exists?(File.join(install_root, "zig_fetch")).should be_false
    package.remove("../zig_fetch", install_root).should be_false
    package.install(package_path, install_root).should be_true
    package.install(package_path, install_root).should be_false
  ensure
    File.delete(package_path) if package_path && File.file?(package_path)
    FileUtils.rm_rf(install_root) if install_root && Dir.exists?(install_root)
  end

  it "rejects symlink and hardlink entries before extraction" do
    source = "/tmp/cri-package-links-#{Process.pid}"
    link_package_path = "/tmp/cri-links-#{Process.pid}.tar.gz"
    install_root = "/tmp/cri-links-install-#{Process.pid}"
    begin
      Dir.mkdir(source)
      File.write(File.join(source, "regular.txt"), "safe")
      File.symlink("/etc/passwd", File.join(source, "symlink.txt"))
      File.link(File.join(source, "regular.txt"), File.join(source, "hardlink.txt"))
      Process.run("tar", args: ["-czf", link_package_path, "-C", source, "."]).success?.should be_true

      Cri::PluginPackage.new(Dir.current).install(link_package_path, install_root).should be_false
      Dir.exists?(File.join(install_root, "regular.txt")).should be_false
    ensure
      File.delete(link_package_path) if File.file?(link_package_path)
      FileUtils.rm_rf(source)
      FileUtils.rm_rf(install_root)
    end
  end

  it "rejects archives with too many entries" do
    source = "/tmp/cri-package-many-#{Process.pid}"
    many_package_path = "/tmp/cri-many-#{Process.pid}.tar.gz"
    install_root = "/tmp/cri-many-install-#{Process.pid}"
    begin
      Dir.mkdir(source)
      Cri::PluginPackage::MAX_ARCHIVE_ENTRIES.times do |index|
        File.write(File.join(source, "file-#{index}"), "")
      end
      File.write(File.join(source, "one-too-many"), "")
      Process.run("tar", args: ["-czf", many_package_path, "-C", source, "."]).success?.should be_true

      Cri::PluginPackage.new(Dir.current).install(many_package_path, install_root).should be_false
      Dir.exists?(install_root).should be_false
    ensure
      File.delete(many_package_path) if File.file?(many_package_path)
      FileUtils.rm_rf(source)
      FileUtils.rm_rf(install_root)
    end
  end

  it "rejects archive paths that traverse outside the package root" do
    source = "/tmp/cri-package-traversal-#{Process.pid}"
    traversal_package_path = "/tmp/cri-traversal-#{Process.pid}.tar.gz"
    install_root = "/tmp/cri-traversal-install-#{Process.pid}"
    begin
      Dir.mkdir(source)
      File.write(File.join(source, "payload"), "unsafe")
      Process.run("tar", args: ["-czf", traversal_package_path, "-C", source, "--transform=s,^payload$,../escape,", "payload"]).success?.should be_true

      Cri::PluginPackage.new(Dir.current).install(traversal_package_path, install_root).should be_false
      File.exists?(File.join(install_root, "escape")).should be_false
    ensure
      File.delete(traversal_package_path) if File.file?(traversal_package_path)
      FileUtils.rm_rf(source)
      FileUtils.rm_rf(install_root)
    end
  end

  it "rejects archives above the uncompressed size limit" do
    source = "/tmp/cri-package-large-#{Process.pid}"
    large_package_path = "/tmp/cri-large-#{Process.pid}.tar.gz"
    install_root = "/tmp/cri-large-install-#{Process.pid}"
    begin
      Dir.mkdir(source)
      payload = File.join(source, "payload")
      Process.run("truncate", args: ["-s", (Cri::PluginPackage::MAX_ARCHIVE_BYTES + 1).to_s, payload]).success?.should be_true
      Process.run("tar", args: ["-czf", large_package_path, "-C", source, "payload"]).success?.should be_true

      Cri::PluginPackage.new(Dir.current).install(large_package_path, install_root).should be_false
      Dir.exists?(install_root).should be_false
    ensure
      File.delete(large_package_path) if File.file?(large_package_path)
      FileUtils.rm_rf(source)
      FileUtils.rm_rf(install_root)
    end
  end
end
