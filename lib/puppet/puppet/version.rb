# The version method and constant are isolated in puppet/version.rb so that a
# simple `require 'puppet/version'` allows a rubygems gemspec or bundler
# Gemfile to get the Puppet version of the gem install.
#
# The version is programatically settable because we want to allow the
# Raketasks and such to set the version based on the output of `git describe`
#
module Puppet
  # Support reading the PE version data written by the installer and
  # annotating the version number displayed to inform the client.
  PEVersionFile = '/opt/puppet/pe_version'
  if File.readable? PEVersionFile then
    if File.zero? PEVersionFile then
      PEVersion = ""
    else
      PEVersion = " #{File.new(PEVersionFile).gets}"
    end
  else
    PEVersion = nil
  end

  if PEVersion then
    PUPPETVERSION = '2.7.26 (Puppet Enterprise%s)' % PEVersion.to_s.rstrip.chomp
  else
    PUPPETVERSION = '2.7.26'
  end

  def self.version
    @puppet_version || PUPPETVERSION
  end

  def self.version=(version)
    @puppet_version = version
  end
end
