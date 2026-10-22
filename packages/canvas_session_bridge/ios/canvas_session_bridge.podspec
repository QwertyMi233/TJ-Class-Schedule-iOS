Pod::Spec.new do |s|
  s.name             = 'canvas_session_bridge'
  s.version          = '0.0.1'
  s.summary          = 'Canvas official session and token rotation on device.'
  s.description      = s.summary
  s.homepage         = 'https://github.com/qp338113/TJ-Class-Schedule'
  s.license          = { :type => 'MIT', :file => '../LICENSE' }
  s.author           = { 'TJ Schedule contributors' => 'https://tjschedule.icu' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.resource_bundles = { 'canvas_session_bridge_resources' => ['Resources/**/*'] }
  s.dependency 'Flutter'
  s.platform = :ios, '17.0'
  s.swift_version = '5.0'
  s.frameworks = 'WebKit', 'Security', 'UIKit'
end
