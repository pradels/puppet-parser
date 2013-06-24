class PuppetParser
  class Config
    def initialize
      @configuration = {
        "ignore_paths" => {
          "begin_with" => [],
          "contains"   => [],
        }
      }

      config_path = File.dirname(__FILE__) + "/../../conf/puppet-parser-conf.yaml"
      return if not File.exist?(config_path)

      File.open(config_path) do |yaml_file|
        configuration = YAML::load(yaml_file)
        @configuration = configuration if configuration != nil
      end     
    end

    def get
      @configuration
    end
  end
end
