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
  s.platform     = :watchos, '7.0'
  s.source_files = 'ApproovServiceURLSession/**/*.{h,m,swift}'
  s.requires_arc = true
end

