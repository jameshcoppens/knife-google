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

class Chef::Knife::Cloud
  module GoogleServiceHelpers
    def create_service_instance
      Chef::Knife::Cloud::GoogleService.new(
        project: locate_config_value(:gce_project),
        zone:    locate_config_value(:gce_zone)
      )
    end

    def check_for_missing_config_values!(*keys)
      missing = keys.select { |x| locate_config_value(x).nil? }

      unless missing.empty? # rubocop:disable Style/GuardClause
        ui.error("The following required parameters are missing: #{missing.join(', ')}")
        exit(1)
      end
    end
  end
end
