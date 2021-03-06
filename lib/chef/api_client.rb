#
# Author:: Adam Jacob (<adam@chef.io>)
# Author:: Nuo Yan (<nuo@chef.io>)
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

require_relative "config"
require_relative "mixin/params_validate"
require_relative "mixin/from_file"
require_relative "mash"
require_relative "json_compat"
require_relative "search/query"
require_relative "server_api"

# DEPRECATION NOTE
#
# This code will be removed in Chef 13 in favor of the code in Chef::ApiClientV1,
# which will be moved to this namespace. New development should occur in
# Chef::ApiClientV1 until the time before Chef 13.
class Chef
  class ApiClient

    include Chef::Mixin::FromFile
    include Chef::Mixin::ParamsValidate

    # Create a new Chef::ApiClient object.
    def initialize
      @name = ""
      @public_key = nil
      @private_key = nil
      @admin = false
      @validator = false
    end

    # Gets or sets the client name.
    #
    # @param [Optional String] The name must be alpha-numeric plus - and _.
    # @return [String] The current value of the name.
    def name(arg = nil)
      set_or_return(
        :name,
        arg,
        regex: /^[\-[:alnum:]_\.]+$/
      )
    end

    # Gets or sets whether this client is an admin.
    #
    # @param [Optional True/False] Should be true or false - default is false.
    # @return [True/False] The current value
    def admin(arg = nil)
      set_or_return(
        :admin,
        arg,
        kind_of: [ TrueClass, FalseClass ]
      )
    end

    # Gets or sets the public key.
    #
    # @param [Optional String] The string representation of the public key.
    # @return [String] The current value.
    def public_key(arg = nil)
      set_or_return(
        :public_key,
        arg,
        kind_of: String
      )
    end

    # Gets or sets whether this client is a validator.
    #
    # @param [Boolean] arg whether or not the client is a validator.  If
    #   `nil`, retrieves the already-set value.
    # @return [Boolean] The current value
    def validator(arg = nil)
      set_or_return(
        :validator,
        arg,
        kind_of: [TrueClass, FalseClass]
      )
    end

    # Gets or sets the private key.
    #
    # @param [Optional String] The string representation of the private key.
    # @return [String] The current value.
    def private_key(arg = nil)
      set_or_return(
        :private_key,
        arg,
        kind_of: [String, FalseClass]
      )
    end

    # The hash representation of the object. Includes the name and public_key.
    # Private key is included if available.
    #
    # @return [Hash]
    def to_h
      result = {
        "name" => @name,
        "public_key" => @public_key,
        "validator" => @validator,
        "admin" => @admin,
        "json_class" => self.class.name,
        "chef_type" => "client",
      }
      result["private_key"] = @private_key if @private_key
      result
    end

    alias_method :to_hash, :to_h

    # The JSON representation of the object.
    #
    # @return [String] the JSON string.
    def to_json(*a)
      Chef::JSONCompat.to_json(to_h, *a)
    end

    def self.from_hash(o)
      client = Chef::ApiClient.new
      client.name(o["name"] || o["clientname"])
      client.private_key(o["private_key"]) if o.key?("private_key")
      client.public_key(o["public_key"])
      client.admin(o["admin"])
      client.validator(o["validator"])
      client
    end

    def self.from_json(j)
      from_hash(Chef::JSONCompat.parse(j))
    end

    def self.http_api
      Chef::ServerAPI.new(Chef::Config[:chef_server_url], { api_version: "0" })
    end

    def self.reregister(name)
      api_client = load(name)
      api_client.reregister
    end

    def self.list(inflate = false)
      if inflate
        response = {}
        Chef::Search::Query.new.search(:client) do |n|
          n = json_create(n) if n.instance_of?(Hash)
          response[n.name] = n
        end
        response
      else
        http_api.get("clients")
      end
    end

    # Load a client by name via the API
    def self.load(name)
      response = http_api.get("clients/#{name}")
      if response.is_a?(Chef::ApiClient)
        response
      else
        from_hash(response)
      end
    end

    # Remove this client via the REST API
    def destroy
      http_api.delete("clients/#{@name}")
    end

    # Save this client via the REST API, returns a hash including the private key
    def save
      http_api.put("clients/#{name}", { name: name, admin: admin, validator: validator })
    rescue Net::HTTPClientException => e
      # If that fails, go ahead and try and update it
      if e.response.code == "404"
        http_api.post("clients", { name: name, admin: admin, validator: validator })
      else
        raise e
      end
    end

    def reregister
      reregistered_self = http_api.put("clients/#{name}", name: name, admin: admin, validator: validator, private_key: true )
      if reregistered_self.respond_to?(:[])
        private_key(reregistered_self["private_key"])
      else
        private_key(reregistered_self.private_key)
      end
      self
    end

    # Create the client via the REST API
    def create
      http_api.post("clients", self)
    end

    # As a string
    def to_s
      "client[#{@name}]"
    end

    def inspect
      "Chef::ApiClient name:'#{name}' admin:'#{admin.inspect}' validator:'#{validator}' " +
        "public_key:'#{public_key}' private_key:'#{private_key}'"
    end

    def http_api
      @http_api ||= Chef::ServerAPI.new(Chef::Config[:chef_server_url], { api_version: "0" })
    end

  end
end
