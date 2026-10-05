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
        reject_duplicate_names
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

      private def reject_duplicate_names
        manifests.each do |manifest|
          next if manifest.name.empty?
          next unless manifests.count { |candidate| candidate.name == manifest.name } > 1
          next if manifest.errors.any? { |error| error == "duplicate extension name: #{manifest.name}" }

          manifest.errors << "duplicate extension name: #{manifest.name}"
        end
      end
    end
  end
end
