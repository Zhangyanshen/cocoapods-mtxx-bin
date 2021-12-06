require 'cocoapods'
require 'cocoapods-mtxx-bin/gem_version'

if Pod.match_version?('~> 1.4')
  require 'cocoapods-mtxx-bin/native/podfile'
  require 'cocoapods-mtxx-bin/native/installation_options'
  require 'cocoapods-mtxx-bin/native/specification'
  require 'cocoapods-mtxx-bin/native/path_source'
  require 'cocoapods-mtxx-bin/native/analyzer'
  require 'cocoapods-mtxx-bin/native/installer'
  require 'cocoapods-mtxx-bin/native/podfile_generator'
  require 'cocoapods-mtxx-bin/native/pod_source_installer'
  require 'cocoapods-mtxx-bin/native/linter'
  require 'cocoapods-mtxx-bin/native/resolver'
  require 'cocoapods-mtxx-bin/native/source'
  require 'cocoapods-mtxx-bin/native/validator'
  require 'cocoapods-mtxx-bin/native/acknowledgements'
  require 'cocoapods-mtxx-bin/native/sandbox_analyzer'
  require 'cocoapods-mtxx-bin/native/podspec_finder'
  require 'cocoapods-mtxx-bin/native/file_accessor'
  require 'cocoapods-mtxx-bin/native/pod_target_installer'
  require 'cocoapods-mtxx-bin/native/target_validator'

end
