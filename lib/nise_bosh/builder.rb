require 'yaml'
require 'erb'

module NiseBosh
  class Builder
    def initialize(options, logger)
      check_ruby_version
      initialize_ip_address(options)
      initialize_options(options)
      initialize_release_file
      initialize_depoy_config

      @logger = logger
      @index ||=  @options[:index] || 0

      Bosh::Director::Config.set_nise_bosh(self)
      Bosh::Agent::Config.set_nise_bosh(self)
    end

    attr_reader :logger
    attr_reader :options

    def check_ruby_version
      if RUBY_VERSION < '1.9.0'
        raise "Ruby 1.9.0 or higher is required. Your Ruby version is #{RUBY_VERSION}"
      end
    end

    def initialize_ip_address(options)
      @ip_address = options[:ip_address]
      @ip_address ||= %x[ip -4 -o address show].match('inet ([\d.]+)/.*? scope global') { |md| md[1] }
    end

    def initialize_options(options)
      @options = options
      @options[:repo_dir] = File.expand_path(@options[:repo_dir])
      raise "Release repository does not exist." unless File.exists?(@options[:repo_dir])

    end

    def initialize_release_file
      config_dir = File.join(@options[:repo_dir], "config")

      final_config_path = File.join(config_dir, "final.yml")
      final_name = File.exists?(final_config_path) ? YAML.load_file(final_config_path)["final_name"] : nil
      final_index_path = File.join(@options[:repo_dir], "releases", "index.yml")
      final_index = File.exists?(final_index_path) ? YAML.load_file(final_index_path)["builds"] : {}

      dev_config_path = File.join(config_dir, "dev.yml")
      dev_name = File.exists?(dev_config_path) ? YAML.load_file(dev_config_path)["dev_name"] : nil
      dev_index_path = File.join(@options[:repo_dir], "dev_releases", "index.yml")
      dev_index = File.exists?(dev_index_path) ? YAML.load_file(dev_index_path)["builds"] : {}

      if @options[:release_file].nil? && final_index.size == 0 && dev_index.size == 0
        raise "No release index found!\nTry `bosh cleate release` in your release repository."
      end
      newest_release = get_newest_release(final_index.merge(dev_index).map {|k, v| v["version"]})

      begin
        @release_file = @options[:release_file] ||
          (newest_release.split("-")[1] == "dev" ?
          File.join(@options[:repo_dir], "dev_releases", "#{dev_name}-#{newest_release}.yml"):
          File.join(@options[:repo_dir], "releases", "#{final_name}-#{newest_release}.yml"))
        @release = YAML.load_file(@release_file)
        @spec = @release["packages"].inject({}){|h, e| h[e["name"]] = e; h}
      rescue
        raise "Faild to load release file!"
      end
    end

    def get_newest_release(index)
      sort_release_version(index).last
    end

    def sort_release_version(index)
      result = index.map {|v| v.to_s.split("-")}.sort do |(v1, v1_dev) , (v2, v2_dev)|
        (v1, v1_frc) = v1.split("."); (v2, v2_frc) = v2.split(".")
        v1_frc ||= "0"; v2_frc ||= "0"
        (v1 != v2) ? v1.to_i <=> v2.to_i :
          (v1_frc != v2_frc) ? v1_frc.to_i <=> v2_frc.to_i :
          (v1_dev == v2_dev) ? raise("Invalid index file") :
          (v2_dev == "dev") ? 1 :
          -1
      end
      result.map {|v| v[1] ? v.join("-") : v[0]}
    end

    def initialize_depoy_config()
      if @options[:deploy_config]
        begin
          @deploy_config = YAML.load_file(@options[:deploy_config])
        rescue
          raise "Deploy config file not found!"
        end

        # default values
        @deploy_config["name"] ||= "dummy"
        @deploy_config["releases"] ||= [{"name" => @release["name"], "version" => @release["version"]}]
        @deploy_config["networks"] ||= [{"name" => "default", "subnets" => [{"range" => "#{@ip_address}/24", "cloud_properties" => {"name" => "DUMMY_VLAN"}, "static" => ["#{@ip_address} - #{@ip_address}"]}]}]
        @deploy_config["compilation"] ||= {"workers" => 1, "network" => "default", "cloud_properties" => {}}
        @deploy_config["update"] ||= {"canaries" => 1, "max_in_flight" => 1, "canary_watch_time" => "1-2", "update_watch_time" => "1-2"}
        @deploy_config["resource_pools"] ||= [{"name" => "default", "size" => 9999, "cloud_properties" => {}, "stemcell"=> {"name" => "dummy", "version" => "dummy"}, "network" => "default"}]
      end
    end


    def archive(job, archive_name = nil)
      cleanup_working_directory()
      release_dir = File.join(@options[:working_dir], "release")
      FileUtils.mkdir_p(release_dir)

      resolve_dependency(job_all_packages(job)).each do |package|
        copy_release_file_relative(find_package_archive(package), release_dir)
      end

      job_templates(job).each do |job_template|
        copy_release_file_relative(find_job_template_archive(job_template), release_dir)
      end

      FileUtils.cp(@release_file, File.join(@options[:working_dir], "release.yml"))

      default_name = "#{@release["name"]}-#{job}-#{@release["version"]}.tar.gz"
      out_file_name = archive_name ? (File.directory?(archive_name) ? File.join(archive_name, default_name) : archive_name ) : default_name
      system("tar -C #{@options[:working_dir]} -cvzf #{out_file_name} . > /dev/null")
    end

    def cleanup_working_directory()
      FileUtils.rm_rf(@options[:working_dir])
      FileUtils.mkdir_p(@options[:working_dir])
    end

    def copy_release_file_relative(from_path, to_release_dir)
      to_path = File.join(to_release_dir, from_path[@options[:repo_dir].length..-1])
      FileUtils.mkdir_p(File.dirname(to_path))
      FileUtils.cp_r(from_path, to_path)
    end

    def find_jobs_release(name)
      find_by_name(@release["jobs"], name)
    end

    def find_job_template_archive(name)
      job = find_jobs_release(name)
      v = job["version"]
      major, minor = v.to_s.split("-")
      file_name = File.join(@options[:repo_dir],
        minor == "dev" ? ".dev_builds" : ".final_builds",
        "jobs",
        name,
        "#{v}.tgz")
      unless File.exists?(file_name)
        raise "Job template archive for #{name} not found in #{file_name}."
      end
      File.expand_path(file_name)
    end

    def find_package_archive(package)
      v = @spec[package]["version"]
      major, minor = v.to_s.split("-")
      file_name = File.join(@options[:repo_dir],
        minor == "dev" ? ".dev_builds" : ".final_builds",
        "packages",
        package,
        "#{v}.tgz")
      unless File.exists?(file_name)
        raise "Package archive for #{package} not found in #{file_name}."
      end
      File.expand_path(file_name)
    end

    def install_packages(packages, no_dependency = false)
      unless no_dependency
        @logger.info("Resolving package dependencies...")
        resolved_packages = resolve_dependency(packages)
      else
        resolved_packages = packages
      end
      @logger.info("Installing the following packages: ")
      resolved_packages.each do |package|
        @logger.info(" * #{package}")
      end
      resolved_packages.each do |package|
        @logger.info("Installing package #{package}")
        install_package(package)
      end
    end

    def install_package(package)
      version_file = File.join(@options[:install_dir], "packages", package, ".version")
      current_version = nil
      if File.exists?(version_file)
        current_version = File.read(version_file).strip
      end
      if @options[:force_compile] || current_version != @spec[package]["version"].to_s
        FileUtils.rm_rf(version_file)
        run_packaging(package)
        File.open(version_file, 'w') do |file|
          file.puts(@spec[package]["version"].to_s)
        end
      else
        @logger.info("The same version of the package is already installed. Skipping")
      end
    end

    def run_packaging(name)
      @logger.info("Running the packaging script for #{name}")
      package = find_by_name(@release["packages"], name)
      Bosh::Agent::Message::CompilePackage.process([
          "dummy_blob",
          package["sha1"],
          name,
          package["version"],
          []
        ])
    end

    def resolve_dependency(packages, resolved_packages = [], trace = [])
      packages.each do |package|
        next if resolved_packages.include?(package)
        t = Array.new(trace) << package
        deps = @spec[package]["dependencies"] || []
        unless (deps & t).empty?
          raise "Detected a cyclic dependency"
        end
        resolve_dependency(deps, resolved_packages, t)
        resolved_packages << package
      end
      return resolved_packages
    end

    def package_exists?(package)
      File.exists?(File.join(@options[:repo_dir], "packages", package))
    end

    def install_job(job_name, template_only = false)
      job_sepc = find_by_name(@deploy_config["jobs"], job_name)
      job_sepc["resource_pool"] ||= "default"
      job_sepc["instances"] ||= 1
      job_sepc["networks"] ||= [{"name" => "default", "static_ips" => [@ip_address]}]

      Bosh::Director::DeploymentPlan::Template.set_nise_bosh(self)

      deployment_plan = Bosh::Director::DeploymentPlan.new(@deploy_config)
      deployment_plan.parse

      deployment_plan_compiler = Bosh::Director::DeploymentPlanCompiler.new(deployment_plan)
      deployment_plan_compiler.bind_properties
      deployment_plan_compiler.bind_instance_networks

      target_job = deployment_plan.jobs[deployment_plan.jobs.index { |job| job.name == job_name }]

      Bosh::Director::JobUpdater.new(deployment_plan, target_job).update
      apply_spec = target_job.instances[0].spec
      apply_spec["index"] = @index

      unless template_only
        install_packages(target_job.send("run_time_dependencies"))
      end

      Bosh::Agent::Message::Apply.process([apply_spec])
    end

    def job_template_spec(job_template_name)
      YAML.load(`tar -Oxzf #{find_job_template_archive(job_template_name)} ./job.MF`)
    end

    def job_templates(job_name)
      templates = find_by_name(@deploy_config["jobs"], job_name)["template"]
      templates = [templates] if templates.is_a? String
      templates
    end

    def job_template_packages(job_template_name)
      job_template_spec(job_template_name)["packages"]
    end

    def job_all_packages(job_name)
      job_templates(job_name).inject([]) { |i, template|
        i += job_template_packages(template)
      }.uniq
   end

    def job_exists?(name)
      !find_by_name(@deploy_config["jobs"], name).nil?
    end

    def find_by_name(set, name)
      if set.is_a? Array
        index = set.index do |item|
          (item.respond_to?("name") ?
            item.name :
            (item["name"] || item[:name])
          ) == name
        end
      end
      if index.nil?
        nil
      else
        set[index]
      end
    end

  end
end
