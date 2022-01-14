require 'parallel'

module Pod
  class Command
    class Bin < Command
      class Repo < Bin
        class Update < Repo
          self.summary = '更新私有源'

          self.arguments = [
            CLAide::Argument.new('NAME', false)
          ]

          def self.options
            [
              ['--repo-update', '更新所有私有源，默认只更新二进制相关私有源'],
            ].concat(super)
          end

          def initialize(argv)
            @repo_update = argv.flag?('repo-update')
            @name = argv.shift_argument
            super
          end

          def run
            # show_output = !config.silent?
            if  @name &&  @repo_update
              valid_sources.map { |source|
                UI.message "更新私有源仓库 #{source.to_s}".yellow
                source.update(false )
               }
            end
          end
        end
      end
    end
  end
end
