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

class Chef
  class Resource
    class HomebrewInstall < Chef::Resource
      unified_mode true

      provides :homebrew_install

      description "Use the **homebrew_install** resource to install the Homebrew package manager on macOS systems."
      introduced "16.8"
      examples <<~DOC
      **Install Homebrew using the Internet to download Command Line Tools for Xcode**:
      ```ruby
      homebrew_install 'Install Homebrew and xcode command line tools if necessary' do
        user 'someuser'
        action :install
      end
      ```
      **Install Homebrew using a local source to download Command Line Tools for Xcode from**:
      ```ruby
      homebrew_install 'Install Homebrew and xcode command line tools if necessary' do
        tools_url 'https://somewhere.something.com/downloads/command_line_tools.dmg'
        tools_pkg_name 'Command Line Tools.pkg'
        user 'someuser'
        action :install
      end
      ```
      DOC

      property :tools_url, String,
        description: "A url pointing to a local source for the Command Line Tools for Xcode dmg"

      property :tools_pkg_name, String,
        description: "The name of the pkg inside the dmg located at the tools url"

      property :brew_source, String,
        description: "A url pointing to a Homebrew installer",
        default: "https://github.com/Homebrew/brew/tarball/master"

      property :user, String,
        description: "The user to install Homebrew as. Note: Homebrew cannot be installed as root.",
        required: true

      action :install do
        # Avoid all the work in the below resources if homebrew is already installed
        return if ::File.exist?('/usr/local/bin/brew')

        BREW_REPO = 'https://codeload.github.com/Homebrew/brew/zip/master'.freeze
        USER_HOME = Dir.home(new_resource.user).freeze
        HOMEBREW_CACHE = "#{USER_HOME}/Library/Caches/Homebrew".freeze

        # Creating the basic directory structure needed for Homebrew
        directories = ['bin', 'etc', 'include', 'lib', 'sbin', 'share', 'var', 'opt',
                        'share/zsh', 'share/zsh/site-functions',
                        'var/homebrew', 'var/homebrew/linked',
                        'Cellar', 'Caskroom', 'Homebrew', 'Frameworks'
                      ].freeze
        directories.each do |dir|
          directory "/usr/local/#{dir}" do
            mode '0755'
            owner new_resource.user
            group 'admin'
            action :create
          end
        end

        user_directories = ["#{USER_HOME}", "#{USER_HOME}/Library",
                            "#{USER_HOME}/Library/Caches", "#{USER_HOME}/Library/Caches/Homebrew"
        ]
        user_directories.each do |dir|
          directory "#{dir}" do
            mode '0755'
            owner new_resource.user
            group 'admin'
            action :create
          end
        end

        if new_resource.tools_url
          dmg_package new_resource.tools_pkg_name do
            source new_resource.tools_url
            type 'pkg'
          end
        else
          build_essential 'install Command Line Tools for Xcode' do
            action :upgrade
          end
        end

        script 'Download and unpack Homebrew' do
          interpreter 'bash'
          cwd "/usr/local/Homebrew"
          code <<-CODEBLOCK
            git init -q
            curl #{BREW_REPO} -o brew-master.zip
            unzip brew-master.zip -d /usr/local/Homebrew
          CODEBLOCK
          user new_resource.user
        end

        script 'move files to their correct locations' do
          interpreter 'bash'
          cwd "/usr/local/Homebrew"
          code <<-CODEBLOCK
            mv /usr/local/Homebrew/brew-master/* /usr/local/Homebrew/
            mv /usr/local/Homebrew/brew-master/.* /usr/local/Homebrew/
            rmdir /usr/local/Homebrew/brew-master/
          CODEBLOCK
          user 'root'
        end

        cmd = Mixlib::ShellOut.new("git", "config", "core.autocrlf", "false", :user => new_resource.user, :environment => nil, :cwd => "/usr/local/Homebrew")
        cmd.run_command

        cmd = Mixlib::ShellOut.new("ln", "-sf", "/usr/local/Homebrew/bin/brew", "/usr/local/bin/brew", :user => new_resource.user, :environment => nil, :cwd => "/usr/local/Homebrew")
        cmd.run_command

        cmd = Mixlib::ShellOut.new("/usr/local/bin/brew", "update", "--force", :user => new_resource.user, :environment => nil, :cwd => "/usr/local/Homebrew")
        cmd.run_command

        local_shell = shell_out('echo $SHELL')
        if local_shell.stdout.match(/zsh/)
          shell_out('export PATH="/usr/local/bin:$PATH" >> ~/.zshrc')
        else
          shell_out('export PATH="/usr/local/bin:$PATH" >> ~/.bash_profile')
        end
      end
    end
  end
end