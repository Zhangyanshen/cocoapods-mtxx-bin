require 'json'

module CBin
  module BuildAll
    class ZipFileHelper
      include Pod

      def initialize(pod_target, version, product_dir, build_as_framework = false)
        @pod_target = pod_target
        @version = version
        @product_dir = product_dir
        @build_as_framework = build_as_framework
      end

      # 上传静态库
      def upload_zip_lib
        Dir.chdir(@product_dir) do
          zip_file_name = "#{@pod_target.framework_name}.zip"
          zip_file = File.join(Dir.pwd, "#{zip_file_name}")
          unless File.exist?(zip_file)
            UI.info "#{Dir.pwd}目录下无 #{zip_file_name} 文件".red
            return false
          end
          UI.info "Uploading binary zip file #{@pod_target.root_spec.name} (#{@version || @pod_target.root_spec.version})".yellow do
            upload_url = CBin.config.binary_upload_url_str
            # upload_url = "http://localhost:8080/frameworks"
            command = "curl -F \"name=#{@pod_target.product_module_name}\" -F \"version=#{@version || @pod_target.root_spec.version}\" -F \"file=@#{zip_file}\" #{upload_url}"
            UI.info "#{command}"
            json = `#{command}`
            UI.info json
            error_code = JSON.parse(json)["error_code"]
            if error_code == 0
              Pod::UI.info "#{@pod_target.root_spec.name} (#{@pod_target.root_spec.version}) 上传成功".green
              return true
            else
              Pod::UI.info "#{@pod_target.root_spec.name} (#{@pod_target.root_spec.version}) 上传失败".red
              return false
            end
          end
        end
      end

      # 压缩静态库
      def zip_lib
        Dir.chdir(@product_dir) do
          input_library = "#{@pod_target.framework_name}"
          output_library = "#{@product_dir}/#{input_library}.zip"
          FileUtils.rm_f(output_library) if File.exist?(output_library)
          unless File.exist?(input_library)
            UI.info "没有需要压缩的二进制文件：#{input_library}".red
            return false
          end

          UI.info "Compressing #{input_library} into #{input_library}.zip".yellow do
            command = "zip --symlinks -r #{output_library} #{input_library}"
            UI.info "#{command}"
            `#{command}`
            unless File.exist?(output_library)
              UI.info "压缩 #{output_library} 失败".red
              return false
            end
            return true
          end
        end
      end

    end
  end
end
