require "../spec_helper"

describe Cri::Permissions::GrantPolicy do
  it "loads per-extension grants and disabled state" do
    policy = Cri::Permissions::GrantPolicy.new
    policy.merge_json(JSON.parse(%({
      "extensions": {
        "github_issue": {
          "enabled": true,
          "network": ["https://api.github.com"],
          "secrets": ["GITHUB_TOKEN"]
        },
        "disabled": {"enabled": false}
      }
    })))

    policy.enabled?("github_issue").should be_true
    policy.for_extension("github_issue").network.should eq(["https://api.github.com"])
    policy.for_extension("github_issue").secrets.should eq(["GITHUB_TOKEN"])
    policy.enabled?("disabled").should be_false
  end

  it "round-trips the typed grant configuration" do
    config = Cri::Permissions::GrantPolicyConfig.from_json(%({
      "extensions": {
        "workspace": {
          "network": ["https://example.test"],
          "filesystem_read": ["/tmp/project"],
          "model": true
        }
      }
    }))

    loaded = Cri::Permissions::GrantPolicyConfig.from_json(config.to_json)
    loaded.extensions["workspace"].network.should eq(["https://example.test"])
    loaded.extensions["workspace"].filesystem_read.should eq(["/tmp/project"])
    loaded.extensions["workspace"].model.should be_true

    policy = Cri::Permissions::GrantPolicy.new
    policy.merge(loaded)
    policy.for_extension("workspace").network.should eq(["https://example.test"])
  end

  it "rejects values that do not match the grant schema" do
    expect_raises(JSON::ParseException) do
      Cri::Permissions::GrantPolicyConfig.from_json(%({"extensions":{"bad":{"network":"all"}}}))
    end
  end
end
