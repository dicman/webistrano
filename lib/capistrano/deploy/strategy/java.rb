require 'rubygems'
require 'capistrano/recipes/deploy/strategy/base'
require 'tempfile'  # Dir.tmpdir
require 'find'

module Capistrano
  module Deploy
    module Strategy
      
      # Java deploy strategy 
      # 1. checkout source
      # 2. build package (ant package or maven package)
      # 3. upload package
      # 4. mkdir directory and unzip package
      # 5. upload REVISION version file 
      # * config must set strategy e.g.  set :strategy, Capistrano::Deploy::Strategy::Java.new(self)
      class Java < Base
        def deploy!
          build!
          
          upload(package_file, remote_filename)
          run "mkdir -p #{configuration[:release_path]} && cd #{configuration[:release_path]} && #{java_home}/bin/jar -xf #{remote_filename} && rm #{remote_filename}"
          put revision.to_s, File.join(configuration[:release_path], "REVISION")
        end
      
        def build!
          # clearing destination
          system("rm -rf #{destination}")

          system(command)
          
          logger.trace "cd #{destination}; #{build_command} "
          Dir.chdir(destination) { system(build_command) }
        end
      
        def build_upload!
          build!
          
          logger.trace "cd #{destination}/#{build_dir} "
          Dir.chdir("#{destination}/#{build_dir}") do 
            files = (configuration[:upload_files] || "").split(",").map { |f| Dir[f.strip] }.flatten
            files.each do |file|
              system "rm #{buil_upload_file} && tar -cvzf #{buil_upload_file} #{file}"
              upload(buil_upload_file, "#{configuration[:current_path]}/#{buil_upload_file}")
              run "cd #{configuration[:current_path]} && tar -xvzf #{buil_upload_file} && rm #{buil_upload_file}"
            end
          end
        end
        

        private
        
        def buil_upload_file
          "build_upload.tar.gz"
        end
        
        # Returns the basename of the release_path, which will be used to
        # name the local copy and archive file.
        def destination
          @destination ||= tmpdir;
        end
        
        # Returns the value of the :copy_strategy variable, defaulting to
        # :checkout if it has not been set.
        def copy_strategy
          copy_strategy_symbol = :checkout
          copy_strategy_symbol = :sync if File.exist?("#{destination}/.svn")
          @copy_strategy ||= configuration.fetch(:copy_strategy, copy_strategy_symbol)
        end
        
        # select build strategy ant or maven, default is maven
        def build_strategy
          @build_strategy ||= configuration.fetch(:build_strategy, :maven) 
        end
        
        # build command, package 
        def build_command
          @build_command ||= case build_strategy
            when :maven
            "mvn clean package #{build_option}"
            when :ant
            "ant clean package #{build_option}"
          end
        end
        
        # java home
        def java_home
          @java_home ||= configuration[:java_home] || "/usr/java/"
        end
        
        # package 되어진 war or jar 파일 위치 입니다. 기본 destination 
        def package_file
          @package_file ||= File.join(destination, configuration[:package_file])
        end
	
        def build_option
          @build_option ||= configuration[:build_option] || "" 
        end
        
        # Should return the command(s) necessary to obtain the source code
        # locally.
        def command
          @command ||= case copy_strategy
            when :checkout
            source.checkout(revision, destination)
            when :export
            source.export(revision, destination)
            when :sync
            source.sync(revision, destination)
          end
        end
        
        # The directory to which the copy should be checked out
        def tmpdir
          @tmpdir ||= configuration[:copy_dir] || Dir.tmpdir
        end
        
        # The directory on the remote server to which the archive should be
        # copied
        def remote_dir
          @remote_dir ||= configuration[:copy_remote_dir] || "/tmp"
        end
        
        # The location on the remote server where the file should be
        # temporarily stored.
        def remote_filename
          @remote_filename ||= File.join(remote_dir, "#{File.basename(configuration[:package_file])}")
        end
        
      end
      
    end
    
  end
end
