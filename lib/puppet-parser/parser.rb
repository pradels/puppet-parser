require 'puppet'
require 'puppet/parser/ast/branch'

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
      classes_array = []
      classes = @parser.environment.known_resource_types.hostclasses

      classes.each_pair do |class_name, klass|
        next if class_name == ""

        arguments = {}
        klass.arguments.each do |l, r|
          if r
            if r.class.to_s == "Puppet::Parser::AST::String"
              arguments[l] = "'" + r.value + "'"
            else
              arguments[l] = r.value
            end
          else
            arguments[l] = ""
          end
        end

        # Prepare new class hash.
        class_array = []

        class_array << {'arguments' => arguments}

        classes_array << {
            class_name => class_array
        }

        next if klass.code == nil

        # Walk through class definition.
        klass.code.each do |ast|
          handle_statement(ast, class_array)
        end
      end

      classes_array
    end

    def handle_statement(ast, class_array)
      case ast.class.to_s
        when "Puppet::Parser::AST::VarDef"

          variables = []

          if class_array.length > 0 and class_array[-1]["variables"]
            variables = class_array[-1]["variables"]
          else
            class_array << {"variables" => variables}
          end

          handle_vardef(variables, ast)

        when "Puppet::Parser::AST::Resource"

          resources = []

          if class_array.length > 0 and class_array[-1]["resources"]
            resources = class_array[-1]["resources"]
          else
            class_array << {"resources" => resources}
          end

          resource = []

          if resources.length > 0 and resources[-1][ast.type] != nil
            resource = resources[-1][ast.type]
          else
            resources << { ast.type => resource}
          end

          handle_resource(resource, ast)
        when "Puppet::Parser::AST::ResourceOverride"

          resource_overrides = {}

          if class_array.length > 0 and class_array[-1]["resource_overrides"]
            resource_overrides = class_array[-1]["resource_overrides"]
          else
            class_array << {"resource_overrides" => resource_overrides}
          end

          handle_resource_override(resource_overrides, ast)
        when "Puppet::Parser::AST::ResourceDefaults"

          resource_defaults = {}

          if class_array.length > 0 and class_array[-1]["resource_defaults"]
            resource_defaults= class_array[-1]["resource_defaults"]
          else
            class_array << {"resource_defaults" => resource_defaults}
          end

          handle_resource_defaults(resource_defaults, ast)
        when "Puppet::Parser::AST::CaseStatement"
          caseStatement = {}


          class_array << {"case" => caseStatement}
          caseStatement[handle_concat(ast.test).to_s] = {}

          handle_case(caseStatement[handle_concat(ast.test).to_s], ast)
        when "Puppet::Parser::AST::IfStatement"

          ifStatement = {}
          block = {"if" => ifStatement}
          class_array << block

          test = handle_branch(ast.test)

          if ifStatement[test] == nil
            ifStatement[test] = []
          end

          handle_if(ifStatement[test], ast)

          if defined? ast.else and defined? ast.else.statements and ast.else.statements.children.length > 0
            else_statement = []
            block['else'] = else_statement
            ast.else.statements.each do |statement|
              handle_statement(statement, else_statement)
            end

          end

        when "Puppet::Parser::AST::Function"

          functions = []
          function_statement = {"functions" => functions}

          if class_array.length > 0 and class_array[-1][:functions]
            functions = class_array[-1][:functions]
          else
            class_array << function_statement
          end

          handle_function(functions, ast)
      end
    end

    def nodes
      nodes_hash = {}

      nodes = @parser.environment.known_resource_types.nodes
      nodes.each_pair do |name, node|

        # Prepare new node hash.
        nodes_hash[name] = []

        # Walk through node definition.
        node.code.each do |ast|
          handle_statement(ast, nodes_hash[name])
        end
      end

      nodes_hash
    end

    # Just stripe away " and \" from string.
    def strip_quotes(string)
      string = string.chomp('\"').reverse.chomp('\"').reverse
      string.chomp('"').reverse.chomp('"').reverse
    end

    def handle_vardef(vardefs, ast_node)
      if ast_node.value == nil
        rvalue = nil
      else
        rvalue = handle_concat(ast_node.value)
      end
      vardefs << { ast_node.name.to_s => handle_resource_param_value(rvalue) }
    end

    # Deals with inline variables.
    def handle_concat(concat)
      if concat.class.to_s == 'Puppet::Parser::AST::Concat'
        ret_val = String.new("")
        concat.value.each do |value|
          if value.to_s[0].eql?("$")
            ret_val.concat('#{' + value.to_s + '}')
          else
            ret_val.concat(value.to_s)
          end
        end
        ret_val.gsub!('"', '')
      else
        return concat
      end
    end

    def handle_case(hash, ast_node)

      if ast_node.options == nil
        rvalue = nil
      else
        delimiter = ", "
        ast_node.options.each do |option|

          # Handle multiple cases for one block
          cases = String.new('')
          option.value.each do |opt|
            cases << handle_concat(opt).to_s
            cases << delimiter
          end

          # Remove the last delimiter
          if cases.length >= delimiter.length
            cases = cases[0..cases.length - delimiter.length - 1]
          end

          hash[cases] = []

          option.statements.each do |each_opt|
            handle_statement(each_opt, hash[cases])
          end
        end
      end
    end

    def handle_resource(resource, ast_node)
      ast_node.instances.each do |instance|
        if instance.title.class.to_s == "Puppet::Parser::AST::ASTArray"
          instance.title.each do |ele|
            handle_resource_helper(resource, ele, instance)
          end
        else
          handle_resource_helper(resource, instance.title, instance)
        end
      end
    end

    def handle_resource_helper(resource, title, instance)
      instance_title = strip_quotes(handle_concat(title).to_s)

      resource_attr = {}
      resource << { instance_title => resource_attr}

      # Fill in each parameter.
      instance.parameters.each do |parameter|
        resource_attr[parameter.param] = handle_resource_param_value(handle_concat(parameter.value))
      end
    end

    def handle_resource_override(hash, ast_node)
      hash[ast_node.object.to_s] = {}

      ast_node.parameters.each do |parameter|
        hash[ast_node.object.to_s][parameter.param.to_s] =
            handle_resource_param_value(handle_concat(parameter.value))
      end
    end

    def handle_resource_defaults(hash, ast_node)
      hash[ast_node.type.to_s] = {}

      ast_node.parameters.each do |parameter|
        hash[ast_node.type.to_s][parameter.param.to_s] =
            handle_resource_param_value(handle_concat(parameter.value))
      end
    end

    def handle_function(functions, ast_node)
      return if ast_node.name != "include"

      includes = []
      function = { "include" => includes }

      ast_node.arguments.each do |argument|
        includes << strip_quotes(handle_concat(argument).to_s)
      end

      functions << function
    end

    def handle_resource_param_value(value)

      case value.class.to_s
        when "Puppet::Parser::AST::ASTArray"
          ret_value = []
          value.each do |item|
              ret_value << strip_quotes(handle_concat(item).to_s)
          end
        else
            ret_value = strip_quotes(handle_concat(value).to_s)
      end

      ret_value
    end

    def handle_branch(condition)
      ret_value = ""

      if condition.class < Puppet::Parser::AST::Branch
        while condition.class < Puppet::Parser::AST::Branch
          ret_value = " #{condition.operator.to_s} #{condition.rval.to_s}#{ret_value}"
          if condition.lval.class < Puppet::Parser::AST::Branch
            condition = condition.lval
          else
            ret_value = condition.lval.to_s + ret_value
            break
          end
        end
      end

      if ret_value == ""
        ret_value = condition.to_s
      end

      ret_value
    end

    def handle_if(array, if_ast)
      if_ast.statements.each do |ast|
        handle_statement(ast, array)
      end
    end
  end
end
