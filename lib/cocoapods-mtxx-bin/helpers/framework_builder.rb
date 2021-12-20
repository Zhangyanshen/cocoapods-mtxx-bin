# copy from https://github.com/CocoaPods/cocoapods-packager

require 'cocoapods-mtxx-bin/helpers/framework.rb'
require 'English'
require 'cocoapods-mtxx-bin/config/config_builder'
require 'shellwords'

module CBin
  class Framework
    class Builder
      include Pod
#Debug下还待完成
      def initialize(spec, installer, platform, source_dir, isRootSpec = true, build_model="Release")
        @spec = spec
        @source_dir = source_dir
        @installer = installer
        @platform = platform
        @build_model = build_model
        @isRootSpec = isRootSpec

        @file_accessors = @installer.pod_targets.select { |t| t.pod_name == @spec.name }.flat_map(&:file_accessors) if installer
      end

      # 利用xcodebuild打包
      def build
        defines = compile
        build_sim_libraries(defines)

        defines
      end

      def lipo_create(defines)
        # 合并静态库
        merge_static_libs
        # 拷贝资源文件
        copy_resources
        # 拷贝swiftmodule
        copy_swiftmodules
        # 拷贝动态库
        copy_dynamic_libs
        # 拷贝最终产物
        copy_target_product
        # 返回Framework目录
        framework
      end

      private

      # 拷贝最终产物
      def copy_target_product
        framework
        fwk = "#{build_device_dir}/#{@spec.name}.framework"
        `cp -r #{fwk} #{framework.root_path}`
      end

      # 拷贝动态库
      def copy_dynamic_libs
        dynamic_libs = vendored_dynamic_libraries
        if dynamic_libs && dynamic_libs.size > 0
          des_dir = "#{build_device_dir}/#{@spec.name}.framework/fwks"
          FileUtils.mkdir(des_dir) unless File.exist?(des_dir)
          dynamic_libs.map do |lib|
            `cp -r #{lib} #{des_dir}`
          end
        end
      end

      # 拷贝swiftmodule
      def copy_swiftmodules
        swift_module = "#{build_device_dir}/#{@spec.name}.framework/Modules/#{@spec.name}.swiftmodule"
        if File.exist?(swift_module)
          src_swift = "#{build_sim_dir}/#{@spec.name}.framework/Modules/#{@spec.name}.swiftmodule"
          `cp -af #{src_swift}/* #{swift_module}`
          `cp -af #{src_swift}/Project/* #{swift_module}/Project`
        end
      end

      # 拷贝资源文件
      def copy_resources
        bundle = "#{build_device_dir}/#{@spec.name}.bundle"
        if File.exist?(bundle)
          `cp -r #{bundle} #{build_device_dir}/#{@spec.name}.framework`
        end
      end

      # 合并静态库
      def merge_static_libs
        # 合并真机静态库
        merge_static_libs_for_device if @isRootSpec
        # 合并模拟器静态库
        merge_static_libs_for_sim if @isRootSpec
        # 合并真机和模拟器
        merge_device_sim
      end

      # 合并真机和模拟器
      def merge_device_sim
        libs = static_libs_in_sandbox + static_libs_in_sandbox(build_sim_dir)
        output = "#{build_device_dir}/#{@spec.name}.framework/#{@spec.name}"
        `lipo -create -output #{output} #{libs.join(' ')}`
      end

      # 合并真机静态库
      def merge_static_libs_for_device
        static_libs = static_libs_in_sandbox + vendored_static_libraries
        libs = ios_architectures.map do |arch|
          library = "#{build_device_dir}/package-#{@spec.name}-#{arch}.a"
          `libtool -arch_only #{arch} -static -o #{library} #{static_libs.join(' ')}`
          library
        end
        output = "#{build_device_dir}/#{@spec.name}.framework/#{@spec.name}"
        `lipo -create -output #{output} #{libs.join(' ')}`
      end

      # 合并模拟器静态库
      def merge_static_libs_for_sim
        static_libs = static_libs_in_sandbox(build_sim_dir) + vendored_static_libraries
        libs = ios_architectures_sim.map do |arch|
          library = "#{build_sim_dir}/package-#{@spec.name}-#{arch}.a"
          `libtool -arch_only #{arch} -static -o #{library} #{static_libs.join(' ')}`
          library
        end
        output = "#{build_sim_dir}/#{@spec.name}.framework/#{@spec.name}"
        `lipo -create -output #{output} #{libs.join(' ')}`
      end

      # 真机路径
      def build_device_dir
        'build-device'
      end

      # 模拟器路径
      def build_sim_dir
        'build-simulator'
      end

      # 获取静态库
      def vendored_static_libraries
        return [] if @file_accessor.nil?
        file_accessors = @file_accessors
        libs = file_accessors.flat_map(&:vendored_static_frameworks).map { |f| f + f.basename('.*') } || []
        libs += file_accessors.flat_map(&:vendored_static_libraries)
        @vendored_static_libraries = libs.compact.map(&:to_s)
        @vendored_static_libraries
      end

      # 获取动态库
      def vendored_dynamic_libraries
        return [] if @file_accessor.nil?
        file_accessors = @file_accessors
        libs = file_accessors.flat_map(&:vendored_dynamic_frameworks) || []
        libs += file_accessors.flat_map(&:vendored_dynamic_libraries)
        @vendored_dynamic_libraries = libs.compact.map(&:to_s)
        @vendored_dynamic_libraries
      end

      # 获取静态库
      def static_libs_in_sandbox(build_dir = build_device_dir)
        Dir.glob("#{build_dir}/#{@spec.name}.framework/#{@spec.name}")
      end

      # 真机CPU架构
      def ios_architectures
        archs = %w[arm64]
        vendored_static_libraries.each do |library|
          archs = `lipo -info #{library}`.split & archs
        end
        archs
      end

      # 模拟器CPU架构
      def ios_architectures_sim
        archs = %w[x86_64]
        vendored_static_libraries.each do |library|
          archs = `lipo -info #{library}`.split & archs
        end
        archs
      end

      # 真机编译（只支持 arm64）
      def compile
        defines = "GCC_PREPROCESSOR_DEFINITIONS='$(inherited)'"
        defines += ' '
        defines += @spec.consumer(@platform).compiler_flags.join(' ')

        options = "ARCHS=\'#{ios_architectures.join(' ')}\' OTHER_CFLAGS=\'-fembed-bitcode -Qunused-arguments\'"
        xcodebuild(defines, options, build_device_dir, @build_model)

        defines
      end

      # 模拟器编译（只支持 x86-64）
      def build_sim_libraries(defines)
        if @platform.name == :ios
          options = "-sdk iphonesimulator ARCHS=\'#{ios_architectures_sim.join(' ')}\'"
          xcodebuild(defines, options, build_sim_dir, @build_model)
        end
      end

      def target_name
        # 区分多平台，如配置了多平台，会带上平台的名字
        # 如libwebp-iOS
        if @spec.available_platforms.count > 1
          "#{@spec.name}-#{Platform.string_name(@spec.consumer(@platform).platform_name)}"
        else
          @spec.name
        end
      end

      # 调用 xcodebuild 编译
      def xcodebuild(defines = '', args = '', build_dir = 'build', build_model = 'Release')
        unless File.exist?("Pods.xcodeproj") #cocoapods-generate v2.0.0
          command = "xcodebuild #{defines} #{args} CONFIGURATION_BUILD_DIR=#{File.join(File.expand_path("..", build_dir), File.basename(build_dir))} clean build -configuration #{build_model} -target #{target_name} -project ./Pods/Pods.xcodeproj 2>&1"
        else
          command = "xcodebuild #{defines} #{args} CONFIGURATION_BUILD_DIR=#{build_dir} clean build -configuration #{build_model} -target #{target_name} -project ./Pods.xcodeproj 2>&1"
        end

        UI.message "command = #{command}"
        output = `#{command}`.lines.to_a

        if $CHILD_STATUS.exitstatus != 0
          raise <<~EOF
            Build command failed: #{command}
            Output:
            #{output.map { |line| "    #{line}" }.join}
          EOF

          Process.exit
        end
      end

      def framework
        @framework ||= begin
                         framework = Framework.new(@spec.name, @platform.name.to_s)
                         framework.make
                         framework
                       end
      end

      # ---------- 以下方法无用 -------------

      def is_debug_model
        @build_model == "Debug"
      end

      def build_static_library_for_ios(output)
        static_libs = static_libs_in_sandbox('build') + static_libs_in_sandbox('build-simulator') + @vendored_libraries
        # if is_debug_model
        ios_architectures.map do |arch|
          static_libs += static_libs_in_sandbox("build-#{arch}") + @vendored_libraries
        end
        ios_architectures_sim do |arch|
          static_libs += static_libs_in_sandbox("build-#{arch}") + @vendored_libraries
        end
        # end

        build_path = Pathname("build")
        build_path.mkpath unless build_path.exist?

        # if is_debug_model
        libs = (ios_architectures + ios_architectures_sim) .map do |arch|
          # library = "build-#{arch}/lib#{target_name}.a"
          library = "build-#{arch}/#{target_name}.framework/#{target_name}"
          library
        end
        # else
        #   libs = ios_architectures.map do |arch|
        #     library = "build/package-#{@spec.name}-#{arch}.a"
        #     # libtool -arch_only arm64 -static -o build/package-armv64.a build/libIMYFoundation.a build-simulator/libIMYFoundation.a
        #     # 从liBFoundation.a 文件中，提取出 arm64 架构的文件，命名为build/package-armv64.a
        #     UI.message "libtool -arch_only #{arch} -static -o #{library} #{static_libs.join(' ')}"
        #     `libtool -arch_only #{arch} -static -o #{library} #{static_libs.join(' ')}`
        #     library
        #   end
        # end

        UI.message "lipo -create -output #{output} #{libs.join(' ')}"
        `lipo -create -output #{output} #{libs.join(' ')}`
      end

      def cp_to_source_dir
        framework_name = "#{@spec.name}.framework"
        target_dir = File.join(CBin::Config::Builder.instance.zip_dir,framework_name)
        FileUtils.rm_rf(target_dir) if File.exist?(target_dir)

        zip_dir = CBin::Config::Builder.instance.zip_dir
        FileUtils.mkdir_p(zip_dir) unless File.exist?(zip_dir)

        `cp -fa #{framework.root_path}/#{framework_name} #{target_dir}`
      end

      def copy_headers
        #走 podsepc中的public_headers
        public_headers = Array.new

        #by slj 如果没有头文件，去 "Headers/Public"拿
        # if public_headers.empty?
        spec_header_dir = "./Headers/Public/#{@spec.name}"
        unless File.exist?(spec_header_dir)
          spec_header_dir = "./Pods/Headers/Public/#{@spec.name}"
        end
        return unless File.exist?(spec_header_dir)
        # raise "copy_headers #{spec_header_dir} no exist " unless File.exist?(spec_header_dir)
        Dir.chdir(spec_header_dir) do
          headers = Dir.glob('*.h')
          headers.each do |h|
            public_headers << Pathname.new(File.join(Dir.pwd,h))
          end
        end
        # end

        # UI.message "Copying public headers #{public_headers.map(&:basename).map(&:to_s)}"

        public_headers.each do |h|
          `ditto #{h} #{framework.headers_path}/#{h.basename}`
        end

        # If custom 'module_map' is specified add it to the framework distribution
        # otherwise check if a header exists that is equal to 'spec.name', if so
        # create a default 'module_map' one using it.
        if !@spec.module_map.nil?
          module_map_file = @file_accessor.module_map
          if Pathname(module_map_file).exist?
            module_map = File.read(module_map_file)
          end
        elsif public_headers.map(&:basename).map(&:to_s).include?("#{@spec.name}.h")
          module_map = <<-MAP
          framework module #{@spec.name} {
            umbrella header "#{@spec.name}.h"

            export *
            module * { export * }
          }
          MAP
        end

        unless module_map.nil?
          UI.message "Writing module map #{module_map}"
          unless framework.module_map_path.exist?
            framework.module_map_path.mkpath
          end
          File.write("#{framework.module_map_path}/module.modulemap", module_map)
        end
      end

      def copy_license
        UI.section "Copying license #{@spec}" do
          license_file = @spec.license[:file] || 'LICENSE'
          `cp "#{license_file}" .` if Pathname(license_file).exist?
        end
      end

      # def copy_resources
      #   UI.section "copy_resources #{@spec}" do
      #     resource_dir = './build/*.bundle'
      #     resource_dir = './build-armv7/*.bundle' if File.exist?('./build-armv7')
      #     resource_dir = './build-arm64/*.bundle' if File.exist?('./build-arm64')
      #
      #     bundles = Dir.glob(resource_dir)
      #
      #     bundle_names = [@spec, *@spec.recursive_subspecs].flat_map do |spec|
      #       consumer = spec.consumer(@platform)
      #       consumer.resource_bundles.keys +
      #         consumer.resources.map do |r|
      #           File.basename(r, '.bundle') if File.extname(r) == 'bundle'
      #         end
      #     end.compact.uniq
      #
      #     bundles.select! do |bundle|
      #       bundle_name = File.basename(bundle, '.bundle')
      #       bundle_names.include?(bundle_name)
      #     end
      #
      #     if bundles.count > 0
      #       UI.message "Copying bundle files #{bundles}"
      #       bundle_files = bundles.join(' ')
      #       `cp -rp #{bundle_files} #{framework.resources_path} 2>&1`
      #     end
      #
      #     real_source_dir = @source_dir
      #     unless @isRootSpec
      #       spec_source_dir = File.join(Dir.pwd,"#{@spec.name}")
      #       unless File.exist?(spec_source_dir)
      #         spec_source_dir = File.join(Dir.pwd,"Pods/#{@spec.name}")
      #       end
      #       raise "copy_resources #{spec_source_dir} no exist " unless File.exist?(spec_source_dir)
      #
      #       real_source_dir = spec_source_dir
      #     end
      #     resources = [@spec, *@spec.recursive_subspecs].flat_map do |spec|
      #       expand_paths(real_source_dir, spec.consumer(@platform).resources)
      #     end.compact.uniq
      #
      #     if resources.count == 0 && bundles.count == 0
      #       framework.delete_resources
      #       return
      #     end
      #
      #     if resources.count > 0
      #       #把 路径转义。 避免空格情况下拷贝失败
      #       escape_resource = []
      #       resources.each do |source|
      #         escape_resource << Shellwords.join(source)
      #       end
      #       UI.message "Copying resources #{escape_resource}"
      #       `cp -rp #{escape_resource.join(' ')} #{framework.resources_path}`
      #     end
      #   end
      # end

      def expand_paths(source_dir, path_specs)
        path_specs.map do |path_spec|
          Dir.glob(File.join(source_dir, path_spec))
        end
      end
    end
  end
end
