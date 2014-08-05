require 'puppet/version'

# Try to load rubygems.  Hey rubygems, I hate you.
begin
  require 'rubygems'
rescue LoadError
end

# see the bottom of the file for further inclusions
# Also see the new Vendor support - towards the end

require 'singleton'
require 'facter'
require 'puppet/error'
require 'puppet/util'
require 'puppet/util/autoload'
require 'puppet/util/settings'
require 'puppet/util/feature'
require 'puppet/util/suidmanager'
require 'puppet/util/run_mode'

#------------------------------------------------------------
# the top-level module
#
# all this really does is dictate how the whole system behaves, through
# preferences for things like debugging
#
# it's also a place to find top-level commands like 'debug'

module Puppet
  require 'puppet/file_system'

  class << self
    include Puppet::Util
    attr_reader :features
    attr_writer :name
  end

  # the hash that determines how our system behaves
  @@settings = Puppet::Util::Settings.new

  # The services running in this process.
  @services ||= []

  require 'puppet/util/logging'

  extend Puppet::Util::Logging

  # The feature collection
  @features = Puppet::Util::Feature.new('puppet/feature')

  # Load the base features.
  require 'puppet/feature/base'

  # Store a new default value.
  def self.setdefaults(section, hash)
    @@settings.setdefaults(section, hash)
  end

  # configuration parameter access and stuff
  def self.[](param)
    if param == :debug
      return Puppet::Util::Log.level == :debug
    else
      return @@settings[param]
    end
  end

  # configuration parameter access and stuff
  def self.[]=(param,value)
    @@settings[param] = value
  end

  def self.clear
    @@settings.clear
  end

  def self.debug=(value)
    if value
      Puppet::Util::Log.level=(:debug)
    else
      Puppet::Util::Log.level=(:notice)
    end
  end

  def self.settings
    @@settings
  end

  def self.run_mode
    $puppet_application_mode || Puppet::Util::RunMode[:user]
  end

  def self.application_name
    $puppet_application_name ||= "apply"
  end

  # Load all of the configuration parameters.
  require 'puppet/defaults'

  def self.genmanifest
    if Puppet[:genmanifest]
      puts Puppet.settings.to_manifest
      exit(0)
    end
  end

  # Parse the config file for this process.
  def self.parse_config
    Puppet.settings.parse
  end

  # Create a new type.  Just proxy to the Type class.  The mirroring query
  # code was deprecated in 2008, but this is still in heavy use.  I suppose
  # this can count as a soft deprecation for the next dev. --daniel 2011-04-12
  def self.newtype(name, options = {}, &block)
    Puppet::Type.newtype(name, options, &block)
  end

  # Load vendored (setup paths, and load what is needed upfront).
  # See the Vendor class for how to add additional vendored gems/code
  require "puppet/vendor"
  Puppet::Vendor.load_vendored

  # Set default for YAML.load to unsafe so we don't affect programs
  # requiring puppet -- in puppet we will call safe explicitly
  SafeYAML::OPTIONS[:default_mode] = :unsafe
end

require 'puppet/type'
require 'puppet/parser'
require 'puppet/resource'
require 'puppet/network'
require 'puppet/ssl'
require 'puppet/module'
require 'puppet/util/storage'
require 'puppet/status'
require 'puppet/file_bucket/file'
