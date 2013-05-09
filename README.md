[![Build Status](https://travis-ci.org/nttlabs/nise_bosh.png?branch=v1)](https://travis-ci.org/nttlabs/nise_bosh)
[![Code Climate](https://codeclimate.com/github/nttlabs/nise_bosh.png)](https://codeclimate.com/github/nttlabs/nise_bosh)

# Nise BOSH

## What's this?

Nise BOSH is a lightweight BOSH emulator. You can easily install multiple BOSH packages on your servers by Nise BOSH commands. 'Nise' means 'Pseudo' in Japanese.

## Links

* [Step by Step Guide on Cloud Foundry Blog](http://blog.cloudfoundry.com/2013/04/15/ntt-contributes-nise-bosh-a-tool-to-speed-up-bosh-development/)
* [Architecture Guide](http://www.slideshare.net/i_yudai/nise-bosh-in-action)

## Requirements

* Ubuntu 10.04, 12.04
 * Ubuntu 10.04 64bit is recmmended when you install cf-release jobs.
* Ruby 1.9.2 or higher
* Bundler

## How to use

### Install required gems

You can install the requried gems to execute Nise BOSH commands with bundler.

Run the command below:

    bundle install

### Release repository

Nise BOSH requries a clone of the 'release' repository you want to install (e.g. cf-release for Cloud Foundry). Clone the repository and checkout its submodules at your preferred directory.

    git clone git@github.com:cloudfoundry/cf-release.git
    cd cf-release
    git submodule sync
    git submodule update --init --recursive

### Build a release

You have to build a release of your release repository to create package tarballs.

If you have not installed BOSH CLI. You can install it with the `gem` command.

    gem install bosh_cli

Then build a release, this might take several minutes at the first run.

    bosh create release

You will be asked the name of the build, input the preferred name such as 'appcloud'.

The command generates "dev_releases" and ".dev_builds" directories in your cloned release directory. You can find the "release file" for the build at "dev_release/\<build_name\>-\<viersion\>-dev.yml", which includes the list of all the packages, jobs, and their dependencies.

Note that, when you have any modification in your release repository, you have to commit them once before buliding a new release. You might need to execute 'bosh create release ' with "--force" option when you have added new files into the blobs directory.

### Describe a deployment manifest

Nise-BOSH requires a deployment manifest, which contains the configuration of your release. The Nise-BOSH's manifest file is compatible with, or a subset of, BOSH's manifest format.

You can find an example at [Cloud foundry docs](http://docs.cloudfoundry.com/docs/running/deploying-cf/vsphere/cloud-foundry-example-manifest.html).

    ---
    properties:
      domain: vcap.me
    
      networks:
        apps: default
        management: default
    
      nats:
        user: nats
        password: nats
        address: 127.0.0.1
        port: 4222
    
      dea_next:
        streaming_timeout: 60
        memory_mb: 4096
        memory_overcommit_factor: 1
        disk_mb: 32000
        disk_overcommit_factor: 1
        num_instances: 30

### Run

Run `nise-bosh` command. You may want to run with 'sudo' and/or 'bundle exec'

    ./bin/nise-bosh <path_to_release_repository> <path_to_deploy_manifest> <job_name>

Example:

    sudo PATH=$PATH bundle exec ./bin/nise-bosh ~/cf-release ~/deploy.conf dea_next

### Initialize the environment (optional)

You need to install and create the required apt packages and users on your environemnt to execute certain job processes from cf-release. The original BOSH sets up the environment using a stemcell, but Nise-BOSH does not support it. You can simulate a stemcell-like environment on your server by executing the `bin/init` script.

    sudo ./bin/init

This script runs the minimal (sometimes insufficient) commands extracted from the stemcell-builder stages.

### Create stemcell_base.tar.gz (optional)

Some packages require the `/var/vcap/stemcell_base.tar.gz` file to create Warden containers. You can create the file by executing the `bin/gen-stemcell` script.

    sudo ./bin/gen-stemcell

### Launch processes

Once instllation is complete, you can launch job processes by the `run-job` command.

    ./bin/run-job start

This command automatically loads the monitrc file (default in: /var/vcap/bosh/etc/monitrc) and starts all the processes defined in it. You can also invoke stop and status commands by giving an option.

    ./bin/run-job status
    ./bin/run-job stop

## Command line options

### '-y': Assume yes as an answer to all prompts

Nise-BOSH does not ask any prompts.

### '-f': Force install packages

By default, Nise-BOSH does not re-install packages that are already installed. This option forces Nise BOSH to re-install all packages.

### '-d': Install directory

Nise-BOSH installs packages into this directory. The default value is `/var/vcap`. Be sure to change this value because some packages given by cf-release have hard-coded directory names in their packaging scripts and template files.

### '--working-dir': Temporary working directory

Nise-BOSH uses the given directory to run packaging scripts. The default value is `/tmp/nise_bosh`.

### '-t': Install template files only

Nise-BOSH does not install the required packages for the given job. Nise-BOSH only fills template files for the given job and writes them out to the install directory.

### '-r': Release file

Nise-BOSH uses the given release file for deploying. By default, Nise BOSH automatically detects the newest release file.

### '-n': IP address for the host

Nise-BOSH assumes the IP address of your host using 'ip' command by default. You can overwrite the value by this option.

### '-i': Index number for the host

Nise-BOSH assumes the index number of your host is assigned as 0 by default. When you install the same job on multiple hosts, you can set the index number with this option. The value "spec.index" in the job template files is replaced with this value.

### '-p': Install specific packages

Nise-BOSH installs the given packages, not a job. When this option is choosen, the file path for the deploy manifest file must be ommited.

Example:

    sudo PATH=$PATH bundle exec ./bin/nise-bosh -p ~/cf-release_interim dea_jvm dea_ruby

### '--no-dependency': Install no dependeny packages

Nise-BOSH does not install dependency packages. This option must be used with '-c' option.

### '-a': Create an archive file for a job

Nise-BOSH aggregates the packages and the index file required to install the given job and creates an archive file that includes them. This behavior is similar to 'bosh create release --with-tarball', but the generated archive file contains the minimum packages to install the given job.

## Appendix

### stemcell_base.tar.gz builder

You can generate stemcell_base.tar.gz for the rootfs of Warden containers by the 'gen-stemcell' command. Default config files are found in the config directory. Before executing, change the password for containers in config/stemcell-settings.sh.

    sudo ./bin/gen-stemcell [<output_filename_or_directory>]

The generated archive file is placed on /var/vcap/stemcell_base.tar.gz by default. You can change the path and other behaviour by the giving command line options shown by the '--help' option.

### init

You can install basic apt packages and create users for the BOSH stemcell with this command.

### bget

You can download objects from the blobstore for cf-release by using the 'bget' command.

    ./bin/bget -o <output_file_name> <object_id>

## License

Apache License Version 2.0

The original BOSH is developed by VMware, inc. and distributed under Apache License Version 2.0.
