class PuppetParser
  class Parser

    def initialize
      @parser = Puppet::Parser::Parser.new('puppet-parser')
    end

    def parse_file(filename)
      if not File.exists? filename
        raise PuppetParser::NoSuchPathError, filename
      end

      begin
        @parser.import(File.expand_path(filename))
      rescue Puppet::ParseError => e
        raise PuppetParser::ParseError, e.message
      end
    end

    def classes
      classes_hash = {}
      classes = @parser.environment.known_resource_types.hostclasses

      classes.each_pair do |class_name, klass|
        next if class_name == ""

        # Prepare new class hash.
        classes_hash[class_name] = initialize_class_hash
        classes_hash[class_name]["parent"] = klass.parent.to_s

        next if klass.code == nil

        # Walk through class definition.
        klass.code.each do |ast|
          #puts ast.class.to_s
          case ast.class.to_s
            when "Puppet::Parser::AST::VarDef"
              handle_vardef(classes_hash[class_name]["variables"], ast)
            when "Puppet::Parser::AST::Resource"
              if classes_hash[class_name]["resources"][ast.type] == nil
                classes_hash[class_name]["resources"][ast.type] = {}
              end

              handle_resource(classes_hash[class_name]["resources"][ast.type], ast)
            when "Puppet::Parser::AST::ResourceOverride"
              handle_resource_override(classes_hash[class_name]["resource_overrides"], ast)
            else
              next
          end
        end
      end

      classes_hash
    end

    def initialize_class_hash
      {
        "variables"          => {},
        "resources"          => {},
        "resource_overrides" => {},
        "parent"             => nil,

        # Empty for now.
        "resource_defaults"  => {},
        "includes"           => {},
      }
    end


    # Return a hash describeing nodes parsed.
    # 
    # {
    #   :name => {
    #     :variables => {
    #       :varname => value,
    #       :varname => value,
    #     }
    #
    #     :resources => {
    #       :type => {
    #         :name => {
    #           :parameter => value,
    #           :parameter => value,
    #         },
    #         :name => {
    #           :parameter => value,
    #           :parameter => value,
    #         },
    #       }
    #     }
    #
    #     :includes => {
    #       :name => {},
    #       :name => {},
    #     }
    #   }
    # }

    def nodes
      nodes_hash = {}

      nodes = @parser.environment.known_resource_types.nodes
      nodes.each_pair do |name, node|

        # Prepare new node hash.
        nodes_hash[name] = initialize_node_hash

        # Walk through node definition.
        node.code.each do |ast|
          case ast.class.to_s
            when "Puppet::Parser::AST::VarDef"
              handle_vardef(nodes_hash[name]["variables"], ast)
            when "Puppet::Parser::AST::Resource"
              if ast.type == "class"
                resource_type = nodes_hash[name]["includes"]
              else
                if not nodes_hash[name]["resources"][ast.type]
                  nodes_hash[name]["resources"][ast.type] = {}
                end
                resource_type = nodes_hash[name]["resources"][ast.type]
              end

              handle_resource(resource_type, ast)
            when "Puppet::Parser::AST::Function"
              handle_function(nodes_hash[name]["includes"], ast)
            else
              # Just skip unknown AST types.
              next
          end
        end
      end

      nodes_hash
    end

    def initialize_node_hash
      {
        "variables" => {},
        "resources" => {},
        "includes"  => {},
      }
    end

    # Just stripe away " and \" from string.
    def strip_quotes(string)
      string = string.chomp('\"').reverse.chomp('\"').reverse
      string.chomp('"').reverse.chomp('"').reverse
    end

    def handle_vardef(hash, ast_node)
      if ast_node.value == nil
        rvalue = nil
      else
        rvalue = ast_node.value.to_s
      end
      hash[ast_node.name.to_s] = handle_resource_param_value(rvalue)
    end

    def handle_resource(hash, ast_node)
      ast_node.instances.each do |instance|
        instance_title = strip_quotes(instance.title.to_s)
        hash[instance_title] = {}

        # Fill in each parameter.
        instance.parameters.each do |parameter|
          hash[instance_title][parameter.param.to_s] = handle_resource_param_value(parameter.value)
        end
      end
    end

    def handle_resource_override(hash, ast_node)
      hash[ast_node.object.to_s] = {}

      ast_node.parameters.each do |parameter|
        hash[ast_node.object.to_s][parameter.param.to_s] = 
          handle_resource_param_value(parameter.value)
      end
    end

    def handle_function(hash, ast_node)
      return if ast_node.name != "include"

      argument_name = strip_quotes(ast_node.arguments[0].to_s)
      hash[argument_name] = {}
    end

    def handle_resource_param_value(value)
      ret_value = nil

      case value.class.to_s
        when "Puppet::Parser::AST::ASTArray"
          ret_value = []
          value.each do |item|
            ret_value << strip_quotes(item.to_s)
          end
        else
          ret_value = strip_quotes(value.to_s)
      end

      ret_value
    end
  end
end
