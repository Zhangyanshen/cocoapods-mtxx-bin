require 'cocoapods-mtxx-bin/config/config_hot_key_asker'

module Pod
  class Command
    class Bin < Command
      class Imy < Bin
        self.summary = '设置快捷键'
        self.description = <<-DESC
          设置快捷键
        DESC

        self.arguments = [
            CLAide::Argument.new('1', false)
        ]

        def self.options
          [
          ].concat(super)
        end

        def initialize(argv)
          @hot_key = argv.shift_argument || '1'
          super
        end

        def run
          CBin.config_hot_key.set_hot_key_index(@hot_key)
          UI.puts  "cd #{CBin.config_hot_key.hot_key_dir}".yellow

          if Dir.exist?(CBin.config_hot_key.hot_key_dir)
            Dir.chdir(CBin.config_hot_key.hot_key_dir) do
              UI.puts " #{CBin.config_hot_key.hot_key_cmd}".yellow
              system CBin.config_hot_key.hot_key_cmd
            end
          else
            raise "配置项中文件目录不存在 #{CBin.config_hot_key.hot_key_dir}"
          end


        end

      end
    end
  end
end
