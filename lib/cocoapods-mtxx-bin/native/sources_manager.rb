

require 'cocoapods'
require 'cocoapods-mtxx-bin/config/config'

module Pod
  class Source
    class Manager
      # 源码 source list
      def code_source_list
        CBin.config.code_repo_url_list.split(";").map { |source| source_with_name_or_url(source)}
      end
      # 二进制 source
      def binary_source
        source_with_name_or_url(CBin.config.binary_repo_url)
      end
    end
  end
end
