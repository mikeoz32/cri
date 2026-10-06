require "../spec_helper"
require "file_utils"

describe Cri::SessionStore do
  it "persists extension state with the session" do
    workspace = File.join(Dir.tempdir, "cri-session-state-#{Random::Secure.hex(4)}")
    Dir.mkdir_p(workspace)
    begin
      store = Cri::SessionStore.new(workspace)
      session = Cri::Session.new("0123456789abcdef")
      session.set_extension_data("todo", Cri::RawJSON.new(%({"items":[{"id":"1","done":false}]})))
      store.save(session)

      restored = store.load(session.id).not_nil!
      restored.extension_data("todo").not_nil!.raw.should eq(%({"items":[{"id":"1","done":false}]}))
    ensure
      FileUtils.rm_rf(workspace)
    end
  end
end
