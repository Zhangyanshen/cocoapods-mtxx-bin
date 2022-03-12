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

        CDN = 'https://cdn.cocoapods.org/'.freeze
        MASTER_HTTP = 'https://github.com/CocoaPods/Specs.git'.freeze
        MASTER_SSH = 'git@github.com:CocoaPods/Specs.git'.freeze
        MT_REPO = 'techgit.meitu.com'.freeze

        self.summary = '根据壳工程打包所有依赖组件为静态库（static framework）'
        self.description = <<-DESC
          #{self.summary}
        DESC

        def self.options
          [
            %w[--clean 删除编译临时目录],
            %w[--repo-update 更新Podfile中指定的repo仓库]
          ].concat(super).uniq
        end

        def initialize(argv)
          @clean = argv.flag?('clean', false )
          @repo_update = argv.flag?('repo-update', false )
          @base_dir = "#{Pathname.pwd}/build_pods"
          super
        end

        def run
          # 读取配置文件
          read_config
          # 更新repo仓库
          repo_update
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
          UI.title "Read config from file `BinConfig.yaml`".green do
            config_file = File.join(Dir.pwd, 'BinConfig.yaml')
            return unless File.exist?(config_file)
            config = YAML.load(File.open(config_file))
            return if config.nil?
            build_config = config['build_config']
            return if build_config.nil?
            @pre_build = build_config['pre_build']
            @post_build = build_config['post_build']
            @black_list = build_config['black_list']
            @write_list = build_config['write_list']
          end
        end

        # 更新repo仓库
        def repo_update
          UI.title "Repo update".green do
            return if podfile.nil?
            sources_manager = Pod::Config.instance.sources_manager
            podfile.sources.map { |src|
              # next if src.include?(CDN) || src.include?(MASTER_HTTP) || src.include?(MASTER_SSH)
              next unless src.include?(MT_REPO)
              UI.message "Update repo: #{src}"
              source = sources_manager.source_with_name_or_url(src)
              source.update(false )
            }
          end if @repo_update
        end

        # 执行pre build
        def pre_build
          UI.title "Execute the command of pre build".green do
            system(@pre_build)
          end if @pre_build
        end

        # 执行post build
        def post_build(results)
          UI.title "Execute the command of post build".green do
            system(@post_build)
          end if @post_build
        end

        # 获取 podfile
        def podfile
          @podfile ||= begin
                         podfile_path = File.join(Pathname.pwd,"Podfile")
                         raise "Podfile不存在" unless File.exist?(podfile_path)
                         sources_manager = Pod::Config.instance.sources_manager
                         podfile = Podfile.from_file(Pathname.new(podfile_path))
                         podfile_hash = podfile.to_hash
                         podfile_hash['sources'] = (podfile_hash['sources'] || []).concat(sources_manager.code_source_list.map(&:url))
                         podfile_hash['sources'] << sources_manager.binary_source.url
                         podfile_hash['sources'].uniq!
                         Podfile.from_hash(podfile_hash)
                       end
        end

        # 获取 podfile.lock
        def lockfile
          @lockfile ||= begin
                          lock_path = File.join(Pathname.pwd,"Podfile.lock")
                          raise "Podfile.lock不存在，请执行pod install" unless File.exist?(lock_path)
                          Lockfile.from_file(Pathname.new(lock_path))
                        end
        end

        # 获取 sandbox
        def sandbox
          @sandbox ||= begin
                         sandbox_path = File.join(Pathname.pwd, "Pods")
                         raise "Pods文件夹不存在，请执行pod install" unless File.exist?(sandbox_path)
                         Pod::Sandbox.new(sandbox_path)
                       end
        end

        # 根据podfile和podfile.lock分析依赖
        def analyse
          UI.title "Analyze dependencies".green do
            analyzer = Pod::Installer::Analyzer.new(
              sandbox,
              podfile,
              lockfile
            )
            analyzer.analyze(true )
          end
        end

        # 删除编译产物
        def clean_build_pods
          UI.title "Clean build pods".green do
            build_path = Dir.pwd + "/build"
            FileUtils.rm_rf(build_path) if File.exist?(build_path)
            build_pods_path = Dir.pwd + "/build_pods"
            FileUtils.rm_rf(build_pods_path) if File.exist?(build_pods_path)
          end
        end

        # 构建所有pod_targets
        def build_pod_targets
          UI.title "Build all pod targets".green do
            pod_targets = @analyze_result.pod_targets.uniq
            success_pods = []
            fail_pods = []
            local_pods = []
            external_pods = []
            binary_pods = []
            created_pods = []
            pod_targets.map do |pod_target|
              begin
                version = BinHelper.version(pod_target.pod_name, pod_target.version, @analyze_result.specifications)
                # 本地库
                if @sandbox.local?(pod_target.pod_name)
                  local_pods << pod_target.pod_name
                  show_skip_tip("#{pod_target.pod_name} 是本地库")
                  next
                end
                # 外部源（如 git）
                if @sandbox.checkout_sources[pod_target.pod_name]
                  external_pods << pod_target.pod_name
                  show_skip_tip("#{pod_target.pod_name} 以external方式引入")
                  next
                end
                # 无源码
                if !@sandbox.local?(pod_target.pod_name) && !pod_target.should_build?
                  binary_pods << pod_target.pod_name
                  show_skip_tip("#{pod_target.pod_name} 无需编译")
                  next
                end
                # 已经有相应的二进制版本
                if has_created_binary?(pod_target.pod_name, version)
                  created_pods << pod_target.pod_name
                  show_skip_tip("#{pod_target.pod_name}(#{version}) 已经有二进制版本了")
                  next
                end
                # 是否跳过编译（黑名单、白名单）
                next if skip_build?(pod_target)
                # 构建产物
                builder = Builder.new(pod_target, @sandbox.checkout_sources)
                result = builder.build
                fail_pods << pod_target.pod_name unless result
                next unless result
                builder.create_binary
                # 压缩并上传zip
                zip_helper = ZipFileHelper.new(pod_target, version, builder.product_dir, builder.build_as_framework)
                result = zip_helper.zip_lib
                fail_pods << pod_target.pod_name unless result
                next unless result
                result = zip_helper.upload_zip_lib
                fail_pods << pod_target.pod_name unless result
                next unless result
                # 生成二进制podspec并上传
                podspec_creator = PodspecUtil.new(pod_target, version, builder.build_as_framework)
                bin_spec = podspec_creator.create_binary_podspec
                bin_spec_file = podspec_creator.write_binary_podspec(bin_spec)
                podspec_creator.push_binary_podspec(bin_spec_file)
                success_pods << pod_target.pod_name
              rescue Pod::StandardError => e
                UI.info "#{pod_target} 编译失败，原因：#{e}".red
                fail_pods << pod_target.pod_name
                next
              end
            end
            results = {
              'Total' => pod_targets,
              'Success' => success_pods,
              'Fail' => fail_pods,
              'Local' => local_pods,
              'External' => external_pods,
              'No Source File' => binary_pods,
              'Created Binary' => created_pods,
              'Black List' => @black_list || [],
              'Write List' => @write_list || []
            }
            show_results(results)
            results
          end
        end

        def show_skip_tip(title)
          UI.info title.yellow
        end

        # 是否跳过编译
        def skip_build?(pod_target)
          (!@black_list.nil? && @black_list.include?(pod_target.pod_name)) ||
            (!@write_list.nil? && !@write_list.empty? && !@write_list.include?(pod_target.pod_name))
        end

        # 展示结果
        def show_results(results)
          UI.title "打包结果：".green do
            UI.info "——————————————————————————————————".green
            UI.info "|#{"Type".center(20)}|#{"Count".center(11)}|".green
            UI.info "——————————————————————————————————".green
            results.each do |key, value|
              UI.info "|#{key.center(20)}|#{value.size.to_s.center(11)}|".green
            end
            UI.info "——————————————————————————————————".green

            # 打印出失败的 target
            unless results['Fail'].empty?
              UI.info "\n打包失败的库：#{results['Fail']}".red
            end
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
