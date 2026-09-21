require "../spec_helper"

describe Cri::Permissions::GrantSet do
  it "matches network paths on boundaries" do
    requested = Cri::Permissions::Request.new(network: ["https://api.example.com/v1"])
    grants = Cri::Permissions::GrantSet.new(network: ["https://api.example.com/v1"])

    grants.allows_network?("https://api.example.com/v1/issues", requested).should be_true
    grants.allows_network?("https://api.example.com/v12", requested).should be_false
    grants.allows_network?("http://api.example.com/v1/issues", requested).should be_false
  end

  it "rejects malformed URLs and unrequested secrets" do
    requested = Cri::Permissions::Request.new(network: ["not a url"], secrets: [] of String)
    grants = Cri::Permissions::GrantSet.new(network: ["not a url"], secrets: ["TOKEN"])

    grants.allows_network?("not a url", requested).should be_false
    grants.allows_secret?("TOKEN", requested).should be_false
  end

  it "keeps filesystem roots on directory boundaries" do
    requested = Cri::Permissions::Request.new(filesystem_read: ["/tmp/project"])
    grants = Cri::Permissions::GrantSet.new(filesystem_read: ["/tmp/project"])

    grants.allows_file_read?("/tmp/project/file.txt", requested).should be_true
    grants.allows_file_read?("/tmp/project-old/file.txt", requested).should be_false
  end
end
