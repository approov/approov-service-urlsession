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
  s.exclude_archs = 'i386 armv7k arm64'
  # The Approov SDK dependency
  pod 'Approov', :podspec => 'https://raw.githubusercontent.com/approov/approov-watchos-sdk/refs/heads/main/Approov.podspec'
end

