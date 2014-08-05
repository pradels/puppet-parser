require 'puppet'
require 'puppet/application/master'
require 'puppet/ssl/certificate_authority'
require 'date'

class Puppet::Util::License
  LicenseKey      = '/etc/puppetlabs/license.key'
  EnterpriseURL   = "http://www.puppetlabs.com/how-to-buy"
  EnterpriseEmail = "sales@puppetlabs.com"
  EnterprisePhone = "+1 (877) 575-9775"

  EnterpriseContactDetails = "
You can reach Puppet Labs for sales, support, or maintenance agreements
by email to #{EnterpriseEmail}, on #{EnterprisePhone}, or visit us on
the web at #{EnterpriseURL} for more information."

  # This method is necessary because the CA API is not very friendly to the
  # use we are putting it to, and we can't modify it in this PE release.
  # --daniel 2011-01-13
  def self.ca_considers_node_live(name, ca)
    ca.verify name              # returns nil on success, or throws on failure
    true                        # yes, this is needed --daniel 2011-01-13
  rescue Puppet::SSL::CertificateAuthority::CertificateVerificationError
    false
  end

  def self.valid_license_date(date)
    return true if date.nil?
    return true if date.is_a? Date
    return false
  end

  def self.display_license_status
    # We define licensing in terms of live CA certs, and only locally.
    return false unless Puppet::SSL::CertificateAuthority.ca?

    ca = Puppet::SSL::CertificateAuthority.new

    # if no license exists, or there is a malformed license file, default to a complimentary license
    complimentary_license = true

    begin

      license = YAML.load_file(LicenseKey)

      ["start", "end"].each do |e|
        unless valid_license_date(license[e]) then
          raise "The #{e} value (#{license[e]}) in the license file is improper"
        end
      end

      unless license["nodes"].is_a?(Integer) and license["nodes"] > 0 then
        raise "The node count (#{license["nodes"]}) in the license is improper"
      end

      complimentary_license = false

    rescue Errno::ENOENT

      # the license key could not be found

      license = {
        "nodes" => 10,
        "start" => nil,
        "end"   => nil,
        "to"    => "        N/A

You are using a complimentary ten node license provided free by Puppet Labs."
      }

    rescue => detail

      Puppet.crit(["",
          "Your License is incorrectly formatted or corrupted!",
          detail,
          "",
          "Please contact Puppet Labs to correct this problem: email #{EnterpriseEmail}",
          "or visit our website at: " + EnterpriseURL].join("\n"))

      return true
    end

    live, dead = ca.list.
      reject { |n| n == 'ca' or n.start_with? 'pe-internal-' }.
      partition { |n| ca_considers_node_live(n, ca) }.
      map { |a| a.length }

    live.nil? and raise "Internal failure reading Certificate Authority live node list"
    dead.nil? and raise "Internal failure reading Certificate Authority dead node list"

    warning = error = false
    contact = true

    text  = ["",
             "You have #{live == 0 ? 'no' : live} active and " +
             "#{dead == 0 ? 'no' : dead} inactive nodes.",
             "You are currently licensed for #{license["nodes"]} active nodes."
            ]

    if license["start"] then
      text << "Your support and maintenance agreement starts on #{license["start"]}"
    end
    if license["end"] then
      text << "Your support and maintenance agreement ends on #{license["end"]}"
    end

    if license["to"] then
      text << ""
      text << "This Puppet Enterprise distribution is licensed to:"
      text << license["to"]
    end

    if live > license["nodes"] then
      error = true

      over = live - license["nodes"]

      text << "You have exceeded the node count in your license by #{over} active node#{over == 1 ? '' : 's'}!"
      text << ""
      text << "You should make sure that all unused node certificates have been are removed"
      text << "from the certificate authority with the 'puppet cert --clean' command; you can"
      text << "use the command 'puppet cert --list --all' to review the list of all node"
      text << "certificates."
      text << ""
      text << "Please contact Puppet Labs to obtain additional licenses to bring your network"
      text << "back in compliance."
    end

    if complimentary_license
      text << ""
      text << "Your complimentary license does not include Support & Maintenance. If you"
      text << "would like to obtain official Support & Maintenance, please contact us"
      text << "for pricing, and to find out about volume discounts."
    end

    if license["end"] && Date.today > license["end"] then
      error = true
      late = Date.today - license["end"]

      text << ""
      text << "Your Support & Maintenance agreement expired on #{license["end"]}!"
      text << "You have run for #{late} day#{late == 1 ? '' : 's'} without a support agreement; please contact"
      text << "Puppet Labs urgently to renew your Support & Maintenance agreement."
    elsif license["end"] && (Date.today + 30) >= license["end"] then
      warning = true
      left = license["end"] - Date.today

      text << ""
      text << "Your Support & Maintenance term expires on #{license["end"]}."
      text << "You have #{left} day#{left == 1 ? '' : 's'} remaining under that agreement; please contact"
      text << "Puppet Labs to renew your Support & Maintenance agreement:"
    else
      contact = false           # ...and you are in compliance.
    end

    contact and text << EnterpriseContactDetails

    level = error ? :alert : warning ? :warning : :notice

    # (#12660) To avoid sending a massive string to the logging system, we send
    # the message line by line.  Sending a large string is a problem because it
    # gets truncated by syslog.
    text.each do |line|
      # The chomp is here just to ensure we don't send newlines to the logger
      Puppet.send level, line.chomp
    end

    return true
  end
end
