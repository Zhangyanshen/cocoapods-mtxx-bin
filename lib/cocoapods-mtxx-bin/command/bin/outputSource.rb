require 'cocoapods-mtxx-bin/helpers/buildAll/builder'
require 'cocoapods-mtxx-bin/helpers/buildAll/podspec_util'
require 'cocoapods-mtxx-bin/helpers/buildAll/zip_file_helper'
require 'cocoapods-mtxx-bin/helpers/buildAll/bin_helper'
require 'cocoapods-mtxx-bin/config/config'
require 'yaml'
require 'digest'

module Pod
  class Command
    class Bin < Command
      class OutputSource < Bin
        self.summary = '输出各个组件的source源，默认输出全部组件的source'
        self.description = <<-DESC
          #{summary}
        DESC

        def self.options
          [
            %w[--error-source 过滤异常的source，比如http的，CI打包只支持SSH认证]
          ].concat(super).uniq
        end

        def initialize(argv)
          @error_source = argv.flag?('error-source', false)
          super
        end

        def run
          # 开始时间
          @start_time = Time.now.to_i
          # 更新repo仓库
          repo_update
          # 分析依赖
          @analyze_result = analyse
          # 打印source
          show_cost_source
          # 计算耗时
          show_cost_time
        end

        private

        # 打印source
        def show_cost_source
          all_source_list = []
          error_source_list = []
          @analyze_result.specifications.each do |specification|
            next if specification.subspec?
            all_source_list << specification.source
            if @error_source && verified_git_address(specification)
              error_source_list << specification.name + '  ' + specification.source[:git] + + '  ' + specification.source[:tag]
            end
          end
          if @error_source
            UI.info '问题组件，source 为http CI打包不支持http认证，应修改为ssh'.red
            UI.info error_source_list.to_s.red
          else
            UI.info '输出所有pod组件source'.green
            UI.info error_source_list.to_s.green
          end
        end

        # git clone 地址 是否非法
        def verified_git_address(specification)
          return false if specification.source[:git].nil?
          git = specification.source[:git]
          git.include?('http://techgit.meitu.com') || git.include?('https://techgit.meitu.com')
        end

        # 打印耗时
        def show_cost_time
          return if @start_time.nil?
          UI.info "总耗时：#{Time.now.to_i - @start_time}s".green
        end

        # 更新repo仓库
        def repo_update
          if @repo_update
            UI.title 'Repo update'.green do
              return if podfile.nil?
              sources_manager = Pod::Config.instance.sources_manager
              podfile.sources.uniq.map do |src|
                # next if src.include?(CDN) || src.include?(MASTER_HTTP) || src.include?(MASTER_SSH)
                next unless src.include?(MT_REPO)
                UI.message "Update repo: #{src}"
                source = sources_manager.source_with_name_or_url(src)
                source.update(false)
              end
            end
          end
        end

        # 获取 podfile
        def podfile
          @podfile ||= begin
                         podfile_path = File.join(Pathname.pwd, 'Podfile')
                         raise 'Podfile不存在' unless File.exist?(podfile_path)
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
                          lock_path = File.join(Pathname.pwd, 'Podfile.lock')
                          raise 'Podfile.lock不存在，请执行pod install' unless File.exist?(lock_path)
                          Lockfile.from_file(Pathname.new(lock_path))
                        end
        end

        # 获取 sandbox
        def sandbox
          @sandbox ||= begin
                         sandbox_path = File.join(Pathname.pwd, 'Pods')
                         raise 'Pods文件夹不存在，请执行pod install' unless File.exist?(sandbox_path)
                         Pod::Sandbox.new(sandbox_path)
                       end
        end

        # 根据podfile和podfile.lock分析依赖
        def analyse
          UI.title 'Analyze dependencies'.green do
            analyzer = Pod::Installer::Analyzer.new(
              sandbox,
              podfile,
              lockfile
            )
            analyzer.analyze(true)
          end
        end
      end
    end
  end
end
