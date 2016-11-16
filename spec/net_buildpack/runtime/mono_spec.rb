# Encoding: utf-8
# Cloud Foundry NET Buildpack
# Copyright 2013 the original author or authors.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

require 'spec_helper'
require 'fileutils'
require 'net_buildpack/runtime/mono'

module NETBuildpack::Runtime

  describe Mono do

    DETAILS = [NETBuildpack::Util::TokenizedVersion.new('3.2.0'), 'test-uri']

    let(:application_cache) { double('ApplicationCache') }

    before do
      $stdout = StringIO.new
      $stderr = StringIO.new

      NETBuildpack::Repository::ConfiguredItem.stub(:find_item).and_return(DETAILS)
      NETBuildpack::Util::ApplicationCache.stub(:new).and_return(application_cache)
      application_cache.stub(:get).with('test-uri').and_yield(File.open('spec/fixtures/stub-mono.tar.gz'))
        
    end

    it 'should detect with id of mono-<version>' do
      Dir.mktmpdir do |root|
        
        NETBuildpack::Runtime::Stack.stub(:detect_stack).and_return(:linux)

        detected = Mono.new(
            :app_dir => root
        ).detect

        expect(detected).to eq('mono-3.2.0')
      end
    end

    it 'should not detect when running on Windows' do
      Dir.mktmpdir do |root|
        
        NETBuildpack::Runtime::Stack.stub(:detect_stack).and_return(:windows)
        detected = Mono.new(
            :app_dir => root
          ).detect
        expect(detected).to be_nil
      end
    end

    it 'should extract Mono from a GZipped TAR' do
      Dir.mktmpdir do |root|
        
        detected = Mono.new(
            :app_dir => root
        ).compile

        mono = File.join(root, 'vendor', 'mono', 'bin', 'mono')
        expect(File.exists?(mono)).to be_true
      end
    end

    it 'should fail when ConfiguredItem.find_item fails' do
      Dir.mktmpdir do |root|
        NETBuildpack::Repository::ConfiguredItem.stub(:find_item).and_raise('test error')
        expect do
          Mono.new(
            :app_dir => root
          ).detect
        end.to raise_error(/Error\ finding\ mono\ version:\ test\ error/)
      end
    end

    it 'runs mozroots with XDG_CONFIG_HOME set correctly' do
      Dir.mktmpdir do |root|

        NETBuildpack::Util::RunCommand.stub(:exec) do |cmd, logger, options|
            case cmd
            when /ln.+/i
                cmd.should include('-s')
                cmd.should include("#{root}/vendor /app/vendor")
            when /.*mozroots.*/i
                cmd.should include('mozroots')
                cmd.should include('--import')
                cmd.should include('--sync')
                cmd.should include('--machine')
                cmd.should include('--url http://hg.mozilla.org/releases/mozilla-release/raw-file/default/security/nss/lib/ckfw/builtins/certdata.txt')
                options[:env].should include('HOME'=>root, 'XDG_CONFIG_HOME' => '$HOME/.config')
            end
            0
        end

        detected = Mono.new(
            :app_dir => root
        ).compile
      end
    end

    it '[on release] creates a valid start.sh' do
      Dir.mktmpdir do |root|

        Mono.new(
            :app_dir => root,
            :start_script => { :init => ["init command 1", "init command 2"], :run => "run command" }
        ).release

        start_script_path = File.join(root, 'start.sh')
        expect(File.exists?(start_script_path)).to be_true

        start_script = File.read(start_script_path)
        expected_start_script = <<EXPECTED_START_SCRIPT
#!/usr/bin/env bash
init command 1
init command 2
run command
EXPECTED_START_SCRIPT
        expect(start_script).to eq(expected_start_script)
      end
    end

    it 'runs mono with the --server flag (see http://www.mono-project.com/Release_Notes_Mono_3.2#New_in_Mono_3.2.3)' do
      Dir.mktmpdir do |root|

        run_command = ""
        Mono.new(
            :app_dir => root,
            :runtime_command => run_command
        ).release

        expect(run_command).to include("mono --server")
      end
    end

    it 'adds correct env vars to config_vars ' do
      Dir.mktmpdir do |root|

        config_vars = {}
        Mono.new(
            :app_dir => root,
            :config_vars => config_vars
        ).release

        expect(config_vars["LD_LIBRARY_PATH"]).to include("$HOME/vendor/mono/lib")
        expect(config_vars["DYLD_LIBRARY_FALLBACK_PATH"]).to include("$HOME/vendor/mono/lib")
        expect(config_vars["C_INCLUDE_PATH"]).to include("$HOME/vendor/mono/include")
        expect(config_vars["ACLOCAL_PATH"]).to include("$HOME/vendor/mono/share/aclocal")
        expect(config_vars["PKG_CONFIG_PATH"]).to include("$HOME/vendor/mono/lib/pkgconfig")
        expect(config_vars["PATH"]).to include("$HOME/vendor/mono/bin")
        expect(config_vars["RUNTIME_COMMAND"]).to include("$HOME/vendor/mono/bin/mono")
        expect(config_vars["XDG_CONFIG_HOME"]).to include("$HOME/.config")
      end
    end

    it 'should include /usr/local/sbin, /usr/local/bin, /usr/sbin, /usr/bin, /sbin, /bin in the path' do
      Dir.mktmpdir do |root|

        config_vars = {}
        Mono.new(
            :app_dir => root,
            :config_vars => config_vars
        ).release

        expect(config_vars["PATH"]).to include("/usr/local/sbin")
        expect(config_vars["PATH"]).to include("/usr/local/bin")
        expect(config_vars["PATH"]).to include("/usr/sbin")
        expect(config_vars["PATH"]).to include("/usr/bin")
        expect(config_vars["PATH"]).to include("/sbin")
        expect(config_vars["PATH"]).to include("/bin")
      end
    end

    it 'should set MONO_GC_PARAMS with a limited the max heap size' do
      Dir.mktmpdir do |root|

        config_vars = {}
        Mono.new(
            :app_dir => root,
            :config_vars => config_vars
        ).release

        expect(config_vars["MONO_GC_PARAMS"]).to include("major=marksweep-par")
        expect(config_vars["MONO_GC_PARAMS"]).to include("max-heap-size=464M")
      end
    end

  end # describe
end #module
