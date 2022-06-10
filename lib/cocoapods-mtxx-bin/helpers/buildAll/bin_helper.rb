require 'digest'

module CBin
  module BuildAll
    class BinHelper
      include Pod

      # 二进制版本号（x.y.z.bin[md5前6位]）
      def self.version(pod_name, original_version, specifications)
        specs = specifications.map(&:name).select { |spec|
          spec.include?(pod_name) && !spec.include?('/Binary')
        }.sort!
        xcode_version = `xcodebuild -version`.split(' ').join('')
        specs << xcode_version
        specs_str = specs.join('')
        "#{original_version}.bin#{Digest::MD5.hexdigest(specs_str)[0,6]}"
      end

    end
  end
end
