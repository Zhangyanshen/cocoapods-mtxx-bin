require 'cocoapods-mtxx-bin/helpers/buildAll/builder'
require 'cocoapods-mtxx-bin/helpers/buildAll/podspec_util'
require 'cocoapods-mtxx-bin/helpers/buildAll/zip_file_helper'
require 'cocoapods-mtxx-bin/helpers/buildAll/bin_helper'
require 'yaml'
require 'digest'

module Pod
  class Command
    class Bin < Command
      class BuildAll < Bin
        include CBin::BuildAll

        self.summary = '根据壳工程打包所有依赖组件为静态库（static framework）'
        self.description = <<-DESC
          #{self.summary}
        DESC

        def self.options
          [
            %w[--clean 删除编译临时目录]
          ].concat(super).uniq
        end

        def initialize(argv)
          @clean = argv.flag?('clean', false )
          @base_dir = "#{Pathname.pwd}/build_pods"
          super
        end

        def run
          # 读取配置文件
          read_config
          # 执行pre_build命令
          pre_build
          # 分析依赖
          @analyze_result = analyse
          # 删除编译产物
          clean_build_pods
          # 编译所有pod_targets
          results = build_pod_targets
          # 执行post_build命令
          post_build(results)
          # 删除编译产物
          clean_build_pods if @clean
        end

        private

        # 读取配置文件
        def read_config
          config_file = File.join(Dir.pwd, 'BinConfig.yaml')
          return unless File.exist?(config_file)
          config = YAML.load(File.open(config_file))
          return if config.nil?
          build_config = config['build_config']
          return if build_config.nil?
          @pre_build = build_config['pre_build']
          @post_build = build_config['post_build']
          @black_list = build_config['black_list']
        end

        # 执行pre build
        def pre_build
          UI.title("Execute the command of pre build".green) do
            system(@pre_build)
          end if @pre_build
        end

        # 执行post build
        def post_build(results)
          UI.title("Execute the command of post build".green) do
            system(@post_build)
          end if @post_build
        end

        # 根据podfile和podfile.lock分析依赖
        def analyse
          UI.title("Analyze dependencies".green) do
            podfile_path = File.join(Pathname.pwd,"Podfile")
            raise "Podfile不存在" unless File.exist?(podfile_path)
            @podfile ||= Podfile.from_file(Pathname.new(podfile_path))

            lock_path = File.join(Pathname.pwd,"Podfile.lock")
            raise "Podfile.lock不存在，请执行pod install或pod update" unless File.exist?(lock_path)
            @lockfile ||= Lockfile.from_file(Pathname.new(lock_path))

            sandbox_path = Dir.pwd + '/Pods'
            @sandbox = Pod::Sandbox.new(sandbox_path)

            analyzer = Pod::Installer::Analyzer.new(
              @sandbox,
              @podfile,
              @lockfile
            )
            analyzer.analyze(false )
          end
        end

        # 删除编译产物
        def clean_build_pods
          build_path = Dir.pwd + "/build"
          FileUtils.rm_rf(build_path) if File.exist?(build_path)
          build_pods_path = Dir.pwd + "/build_pods"
          FileUtils.rm_rf(build_pods_path) if File.exist?(build_pods_path)
        end

        # 构建所有pod_targets
        def build_pod_targets
          UI.title("Build all pod targets".green) do
            pod_targets = @analyze_result.pod_targets.uniq
            success_pods = []
            fail_pods = []
            local_pods = []
            external_pods = []
            binary_pods = []
            created_pods = []
            pod_targets.map do |pod_target|
              version = BinHelper.version(pod_target.pod_name, pod_target.version, @analyze_result.specifications)
              local_pods << pod_target.pod_name if @sandbox.local?(pod_target.pod_name)
              external_pods << pod_target.pod_name if @sandbox.checkout_sources[pod_target.pod_name]
              binary_pods << pod_target.pod_name unless pod_target.should_build?
              # 已经有相应的二进制版本
              if has_created_binary?(pod_target.pod_name, version)
                created_pods << pod_target.pod_name
                UI.puts "#{pod_target.pod_name}(#{version}) 已经有二进制版本了".red
                next
              end
              next if skip_build?(pod_target)
              # 构建产物
              builder = Builder.new(pod_target, @sandbox.checkout_sources)
              result = builder.build
              fail_pods << "#{@podfile}" unless result
              next unless result
              builder.create_binary
              # 压缩并上传zip
              zip_helper = ZipFileHelper.new(pod_target, version, builder.product_dir, builder.build_as_framework)
              result = zip_helper.zip_lib
              fail_pods << "#{@podfile}" unless result
              next unless result
              result = zip_helper.upload_zip_lib
              fail_pods << "#{@podfile}" unless result
              next unless result
              # 生成二进制podspec并上传
              podspec_creator = PodspecUtil.new(pod_target, version, builder.build_as_framework)
              bin_spec = podspec_creator.create_binary_podspec
              bin_spec_file = podspec_creator.write_binary_podspec(bin_spec)
              podspec_creator.push_binary_podspec(bin_spec_file)
              success_pods << "#{@podfile}"
            end
            results = {
              'Total' => pod_targets,
              'Success' => success_pods,
              'Fail' => fail_pods,
              'Local' => local_pods,
              'External' => external_pods,
              'No Source File' => binary_pods,
              'Created Binary' => created_pods,
              'Black List' => @black_list || []
            }
            show_results(results)
            results
          end
        end

        # 是否跳过编译
        def skip_build?(pod_target)
          !pod_target.should_build? ||
            @sandbox.local?(pod_target.pod_name) ||
            @sandbox.checkout_sources[pod_target.pod_name] ||
            (!@black_list.nil? && @black_list.include?(pod_target.pod_name))
        end

        # 展示结果
        def show_results(results)
          puts "\n打包结果："
          UI.puts "——————————————————————————————————".green
          UI.puts "|#{"Type".center(20)}|#{"Count".center(11)}|".green
          UI.puts "——————————————————————————————————".green
          results.each do |key, value|
            UI.puts "|#{key.center(20)}|#{value.size.to_s.center(11)}|".green
          end
          UI.puts "——————————————————————————————————".green

          # 打印出失败的 target
          unless results['Fail'].empty?
            UI.puts "\n打包失败的库：#{results['Fail']}".red
          end
        end

        # 是否已经有二进制版本了
        def has_created_binary?(pod_name, version)
          return false if pod_name.nil? || version.nil?
          sources_manager = Config.instance.sources_manager
          binary_source = sources_manager.binary_source
          result = false
          begin
            specification = binary_source.specification(pod_name, version)
            result = true unless specification.nil?
          rescue Pod::StandardError => e
            result = false
          end
          result
        end

      end
    end
  end
end
