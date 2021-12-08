

# copy from https://github.com/CocoaPods/cocoapods-packager

require 'cocoapods-mtxx-bin/native/podfile'
require 'cocoapods/command/gen'
require 'cocoapods/generate'
require 'cocoapods-mtxx-bin/helpers/framework_builder'
require 'cocoapods-mtxx-bin/helpers/library_builder'
require 'cocoapods-mtxx-bin/helpers/sources_helper'
require 'cocoapods-mtxx-bin/command/bin/repo/push'

module CBin
  class Upload
    class Helper
      include CBin::SourcesHelper

      def initialize(spec,code_dependencies,sources)
        @spec = spec
        @code_dependencies = code_dependencies
        @sources = sources
      end

      # 创建binary-template.podsepc
      # 上传二进制文件
      # 上传二进制 podspec
      def upload
        Dir.chdir(CBin::Config::Builder.instance.root_dir) do
          # 上传zip包
          res_zip = curl_zip
          if res_zip
            # 创建二进制podspec
            filename = spec_creator
            # 上传二进制 podspec
            push_binary_repo(filename)
          end
          res_zip
        end
      end

      # 创建二进制podspec
      def spec_creator
        spec_creator = CBin::SpecificationSource::Creator.new(@spec)
        # 创建二进制podspec
        spec_creator.create
        # 将二进制podspec写入文件
        spec_creator.write_spec_file
        # 返回二进制podspec文件路径
        spec_creator.filename
      end

      # 推送二进制
      # curl http://ci.xxx:9192/frameworks -F "name=IMYFoundation" -F "version=7.7.4.2" -F "annotate=IMYFoundation_7.7.4.2_log" -F "file=@bin_zip/bin_IMYFoundation_7.7.4.2.zip"
      def curl_zip
        zip_file = "#{CBin::Config::Builder.instance.library_file(@spec)}.zip"
        res = File.exist?(zip_file)
        unless res
          zip_file = CBin::Config::Builder.instance.framework_zip_file(@spec) + ".zip"
          res = File.exist?(zip_file)
        end
        if res
          print <<EOF
          上传二进制文件
          curl #{CBin.config.binary_upload_url} -F "name=#{@spec.name}" -F "version=#{@spec.version}" -F "annotate=#{@spec.name}_#{@spec.version}_log" -F "file=@#{zip_file}"
EOF
          `curl #{CBin.config.binary_upload_url} -F "name=#{@spec.name}" -F "version=#{@spec.version}" -F "annotate=#{@spec.name}_#{@spec.version}_log" -F "file=@#{zip_file}"` if res
        end

        res
      end

      # 上传二进制 podspec
      def push_binary_repo(binary_podsepc_json)
        argvs = [
            "#{binary_podsepc_json}",
            "--binary",
            "--sources=#{sources_option(@code_dependencies, @sources)},https:\/\/cdn.cocoapods.org",
            "--skip-import-validation",
            "--use-libraries",
            "--allow-warnings",
            "--verbose",
            "--code-dependencies"
        ]
        if @verbose
          argvs += ['--verbose']
        end

        push = Pod::Command::Bin::Repo::Push.new(CLAide::ARGV.new(argvs))
        push.validate!
        push.run
      end

    end
  end
end
