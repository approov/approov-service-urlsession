Pod::Spec.new do |s|
  s.name         = "ApproovURLSession"
  s.version      = "3.3.3"
  s.summary      = "Approov mobile attestation SDK"
  s.description  = <<-DESC
    Approov SDK integrates security attestation and secure string fetching for both iOS and watchOS apps.
  DESC
  s.homepage     = "https://approov.io"
  s.license      = { type: "Commercial", file: "LICENSE" }
  s.authors      = { "CriticalBlue, Ltd." => "support@approov.io" }
  s.source       = { git: "https://github.com/approov/approov-service-urlsession.git", tag: s.version }

  # Supported platforms
  s.ios.deployment_target = '12.0'
  s.watchos.deployment_target = '7.0'

  # Specify the source code paths for the combined target
  s.source_files = 'Sources/ApproovURLSession/**/*'

  s.dependency 'approov-ios-sdk', '3.3.3'

end
