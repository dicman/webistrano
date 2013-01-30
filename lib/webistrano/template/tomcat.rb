module Webistrano
  module Template
    module Tomcat
      
      CONFIG = Webistrano::Template::Base::CONFIG.dup.merge({
        :deploy_via => :java,
        :use_sudo =>  false,
        :java_home => 'Absolute path to Java Home Directory, because using jar, e.g. /usr/java',
        :build_strategy => 'choose :ant or :maven',
        :copy_dir => 'scm checkout directory',
        :package_file => 'Relative path to war or jar filename, e.g. test.war or target/test.war',
        :tomcat_home => 'Absolute path to Tomcat Home, e.g. /path/to/tomcat',
        :tomcat_log => 'Absolute path to Tomcat log, e.g. /path/to/tomcat/logs/catalina.out',
        :nginx_home => 'Absolute path to Nginx Home Directory, e.g. /path/to/nginx',
        :nginx_init_script => 'Absolute path to Nginx init script, e.g. /path/to/nginx/sbin/nginx',
        :tomcat_startup_script => "Absolute path to Tomcat startup, e.g. nohup /path/to/tomcat/bin/startup.sh",
        :tomcat_startup_check_text => "Startup check message, e.g. Server startup",
        :tomcat_shutdown_script => "Absolute path to Tomcat shutdown, e.g. /path/to/tomcat/bin/shutdown.sh",
        :tomcat_shutdown_check_text => "Shutdown check message, e.g. org.apache.catalina.startup.Bootstrap start",
        :tomcat_startup_timeout => "90",
        :tomcat_shutdown_timeout => "30",
        :tomcat_restart_delay_time => "10"
      }).freeze


      DESC = <<-'EOS'
        Template for use in Java, Tomcat, Apache  for application servers.
        Uses default Capistrano tasks.
      EOS
      
      #  copy from http://github.com/leehambley/railsless-deploy/tree/master to line  23 ~ 285 
      TASKS = Webistrano::Template::Base::TASKS + <<-'EOS'


def make_tomcat_startup_script
  _run_script = ERB.new <<-CMD
