require "../spec_helper"
require "file_utils"

describe Cri::PathSecurity do
  it "rejects an existing symlink that points outside the granted root" do
    root = "/tmp/cri-path-security-#{Process.pid}-#{Random.rand(1_000_000)}"
    outside = "#{root}-outside"
    begin
      Dir.mkdir(root)
      Dir.mkdir(outside)
      File.write(File.join(outside, "secret.txt"), "secret")
      link = File.join(root, "link.txt")
      File.symlink(File.join(outside, "secret.txt"), link)

      Cri::PathSecurity.within?(link, root).should be_false
      grants = Cri::Permissions::GrantSet.new(filesystem_read: [root])
      requested = Cri::Permissions::Request.new(filesystem_read: [root])
      grants.allows_file_read?(link, requested).should be_false
    ensure
      FileUtils.rm_rf(root)
      FileUtils.rm_rf(outside)
    end
  end

  it "allows a missing child inside an existing root for preauthorization" do
    root = "/tmp/cri-path-security-#{Process.pid}-#{Random.rand(1_000_000)}"
    begin
      Dir.mkdir(root)
      grants = Cri::Permissions::GrantSet.new(filesystem_write: [root])
      requested = Cri::Permissions::Request.new(filesystem_write: [root])

      grants.allows_file_write?(File.join(root, "new.txt"), requested).should be_true
      grants.allows_file_write?(File.join(root, "nested", "new.txt"), requested).should be_false
    ensure
      FileUtils.rm_rf(root)
    end
  end
end
