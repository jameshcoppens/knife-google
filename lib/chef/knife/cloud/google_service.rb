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
require "google/apis/compute_v1"

class Chef::Knife::Cloud
  class GoogleService < Service
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

    def create_server
      # raise if not valid machine type

    end

    def delete_server
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
          private_ip:   instance_private_ip(instance),
          public_ip:    instance_public_ip(instance)
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

    def instance_private_ip(instance)
      instance.network_interfaces.first.network_ip
    rescue NoMethodError
      "unknown"
    end

    def instance_public_ip(instance)
      instance.network_interfaces.first.access_configs.first.nat_ip
    rescue NoMethodError
      "unknown"
    end

    def server_summary(server, _columns_with_info = nil)
    end

    def is_valid_machine_type?(machine_type)
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

      connection.insert_disk(project, zone, disk, source_image: source_image)

      wait_for do
        created_disk = connection.get_disk(project, zone, name)
        created_disk.status == 'READY'
      end
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
  end
end
