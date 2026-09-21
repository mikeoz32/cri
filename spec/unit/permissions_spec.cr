require "../spec_helper"

describe Cri::Permissions::GrantSet do
  it "requires both requested and granted network scopes" do
    requested = Cri::Permissions::Request.new(network: ["https://api.github.com"])
    grants = Cri::Permissions::GrantSet.new(network: ["https://api.github.com"])

    grants.allows_network?("https://api.github.com/repos/a/b", requested).should be_true
    grants.allows_network?("https://api.github.com.evil/repos/a/b", requested).should be_false
    grants.allows_network?("https://example.com", requested).should be_false
  end

  it "supports subdomain scopes without matching the bare parent" do
    requested = Cri::Permissions::Request.new(network: ["https://*.slack.com"])
    grants = Cri::Permissions::GrantSet.new(network: ["https://*.slack.com"])

    grants.allows_network?("https://api.slack.com/v1", requested).should be_true
    grants.allows_network?("https://slack.com/v1", requested).should be_false
  end

  it "requires both requested and granted secrets" do
    requested = Cri::Permissions::Request.new(secrets: ["GITHUB_TOKEN"])
    grants = Cri::Permissions::GrantSet.new(secrets: ["GITHUB_TOKEN"])

    grants.allows_secret?("GITHUB_TOKEN", requested).should be_true
    grants.allows_secret?("OTHER", requested).should be_false
  end
end
