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
  module GoogleServiceOptions
    def self.included(includer)
      includer.class_eval do
        option :gce_project,
          :long => "--gce-project PROJECT",
          :description => "Name of the Google Cloud project to use"

        option :gce_zone,
          :short => "-Z ZONE",
          :long => "--gce-zone ZONE",
          :description => "Name of the Google Compute Engine zone to use"
      end
    end
  end
end
