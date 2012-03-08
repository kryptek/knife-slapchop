module SlapChop
  class Slapchop < Chef::Knife

    banner "knife slapchop"

    option :build, :long => '--build CLUSTER', :short => '-b CLUSTER', :description => 'Build a cluster with slapchop' 
    option :identity, :long => '--identity-file FILE', :short => '-i FILE', :description => 'Full path to your SSH identity file'

    deps do
      require 'fog'
      require 'yaml'
      require 'formatador'
      require 'chef/knife/bootstrap'
      require 'terminal-table/import'
      Chef::Knife::Bootstrap.load_deps
    end

    def run
      @slapchop_config = YAML.load_file("#{File.dirname(__FILE__)}/slapchop.yml")
      @identity = config[:identity]
      @build = config[:build]
      @slapchop_config[config[:build]]['zones'].keys.each do |zone|
        for server in 1..@slapchop_config[config[:build]]['zones'][zone]
          puts "[!] Bootstrapping server ##{server} in #{zone}"
          Thread.new { create_server zone }
        end
      end
      Thread.list.each { |thread| thread.join if thread != Thread.main }
    end

    def create_server zone
      $stdout.sync = true
      connection = Fog::Compute.new(
        :provider => 'AWS',
        :aws_access_key_id => ENV['AWS_ACCESS_KEY_ID'],
        :aws_secret_access_key => ENV['AWS_SECRET_ACCESS_KEY'],
        :region => 'us-east-1'
      )
      ami = connection.images.get(@slapchop_config[@build][:ami])
      if ami.nil?
        puts "::_! Invalid AMI Image Specified.   :|"
        exit 1
      end
      server_def = {
        :image_id => @slapchop_config[@build][:image_id],
        :groups => @slapchop_config[@build][:groups].split(','),
        :flavor_id => @slapchop_config[@build][:flavor],
        :key_name => @slapchop_config[@build][:aws_ssh_key_id],
        :availability_zone => zone
      }
      server = connection.servers.create(server_def)
      unless @slapchop_config[@build][:tags].nil?
        begin
          tag_tbl = Terminal::Table.new :title => "Tagged instance: #{server.id}", :headings => ['[cyan]key[white]', '[cyan]value[white]'] 

          @slapchop_config[@build][:tags].each do |key, value|
            connection.create_tags(server.id, "#{key}" => "#{value.split(" ")[1]}")
            tag_tbl << ["[green]#{key}[white]", value.split(" ")[1]]
          end
          Formatador.display("#{tag_tbl}\n")
        rescue
          Formatador.display("[light_red] Server #{server.id} did not respond! Retrying..\n")
          sleep 1
          retry 
        end
      end
      puts "Waiting to bootstrap #{server.id}"
      server.wait_for { print "."; ready? }
      puts ("\n")
      ip_to_test = server.public_ip_address
      print(".") until tcp_test_ssh(ip_to_test) {
        sleep 1
        puts("done")
      }
      sleep 5 # Sleeping for ~5s helps allow the servers to finish booting.
      bootstrap_server(server).run
      puts "\n"
      puts "-------------------- #{zone} ------------------"
      puts "Instance ID: #{server.id}"
      puts "Public IP Address: #{server.public_ip_address}"
      puts "Public DNS: #{server.dns_name}"
      puts "--------------------------------------------------"
      @server_list.store(server.id,server.dns_name)
    rescue Fog::Compute::AWS::NotFound => error
      puts "@@@@@@@@@@@@@ ERROR @@@@@@@@@@@@@"
      puts error
      puts "@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@"
    rescue Fog::Compute::AWS::Error => error
      puts "@@@@@@@@@@@@@ ERROR @@@@@@@@@@@@@"
      puts error
      puts "@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@"
    end

    ##
    # Chef::Bootstrap a server.
    #
    def bootstrap_server(server)
      puts "!Bootstrapping #{server.id}"
      bootstrap = Chef::Knife::Bootstrap.new
      bootstrap.name_args = server.dns_name
      bootstrap.config[:run_list] = @slapchop_config[@build][:run_list].split(/[\s,]+/)
      bootstrap.config[:ssh_user] = 'ubuntu'
      bootstrap.config[:identity_file] = @identity
      bootstrap.config[:chef_node_name] = server.id
      bootstrap.config[:prerelease] = '--prerelease'
      bootstrap.config[:bootstrap_version] = '0.10.0'
      bootstrap.config[:distro] = 'ubuntu10.04-gems'
      bootstrap.config[:use_sudo] = true
      bootstrap.config[:template_file] = false
      bootstrap.config[:environment] = @slapchop_config[@build][:environment]
      bootstrap.config[:no_host_key_verify] = false
      bootstrap
    end

    def tcp_test_ssh(hostname)
      tcp_socket = TCPSocket.new(hostname, 22)
      readable = IO.select([tcp_socket], nil, nil, 5)
      if readable
        Chef::Log.debug("sshd accepting connections on #{hostname}, banner is #{tcp_socket.gets}")
        yield
        true
      else
        false
      end
    rescue Errno::ETIMEDOUT
      false
    rescue Errno::EPERM
      false
    rescue Errno::ECONNREFUSED
      sleep 2
      false
      # This happens on EC2 quite often..
    rescue Errno::EHOSTUNREACH
      sleep 2
      false
    ensure
      tcp_socket && tcp_socket.close
    end

  end
end