#!/usr/bin/env bash
if [ -e #{tomcat_log} ]; then
  set +o noclobber;
  mv #{tomcat_log} #{tomcat_log}.#{Time.now.strftime('%Y%m%d-%H%M%S')}
  cat /dev/null > #{tomcat_log};
fi;
export PATH=#{java_home}/bin:$PATH
#{'nohup ' unless tomcat_startup_script.start_with? 'nohup'}#{tomcat_startup_script};
sleep 2;
count=0;
until [ $(cat #{tomcat_log} 2> /dev/null | grep '#{tomcat_startup_check_text}' | wc -l) -eq 1 ] || [ $count -gt #{tomcat_startup_timeout} ]; do
  let count=$count+1;
  echo "waiting for tomcat to startup: ${count}s";
  sleep 1;
done;
if [ $count -gt #{tomcat_startup_timeout} ]; then
  echo "TIME OUT: Please check the Tomcat's status manually." 1>&2;
fi;
  CMD

  _run_script.result
end

def make_tomcat_shutdown_script
  _run_script = ERB.new <<-CMD
#!/usr/bin/env bash
#{tomcat_shutdown_script};
sleep 2;
count=0;
until [ $(pgrep -f "#{tomcat_shutdown_check_text}" | wc -l) -eq 0 ] || [ $count -gt #{tomcat_shutdown_timeout} ]; do
  let count=$count+1;
  echo "waiting for tomcat to shutdown: ${count}s";
  sleep 1;
done;
if [ $(pgrep -f "#{tomcat_shutdown_check_text}" | wc -l) -gt 0 ] && [ $count -gt #{tomcat_shutdown_timeout} ]; then
  pkill -9 -f '#{tomcat_shutdown_check_text}';
  echo "TIME OUT: Kill Tomcat process forcefully.";
fi;
  CMD

  _run_script.result
end


namespace :deploy do
  desc <<-DESC
            Deploys your project. This calls both `update' and `restart'. Note that \
            this will generally only work for applications that have already been deployed \
            once. For a "cold" deploy, you'll want to take a look at the `deploy:cold' \
            task, which handles the cold start specifically.
          DESC
  task :default do
    update
    restart
  end
  
  desc <<-DESC
            Prepares one or more servers for deployment. Before you can use any \
            of the Capistrano deployment tasks with your project, you will need to \
            make sure all of your servers have been prepared with `cap deploy:setup'. When \
            you add a new server to your cluster, you can easily run the setup task \
            on just that server by specifying the HOSTS environment variable:
       
              $ cap HOSTS=new.server.com deploy:setup
       
            It is safe to run this task on servers that have already been set up; it \
            will not destroy any deployed revisions or data.
          DESC
  task :setup, :except => { :no_release => true } do
    dirs = [deploy_to, releases_path, shared_path]
    dirs += shared_children.map { |d| File.join(shared_path, d) }
    run "#{try_sudo} mkdir -p #{dirs.join(' ')} && #{try_sudo} chmod g+w #{dirs.join(' ')}"
  end
  
  desc <<-DESC
            Copies your project and updates the symlink. It does this in a \
            transaction, so that if either `update_code' or `symlink' fail, all \
            changes made to the remote servers will be rolled back, leaving your \
            system in the same state it was in before `update' was invoked. Usually, \
            you will want to call `deploy' instead of `update', but `update' can be \
            handy if you want to deploy, but not immediately restart your application.
          DESC
  task :update do
    transaction do
      update_code
      symlink
    end
  end
  
  desc <<-DESC
            Copies your project to the remote servers. This is the first stage \
            of any deployment; moving your updated code and assets to the deployment \
            servers. You will rarely call this task directly, however; instead, you \
            should call the `deploy' task (to do a complete deploy) or the `update' \
            task (if you want to perform the `restart' task separately).
       
            You will need to make sure you set the :scm variable to the source \
            control software you are using (it defaults to :subversion), and the \
            :deploy_via variable to the strategy you want to use to deploy (it \
            defaults to :checkout).
          DESC
  task :update_code, :except => { :no_release => true } do
    on_rollback { run "rm -rf #{release_path}; true" }
    strategy.deploy!
    finalize_update
  end
  
  desc <<-DESC
            [internal] Touches up the released code. This is called by update_code \
            after the basic deploy finishes. It assumes a Rails project was deployed, \
            so if you are deploying something else, you may want to override this \
            task with your own environment's requirements.
       
            This task will make the release group-writable (if the :group_writable \
            variable is set to true, which is the default). It will then set up \
            symlinks to the shared directory for the log, system, and tmp/pids \
            directories, and will lastly touch all assets in public/images, \
            public/stylesheets, and public/javascripts so that the times are \
            consistent (so that asset timestamping works).  This touch process \
            is only carried out if the :normalize_asset_timestamps variable is \
            set to true, which is the default.
          DESC
  task :finalize_update, :except => { :no_release => true } do
    run "chmod -R g+w #{latest_release}" if fetch(:group_writable, true)
  end
  
  desc <<-DESC
            Updates the symlink to the most recently deployed version. Capistrano works \
            by putting each new release of your application in its own directory. When \
            you deploy a new version, this task's job is to update the `current' symlink \
            to point at the new version. You will rarely need to call this task \
            directly; instead, use the `deploy' task (which performs a complete \
            deploy, including `restart') or the 'update' task (which does everything \
            except `restart').
          DESC
  task :symlink, :except => { :no_release => true } do
    on_rollback do
      if previous_release
        run "rm -f #{current_path}; ln -s #{previous_release} #{current_path}; true"
      else
        logger.important "no previous release to rollback to, rollback of symlink skipped"
      end
    end
    
    run "rm -f #{current_path} && ln -s #{latest_release} #{current_path}"
  end
  
  desc <<-DESC
            Copy files to the currently deployed version. This is useful for updating \
            files piecemeal, such as when you need to quickly deploy only a single \
            file. Some files, such as updated templates, images, or stylesheets, \
            might not require a full deploy, and especially in emergency situations \
            it can be handy to just push the updates to production, quickly.
       
            To use this task, specify the files and directories you want to copy as a \
            comma-delimited list in the FILES environment variable. All directories \
            will be processed recursively, with all files being pushed to the \
            deployment servers.
       
              $ cap deploy:upload FILES=templates,controller.rb
       
            Dir globs are also supported:
       
              $ cap deploy:upload FILES='config/nginx/*.conf'
          DESC
  task :upload, :except => { :no_release => true } do
    files = (ENV["FILES"] || "").split(",").map { |f| Dir[f.strip] }.flatten
    abort "Please specify at least one file or directory to update (via the FILES environment variable)" if files.empty?
    
    files.each { |file| top.upload(file, File.join(current_path, file)) }
  end
  
  desc <<-DESC
            Build Project And upload Files 
            
            upload_files=WEB-INF/vm,WEB-INF/js/*.js
            
            
          DESC
  task :build_upload, :expect => { :no_release => true } do
    strategy.build_upload!
  end
  
  namespace :rollback do
    desc <<-DESC
              [internal] Points the current symlink at the previous revision.
              This is called by the rollback sequence, and should rarely (if
              ever) need to be called directly.
            DESC
    task :revision, :except => { :no_release => true } do
      if previous_release
        run "rm #{current_path}; ln -s #{previous_release} #{current_path}"
      else
        abort "could not rollback the code because there is no prior release"
      end
    end

    
    desc <<-DESC
              [internal] Removes the most recently deployed release.
              This is called by the rollback sequence, and should rarely
              (if ever) need to be called directly.
            DESC
    task :cleanup, :except => { :no_release => true } do
      run "if [ `readlink #{current_path}` != #{current_release} ]; then rm -rf #{current_release}; fi"
    end
    
    desc <<-DESC
              Rolls back to the previously deployed version. The `current' symlink will \
              be updated to point at the previously deployed version, and then the \
              current release will be removed from the servers.
            DESC
    task :code, :except => { :no_release => true } do
      revision
      cleanup
    end
    
    desc <<-DESC
              Rolls back to a previous version and restarts. This is handy if you ever \
              discover that you've deployed a lemon; `cap rollback' and you're right \
              back where you were, on the previously deployed version.
            DESC
    task :default do
      revision
      cleanup
    end
  end
  
  desc <<-DESC
            Clean up old releases. By default, the last 5 releases are kept on each \
            server (though you can change this with the keep_releases variable). All \
            other deployed revisions are removed from the servers. By default, this \
            will use sudo to clean up the old releases, but if sudo is not available \
            for your environment, set the :use_sudo variable to false instead.
          DESC
  task :cleanup, :except => { :no_release => true } do
    count = fetch(:keep_releases, 5).to_i
    if count >= releases.length
      logger.important "no old releases to clean up"
    else
      logger.info "keeping #{count} of #{releases.length} deployed releases"
      
      directories = (releases - releases.last(count)).map { |release|
        File.join(releases_path, release) }.join(" ")
      
      try_sudo "rm -rf #{directories}"
    end
  end
  
  desc <<-DESC
            Test deployment dependencies. Checks things like directory permissions, \
            necessary utilities, and so forth, reporting on the things that appear to \
            be incorrect or missing. This is good for making sure a deploy has a \
            chance of working before you actually run `cap deploy'.
       
            You can define your own dependencies, as well, using the `depend' method:
       
              depend :remote, :gem, "tzinfo", ">=0.3.3"
              depend :local, :command, "svn"
              depend :remote, :directory, "/u/depot/files"
          DESC
  task :check, :except => { :no_release => true } do
    dependencies = strategy.check!
    
    other = fetch(:dependencies, {})
    other.each do |location, types|
      types.each do |type, calls|
        if type == :gem
          dependencies.send(location).command(fetch(:gem_command, "gem")).or("`gem' command could not be found. Try setting :gem_command")
        end
        
        calls.each do |args|
          dependencies.send(location).send(type, *args)
        end
      end
    end
    
    if dependencies.pass?
      puts "You appear to have all necessary dependencies installed"
    else
      puts "The following dependencies failed. Please check them and try again:"
      dependencies.reject { |d| d.pass? }.each do |d|
        puts "--> #{d.message}"
      end
      abort
    end
  end
  
  desc <<-DESC
            Deploys and starts a `cold' application. This is useful if you have not \
            deployed your application before, or if your application is (for some \
            other reason) not currently running. It will deploy the code, run any \
            pending migrations, and then instead of invoking `deploy:restart', it will \
            invoke `deploy:start' to fire up the application servers.
          DESC
  task :cold do
    update
  end
  
  namespace :pending do
    desc <<-DESC
              Displays the `diff' since your last deploy. This is useful if you want \
              to examine what changes are about to be deployed. Note that this might \
              not be supported on all SCM's.
            DESC
    task :diff, :except => { :no_release => true } do
      system(source.local.diff(current_revision))
    end
    
    desc <<-DESC
              Displays the commits since your last deploy. This is good for a summary \
              of the changes that have occurred since the last deploy. Note that this \
              might not be supported on all SCM's.
            DESC
    task :default, :except => { :no_release => true } do
      from = source.next_revision(current_revision)
      system(source.local.log(from))
    end
  end
  
  desc <<-DESC
            Rollback & Restart 
          DESC
  task :rollback_and_restart, :except => { :no_release => true } do
    rollback.default
    restart
  end
  
  desc <<-DESC
            Restart Apache & Tomcat 
            Job According to Apache Stop -> Tomcat Stop -> Tomcat Start -> Sleep 5 -> Apache Start
            Because, Sleep 5 is Reduce Load to Tomcat Server
          DESC
  task :restart, :except => { :no_release => true } do
    nginx.stop
    tomcat.stop
    tomcat.start
    nginx.start
  end
  
  namespace :nginx do
    
    desc <<-DESC
            start nginx
            DESC
    task :start, :except => { :no_release => true } do
      sudo "#{nginx_init_script}"
    end
    
    desc <<-DESC
            stop nginx
            DESC
    task :stop, :except => { :no_release => true } do
      sudo "#{nginx_init_script} -s stop"
    end
    
    desc <<-DESC
            restart nginx
            DESC
    task :restart, :except => { :no_release => true } do
      sudo "#{nginx_init_script} -s stop; sudo #{nginx_init_script}"
    end

    desc <<-DESC
            reload nginx
            DESC
    task :reload, :except => { :no_release => true } do
      sudo "#{nginx_init_script} -s reload"
    end
    
    desc <<-DESC
            graceful nginx
            DESC
    task :graceful, :except => { :no_release => true } do
      sudo "kill -HUP `cat #{nginx_home}/logs/nginx.pid`"
    end
    
  end  
  
  namespace :tomcat do  
    desc <<-DESC
              Before set tomcat_init_script, tomcat_init_script script must implement star, stop command
            DESC
    task :default, :except => { :no_release => true } do
      tomcat.restart
    end
    
  
    desc <<-DESC
              start tomcat
            DESC
    task :start, :except => { :no_release => true } do
      on_rollback { find_and_execute_task("deploy:tomcat:stop") }

      _temp_shell = "/tmp/strano_tomcat_start.sh" 
      put make_tomcat_startup_script, _temp_shell, :mode => 0744
      run(_temp_shell) { |channel, stream, data| abort "TIME OUT" if data =~ /TIME OUT: Please check the Tomcat/ }
      run "rm -f #{_temp_shell}"
    end
    
    desc <<-DESC
              stop tomcat
            DESC
    task :stop, :except => { :no_release => true } do
      _temp_shell = "/tmp/strano_tomcat_stop.sh"
      put make_tomcat_shutdown_script, _temp_shell, :mode => 0744
      run _temp_shell
      run "rm -f #{_temp_shell}"
    end
    
    desc <<-DESC
              stop and start tomcat
            DESC
    task :restart, :except => { :no_release => true } do
      transaction do
        tomcat.stop
        system("sleep #{tomcat_restart_delay_time}")
        tomcat.start
      end
    end
  end
  
end
      EOS
      
    end
  end
end
