
module CBin
  module BuildAll
    class PodspecUtil
      include Pod

      def initialize(pod_target, version, build_as_framework = false )
        @pod_target = pod_target
        @version = version
        @build_as_framework = build_as_framework
      end

      # 创建二进制podspec
      def create_binary_podspec
        UI.info "创建二进制podspec：#{@pod_target}".yellow
        spec = @pod_target.root_spec.to_hash
        root_dir = @pod_target.framework_name
        # 处理版本号
        spec['version'] = version
        # 处理source
        spec['source'] = source
        # 处理头文件
        spec['source_files'] = "#{root_dir}/Headers/*.h"
        spec['public_header_files'] = "#{root_dir}/Headers/*.h"
        spec['private_header_files'] = "#{root_dir}/PrivateHeaders/*.h"
        # 处理vendored_libraries和vendored_frameworks
        spec['vendored_libraries'] = "#{root_dir}/libs/*.a"
        spec['vendored_frameworks'] = %W[#{root_dir} #{root_dir}/fwks/*.framework]
        # 处理资源
        resources = %W[#{root_dir}/*.{#{special_resource_exts.join(',')}} #{root_dir}/resources/*]
        spec['resources'] = resources
        # 删除无用的字段
        delete_unused(spec)
        # 处理subspecs
        handle_subspecs(spec)
        # 生成二进制podspec
        bin_spec = Pod::Specification.from_hash(spec)
        bin_spec.description = <<-EOF
         「converted automatically by plugin cocoapods-mtxx-bin @美图 - zys」
          #{bin_spec.description}
        EOF
        bin_spec
        # puts bin_spec.to_json
      end

      # podspec写入文件
      def write_binary_podspec(spec)
        UI.info "写入podspec：#{@pod_target}".yellow
        podspec_dir = "#{Pathname.pwd}/build_pods/#{@pod_target}/Products/podspec"
        FileUtils.mkdir(podspec_dir) unless File.exist?(podspec_dir)
        file = "#{podspec_dir}/#{@pod_target.pod_name}.podspec.json"
        FileUtils.rm_rf(file) if File.exist?(file)

        File.open(file, "w+") do |f|
          f.write(spec.to_pretty_json)
        end
        file
      end

      # 上传二进制podspec
      def push_binary_podspec(binary_podsepc_json)
        UI.info "推送podspec：#{@pod_target}".yellow
        return unless File.exist?(binary_podsepc_json)
        repo_name = Pod::Config.instance.sources_manager.binary_source.name
        # repo_name = 'example-private-spec-bin'
        argvs = %W[#{repo_name} #{binary_podsepc_json} --skip-import-validation --use-libraries --allow-warnings --verbose]

        push = Pod::Command::Repo::Push.new(CLAide::ARGV.new(argvs))
        push.validate!
        push.run
      end

      private

      # 删除无用的字段
      def delete_unused(spec)
        spec.delete('project_header_files')
        spec.delete('resource_bundles')
        spec.delete('exclude_files')
        spec.delete('preserve_paths')
        spec.delete('prepare_command')
      end

      # 处理subspecs
      def handle_subspecs(spec)
        if spec['subspecs'] && spec['subspecs'].size > 0
          # 全部的subspecs
          spec_names = @pod_target.specs.map(&:name).select { |spec_name| spec_name.include?('/') }.map { |spec_name| spec_name.split('/')[1] }
          spec['subspecs'] = spec['subspecs'].select { |subspec| spec_names.include?(subspec['name']) }
          bin_subspec = {
            'name' => 'Binary',
            'source_files' => spec['source_files'],
            'public_header_files' => spec['public_header_files'],
            'private_header_files' => spec['private_header_files'],
            'vendored_frameworks' => spec['vendored_frameworks'],
            'vendored_libraries' => spec['vendored_libraries'],
            'resources' => spec['resources']
          }
          spec['subspecs'] << bin_subspec
          spec['subspecs'].map do |subspec|
            next if subspec['name'] == 'Binary'
            # 处理单个subspec
            handle_single_subspec(subspec)
            # 递归处理subspec
            recursive_handle_subspecs(subspec['subspecs'])
          end
        end
      end

      # 递归处理subspecs
      def recursive_handle_subspecs(subspecs)
        return unless subspecs && subspecs.size > 0
        subspecs.map do |s|
          # 处理单个subspec
          handle_single_subspec(s)
          # 递归处理
          handle_subspecs(s['subspecs'])
        end
      end

      # 处理单个subspec
      def handle_single_subspec(subspec)
        subspec.delete('source_files')
        subspec.delete('public_header_files')
        subspec.delete('project_header_files')
        subspec.delete('private_header_files')
        subspec.delete('vendored_frameworks')
        subspec.delete('vendored_libraries')
        subspec.delete('resource_bundles')
        subspec.delete('resources')
        subspec.delete('exclude_files')
        subspec.delete('preserve_paths')
        if subspec['dependencies']
          subspec['dependencies']["#{@pod_target.pod_name}/Binary"] = []
        else
          subspec['dependencies'] = {"#{@pod_target.pod_name}/Binary": []}
        end
      end

      def source
        # url = "http://localhost:8080/frameworks/#{@pod_target.root_spec.module_name}/#{version}/zip"
        url = "#{CBin.config.binary_download_url_str}/#{@pod_target.root_spec.module_name}/#{version}/#{@pod_target.root_spec.module_name}.framework_#{version}.zip"
        { http: url, type: 'zip' }
      end

      def version
        @version || @pod_target.root_spec.version
      end

      # 特殊的资源后缀
      def special_resource_exts
        %w[momd mom cdm nib storyboardc]
      end

    end
  end
end
