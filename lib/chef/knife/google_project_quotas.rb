#
# Author:: Paul Rossman (<paulrossman@google.com>)
# Author:: Chef Partner Engineering (<partnereng@chef.io>)
# Copyright:: Copyright 2015-2016 Google Inc., Chef Software, Inc.
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

require "chef/knife"
require "chef/knife/cloud/list_resource_command"
require "chef/knife/cloud/google_service"
require "chef/knife/cloud/google_service_helpers"
require "chef/knife/cloud/google_service_options"

class Chef::Knife::Cloud
  class GoogleProjectQuotas < ResourceListCommand
    include GoogleServiceHelpers
    include GoogleServiceOptions

    banner "knife google project quotas"

    def validate_params!
      check_for_missing_config_values!
      super
    end

    def before_exec_command
      @columns_with_info = [
        { label: "Quota", key: "metric", value_callback: method(:format_name) },
        { label: "Limit", key: "limit", value_callback: method(:format_number) },
        { label: "Usage", key: "usage", value_callback: method(:format_number) }
      ]

      @sort_by_field = "metric"
    end

    def query_resource
      service.list_project_quotas
    end

    def format_name(name)
      name.split("_").map { |x| x.capitalize }.join(" ")
    end

    def format_number(number)
      number % 1 == 0 ? number.to_i.to_s : number.to_s
    end
  end
end
