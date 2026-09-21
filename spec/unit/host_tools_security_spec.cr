require "../spec_helper"
require "file_utils"

describe "built-in filesystem tools" do
  it "does not read a symlink outside the project" do
    root = "/tmp/cri-host-tools-#{Process.pid}-#{Random.rand(1_000_000)}"
    outside = "#{root}-outside"
    begin
      Dir.mkdir(root)
      Dir.mkdir(outside)
      File.write(File.join(outside, "secret.txt"), "secret")
      File.symlink(File.join(outside, "secret.txt"), File.join(root, "link.txt"))

      result = Cri::ReadFileTool.new(root).call(JSON.parse(%({"path":"link.txt"})))
      result.ok.should be_false
    ensure
      FileUtils.rm_rf(root)
      FileUtils.rm_rf(outside)
    end
  end

  it "does not list a symlinked directory outside the project" do
    root = "/tmp/cri-host-tools-#{Process.pid}-#{Random.rand(1_000_000)}"
    outside = "#{root}-outside"
    begin
      Dir.mkdir(root)
      Dir.mkdir(outside)
      File.write(File.join(outside, "secret.txt"), "secret")
      File.symlink(outside, File.join(root, "external"))

      result = Cri::ListFilesTool.new(root).call(JSON.parse(%({"path":"external"})))
      result.ok.should be_false
    ensure
      FileUtils.rm_rf(root)
      FileUtils.rm_rf(outside)
    end
  end
end
