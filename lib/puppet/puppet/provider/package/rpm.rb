require 'puppet/provider/package'

# RPM packaging.  Should work anywhere that has rpm installed.
Puppet::Type.type(:package).provide :rpm, :source => :rpm, :parent => Puppet::Provider::Package do
  desc "RPM packaging support; should work anywhere with a working `rpm`
    binary."

  has_feature :versionable

  # The query format by which we identify installed packages
  NEVRAFORMAT = "%{NAME} %|EPOCH?{%{EPOCH}}:{0}| %{VERSION} %{RELEASE} %{ARCH}"
  NEVRA_FIELDS = [:name, :epoch, :version, :release, :arch]

  commands :rpm => "rpm"

  if command('rpm')
    confine :true => begin
      rpm('--version')
      rescue Puppet::ExecutionFailure
        false
      else
        true
      end
  end

  def self.current_version
    return @current_version unless @current_version.nil?
    output = rpm "--version"
    @current_version = output.gsub('RPM version ', '').strip
  end

  # rpm < 4.1 don't support --nosignature
  def self.nosignature
    '--nosignature' unless Puppet::Util::Package.versioncmp(current_version, '4.1') < 0
  end

  # rpm < 4.0.2 don't support --nodigest
  def self.nodigest
    '--nodigest' unless Puppet::Util::Package.versioncmp(current_version, '4.0.2') < 0
  end

  def self.instances
    packages = []

    # list out all of the packages
    begin
      execpipe("#{command(:rpm)} -qa #{nosignature} #{nodigest} --qf '#{NEVRAFORMAT}\n'") { |process|
        # now turn each returned line into a package object
        process.each_line { |line|
          hash = nevra_to_hash(line)
          packages << new(hash)
        }
      }
    rescue Puppet::ExecutionFailure
      raise Puppet::Error, "Failed to list packages"
    end

    packages
  end

  # Find the fully versioned package name and the version alone. Returns
  # a hash with entries :instance => fully versioned package name, and
  # :ensure => version-release
  def query
    #NOTE: Prior to a fix for issue 1243, this method potentially returned a cached value
    #IF YOU CALL THIS METHOD, IT WILL CALL RPM
    #Use get(:property) to check if cached values are available
    cmd = ["-q", @resource[:name], "#{self.class.nosignature}", "#{self.class.nodigest}", "--qf", "#{NEVRAFORMAT}\n"]

    begin
      output = rpm(*cmd)
    rescue Puppet::ExecutionFailure
      return nil
    end

    # FIXME: We could actually be getting back multiple packages
    # for multilib
    @property_hash.update(self.class.nevra_to_hash(output))

    @property_hash.dup
  end

  # Here we just retrieve the version from the file specified in the source.
  def latest
    unless source = @resource[:source]
      @resource.fail "RPMs must specify a package source"
    end

    cmd = [command(:rpm), "-q", "--qf", "#{NEVRAFORMAT}\n", "-p", "#{@resource[:source]}"]
    h = self.class.nevra_to_hash(execfail(cmd, Puppet::Error))
    h[:ensure]
  end

  def install
    source = nil
    unless source = @resource[:source]
      @resource.fail "RPMs must specify a package source"
    end
    # RPM gets pissy if you try to install an already
    # installed package
    if @resource.should(:ensure) == @property_hash[:ensure] or
      @resource.should(:ensure) == :latest && @property_hash[:ensure] == latest
      return
    end

    flag = "-i"
    flag = ["-U", "--oldpackage"] if @property_hash[:ensure] and @property_hash[:ensure] != :absent

    rpm flag, source
  end

  def uninstall
    query if get(:arch) == :absent
    nvr = "#{get(:name)}-#{get(:version)}-#{get(:release)}"
    arch = ".#{get(:arch)}"
    # If they specified an arch in the manifest, erase that Otherwise,
    # erase the arch we got back from the query. If multiple arches are
    # installed and only the package name is specified (without the
    # arch), this will uninstall all of them on successive runs of the
    # client, one after the other

    # version of RPM prior to 4.2.1 can't accept the architecture as
    # part of the package name.
    unless Puppet::Util::Package.versioncmp(self.class.current_version, '4.2.1') < 0
      if @resource[:name][-arch.size, arch.size] == arch
        nvr += arch
      else
        nvr += ".#{get(:arch)}"
      end
    end
    rpm "-e", nvr
  end

  def update
    self.install
  end

  def self.nevra_to_hash(line)
    line.chomp!
    hash = {}
    NEVRA_FIELDS.zip(line.split) { |f, v| hash[f] = v }
    hash[:provider] = self.name
    hash[:ensure] = "#{hash[:version]}-#{hash[:release]}"
    hash
  end
end
