$LOAD_PATH.unshift File.expand_path(File.join(File.dirname(__FILE__), "puppet"))
require 'puppet'
require 'puppet-parser/parser'
require 'puppet-parser/errors'
require 'puppet-parser/config'
require 'puppet-parser/version'

class PuppetParser
  def initialize(options)
    @config = PuppetParser::Config.new
    @parser = PuppetParser::Parser.new

    @options = options

    @output = {}
    @output["nodes"] = {} if @options[:nodes]
    @output["classes"] = {} if @options[:classes]
  end

  def parse(files)
    files.each do |file|
      @parser.parse_file(file)
    end

    @output["nodes"].merge!(@parser.nodes) if @options[:nodes]
    @output["classes"].merge!(@parser.classes) if @options[:classes]

    @output
  end

  def walk(paths)
    files_to_parse = []

    paths.each do |path|
      path = path.gsub(/\/$/, '')

      if File.directory?(path)
        files_to_parse += Dir.glob("#{path}/**/*.pp")
      elsif File.exists?(path)
        files_to_parse << path
      else
        # Don't report error if some file is not accessible. Just skip it.
        #raise PuppetParser::NoSuchPathError, path
      end
    end

    @config.get["ignore_paths"].each_pair do |type, list|
      next if list == nil

      case type
        when "begin_with"
          list.each do |begin_with|
            files_to_parse.reject! { |path| path.match /^#{begin_with}/}
          end
        else
          # Hmm this should result into warning.
      end
    end

    files_to_parse
  end

  def run(paths)
    files_to_parse = walk paths

    # Just print output in yaml format.
    puts parse(files_to_parse.to_a).to_yaml
  end
end
