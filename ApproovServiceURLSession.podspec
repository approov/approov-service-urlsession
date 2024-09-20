Pod::Spec.new do |s|
  s.name         = 'ApproovServiceURLSession'
  s.version      = '1.0.0'
  s.summary      = 'Approov Service URLSession for watchOS'
  s.description  = <<-DESC
                    This is the Approov Service URLSession library for watchOS.
                    DESC
  s.homepage     = 'https://github.com/approov/approov-service-urlsession'
  s.license      = { :type => 'MIT', :file => 'LICENSE' }
  s.author       = { 'Approov' => 'support@approov.io' }
  s.source       = { :git => 'https://github.com/approov/approov-service-urlsession.git', :branch => 'watchOS' }
  s.watchos.deployment_target = '7.0'

  s.swift_versions = ['5']
  s.source_files = 'Sources/ApproovURLSession/**/*.{swift}'
  s.requires_arc = true
   # Exclude architectures for watchOS and watchOS simulator
<<<<<<< HEAD
   s.pod_target_xcconfig = {
=======
  s.pod_target_xcconfig = {
>>>>>>> efe22c295b7ab7de021e67db27ca0cbc414466a4
    'EXCLUDED_ARCHS[sdk=watchos*]' => 'i386 armv7k arm64',
    'EXCLUDED_ARCHS[sdk=watchsimulator*]' => 'i386 armv7k arm64',
    'FRAMEWORK_SEARCH_PATHS' => '$(inherited) $(PODS_ROOT)/Approov $(PODS_CONFIGURATION_BUILD_DIR)/ApproovServiceURLSession $(PODS_XCFRAMEWORKS_BUILD_DIR)/Approov/Frameworks'
  }
<<<<<<< HEAD
  s.frameworks = 'Approov'
=======
>>>>>>> efe22c295b7ab7de021e67db27ca0cbc414466a4
  # The Approov SDK dependency
  s.dependency 'Approov'
end

