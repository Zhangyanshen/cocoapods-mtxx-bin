require 'cocoapods/installer/project_cache/target_metadata.rb'
require 'parallel'
require 'cocoapods'
require 'xcodeproj'
require 'cocoapods-mtxx-bin/native/pod_source_installer'

module Pod
  class Installer
    alias old_create_pod_installer create_pod_installer
    def create_pod_installer(pod_name)
      installer = old_create_pod_installer(pod_name)
      installer.installation_options = installation_options
      installer
    end

    alias old_install_pod_sources install_pod_sources
    def install_pod_sources
      if installation_options.install_with_multi_threads
        install_pod_sources_with_multiple_threads
      else
        old_install_pod_sources
      end
    end

    # 多线程下载
    def install_pod_sources_with_multiple_threads
      @installed_specs = []
      pods_to_install = sandbox_state.added | sandbox_state.changed
      title_options = { :verbose_prefix => '-> '.green }
      thread_count = installation_options.multi_threads_count
      Parallel.each(root_specs.sort_by(&:name), in_threads: thread_count) do |spec|
        if pods_to_install.include?(spec.name)
          if sandbox_state.changed.include?(spec.name) && sandbox.manifest
            current_version = spec.version
            previous_version = sandbox.manifest.version(spec.name)
            has_changed_version = current_version != previous_version
            current_repo = analysis_result.specs_by_source.detect { |key, values| break key if values.map(&:name).include?(spec.name) }
            current_repo &&= (Pod::TrunkSource::TRUNK_REPO_NAME if current_repo.name == Pod::TrunkSource::TRUNK_REPO_NAME) || current_repo.url || current_repo.name
            previous_spec_repo = sandbox.manifest.spec_repo(spec.name)
            has_changed_repo = !previous_spec_repo.nil? && current_repo && !current_repo.casecmp(previous_spec_repo).zero?
            title = "Installing #{spec.name} #{spec.version}"
            title << " (was #{previous_version} and source changed to `#{current_repo}` from `#{previous_spec_repo}`)" if has_changed_version && has_changed_repo
            title << " (was #{previous_version})" if has_changed_version && !has_changed_repo
            title << " (source changed to `#{current_repo}` from `#{previous_spec_repo}`)" if !has_changed_version && has_changed_repo
          else
            title = "Installing #{spec}"
          end
          UI.titled_section(title.green, title_options) do
            install_source_of_pod(spec.name)
          end
        else
          UI.section("Using #{spec}", title_options[:verbose_prefix]) do
            create_pod_installer(spec.name)
          end
        end
      end
    end

    # alias old_write_lockfiles write_lockfiles
    # def write_lockfiles
    #   old_write_lockfiles
    #   if File.exist?('Podfile_local')
    #
    #     project = Xcodeproj::Project.open(config.sandbox.project_path)
    #     #获取主group
    #     group = project.main_group
    #     group.set_source_tree('SOURCE_ROOT')
    #     #向group中添加 文件引用
    #     file_ref = group.new_reference(config.sandbox.root + '../Podfile_local')
    #     #podfile_local排序
    #     podfile_local_group = group.children.last
    #     group.children.pop
    #     group.children.unshift(podfile_local_group)
    #     #保存
    #     project.save
    #   end
    # end
  end

  module Downloader
    class Cache
      # 多线程锁
      @@lock = Mutex.new

      # 后面如果要切到进程的话，可以在 cache root 里面新建一个文件
      # 利用这个文件 lock
      # https://stackoverflow.com/questions/23748648/using-fileflock-as-ruby-global-lock-mutex-for-processes

      # rmtree 在多进程情况下可能  Directory not empty @ dir_s_rmdir 错误
      # old_ensure_matching_version 会移除不是同一个 CocoaPods 版本的组件缓存
      alias old_ensure_matching_version ensure_matching_version
      def ensure_matching_version
        @@lock.synchronize do
          version_file = root + 'VERSION'
          # version = version_file.read.strip if version_file.file?

          # root.rmtree if version != Pod::VERSION && root.exist?
          root.mkpath

          version_file.open('w') { |f| f << Pod::VERSION }
        end
      end
    end
  end
end
