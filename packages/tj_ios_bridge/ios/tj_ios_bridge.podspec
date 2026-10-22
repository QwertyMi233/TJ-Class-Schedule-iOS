Pod::Spec.new do |s|
  s.name             = 'tj_ios_bridge'
  s.version          = '0.1.0'
  s.summary          = 'TJ Schedule iOS platform integrations.'
  s.description      = s.summary
  s.homepage         = 'https://github.com/qp338113/TJ-Class-Schedule'
  s.license          = { :type => 'MIT', :file => '../LICENSE' }
  s.author           = { 'TJ Schedule contributors' => 'https://tjschedule.icu' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.resource_bundles = { 'tj_ios_bridge_privacy' => ['Resources/PrivacyInfo.xcprivacy'] }
  s.dependency 'Flutter'
  s.platform = :ios, '17.0'
  s.swift_version = '5.0'
  s.frameworks = 'CoreLocation', 'WidgetKit', 'UserNotifications', 'UIKit'
end
