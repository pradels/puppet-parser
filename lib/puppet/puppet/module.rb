require 'puppet/util/logging'
require 'semver'
require 'puppet/module_tool/applications'

# Support for modules
class Puppet::Module
  class Error < Puppet::Error; end
  class MissingModule < Error; end
  class IncompatibleModule < Error; end
  class UnsupportedPlatform < Error; end
  class IncompatiblePlatform < Error; end
  class MissingMetadata < Error; end
  class InvalidName < Error; end
  class InvalidFilePattern < Error; end

  include Puppet::Util::Logging

  TEMPLATES = "templates"
  FILES = "files"
  MANIFESTS = "manifests"
  PLUGINS = "plugins"

  FILETYPES = [MANIFESTS, FILES, TEMPLATES, PLUGINS]

  # Find and return the +module+ that +path+ belongs to. If +path+ is
  # absolute, or if there is no module whose name is the first component
  # of +path+, return +nil+
  def self.find(modname, environment = nil)
    return nil unless modname
    Puppet::Node::Environment.new(environment).module(modname)
  end

  attr_reader :name, :environment
  attr_writer :environment

  attr_accessor :dependencies, :forge_name
  attr_accessor :source, :author, :version, :license, :puppetversion, :summary, :description, :project_page

  def has_metadata?
    return false unless metadata_file

    return false unless FileTest.exist?(metadata_file)

    metadata = PSON.parse File.read(metadata_file)


    return metadata.is_a?(Hash) && !metadata.keys.empty?
  end

  def initialize(name, options = {})
    @name = name
    @path = options[:path]

    assert_validity

    if options[:environment].is_a?(Puppet::Node::Environment)
      @environment = options[:environment]
    else
      @environment = Puppet::Node::Environment.new(options[:environment])
    end

    load_metadata if has_metadata?

    validate_puppet_version
  end

  FILETYPES.each do |type|
    # A boolean method to let external callers determine if
    # we have files of a given type.
    define_method(type +'?') do
      return false unless path
      return false unless FileTest.exist?(subpath(type))
      return true
    end

    # A method for returning a given file of a given type.
    # e.g., file = mod.manifest("my/manifest.pp")
    #
    # If the file name is nil, then the base directory for the
    # file type is passed; this is used for fileserving.
    define_method(type.to_s.sub(/s$/, '')) do |file|
      return nil unless path

      # If 'file' is nil then they're asking for the base path.
      # This is used for things like fileserving.
      if file
        full_path = File.join(subpath(type), file)
      else
        full_path = subpath(type)
      end

      return nil unless FileTest.exist?(full_path)
      return full_path
    end
  end

  def exist?
    ! path.nil?
  end

  # Find the first 'files' directory.  This is used by the XMLRPC fileserver.
  def file_directory
    subpath("files")
  end

  def license_file
    return @license_file if defined?(@license_file)

    return @license_file = nil unless path
    @license_file = File.join(path, "License")
  end

  def load_metadata
    data = PSON.parse File.read(metadata_file)
    @forge_name = data['name'].gsub('-', '/') if data['name']

    [:source, :author, :version, :license, :puppetversion, :dependencies].each do |attr|
      unless value = data[attr.to_s]
        unless attr == :puppetversion
          raise MissingMetadata, "No #{attr} module metadata provided for #{self.name}"
        end
      end

      # NOTICE: The fallback to `versionRequirement` is something we'd like to
      # not have to support, but we have a reasonable number of releases that
      # don't use `version_requirement`. When we can deprecate this, we should.
      if attr == :dependencies
        value.tap do |dependencies|
          dependencies.each do |dep|
            dep['version_requirement'] ||= dep['versionRequirement'] || '>= 0.0.0'
          end
        end
      end

      send(attr.to_s + "=", value)
    end
  end

  # Return the list of manifests matching the given glob pattern,
  # defaulting to 'init.{pp,rb}' for empty modules.
  def match_manifests(rest)
    if rest
      wanted_manifests = wanted_manifests_from(rest)
      searched_manifests = wanted_manifests.glob.reject { |f| FileTest.directory?(f) }
    else
      searched_manifests = []
    end

    # (#4220) Always ensure init.pp in case class is defined there.
    init_manifests = [manifest("init.pp"), manifest("init.rb")].compact
    init_manifests + searched_manifests
  end

  def metadata_file
    return @metadata_file if defined?(@metadata_file)

    return @metadata_file = nil unless path
    @metadata_file = File.join(path, "metadata.json")
  end

  # Find this module in the modulepath.
  def path
    @path ||= environment.modulepath.collect { |path| File.join(path, name) }.find { |d| FileTest.directory?(d) }
  end

  def modulepath
    File.dirname(path) if path
  end

  # Find all plugin directories.  This is used by the Plugins fileserving mount.
  def plugin_directory
    subpath("plugins")
  end

  def supports(name, version = nil)
    @supports ||= []
    @supports << [name, version]
  end

  def to_s
    result = "Module #{name}"
    result += "(#{path})" if path
    result
  end

  def dependencies_as_modules
    dependent_modules = []
    dependencies and dependencies.each do |dep|
      author, dep_name = dep["name"].split('/')
      found_module = environment.module(dep_name)
      dependent_modules << found_module if found_module
    end

    dependent_modules
  end

  def required_by
    environment.module_requirements[self.forge_name] || {}
  end

  def has_local_changes?
    changes = Puppet::ModuleTool::Applications::Checksummer.run(path)
    !changes.empty?
  end

  def local_changes
    Puppet::ModuleTool::Applications::Checksummer.run(path)
  end

  # Identify and mark unmet dependencies.  A dependency will be marked unmet
  # for the following reasons:
  #
  #   * not installed and is thus considered missing
  #   * installed and does not meet the version requirements for this module
  #   * installed and doesn't use semantic versioning
  #
  # Returns a list of hashes representing the details of an unmet dependency.
  #
  # Example:
  #
  #   [
  #     {
  #       :reason => :missing,
  #       :name   => 'puppetlabs-mysql',
  #       :version_constraint => 'v0.0.1',
  #       :mod_details => {
  #         :installed_version => '0.0.1'
  #       }
  #       :parent => {
  #         :name    => 'puppetlabs-bacula',
  #         :version => 'v1.0.0'
  #       }
  #     }
  #   ]
  #
  def unmet_dependencies
    unmet_dependencies = []
    return unmet_dependencies unless dependencies

    dependencies.each do |dependency|
      forge_name = dependency['name']
      version_string = dependency['version_requirement'] || '>= 0.0.0'

      dep_mod = begin
        environment.module_by_forge_name(forge_name)
      rescue => e
        nil
      end

      error_details = {
        :name => forge_name,
        :version_constraint => version_string.gsub(/^(?=\d)/, "v"),
        :parent => {
          :name => self.forge_name,
          :version => self.version.gsub(/^(?=\d)/, "v")
        },
        :mod_details => {
          :installed_version => dep_mod.nil? ? nil : dep_mod.version
        }
      }

      unless dep_mod
        error_details[:reason] = :missing
        unmet_dependencies << error_details
        next
      end

      if version_string
        begin
          required_version_semver_range = SemVer[version_string]
          actual_version_semver = SemVer.new(dep_mod.version)
        rescue ArgumentError
          error_details[:reason] = :non_semantic_version
          unmet_dependencies << error_details
          next
        end

        unless required_version_semver_range.include? actual_version_semver
          error_details[:reason] = :version_mismatch
          unmet_dependencies << error_details
          next
        end
      end
    end

    unmet_dependencies
  end

  def validate_puppet_version
    return unless puppetversion and puppetversion != Puppet.version
    raise IncompatibleModule, "Module #{self.name} is only compatible with Puppet version #{puppetversion}, not #{Puppet.version}"
  end

  private

  def wanted_manifests_from(pattern)
    begin
      extended = File.extname(pattern).empty? ? "#{pattern}.{pp,rb}" : pattern
      relative_pattern = Puppet::FileSystem::PathPattern.relative(extended)
    rescue Puppet::FileSystem::PathPattern::InvalidPattern => error
      raise Puppet::Module::InvalidFilePattern.new(
        "The pattern \"#{pattern}\" to find manifests in the module \"#{name}\" " +
        "is invalid and potentially unsafe.", error)
    end

    absolute_path_to_manifests = Puppet::FileSystem::PathPattern.absolute(subpath(MANIFESTS))
    relative_pattern.prefix_with(absolute_path_to_manifests)
  end

  def subpath(type)
    return File.join(path, type) unless type.to_s == "plugins"

    backward_compatible_plugins_dir
  end

  def backward_compatible_plugins_dir
    if dir = File.join(path, "plugins") and FileTest.exist?(dir)
      Puppet.warning "using the deprecated 'plugins' directory for ruby extensions; please move to 'lib'"
      return dir
    else
      return File.join(path, "lib")
    end
  end

  def assert_validity
    raise InvalidName, "Invalid module name #{name}; module names must be alphanumeric (plus '-'), not '#{name}'" unless name =~ /^[-\w]+$/
  end

  def ==(other)
    self.name == other.name &&
    self.version == other.version &&
    self.path == other.path &&
    self.environment == other.environment
  end
end
