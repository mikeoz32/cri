require "../spec_helper"

describe Cri::Wasm::ConformanceChecker do
  it "checks the raw fixture module without a runtime" do
    result = Cri::Wasm::ConformanceChecker.new.check("examples/extensions/fixture/plugin.wasm")

    result.valid?.should be_true
    result.has_memory.should be_true
    result.imports.should be_empty
    result.exports.should contain("cri_call")
  end

  it "checks the freestanding Zig module" do
    result = Cri::Wasm::ConformanceChecker.new.check("examples/extensions/zig_fetch/plugin.wasm")

    result.valid?.should be_true
    result.imports.should be_empty
    result.exports.should contain("cri_resume")
  end
end
