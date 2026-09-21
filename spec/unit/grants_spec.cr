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
end
