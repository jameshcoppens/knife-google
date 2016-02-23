#
# Author:: Chef Partner Engineering (<partnereng@chef.io>)
# Copyright:: Copyright (c) 2016 Chef Software, Inc.
# License:: Apache License, Version 2.0
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

require "chef/knife/cloud/exceptions"
require "chef/knife/cloud/service"
require "chef/knife/cloud/helpers"
require "chef/knife/cloud/google_service_helpers"
require "google/apis/compute_v1"
require "ipaddr"

class Chef::Knife::Cloud
  class GoogleService < Service
    include Chef::Knife::Cloud::GoogleServiceHelpers

    attr_reader :project, :zone

    def initialize(options = {})
      @project = options[:project]
      @zone    = options[:zone]
    end

    def connection
      return @connection unless @connection.nil?

      @connection = Google::Apis::ComputeV1::ComputeService.new
      @connection.authorization = authorization

      @connection
    end

    def authorization
      @authorization ||= Google::Auth.get_application_default(
        [
          "https://www.googleapis.com/auth/cloud-platform",
          "https://www.googleapis.com/auth/compute"
        ]
      )
    end

    def create_server(options={})
      validate_server_create_options!(options)

      ui.msg("Creating instance...")
      instance = create_instance(options)
      ui.msg("Instance created!")

      instance
    end

    def delete_server
    end

    def validate_server_create_options!(options)
      raise "Invalid machine type: #{options[:machine_type]}" unless valid_machine_type?(options[:machine_type])
      raise "Invalid network: #{options[:network]}" unless valid_network?(options[:network])
      raise "Invalid Public IP setting: #{options[:public_ip]}" unless valid_public_ip_setting?(options[:public_ip])
      raise "Invalid image: #{options[:image]}" unless valid_image?(options[:image], options[:image_project])
      raise "Invalid machine type: #{options[:machine_type]}" unless valid_machine_type?(options[:machine_type])
    end

    def check_api_call(&block)
      block.call
    rescue Google::Apis::ClientError
      false
    else
      true
    end

    def valid_machine_type?(machine_type)
      return false if machine_type.nil?
      check_api_call { connection.get_machine_type(project, zone, machine_type) }
    end

    def valid_network?(network)
      return false if network.nil?
      check_api_call { connection.get_network(project, network) }
    end

    def valid_public_ip_setting?(public_ip)
      public_ip.downcase! if public_ip.respond_to?(:downcase)

      if public_ip.nil? || public_ip == "ephemeral" || public_ip == "none"
        true
      elsif valid_ip_address?(public_ip)
        true
      else
        false
      end
    end

    def valid_ip_address?(ip_address)
      IPAddr.new(ip_address)
    rescue IPAddr::InvalidAddressError
      false
    else
      true
    end

    def valid_image?(image, image_project)
      return false if image.nil?
      project_name = image_project.nil? ? project : image_project

      check_api_call { connection.get_image(project_name, image) }
    end

    def create_instance(options)
      instance_object = instance_object_for(options)
      operation = connection.insert_instance(project, zone, instance_object)

      wait_for_operation(operation.name)
      wait_for_status('RUNNING') { connection.get_instance(project, zone, options[:name]) }

      connection.get_instance(project, zone, options[:name])
    end

    def instance_object_for(options)
      inst_obj                    = Google::Apis::ComputeV1::Instance.new
      inst_obj.name               = options[:name]
      inst_obj.can_ip_forward     = options[:can_ip_forward]
      inst_obj.disks              = instance_disks_for(options)
      inst_obj.machine_type       = machine_type_url_for(options[:machine_type])
      inst_obj.metadata           = instance_metadata_for(options[:metadata])
      inst_obj.network_interfaces = instance_network_interfaces_for(options)
      inst_obj.scheduling         = instance_scheduling_for(options)
      inst_obj.service_accounts   = instance_service_accounts_for(options) if use_service_accounts?(options)

      inst_obj
    end

    def instance_disks_for(options)
      disks = []
      disks << instance_boot_disk_for(options)
      options[:additional_disks].each do |disk_name|
        begin
          disk = connection.get_disk(project, zone, disk_name)
        rescue Google::Apis::ClientError => e
          ui.error("Unable to attach disk #{disk_name} to the instance: #{e.message}")
          raise
        end

        disks << disk
      end

      disks
    end

    def instance_boot_disk_for(options)
      disk = Google::Apis::ComputeV1::AttachedDisk.new
      params = Google::Apis::ComputeV1::AttachedDiskInitializeParams.new

      disk.boot           = true
      params.disk_name    = boot_disk_name_for(options)
      params.disk_size_gb = options[:boot_disk_size]
      params.disk_type    = disk_type_url_for(options[:boot_disk_ssd] ? "pd-ssd" : "pd-standard")
      params.source_image = disk_image_url_for(options[:image], options[:image_project])

      disk.initialize_params = params
      disk
    end

    def disk_image_url_for(image, image_project)
      project_name = image_project.nil? ? project : image_project
      "projects/#{project_name}/global/images/#{image}"
    end

    def boot_disk_name_for(options)
      options[:boot_disk_name].nil? ? options[:name] : options[:boot_disk_name]
    end

    def machine_type_url_for(machine_type)
      "zones/#{zone}/machineTypes/#{machine_type}"
    end

    def instance_metadata_for(metadata)
      # Google::Apis::ComputeV1::Metadata
    end

    def instance_network_interfaces_for(options)
      interface = Google::Apis::ComputeV1::NetworkInterface.new
      interface.network = network_url_for(options[:network])
      interface.access_configs = instance_access_configs_for(options[:public_ip])

      Array(interface)
    end

    def instance_access_configs_for(public_ip)
      return [] if public_ip.nil? || public_ip == "NONE"

      access_config = Google::Apis::ComputeV1::AccessConfig.new
      access_config.name = "External NAT"
      access_config.type = "ONE_TO_ONE_NAT"
      access_config.nat_ip = public_ip if valid_ip_address?(public_ip)

      Array(access_config)
    end

    def network_url_for(network)
      "projects/#{project}/global/networks/#{network}"
    end

    def instance_scheduling_for(options)
      scheduling = Google::Apis::ComputeV1::Scheduling.new
      scheduling.automatic_restart = options[:auto_restart].to_s
      scheduling.on_host_maintenance = migrate_setting_for(options[:auto_migrate])

      scheduling
    end

    def migrate_setting_for(auto_migrate)
      auto_migrate ? "MIGRATE" : "TERMINATE"
    end

    def instance_service_accounts_for(options)
      # Google::Apis::ComputeV1::ServiceAccount
    end

    def use_service_accounts?(options)
      # Google::Apis::ComputeV1::ServiceAccount
      # TODO
      false
    end

    def max_pages
      # TODO: make configurable
      20
    end

    def max_results
      # TODO: make configurable
      100
    end

    def paginated_results(api_method, items_method, *args)
      items      = []
      next_token = nil
      loop_num   = 1

      loop do
        loop_num += 1

        response = connection.send(api_method.to_sym, *args, max_results: max_results, page_token: next_token)
        items += response.send(items_method.to_sym)

        next_token = response.next_page_token
        break if next_token.nil?

        if loop_num >= max_pages
          ui.warn("Max pages (#{max_pages} reached, but more results exist - truncating results...")
          break
        end
      end

      items
    end

    def list_servers
      instances = paginated_results(:list_instances, :items, project, zone)
      return [] if instances.nil?

      instances.each_with_object([]) do |instance, memo|
        memo << OpenStruct.new(
          name:         instance.name,
          status:       instance.status,
          machine_type: instance.machine_type.split("/").last,
          network:      instance_network(instance),
          private_ip:   private_ip_for(instance),
          public_ip:    public_ip_for(instance)
        )
      end
    end

    def list_zones
      zones = paginated_results(:list_zones, :items, project)
      return [] if zones.nil?

      zones
    end

    def list_disks
      disks = paginated_results(:list_disks, :items, project, zone)
      return [] if disks.nil?

      disks
    end

    def list_regions
      regions = paginated_results(:list_regions, :items, project)
      return [] if regions.nil?

      regions
    end

    def list_project_quotas
      quotas = connection.get_project(project).quotas
      return [] if quotas.nil?

      quotas
    end

    def instance_network(instance)
      instance.network_interfaces.first.network.split("/").last
    rescue NoMethodError
      "unknown"
    end

    def server_summary(server, _columns_with_info = nil)
      # TODO
      #msg_pair('Server Label', server.label)
    end

    def project_for_image(image)
      case image
      when /centos/
        "centos-cloud"
      when /container-vm/
        "google-containers"
      when /coreos/
        "coreos-cloud"
      when /debian/
        "debian-cloud"
      when /opensuse-cloud/
        "opensuse-cloud"
      when /rhel/
        "rhel-cloud"
      when /sles/
        "suse-cloud"
      when /ubuntu/
        "ubuntu-os-cloud"
      else
        raise "Unable to find a GCE project for image #{image}"
      end
    end

    def create_disk(name, size, type, source_image=nil)
      disk = Google::Apis::ComputeV1::Disk.new
      disk.name    = name
      disk.size_gb = size
      disk.type    = disk_type_url_for(type)

      ui.msg("Creating a #{size} GB disk named #{name}...")

      operation = connection.insert_disk(project, zone, disk, source_image: source_image)
      wait_for_operation(operation.name)

      ui.msg("Waiting for disk to be ready...")

      wait_for_status("READY") { connection.get_disk(project, zone, name) }

      ui.msg("Disk created successfully.")
    end

    def delete_disk(name)
      connection.delete_disk(project, zone, name)
    end

    def disk_type_url_for(type)
      "zones/#{zone}/diskTypes/#{type}"
    end

    def wait_for(&block)
      # TODO
    end

    def wait_time
      # TODO: make configurable
      600
    end

    def refresh_time
      # TODO: make configurable
      2
    end

    def wait_for_status(requested_status, &block)
      last_status = ''

      begin
        Timeout.timeout(wait_time) do
          loop do
            item = block.call
            current_status = item.status

            if current_status == requested_status
              print "\n"
              break
            end

            if last_status == current_status
              print '.'
            else
              last_status = current_status
              print "\n"
              print "Current status: #{current_status}."
            end

            sleep refresh_time
          end
        end
      rescue Timeout::Error
        ui.msg('')
        ui.error("Request did not complete in #{wait_time} seconds. Check the Google Cloud Console for more info.")
        exit 1
      end
    end

    def zone_operation(operation)
      connection.get_zone_operation(project, zone, operation)
    end

    def wait_for_operation(operation)
      wait_for_status("DONE") { zone_operation(operation) }

      if operation_error?(operation)
        operation_errors(operation).each do |error|
          ui.error("#{ui.color(error.code, :bold)}: #{error.message}")
        end

        raise "Operation #{operation} failed."
      end
    end

    def operation_error?(operation)
      !zone_operation(operation).error.nil?
    end

    def operation_errors(operation)
      return [] if zone_operation(operation).error.nil?

      zone_operation(operation).error.errors
    end

    def server_creation_object_for
      # build it, adding a serviceAccounts section if there are any scopes defined
      #:serviceAccounts => [{ "kind" => 'compute#serviceAccount',
      #                       "email" => config[:service_account_name],
      #                       "scopes" => config[:service_account_scopes] }],
    end
  end
end
