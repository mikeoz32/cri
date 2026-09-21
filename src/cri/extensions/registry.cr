module Cri
  module Extensions
    class Registry
      getter manifests = [] of Manifest
      getter search_dirs : Array(String)

      def initialize(@search_dirs : Array(String))
      end

      def discover
        @manifests.clear
        search_dirs.each do |dir|
          next unless Dir.exists?(dir)
          Dir.glob(File.join(dir, "*", "extension.toml")).sort.each do |path|
            @manifests << Manifest.load(path)
          end
        end
        self
      end

      def valid : Array(Manifest)
        manifests.select(&.valid?)
      end

      def enabled(policy : Permissions::GrantPolicy) : Array(Manifest)
        valid.select { |manifest| policy.enabled?(manifest.name) }
      end

      def find(name : String) : Manifest?
        manifests.find { |m| m.name == name }
      end
    end
  end
end
