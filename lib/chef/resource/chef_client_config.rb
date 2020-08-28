#
# Copyright:: Copyright (c) Chef Software Inc.
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

require_relative "../resource"
require_relative "../dist"

class Chef
  class Resource
    class ChefClientConfig < Chef::Resource
      unified_mode true

      provides :chef_client_config

      description "Use the **chef_client_config** resource to create a client.rb file in the  #{Chef::Dist::PRODUCT} configuration directory."
      introduced "16.5"
      examples <<~DOC
      DOC

      property :config_directory, String,
        default: Chef::Dist::CONF_DIR

      property :user, String

      property :node_name, String,
        default: lazy { node["name"] }

      property :chef_server_url, String,
        required: true

      # @todo Allow inputing this as a string and convert it to the symbol
      property :ssl_verify_mode, Symbol,
        equal_to: [:verify_none, :verify_peer]

      property :formatters, Array, default: lazy {[]}

      property :event_loggers, Array, default: lazy {[]}

      property :log_level, Symbol,
        equal_to: %i{auto trace debug info warn fatal}

      property :log_location, String

      property :http_proxy, String

      property :https_proxy, String

      # @todo: do we need the ftp proxy settings?

      property :no_proxy, String

      # @todo we need to fixup bad plugin naming inputs here
      property :ohai_disabled_plugins, Array, default: lazy {[]}

      # @todo we need to fixup bad plugin naming inputs here
      property :ohai_optional_plugins, Array, default: lazy {[]}

      property :minimal_ohai, [true, false]

      property :start_handlers

      property :report_handlers

      property :exception_handlers

      property :chef_license, String,
        equal_to: %w{accept accept-no-persist accept-silent}

      property :policy_name, String

      property :policy_group, String

      property :named_run_list, String

      property :pid_file, String

      property :file_cache_path, String

      property :file_backup_path, String

      property :run_path, String

      property :file_staging_uses_destdir, String

      action :create do
        unless ::Dir.exist?(new_resource.config_directory)
          directory new_resource.config_directory do
            user new_resource.user unless new_resource.user.nil?
            mode "0750"
            recursive true
          end
        end

        unless ::Dir.exist?(::File.join(new_resource.config_directory, "client.d"))
          directory ::File.join(new_resource.config_directory, "client.d") do
            user new_resource.user unless new_resource.user.nil?
            mode "0750"
            recursive true
          end
        end

        template ::File.join(new_resource.config_directory, "client.rb") do
          source ::File.expand_path("support/client.erb", __dir__)
          local true
          variables(
            chef_license: new_resource.chef_license,
            chef_server_url: new_resource.chef_server_url,
            event_loggers: new_resource.event_loggers,
            exception_handlers: new_resource.exception_handlers,
            file_backup_path: new_resource.file_backup_path,
            file_cache_path: new_resource.file_cache_path,
            file_staging_uses_destdir: new_resource.file_staging_uses_destdir,
            formatters: new_resource.formatters,
            http_proxy: new_resource.http_proxy,
            https_proxy: new_resource.https_proxy,
            log_level: new_resource.log_level,
            log_location: new_resource.log_location,
            minimal_ohai: new_resource.minimal_ohai,
            named_run_list: new_resource.named_run_list,
            no_proxy: new_resource.no_proxy,
            node_name: new_resource.node_name,
            ohai_disabled_plugins: new_resource.ohai_disabled_plugins,
            ohai_optional_plugins: new_resource.ohai_optional_plugins,
            pid_file: new_resource.pid_file,
            policy_group: new_resource.policy_group,
            policy_name: new_resource.policy_name,
            report_handlers: new_resource.report_handlers,
            run_path: new_resource.run_path,
            ssl_verify_mode: new_resource.ssl_verify_mode,
            start_handlers: new_resource.start_handlers
          )
          mode "0640"
          action :create
        end
      end

      action :remove do
        file ::File.join(new_resource.config_directory, "client.rb") do
          action :delete
        end
      end

      action_class do
      end
    end
  end
end
