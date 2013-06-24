class PuppetParser
  class PuppetParserError < StandardError
    def initialize(message)
      @message = message
    end
  end

  class NoSuchPathError < PuppetParserError
    def message
      "No such file to parse (#{@message})."
    end
  end

  class ParseError < PuppetParserError
    def message
      "Error while parsing: #{@message}"
    end
  end

end
