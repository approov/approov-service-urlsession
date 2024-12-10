Pod::Spec.new do |s|
  s.name         = "ApproovURLSession"
  s.version      = "3.2.7"
  s.summary      = "Approov mobile attestation SDK"
  s.description  = <<-DESC
    Approov SDK integrates security attestation and secure string fetching for both iOS and watchOS apps.
  DESC
  s.homepage     = "https://approov.io"
  s.license      = { type: "Commercial", file: "LICENSE" }
  s.authors      = { "CriticalBlue, Ltd." => "support@approov.io" }
  s.source       = { git: "https://github.com/approov/approov-ios-sdk.git", tag: s.version }

  # Supported platforms
  s.ios.deployment_target = '11.0'
  s.watchos.deployment_target = '7.0'

  # Specify the source code paths for the combined target
  s.source_files = "Sources/ApproovURLSession/**/*.{swift,h}"

  # Vendored frameworks for both iOS and watchOS
  s.vendored_frameworks = 'Approov.xcframework'
  s.prepare_command = <<-CMD
    curl -L https://github.com/approov/approov-ios-sdk/releases/download/3.2.4/Approov.xcframework.zip > Approov.xcframework.zip
    unzip -o Approov.xcframework.zip
    rm -f Approov.xcframework.zip
  CMD
  
  # Approov dependency - pulling the binary from GitHub release
  ## Should be removed and not be a direct dependency
  #s.dependency "Approov", "~> 3.2.4"  # Specify the version here if a podspec exists

  # Pod target xcconfig settings if required
  s.pod_target_xcconfig = {
    'VALID_ARCHS' => 'arm64 x86_64 arm64_32 x86_64'  # Combine valid architectures
  }
end

