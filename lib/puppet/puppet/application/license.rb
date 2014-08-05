require 'puppet'
require 'puppet/application'
require 'puppet/util/license'

class Puppet::Application::License < Puppet::Application
  should_parse_config
  run_mode :master

  def setup
    Puppet::Util::Log.newdestination :console
  end

  def main
    if Puppet::SSL::CertificateAuthority.ca? then
      Puppet::SSL::Host.ca_location = :only
      Puppet::Util::License.display_license_status
      exit 0
    else
      puts "This system is not configured as a puppet certificate authority;"
      puts "Your configured CA server is '#{Puppet[:ca_server]}'."
      puts ""
      puts "You can only check license status on the certificate authority.  You will"
      puts "need to log in to that machine and verify the status of your license, and"
      puts "your Support & Maintenance agreement there."
      puts Puppet::Util::License::EnterpriseContactDetails
      exit 1
    end
  end
end
