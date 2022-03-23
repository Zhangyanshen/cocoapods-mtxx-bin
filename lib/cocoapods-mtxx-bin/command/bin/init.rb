require 'cocoapods-mtxx-bin/config/config_asker'

module Pod
  class Command
    class Bin < Command
      class Init < Bin
        self.summary = '初始化插件'
        self.description = <<-DESC
          创建yml配置文件，保存插件需要的配置信息，如源码podspec仓库、二进制下载地址等
        DESC

        def self.options
          [
            %w[--bin-url=URL 配置文件地址，直接从此地址下载配置文件],
            ['--update-sources', '更新源码私有源配置 bin_dev.yml 中的 code_repo_url_list 配置,支持多私有源,多个私有源用分号区分  example：git@techgit.meitu.com:iMeituPic/mtsourcespecs.git;git@techgit.meitu.com:iosmodules/specs.git;https://github.com/CocoaPods/Specs.git']
          ].concat(super)
        end

        def initialize(argv)
          @bin_url = argv.option('bin-url')
          @update_sources = argv.flag?('update-sources')
          super
        end

        def run
          if @update_sources
            update_code_repo_url_list
          else
            if @bin_url.nil?
              config_with_asker
            else
              config_with_url(@bin_url)
            end
          end

        end

        private

        def config_with_url(url)
          require 'open-uri'

          UI.puts "开始下载配置文件...\n"
          file = open(url)
          contents = YAML.safe_load(file.read)

          UI.puts "开始同步配置文件...\n"
          CBin.config.sync_config(contents.to_hash)
          UI.puts "设置完成.\n".green
        rescue Errno::ENOENT => e
          raise Informative, "配置文件路径 #{url} 无效，请确认后重试."
        end

        def config_with_asker
          asker = CBin::Config::Asker.new
          asker.wellcome_message

          config = {}
          template_hash = CBin.config.template_hash
          template_hash.each do |k, v|
            default = begin
                        CBin.config.send(k)
                      rescue StandardError
                        nil
                      end
            config[k] = asker.ask_with_answer(v[:description], default, v[:selection])
          end

          CBin.config.sync_config(config)
          asker.done_message
        end
        def update_code_repo_url_list
          asker = CBin::Config::Asker.new
          config = {}
          template_hash = CBin.config.template_hash
          template_hash.each do |k, v|
            if k == "code_repo_url_list"
              default = begin
                          CBin.config.send(k)
                        rescue StandardError
                          nil
                        end
              config[k] = asker.ask_with_answer(v[:description], default, v[:selection])
            else
              config[k] =  CBin.config.config_old[k]
            end
          end
          CBin.config.sync_config_code_repo_url_list(config)
          asker.done_message_update
        end
      end
    end
  end
end
