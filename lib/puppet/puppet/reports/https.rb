require 'puppet'
require 'net/http'
require 'net/https'
require 'uri'

Puppet::Reports.register_report(:https) do

  desc <<-DESC
  Send report information via HTTPS to the `reporturl`. Each host sends
  its report as a YAML dump and this sends this YAML to a client via HTTPS POST.
  The YAML is the `report` parameter of the request."
  DESC

  def process
    url = URI.parse(Puppet[:reporturl].to_s)
    http = Net::HTTP.new(url.host, url.port)
    http.use_ssl = true
    http.verify_mode = OpenSSL::SSL::VERIFY_NONE

    req = Net::HTTP::Post.new(url.path)
    req.body = self.to_yaml
    req.content_type = "application/x-yaml"

    http.start do |http|
      response = http.request(req)
      unless response.code == "200"
        Puppet.err "Unable to submit report to #{Puppet[:reporturl].to_s} [#{response.code}] #{response.msg}" 
      end
    end

  end
end
