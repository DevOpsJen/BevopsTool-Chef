#
# Author:: Adam Jacob (<adam@chef.io>)
# Copyright:: Copyright (c) Chef Software Inc.
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

require_relative "../knife"
require "chef-utils/dist" unless defined?(ChefUtils::Dist)

class Chef
  class Knife
    class ClientCreate < Knife

      deps do
        require "chef/api_client_v1" unless defined?(Chef::ApiClientV1)
      end

      option :file,
        short: "-f FILE",
        long: "--file FILE",
        description: "Write the private key to a file if the #{ChefUtils::Dist::Server::PRODUCT} generated one."

      option :validator,
        long: "--validator",
        description: "Create the client as a validator.",
        boolean: true

      option :public_key,
        short: "-p FILE",
        long: "--public-key",
        description: "Set the initial default key for the client from a file on disk (cannot pass with --prevent-keygen)."

      option :prevent_keygen,
        short: "-k",
        long: "--prevent-keygen",
        description: "Prevent #{ChefUtils::Dist::Server::PRODUCT} from generating a default key pair for you. Cannot be passed with --public-key.",
        boolean: true

      banner "knife client create CLIENTNAME (options)"

      def client
        @client_field ||= Chef::ApiClientV1.new
      end

      def file
        config[:file]
      end

      def create_client(client)
        # should not be using save :( bad behavior
        Chef::ApiClientV1.from_hash(client).save
      end

      def run
        test_mandatory_field(@name_args[0], "client name")
        client.name @name_args[0]

        if config[:public_key] && config[:prevent_keygen]
          show_usage
          ui.fatal("You cannot pass --public-key and --prevent-keygen")
          exit 1
        end

        if !config[:prevent_keygen] && !config[:public_key]
          client.create_key(true)
        end

        if config[:validator]
          client.validator(true)
        end

        if config[:public_key]
          client.public_key File.read(File.expand_path(config[:public_key]))
        end

        file_is_writable!

        output = edit_hash(client)
        final_client = create_client(output)
        ui.info("Created #{final_client}")

        # output private_key if one
        if final_client.private_key
          if config[:file]
            File.open(config[:file], "w") do |f|
              f.print(final_client.private_key)
            end
          else
            puts final_client.private_key
          end
        end
      end

      #
      # This method is used to verify that the file and it's containing
      # directory are writable.  This ensures that you don't create the client
      # and then lose the private key because you weren't able to write it to
      # disk.
      #
      # @return [void]
      #
      def file_is_writable!
        return unless file

        dir = File.dirname(File.expand_path(file))
        unless File.exist?(dir)
          ui.fatal "Directory #{dir} does not exist. Please create and retry."
          exit 1
        end

        unless File.directory?(dir)
          ui.fatal "#{dir} exists, but is not a directory. Please update your file path (--file #{file}) or re-create #{dir} as a directory."
          exit 1
        end

        unless File.writable?(dir)
          ui.fatal "Directory #{dir} is not writable. Please check the permissions."
          exit 1
        end

        if File.exist?(file) && !File.writable?(file)
          ui.fatal "File #{file} is not writable. Please check the permissions."
          exit 1
        end
      end
    end
  end
end
