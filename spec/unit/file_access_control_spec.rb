#
# Author:: Daniel DeLeo (<dan@chef.io>)
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

require "spec_helper"
require "ostruct"

describe Chef::FileAccessControl do
  describe "Unix" do
    before do
      platform_mock :unix do
        # we have to re-load the file so the proper
        # platform specific module is mixed in
        @node = Chef::Node.new
        load File.join(__dir__, "..", "..", "lib", "chef", "file_access_control.rb")
        @resource = Chef::Resource::File.new("/tmp/a_file.txt")
        @resource.owner("toor")
        @resource.group("wheel")
        @resource.mode("0400")

        @events = Chef::EventDispatch::Dispatcher.new
        @run_context = Chef::RunContext.new(@node, {}, @events)
        @current_resource = Chef::Resource::File.new("/tmp/different_file.txt")
        @provider_requirements = Chef::Provider::ResourceRequirements.new(@resource, @run_context, :create)
        @provider = double("File provider", requirements: @provider_requirements, manage_symlink_access?: false)

        @fac = Chef::FileAccessControl.new(@current_resource, @resource, @provider)
      end
    end

    describe "class methods" do
      it "responds to #writable?" do
        expect(Chef::FileAccessControl).to respond_to(:writable?)
      end
    end

    it "has a resource" do
      expect(@fac.resource).to equal(@resource)
    end

    it "has a file to manage" do
      expect(@fac.file).to eq("/tmp/different_file.txt")
    end

    it "is not modified yet" do
      expect(@fac).not_to be_modified
    end

    it "determines the uid of the owner specified by the resource" do
      expect(Etc).to receive(:getpwnam).with("toor").and_return(OpenStruct.new(uid: 2342))
      expect(@fac.target_uid).to eq(2342)
    end

    it "raises a Chef::Exceptions::UserIDNotFound error when Etc can't find the user's name" do
      expect(Etc).to receive(:getpwnam).with("toor").and_raise(ArgumentError)
      expect { @fac.target_uid; @provider_requirements.run(:create) }.to raise_error(Chef::Exceptions::UserIDNotFound, "cannot determine user id for 'toor', does the user exist on this system?")
    end

    it "does not attempt to resolve the uid if the user is not specified" do
      resource = Chef::Resource::File.new("a file")
      fac = Chef::FileAccessControl.new(@current_resource, resource, @provider)
      expect(fac.target_uid).to be_nil
    end

    it "does not want to update the owner if none is specified" do
      resource = Chef::Resource::File.new("a file")
      fac = Chef::FileAccessControl.new(@current_resource, resource, @provider)
      expect(fac.should_update_owner?).to be_falsey
    end

    it "raises an ArgumentError if the resource's owner is set to something wack" do
      @resource.instance_variable_set(:@owner, :diaf)
      expect { @fac.target_uid; @provider_requirements.run(:create) }.to raise_error(ArgumentError)
    end

    it "uses the resource's uid for the target uid when the resource's owner is specified by an integer" do
      @resource.owner(2342)
      expect(@fac.target_uid).to eq(2342)
    end

    it "wraps uids to their negative complements to correctly handle negative uids" do
      # More: macOS (at least) has negative UIDs for 'nobody' and some other
      # users. Ruby doesn't believe in negative UIDs so you get the diminished radix
      # complement (i.e., it wraps around the maximum size of C unsigned int) of these
      # uids. So we have to get ruby and negative uids to smoke the peace pipe
      # with each other.
      @resource.owner("nobody")
      expect(Etc).to receive(:getpwnam).with("nobody").and_return(OpenStruct.new(uid: (4294967294)))
      expect(@fac.target_uid).to eq(-2)
    end

    it "does not wrap uids to their negative complements beyond -9" do
      # More: when OSX userIDs are created by ActiveDirectory sync, it tends to use huge numbers
      #  which had been incorrectly wrapped.  It does not look like the OSX IDs go below -2
      @resource.owner("bigdude")
      expect(Etc).to receive(:getpwnam).with("bigdude").and_return(OpenStruct.new(uid: (4294967286)))
      expect(@fac.target_uid).to eq(4294967286)
    end

    it "wants to update the owner when the current owner is nil (creating a file)" do
      @current_resource.owner(nil)
      @resource.owner(2342)
      expect(@fac.should_update_owner?).to be_truthy
    end

    it "wants to update the owner when the current owner doesn't match desired" do
      @current_resource.owner(3224)
      @resource.owner(2342)
      expect(@fac.should_update_owner?).to be_truthy
    end

    it "includes updating ownership in its list of desired changes" do
      resource = Chef::Resource::File.new("a file")
      resource.owner(2342)
      @current_resource.owner(100)
      fac = Chef::FileAccessControl.new(@current_resource, resource, @provider)
      expect(fac.describe_changes).to eq(["change owner from '100' to '2342'"])
    end

    it "sets the file's owner as specified in the resource when the current owner is incorrect" do
      @resource.owner(2342)
      expect(File).to receive(:chown).with(2342, nil, "/tmp/different_file.txt")
      @fac.set_owner
      expect(@fac).to be_modified
    end

    it "doesn't set the file's owner if it already matches" do
      @resource.owner(2342)
      @current_resource.owner(2342)
      expect(File).not_to receive(:chown)
      @fac.set_owner
      expect(@fac).not_to be_modified
    end

    it "doesn't want to update a file's owner when it's already correct" do
      @resource.owner(2342)
      @current_resource.owner(2342)
      expect(@fac.should_update_owner?).to be_falsey
    end

    it "determines the gid of the group specified by the resource" do
      expect(Etc).to receive(:getgrnam).with("wheel").and_return(OpenStruct.new(gid: 2342))
      expect(@fac.target_gid).to eq(2342)
    end

    it "uses a user specified gid as the gid" do
      @resource.group(2342)
      expect(@fac.target_gid).to eq(2342)
    end

    it "raises a Chef::Exceptions::GroupIDNotFound error when Etc can't find the user's name" do
      expect(Etc).to receive(:getgrnam).with("wheel").and_raise(ArgumentError)
      expect { @fac.target_gid; @provider_requirements.run(:create) }.to raise_error(Chef::Exceptions::GroupIDNotFound, "cannot determine group id for 'wheel', does the group exist on this system?")
    end

    it "does not attempt to resolve a gid when none is supplied" do
      resource = Chef::Resource::File.new("crab")
      fac = Chef::FileAccessControl.new(@current_resource, resource, @provider)
      expect(fac.target_gid).to be_nil
    end

    it "does not want to update the group when no target group is specified" do
      resource = Chef::Resource::File.new("crab")
      fac = Chef::FileAccessControl.new(@current_resource, resource, @provider)
      expect(fac.should_update_group?).to be_falsey
    end

    it "raises an error when the supplied group name is an alien" do
      @resource.instance_variable_set(:@group, :failburger)
      expect { @fac.target_gid; @provider_requirements.run(:create) }.to raise_error(ArgumentError)
    end

    it "wants to update the group when the current group is nil (creating a file)" do
      @resource.group(2342)
      @current_resource.group(nil)
      expect(@fac.should_update_group?).to be_truthy
    end

    it "wants to update the group when the current group doesn't match the target group" do
      @resource.group(2342)
      @current_resource.group(815)
      expect(@fac.should_update_group?).to be_truthy
    end

    it "includes updating the group in the list of changes" do
      resource = Chef::Resource::File.new("crab")
      resource.group(2342)
      @current_resource.group(815)
      fac = Chef::FileAccessControl.new(@current_resource, resource, @provider)
      expect(fac.describe_changes).to eq(["change group from '815' to '2342'"])
    end

    it "sets the file's group as specified in the resource when the group is not correct" do
      @resource.group(2342)
      @current_resource.group(815)

      expect(File).to receive(:chown).with(nil, 2342, "/tmp/different_file.txt")
      @fac.set_group
      expect(@fac).to be_modified
    end

    it "doesn't want to modify the file's group when the current group is correct" do
      @resource.group(2342)
      @current_resource.group(2342)
      expect(@fac.should_update_group?).to be_falsey
    end

    it "doesnt set the file's group if it is already correct" do
      @resource.group(2342)
      @current_resource.group(2342)

      # @fac.stub(:stat).and_return(OpenStruct.new(:gid => 2342))
      expect(File).not_to receive(:chown)
      @fac.set_group
      expect(@fac).not_to be_modified
    end

    it "uses the supplied mode as octal when it's a string" do
      @resource.mode("444")
      expect(@fac.target_mode).to eq(292) # octal 444 => decimal 292
    end

    it "uses the supplied mode verbatim when it's an integer" do
      @resource.mode(00444)
      expect(@fac.target_mode).to eq(292)
    end

    it "does not try to determine the mode when none is given" do
      resource = Chef::Resource::File.new("blahblah")
      fac = Chef::FileAccessControl.new(@current_resource, resource, @provider)
      expect(fac.target_mode).to be_nil
    end

    it "doesn't want to update the mode when no target mode is given" do
      resource = Chef::Resource::File.new("blahblah")
      fac = Chef::FileAccessControl.new(@current_resource, resource, @provider)
      expect(fac.should_update_mode?).to be_falsey
    end

    it "wants to update the mode when the current mode is nil (creating a file)" do
      @resource.mode("0400")
      @current_resource.mode(nil)
      expect(@fac.should_update_mode?).to be_truthy
    end

    it "wants to update the mode when the desired mode does not match the current mode" do
      @resource.mode("0400")
      @current_resource.mode("0644")
      expect(@fac.should_update_mode?).to be_truthy
    end

    it "includes changing the mode in the list of desired changes" do
      resource = Chef::Resource::File.new("blahblah")
      resource.mode("0750")
      @current_resource.mode("0444")
      fac = Chef::FileAccessControl.new(@current_resource, resource, @provider)
      expect(fac.describe_changes).to eq(["change mode from '0444' to '0750'"])
    end

    it "sets the file's mode as specified in the resource when the current modes are incorrect" do
      # stat returns modes like 0100644 (octal) => 33188 (decimal)
      # @fac.stub(:stat).and_return(OpenStruct.new(:mode => 33188))
      @current_resource.mode("0644")
      expect(File).to receive(:chmod).with(256, "/tmp/different_file.txt")
      @fac.set_mode
      expect(@fac).to be_modified
    end

    it "does not want to update the mode when the current mode is correct" do
      @current_resource.mode("0400")
      expect(@fac.should_update_mode?).to be_falsey
    end

    it "does not set the file's mode when the current modes are correct" do
      # @fac.stub(:stat).and_return(OpenStruct.new(:mode => 0100400))
      @current_resource.mode("0400")
      expect(File).not_to receive(:chmod)
      @fac.set_mode
      expect(@fac).not_to be_modified
    end

    it "sets all access controls on a file" do
      allow(@fac).to receive(:stat).and_return(OpenStruct.new(owner: 99, group: 99, mode: 0100444))
      @resource.mode(0400)
      @resource.owner(0)
      @resource.group(0)
      expect(File).to receive(:chmod).with(0400, "/tmp/different_file.txt")
      expect(File).to receive(:chown).with(0, nil, "/tmp/different_file.txt")
      expect(File).to receive(:chown).with(nil, 0, "/tmp/different_file.txt")
      @fac.set_all
      expect(@fac).to be_modified
    end
  end
end
