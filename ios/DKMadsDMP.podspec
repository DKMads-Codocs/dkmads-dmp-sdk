Pod::Spec.new do |s|
  s.name         = 'DKMadsDMP'
  s.version      = '0.1.0'
  s.summary      = 'DKMads DMP iOS SDK'
  s.homepage     = 'https://dmp.dkmads.com'
  s.license      = { :type => 'MIT' }
  s.author       = { 'DKMads' => 'support@dkmads.com' }
  s.source       = { :git => 'https://github.com/DKMads-Company-Limited/dmp.dkmads.com.git', :tag => s.version.to_s }
  s.platform     = :ios, '14.0'
  s.swift_version = '5.9'
  s.source_files = 'Sources/DKMadsDMP/**/*.swift'
  s.frameworks = 'AppTrackingTransparency', 'AdSupport'
  s.info_plist = { 'NSUserTrackingUsageDescription' => 'This identifier is used to deliver personalized ads and measure campaign performance.' }
end
