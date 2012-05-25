# You can namespace however you like, but it's a good idea to use your own
    # instead of the Chef::Knife namespace.
    module SlapChop
      # Make sure you subclass from Chef::Knife
      class Slapchop < Chef::Knife
 
        banner "knife slapchop"

        option :build, :long => '--build CLUSTER', :short => '-b CLUSTER', :description => 'Build a cluster with slapchop' 
        option :identity, :long => '--identity-file FILE', :short => '-i FILE', :description => 'Full path to your SSH identity file'

        deps do
          require 'ap'
          require 'fog'
          require 'yaml'
          require 'formatador'
          require 'chef/knife/bootstrap'
          require 'terminal-table/import'
          Chef::Knife::Bootstrap.load_deps
        end

        # This method will be executed when you run this knife command.
        def run

          #ap Chef::Config.configuration
          @slapchop_config = YAML.load_file("#{File.dirname(__FILE__)}/slapchop.yml")
          @identity = config[:identity] || @slapchop_config[@build]['identity_file']
          @build = config[:build]
          @server_list = []

          # Configure needed parameters for the chef run.
          Chef::Config[:validation_key] = @slapchop['chef_config']['validation_key']
          Chef::Config[:client_key] = @slapchop_config['chef_config']['client_key']
          Chef::Config[:validation_client_name] = @slapchop_config['chef_config']['validation_client_name']
          Chef::Config[:identity_file] = @identity
          Chef::Config[:chef_server_url] = @slapchop_config['chef_config']['chef_server_url']
          Chef::Config[:log_level] = @slapchop_config['chef_config']['log_level']
          Chef::Config[:log_location] = @slapchop_config['chef_config']['log_location']
          Chef::Config[:node_name] = @slapchop_config['chef_config']['node_name']
          Chef::Config[:cookbook_path] = @slapchop_config['chef_config']['cookbooth_path']
          Chef::Config[:cache_type] = @slapchop_config['chef_config']['cache_type']
          Chef::Config[:environment] = @slapchop_config[@build]['environment']

          @slapchop_config[@build]['zones'].keys.each do |zone|
            for server in 1..@slapchop_config[@build]['zones'][zone]
              puts "[!] Bootstrapping server ##{server} in #{zone}"
              Thread.new { 
                create_server zone 
              }
            end
          end

          Thread.list.each { |thread| 
            thread.join if thread != Thread.main 
          }

        end

        def add_to_elb
          return if @slapchop_config[@build]['elb_name'].nil?

          elb = Fog::AWS::ELB.new(
            provider: 'AWS',
            aws_access_key_id: ENV['AWS_ACCESS_KEY_ID'],
            aws_secret_access_key: ENV['AWS_SECRET_ACCESS_KEY'],
            region: 'us-east-1'
          )

          begin
            Formatador.display "[green]Registering instances with load balancer: #{@slapchop_config[@build]['elb_name']}\n"
            ap @server_list
            elb.register_instances_with_load_balancer(@server_list)
          rescue
            Formatador.display "[red]Error adding instances to load balancer: #{@slapchop_config[@build]['elb_name']}\n"
          end

        end

        def create_server zone

          $stdout.sync = true

          connection = Fog::Compute.new(
            provider: 'AWS',
            aws_access_key_id: ENV['AWS_ACCESS_KEY_ID'],
            aws_secret_access_key: ENV['AWS_SECRET_ACCESS_KEY'],
            region: 'us-east-1'
          )

          ami = connection.images.get(@slapchop_config[@build]['ami'])
          if ami.nil?
            puts "::_! Invalid AMI Image Specified.   :|"
            exit 1
          end

          # us-east-1a
          server_def = {
            image_id: ami,
            groups: @slapchop_config[@build]['groups'].split(','),
            flavor_id: @slapchop_config[@build]['flavor'],
            key_name: @slapchop_config[@build]['aws_ssh_key_id'],
            availability_zone: zone
          }

          server = connection.servers.create(server_def)

          # Fog::Compute::AWS::NotFound if we run create_tags and the server isn't up yet :(
          # Create tags
          #
          puts "TAGS: #{@slapchop_config[@build]['tags']}"
          unless @slapchop_config[@build]['tags'].nil?

            begin

              tag_tbl = table ["[cyan]key[white]", '[cyan]value[white]']

              @slapchop_config[@build]['tags'].each do |key, value|
                connection.create_tags(server.id, "#{key}" "#{value}")
                tag_tbl << ["[green]#{key}[white]", value]
              end

              Formatador.display("\nTAGS::Added to [instance_id: #{server.id}]\n")
              Formatador.display("#{tag_tbl}\n")

            rescue

              Formatador.display("\n[light_red] API Error creating tags on: #{server.id} -- Retrying..\n")
              sleep 1
              retry

            end

          end

          puts "Waiting to bootstrap #{server.id}"
          server.wait_for { print "."; ready? }
          puts ("\n")

          # Test to see if the EC2 is ready to be bootstrapped.
          ip_to_test = server.public_ip_address
          print(".") until tcp_test_ssh(ip_to_test) {
            sleep 1
            puts("done")
          }

          sleep 5
          bootstrap_server(server).run

          puts "\n"
          puts "-------------------- #{zone} ------------------"
          puts "Instance ID: #{server.id}"
          puts "Public IP Address: #{server.public_ip_address}"
          puts "Public DNS: #{server.dns_name}"
          puts "--------------------------------------------------"
          @server_list.push server.id

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
          bootstrap.config[:run_list] = @slapchop_config[@build]['run_list'].split(/[\s,]+/)
          bootstrap.config[:ssh_user] = 'ec2-user'
          bootstrap.config[:identity_file] = @identity
          bootstrap.config[:chef_node_name] = server.id
          bootstrap.config[:prerelease] = '--prerelease'
          bootstrap.config[:bootstrap_version] = '0.10.10'
          bootstrap.config[:distro] = 'amazon-linux'
          bootstrap.config[:use_sudo] = true
          bootstrap.config[:template_file] = "#{ENV['CHEF_DIR']}/.chef/bootstrap/amazon-linux.erb"
          bootstrap.config[:environment] = @slapchop_config[@build]['environment']
          bootstrap.config[:no_host_key_verify] = false
          bootstrap
        end

        ##
        # Tests the remote host to verify whether or not
        # it's ready to be bootstrapped
        #
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
