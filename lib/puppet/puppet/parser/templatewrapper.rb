# A simple wrapper for templates, so they don't have full access to
# the scope objects.
require 'puppet/parser/files'
require 'erb'

class Puppet::Parser::TemplateWrapper
  attr_writer :scope
  include Puppet::Util
  Puppet::Util.logmethods(self)

  def initialize(scope)
    @__scope__ = scope
  end

  def file
    @__file__
  end

  def scope
    @__scope__
  end

  def script_line
    # find which line in the template (if any) we were called from
    (caller.find { |l| l =~ /#{@__file__}:/ }||"")[/:(\d+):/,1]
  end

  # Should return true if a variable is defined, false if it is not
  def has_variable?(name)
    scope.lookupvar(name.to_s, :file => @__file__, :line => script_line) != :undefined
  end

  # Allow templates to access the defined classes
  def classes
    scope.catalog.classes
  end

  # Allow templates to access the tags defined in the current scope
  def tags
    scope.tags
  end

  # Allow templates to access the all the defined tags
  def all_tags
    scope.catalog.tags
  end

  # Ruby treats variables like methods, so we used to expose variables
  # within scope to the ERB code via method_missing.  As per RedMine #1427,
  # though, this means that conflicts between methods in our inheritance
  # tree (Kernel#fork) and variable names (fork => "yes/no") could arise.
  #
  # Worse, /new/ conflicts could pop up when a new kernel or object method
  # was added to Ruby, causing templates to suddenly fail mysteriously when
  # Ruby was upgraded.
  #
  # To ensure that legacy templates using unqualified names work we retain
  # the missing_method definition here until we declare the syntax finally
  # dead.
  def method_missing(name, *args)
    value = scope.lookupvar(name.to_s,:file => @__file__,:line => script_line)
    if value != :undefined
      return value
    else
      # Just throw an error immediately, instead of searching for
      # other missingmethod things or whatever.
      raise Puppet::ParseError.new("Could not find value for '#{name}'", @__file__, script_line)
    end
  end

  def file=(filename)
    unless @__file__ = Puppet::Parser::Files.find_template(filename, scope.compiler.environment.to_s)
      raise Puppet::ParseError, "Could not find template '#{filename}'"
    end

    # We'll only ever not have a parser in testing, but, eh.
    scope.known_resource_types.watch_file(@__file__)
  end

  def result(string = nil)
    if string
      template_source = "inline template"
    else
      string = File.read(@__file__)
      template_source = @__file__
    end

    # Expose all the variables in our scope as instance variables of the
    # current object, making it possible to access them without conflict
    # to the regular methods.
    benchmark(:debug, "Bound template variables for #{template_source}") do
      scope.to_hash.each do |name, value|
        if name.kind_of?(String)
          realname = name.gsub(/[^\w]/, "_")
        else
          realname = name
        end
        instance_variable_set("@#{realname}", value)
      end
    end

    result = nil
    benchmark(:debug, "Interpolated template #{template_source}") do
      template = ERB.new(string, 0, "-")
      template.filename = @__file__
      result = template.result(binding)
    end

    result
  end

  def to_s
    "template[#{(@__file__ ? @__file__ : "inline")}]"
  end
end
