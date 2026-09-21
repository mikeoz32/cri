module Cri
  # Canonicalizes filesystem paths before authorization and I/O. Lexical
  # prefix checks are insufficient because a path inside a trusted directory
  # can be a symlink to an object outside it.
  module PathSecurity
    def self.resolve_existing(path : String, base : String? = nil) : String?
      expanded = base ? File.expand_path(path, base.not_nil!) : File.expand_path(path)
      File.realpath(expanded)
    rescue
      nil
    end

    # Resolves a path that may not exist yet by canonicalizing its nearest
    # existing parent. If the final component already exists, realpath follows
    # it so callers can still enforce the final target's boundary.
    def self.resolve_for_create(path : String, base : String? = nil) : String?
      expanded = base ? File.expand_path(path, base.not_nil!) : File.expand_path(path)
      return resolve_existing(expanded) if File.exists?(expanded)

      parent = File.dirname(expanded)
      parent_real = File.realpath(parent)
      File.join(parent_real, File.basename(expanded))
    rescue
      nil
    end

    def self.within?(path : String, root : String, create : Bool = false) : Bool
      target = create ? resolve_for_create(path) : resolve_for_authorization(path)
      root_real = resolve_for_authorization(root)
      return false unless target && root_real

      target == root_real || target.starts_with?(root_real + File::SEPARATOR)
    end

    # Permission checks may run before a file is created. Preserve the
    # normalized lexical path for a missing target, but canonicalize every
    # existing target so an existing symlink cannot pass by spelling alone.
    def self.resolve_for_authorization(path : String, base : String? = nil) : String?
      expanded = base ? File.expand_path(path, base.not_nil!) : File.expand_path(path)
      resolve_existing(expanded) || expanded
    end

    def self.allowed?(path : String, roots : Array(String), create : Bool = false) : Bool
      roots.any? { |root| within?(path, root, create) }
    end
  end
end
