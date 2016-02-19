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
    end

    def delete_server
    end

    def list_servers
      instances = connection.list_instances(project, zone).items
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
      zones = connection.list_zones(project).items
      return [] if zones.nil? || disks.empty?

      zones
    end

    def list_disks
      disks = connection.list_disks(project, zone).items
      return [] if disks.nil? || disks.empty?

      disks
    end

    def list_regions
      regions = connection.list_regions(project).items
      return [] if regions.nil? || regions.empty?

      regions
    end

    def list_project_quotas
      quotas = connection.get_project(project).quotas
      return [] if quotas.nil? || quotas.empty?

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
  end
end
