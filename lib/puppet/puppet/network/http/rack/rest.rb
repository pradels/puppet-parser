require 'puppet/network/http/handler'
require 'puppet/network/http/rack/httphandler'

class Puppet::Network::HTTP::RackREST < Puppet::Network::HTTP::RackHttpHandler

  include Puppet::Network::HTTP::Handler

  HEADER_ACCEPT = 'HTTP_ACCEPT'.freeze
  ContentType = 'Content-Type'.freeze

  CHUNK_SIZE = 8192

  class RackFile
    def initialize(file)
      @file = file
    end

    def each
      while chunk = @file.read(CHUNK_SIZE)
        yield chunk
      end
    end

    def close
      @file.close
    end
  end

  def initialize(args={})
    super()
    initialize_for_puppet(args)
  end

  def set_content_type(response, format)
    response[ContentType] = format_to_mime(format)
  end

  # produce the body of the response
  def set_response(response, result, status = 200)
    response.status = status
    unless result.is_a?(File)
      response.write result
    else
      response["Content-Length"] = result.stat.size.to_s
      response.body = RackFile.new(result)
    end
  end

  # Retrieve the accept header from the http request.
  def accept_header(request)
    request.env[HEADER_ACCEPT]
  end

  # Retrieve the accept header from the http request.
  def content_type_header(request)
    request.content_type
  end

  # Return which HTTP verb was used in this request.
  def http_method(request)
    request.request_method
  end

  # Return the query params for this request.
  def params(request)
    result = decode_params(request.params)
    result.merge(extract_client_info(request))
  end

  # what path was requested? (this is, without any query parameters)
  def path(request)
    request.path
  end

  # return the request body
  def body(request)
    request.body.read
  end

  # Passenger freaks out if we finish handling the request without reading any
  # part of the body, so make sure we have.
  def cleanup(request)
    request.body.read(1)
    nil
  end

  def extract_client_info(request)
    result = {}
    result[:ip] = request.ip

    # if we find SSL info in the headers, use them to get a hostname.
    # try this with :ssl_client_header, which defaults should work for
    # Apache with StdEnvVars.
    if dn = request.env[Puppet[:ssl_client_header]] and dn_matchdata = dn.match(/^.*?CN\s*=\s*(.*)/)
      result[:node] = dn_matchdata[1].to_str
      result[:authenticated] = (request.env[Puppet[:ssl_client_verify_header]] == 'SUCCESS')
    else
      result[:node] = resolve_node(result)
      result[:authenticated] = false
    end

    result
  end

end
