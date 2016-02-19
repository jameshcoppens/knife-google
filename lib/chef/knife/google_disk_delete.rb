#
# Author:: Paul Rossman (<paulrossman@google.com>)
# Copyright:: Copyright 2015 Google Inc. All Rights Reserved.
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

require "chef/knife/google_base"

class Chef
  class Knife
    class GoogleDiskDelete < Knife

      include Knife::GoogleBase

      banner "knife google disk delete NAME (options)"

      option :gce_zone,
        :short => "-Z ZONE",
        :long => "--gce-zone ZONE",
        :description => "The Zone for this disk",
        :proc => Proc.new { |key| Chef::Config[:knife][:gce_zone] = key }

      def run
        $stdout.sync = true
        raise "Please provide the name of the disk to be deleted" if @name_args.empty?
        ui.confirm("Delete the disk '#{config[:gce_zone]}:#{@name_args.first}'")
        result = client.execute(
          :api_method => compute.disks.delete,
          :parameters => { :project => config[:gce_project], :zone => config[:gce_zone], :disk => @name_args.first })
        body = MultiJson.load(result.body, :symbolize_keys => true)
        if result.status == 200
          ui.warn("Disk '#{config[:gce_zone]}:#{@name_args.first}' deleted")
        else
          raise "#{body[:error][:message]}"
        end
      rescue
        raise
      end

    end
  end
end
