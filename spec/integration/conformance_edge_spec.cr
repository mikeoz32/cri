require "../spec_helper"

describe Cri::Wasm::ConformanceChecker do
  it "rejects malformed bytes" do
    path = "/tmp/cri-invalid-#{Process.pid}.wasm"
    File.write(path, "not wasm")

    result = Cri::Wasm::ConformanceChecker.new.check(path)
    result.valid?.should be_false
    result.errors.should contain("invalid WASM magic")
  ensure
    File.delete(path) if path && File.file?(path)
  end

  it "rejects imported capabilities" do
    # wasm magic/version + one imported function from env.x.
    bytes = Bytes[0x00, 0x61, 0x73, 0x6d, 0x01, 0x00, 0x00, 0x00,
      0x02, 0x09, 0x01, 0x03, 0x65, 0x6e, 0x76, 0x01, 0x78, 0x00, 0x00]
    path = "/tmp/cri-import-#{Process.pid}.wasm"
    File.write(path, String.new(bytes))

    result = Cri::Wasm::ConformanceChecker.new.check(path)
    result.valid?.should be_false
    result.imports.should eq(["env.x"])
    result.errors.should contain("WASM modules must not import host/WASI capabilities")
  ensure
    File.delete(path) if path && File.file?(path)
  end
end
