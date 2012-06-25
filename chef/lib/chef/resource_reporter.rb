#
# Author:: Daniel DeLeo (<dan@opscode.com>)
# Author:: Prajakta Purohit (prajakta@opscode.com>)
#
# Copyright:: Copyright (c) 2012 Opscode, Inc.
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

require 'uri'
require 'chef/event_dispatch/base'

class Chef
  class ResourceReporter < EventDispatch::Base

    class ResourceReport < Struct.new(:new_resource,
                                      :current_resource,
                                      :action,
                                      :exception,
                                      :elapsed_time)

      def self.new_with_current_state(new_resource, action, current_resource)
        report = new
        report.new_resource = new_resource
        report.action = action
        report.current_resource = current_resource
        report
      end

      def self.new_for_exception(new_resource, action)
        report = new
        report.new_resource = new_resource
        report.action = action
        report
      end

      def for_json
        as_hash = {}
        as_hash["type"]   = new_resource.class.dsl_name
        as_hash["name"]   = new_resource.name
        as_hash["id"]     = new_resource.identity
        as_hash["after"]  = new_resource.state
        as_hash["before"] = current_resource.state if current_resource
        as_hash["duration"] = (elapsed_time * 1000).to_i.to_s
        # TODO: include diffs, etc. here:
        as_hash["delta"] = ""
        # TODO: rename as "action"
        as_hash["result"] = action.to_s
        if success?
        else
          #as_hash["result"] = "failed"
        end
        as_hash["cookbook_name"] = new_resource.cookbook_name
        as_hash["cookbook_version"] = new_resource.cookbook_version.version
        as_hash

      end

      def finish
        self.elapsed_time = new_resource.elapsed_time
      end

      def success?
        !self.exception
      end
    end

    attr_reader :updated_resources
    attr_reader :status
    attr_reader :exception
    attr_reader :run_id

    def initialize(rest_client)
      @reporting_enabled = true
      @updated_resources = []
      @total_res_count = 0
      @pending_update  = nil
      @status = "success"
      @exception = nil
      @run_id = nil
      @rest_client = rest_client
      @node = nil
    end

    def node_load_completed(node, expanded_run_list_with_versions, config)
      @node = node
      resource_history_url = "nodes/#{@node.name}/runs"
      server_response = @rest_client.post_rest(resource_history_url, {:action => :begin})
      run_uri = URI.parse(server_response["uri"])
      @run_id = ::File.basename(run_uri.path)
    rescue Net::HTTPServerException => e
      raise unless e.response.code.to_s == "404"
      Chef::Log.debug("Received 404 attempting to generate run history id (URL Path: #{resource_history_url}), assuming feature is not supported.")
      @reporting_enabled = false
    end

    def resource_current_state_loaded(new_resource, action, current_resource)
      unless nested_resource?(new_resource)
        @pending_update = ResourceReport.new_with_current_state(new_resource, action, current_resource)
      end
    end

    def resource_up_to_date(new_resource, action)
      @total_res_count += 1
      @pending_update = nil unless nested_resource?(new_resource)
    end

    def resource_skipped(resource, action, conditional)
      @total_res_count += 1
    end

    def resource_updated(new_resource, action)
      @total_res_count += 1
      resource_completed unless nested_resource?(new_resource)
    end

    def resource_failed(new_resource, action, exception)
      @total_res_count += 1
      unless nested_resource?(new_resource)
        @pending_update ||= ResourceReport.new_for_exception(new_resource, action)
        @pending_update.exception = exception
        resource_completed
      end
    end

    def run_completed(node)
      if reporting_enabled?
        resource_history_url = "nodes/#{@node.name}/runs/#{run_id}"
        run_data = report(node)
        run_data["action"] = "end"
        Chef::Log.info("Sending resource update report (run-id: #{run_id})")
        Chef::Log.debug run_data.inspect
        @rest_client.post_rest(resource_history_url, run_data)
      else
        Chef::Log.debug("Server doesn't support resource history, skipping resource report.")
      end
    end

    def run_failed(exception)
      @exception = exception
      @status = "failed"
    end

    def report(node)
      run_data = {}
      run_data["resources"] = updated_resources.map do |resource_record|
        resource_record.for_json
      end
      run_data["status"] = status
      run_data["run_list"] = node.run_list.to_json
      run_data["total_res_count"] = @total_res_count.to_s
      if exception
        run_data["exception"] = {}
        run_data["exception"]["class"] = exception.inspect
        run_data["exception"]["message"] = exception.message
        run_data["exception"]["backtrace"] = exception.backtrace
        run_data["exception"]["description"] = "FIXME: error inspection stuff should go here"
      end
      run_data["data"] = {}
      run_data
    end

    def reporting_enabled?
      @reporting_enabled
    end

    private

    # If we are getting messages about a resource while we are in the middle of
    # another resource's update, we assume that the nested resource is just the
    # implementation of a provider, and we want to hide it from the reporting
    # output.
    def nested_resource?(new_resource)
      @pending_update && @pending_update.new_resource != new_resource
    end

    def resource_completed
      @pending_update.finish
      @updated_resources << @pending_update
      @pending_update = nil
    end

  end
end
