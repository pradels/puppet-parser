require 'puppet/network/authstore'
require 'puppet/error'

module Puppet::Network

# this exception is thrown when a request is not authenticated
class AuthorizationError < Puppet::Error; end

# Define a set of rights and who has access to them.
# There are two types of rights:
#  * named rights (ie a common string)
#  * path based rights (which are matched on a longest prefix basis)
class Rights

  # We basically just proxy directly to our rights.  Each Right stores
  # its own auth abilities.
  [:allow, :deny, :restrict_method, :restrict_environment, :restrict_authenticated].each do |method|
    define_method(method) do |name, *args|
      if obj = self[name]
        obj.send(method, *args)
      else
        raise ArgumentError, "Unknown right '#{name}'"
      end
    end
  end

  # Check that name is allowed or not
  def allowed?(name, *args)
    !is_forbidden_and_why?(name, :node => args[0], :ip => args[1])
  end

  def is_request_forbidden_and_why?(indirection, method, key, params)
    methods_to_check = if method == :head
                         # :head is ok if either :find or :save is ok.
                         [:find, :save]
                       else
                         [method]
                       end
    authorization_failure_exceptions = methods_to_check.map do |method|
      is_forbidden_and_why?("/#{indirection}/#{key}", params.merge({:method => method}))
    end
    if authorization_failure_exceptions.include? nil
      # One of the methods we checked is ok, therefore this request is ok.
      nil
    else
      # Just need to return any of the failure exceptions.
      authorization_failure_exceptions.first
    end
  end

  def is_forbidden_and_why?(name, args = {})
    res = :nomatch
    right = @rights.find do |acl|
      found = false
      # an acl can return :dunno, which means "I'm not qualified to answer your question,
      # please ask someone else". This is used when for instance an acl matches, but not for the
      # current rest method, where we might think some other acl might be more specific.
      if match = acl.match?(name)
        args[:match] = match
        if (res = acl.allowed?(args[:node], args[:ip], args)) != :dunno
          # return early if we're allowed
          return nil if res
          # we matched, select this acl
          found = true
        end
      end
      found
    end

    # if we end here, then that means we either didn't match
    # or failed, in any case will throw an error to the outside world
    if name =~ /^\// or right
      # we're a patch ACL, let's fail
      msg = "#{(args[:node].nil? ? args[:ip] : "#{args[:node]}(#{args[:ip]})")} access to #{name} [#{args[:method]}]"

      msg += " authenticated " if args[:authenticated]

      error = AuthorizationError.new("Forbidden request: #{msg}")
      if right
        error.file = right.file
        error.line = right.line
      end
    else
      # there were no rights allowing/denying name
      # if name is not a path, let's throw
      raise ArgumentError, "Unknown namespace right '#{name}'"
    end
    error
  end

  def initialize
    @rights = []
  end

  def [](name)
    @rights.find { |acl| acl == name }
  end

  def include?(name)
    @rights.include?(name)
  end

  def each
    @rights.each { |r| yield r.name,r }
  end

  # Define a new right to which access can be provided.
  def newright(name, line=nil, file=nil)
    add_right( Right.new(name, line, file) )
  end

  private

  def add_right(right)
    if right.acl_type == :name and include?(right.key)
      raise ArgumentError, "Right '%s' already exists"
    end
    @rights << right
    sort_rights
    right
  end

  def sort_rights
    @rights.sort!
  end

  # Retrieve a right by name.
  def right(name)
    self[name]
  end

  # A right.
  class Right < Puppet::Network::AuthStore
    attr_accessor :name, :key, :acl_type
    attr_accessor :methods, :environment, :authentication
    attr_accessor :line, :file

    ALL = [:save, :destroy, :find, :search]

    Puppet::Util.logmethods(self, true)

    def initialize(name, line, file)
      @methods = []
      @environment = []
      @authentication = true # defaults to authenticated
      @name = name
      @line = line || 0
      @file = file

      case name
      when Symbol
        @acl_type = :name
        @key = name
      when /^\[(.+)\]$/
        @acl_type = :name
        @key = $1.intern if name.is_a?(String)
      when /^\//
        @acl_type = :regex
        @key = Regexp.new("^" + Regexp.escape(name))
        @methods = ALL
      when /^~/ # this is a regex
        @acl_type = :regex
        @name = name.gsub(/^~\s+/,'')
        @key = Regexp.new(@name)
        @methods = ALL
      else
        raise ArgumentError, "Unknown right type '#{name}'"
      end
      super()
    end

    def to_s
      "access[#{@name}]"
    end

    # There's no real check to do at this point
    def valid?
      true
    end

    def regex?
      acl_type == :regex
    end

    # does this right is allowed for this triplet?
    # if this right is too restrictive (ie we don't match this access method)
    # then return :dunno so that upper layers have a chance to try another right
    # tailored to the given method
    def allowed?(name, ip, args = {})
      return :dunno if acl_type == :regex and not @methods.include?(args[:method])
      return :dunno if acl_type == :regex and @environment.size > 0 and not @environment.include?(args[:environment])
      return :dunno if acl_type == :regex and not @authentication.nil? and args[:authenticated] != @authentication

      begin
        # make sure any capture are replaced if needed
        interpolate(args[:match]) if acl_type == :regex and args[:match]
        res = super(name,ip)
      ensure
        reset_interpolation if acl_type == :regex
      end
      res
    end

    # restrict this right to some method only
    def restrict_method(m)
      m = m.intern if m.is_a?(String)

      raise ArgumentError, "'#{m}' is not an allowed value for method directive" unless ALL.include?(m)

      # if we were allowing all methods, then starts from scratch
      if @methods === ALL
        @methods = []
      end

      raise ArgumentError, "'#{m}' is already in the '#{name}' ACL" if @methods.include?(m)

      @methods << m
    end

    def restrict_environment(env)
      env = Puppet::Node::Environment.new(env)
      raise ArgumentError, "'#{env}' is already in the '#{name}' ACL" if @environment.include?(env)

      @environment << env
    end

    def restrict_authenticated(authentication)
      case authentication
      when "yes", "on", "true", true
        authentication = true
      when "no", "off", "false", false
        authentication = false
      when "all","any", :all, :any
        authentication = nil
      else
        raise ArgumentError, "'#{name}' incorrect authenticated value: #{authentication}"
      end
      @authentication = authentication
    end

    def match?(key)
      # if we are a namespace compare directly
      return self.key == namespace_to_key(key) if acl_type == :name

      # otherwise match with the regex
      self.key.match(key)
    end

    def namespace_to_key(key)
      key = key.intern if key.is_a?(String)
      key
    end

    # this is where all the magic happens.
    # we're sorting the rights array with this scheme:
    #  * namespace rights are all in front
    #  * regex path rights are then all queued in file order
    def <=>(rhs)
      # move namespace rights at front
      return self.acl_type == :name ? -1 : 1 if self.acl_type != rhs.acl_type

      # sort by creation order (ie first match appearing in the file will win)
      # that is don't sort, in which case the sort algorithm will order in the
      # natural array order (ie the creation order)
      0
    end

    def ==(name)
      return(acl_type == :name ? self.key == namespace_to_key(name) : self.name == name.gsub(/^~\s+/,''))
    end

  end

end
end
