require "../spec_helper"

describe Cri::Extensions::Manifest do
  it "rejects executable manifests without a wasm artifact" do
    path = "/tmp/cri-manifest-#{Process.pid}.toml"
    File.write(path, <<-TOML)
      name = "missing"
      version = "0.1.0"
      abi = "cri.extension.v1"

      [[tools]]
      name = "missing.tool"
      TOML

    manifest = Cri::Extensions::Manifest.load(path)
    manifest.valid?.should be_false
    manifest.errors.should contain("wasm is required for executable contributions")
  ensure
    File.delete(path) if path && File.file?(path)
  end

  it "rejects malformed lines and unsupported sections" do
    path = "/tmp/cri-malformed-#{Process.pid}.toml"
    File.write(path, <<-TOML)
      name = "malformed"
      version = "0.1.0"
      abi = "cri.extension.v1"
      this is not toml
      [unknown]
      TOML

    manifest = Cri::Extensions::Manifest.load(path)
    manifest.valid?.should be_false
    manifest.errors.should contain("invalid manifest line: this is not toml")
    manifest.errors.should contain("unsupported manifest section: [unknown]")
  ensure
    File.delete(path) if path && File.file?(path)
  end

  it "allows declarative manifests without wasm" do
    path = "/tmp/cri-declarative-#{Process.pid}.toml"
    File.write(path, <<-TOML)
      name = "prompts"
      version = "0.1.0"
      abi = "cri.extension.v1"
      TOML

    Cri::Extensions::Manifest.load(path).valid?.should be_true
  ensure
    File.delete(path) if path && File.file?(path)
  end

  it "rejects wasm paths outside the package directory" do
    path = "/tmp/cri-traversal-#{Process.pid}.toml"
    File.write(path, <<-TOML)
      name = "traversal"
      version = "0.1.0"
      abi = "cri.extension.v1"
      wasm = "../plugin.wasm"

      [[tools]]
      name = "traversal.tool"
      TOML

    manifest = Cri::Extensions::Manifest.load(path)
    manifest.valid?.should be_false
    manifest.errors.should contain("wasm path must stay inside extension directory")
  ensure
    File.delete(path) if path && File.file?(path)
  end
end
