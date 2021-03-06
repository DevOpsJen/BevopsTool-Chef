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
require "uri"

CACHE_FILE_TRUNCATED_FRIENDLY_FILE_NAME_LENGTH = 64
CACHE_FILE_CHECKSUM_HEX_LENGTH = 32
CACHE_FILE_JSON_FILE_EXTENSION_LENGTH = 5
CACHE_FILE_PATH_LIMIT =
  CACHE_FILE_TRUNCATED_FRIENDLY_FILE_NAME_LENGTH +
  1 +
  CACHE_FILE_CHECKSUM_HEX_LENGTH +
  CACHE_FILE_JSON_FILE_EXTENSION_LENGTH # {friendly}-{md5hex}.json == 102

describe Chef::Provider::RemoteFile::CacheControlData do

  let(:uri) { URI.parse("http://www.google.com/robots.txt") }

  subject(:cache_control_data) do
    Chef::Provider::RemoteFile::CacheControlData.load_and_validate(uri, current_file_checksum)
  end

  let(:cache_path) { "remote_file/http___www_google_com_robots_txt-6dc1b24315d0cff764d30344199c6f7b.json" }
  let(:old_cache_path) { "remote_file/http___www_google_com_robots_txt-9839677abeeadf0691026e0cabca2339.json" }

  # the checksum of the file we have on disk already
  let(:current_file_checksum) { "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855" }

  context "when loading data for an unknown URI" do

    before do
      expect(Chef::FileCache).to receive(:key?).with(cache_path).and_return(false)
      expect(Chef::FileCache).to receive(:key?).with(old_cache_path).and_return(false)
    end

    context "and there is no current copy of the file" do
      let(:current_file_checksum) { nil }

      it "returns empty cache control data" do
        expect(cache_control_data.etag).to be_nil
        expect(cache_control_data.mtime).to be_nil
      end
    end

    it "returns empty cache control data" do
      expect(cache_control_data.etag).to be_nil
      expect(cache_control_data.mtime).to be_nil
    end

    context "and the URI contains a password" do

      let(:uri) { URI.parse("http://bob:password@example.org/") }
      let(:cache_path) { "remote_file/http___bob_XXXX_example_org_-44be109aa176a165ef599c12d97af792.json" }
      let(:old_cache_path) { "remote_file/http___bob_XXXX_example_org_-f121caacb74c05a35bcefdf578ed5fc9.json" }

      it "loads the cache data from a path based on a sanitized URI" do
        Chef::Provider::RemoteFile::CacheControlData.load_and_validate(uri, current_file_checksum)
      end
    end
  end

  describe "when loading data for a known URI" do

    # the checksum of the file last we fetched it.
    let(:last_fetched_checksum) { "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855" }

    let(:etag) { "\"a-strong-identifier\"" }
    let(:mtime) { "Tue, 21 May 2013 19:19:23 GMT" }

    let(:cache_json_data) do
      cache = {}
      cache["etag"] = etag
      cache["mtime"] = mtime
      cache["checksum"] = last_fetched_checksum
      Chef::JSONCompat.to_json(cache)
    end

    context "when the cache control data uses sha256 for its name" do
      before do
        expect(Chef::FileCache).to receive(:key?).with(cache_path).and_return(true)
        expect(Chef::FileCache).to receive(:load).with(cache_path).and_return(cache_json_data)
      end

      context "and there is no on-disk copy of the file" do
        let(:current_file_checksum) { nil }

        it "returns empty cache control data" do
          expect(cache_control_data.etag).to be_nil
          expect(cache_control_data.mtime).to be_nil
        end
      end

      context "and the cached checksum does not match the on-disk copy" do
        let(:current_file_checksum) { "e2a8938cc31754f6c067b35aab1d0d4864272e9bf8504536ef3e79ebf8432305" }

        it "returns empty cache control data" do
          expect(cache_control_data.etag).to be_nil
          expect(cache_control_data.mtime).to be_nil
        end
      end

      context "and the cached checksum matches the on-disk copy" do
        context "when the filename uses sha256" do
          before do
            expect(Chef::FileCache).not_to receive(:key?).with(old_cache_path)
          end
          it "populates the cache control data" do
            expect(cache_control_data.etag).to eq(etag)
            expect(cache_control_data.mtime).to eq(mtime)
          end
        end
      end

      context "and the cached checksum data is corrupted" do
        let(:cache_json_data) { '{"foo",,"bar" []}' }

        it "returns empty cache control data" do
          expect(cache_control_data.etag).to be_nil
          expect(cache_control_data.mtime).to be_nil
        end

        context "and it still is valid JSON" do
          let(:cache_json_data) { "" }

          it "returns empty cache control data" do
            expect(cache_control_data.etag).to be_nil
            expect(cache_control_data.mtime).to be_nil
          end
        end
      end
    end

    context "when the filename uses md5" do
      before do
        expect(Chef::FileCache).to receive(:key?).with(cache_path).and_return(false)
        expect(Chef::FileCache).to receive(:key?).with(old_cache_path).and_return(true)
        expect(Chef::FileCache).to receive(:load).with(old_cache_path).and_return(cache_json_data)
      end

      it "populates the cache control data and creates the cache control data file with the correct path" do
        expect(Chef::FileCache).to receive(:store).with(cache_path, cache_json_data)
        expect(Chef::FileCache).to receive(:delete).with(old_cache_path)
        expect(cache_control_data.etag).to eq(etag)
        expect(cache_control_data.mtime).to eq(mtime)
      end
    end
  end

  describe "when saving to disk" do

    let(:etag) { "\"a-strong-identifier\"" }
    let(:mtime) { "Tue, 21 May 2013 19:19:23 GMT" }
    let(:fetched_file_checksum) { "e2a8938cc31754f6c067b35aab1d0d4864272e9bf8504536ef3e79ebf8432305" }

    let(:expected_serialization_data) do
      data = {}
      data["etag"] = etag
      data["mtime"] = mtime
      data["checksum"] = fetched_file_checksum
      data
    end

    before do
      cache_control_data.etag = etag
      cache_control_data.mtime = mtime
      cache_control_data.checksum = fetched_file_checksum
    end

    it "serializes its properties to JSON" do
      # we have to test this separately because ruby 1.8 hash order is unstable
      # so we can't count on the order of the keys in the json format.

      json_data = cache_control_data.json_data
      expect(Chef::JSONCompat.from_json(json_data)).to eq(expected_serialization_data)
    end

    it "writes data to the cache" do
      json_data = cache_control_data.json_data
      expect(Chef::FileCache).to receive(:store).with(cache_path, json_data)
      cache_control_data.save
    end

    context "and the URI contains a password" do

      let(:uri) { URI.parse("http://bob:password@example.org/") }
      let(:cache_path) { "remote_file/http___bob_XXXX_example_org_-44be109aa176a165ef599c12d97af792.json" }
      let(:old_cache_path) { "remote_file/http___bob_XXXX_example_org_-f121caacb74c05a35bcefdf578ed5fc9.json" }

      it "writes the data to the cache with a sanitized path name" do
        json_data = cache_control_data.json_data
        expect(Chef::FileCache).to receive(:store).with(cache_path, json_data)
        cache_control_data.save
      end
    end

    # Cover the very long remote file path case -- see CHEF-4422 where
    # local cache file names generated from the long uri exceeded
    # local file system path limits resulting in exceptions from
    # file system API's on both Windows and Unix systems.
    context "and the URI results in a file cache path that exceeds #{CACHE_FILE_PATH_LIMIT} characters in length" do
      let(:long_remote_path) { "http://www.bing.com/" + ("0" * (CACHE_FILE_TRUNCATED_FRIENDLY_FILE_NAME_LENGTH * 2 )) }
      let(:uri) { URI.parse(long_remote_path) }
      let(:truncated_remote_uri) { URI.parse(long_remote_path[0...CACHE_FILE_TRUNCATED_FRIENDLY_FILE_NAME_LENGTH]) }
      let(:truncated_file_cache_path) do
        cache_control_data_truncated = Chef::Provider::RemoteFile::CacheControlData.load_and_validate(truncated_remote_uri, current_file_checksum)
        cache_control_data_truncated.send(:sanitized_cache_file_basename)[0...CACHE_FILE_TRUNCATED_FRIENDLY_FILE_NAME_LENGTH]
      end

      it "truncates the file cache path to 102 characters" do
        normalized_cache_path = cache_control_data.send(:sanitized_cache_file_basename)

        expect(Chef::FileCache).to receive(:store).with("remote_file/" + normalized_cache_path, cache_control_data.json_data)

        cache_control_data.save

        expect(normalized_cache_path.length).to eq(CACHE_FILE_PATH_LIMIT)
      end

      it "uses a file cache path that starts with the first #{CACHE_FILE_TRUNCATED_FRIENDLY_FILE_NAME_LENGTH} characters of the URI" do
        normalized_cache_path = cache_control_data.send(:sanitized_cache_file_basename)

        expect(truncated_file_cache_path.length).to eq(CACHE_FILE_TRUNCATED_FRIENDLY_FILE_NAME_LENGTH)
        expect(normalized_cache_path.start_with?(truncated_file_cache_path)).to eq(true)
      end
    end

  end

end
