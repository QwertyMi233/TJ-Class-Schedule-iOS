Pod::Spec.new do |s|
  s.name = 'tj_text_recognition'
  s.version = '0.1.0'
  s.summary = 'On-device screenshot text recognition with Apple Vision.'
  s.description = s.summary
  s.homepage = 'https://github.com/QwertyMi233/TJ-Class-Schedule-iOS'
  s.license = { :type => 'MIT', :file => '../LICENSE' }
  s.author = { 'TJ Schedule contributors' => 'https://tjschedule.icu' }
  s.source = { :path => '.' }
  s.source_files = 'Classes/**/*'
  s.dependency 'Flutter'
  s.platform = :ios, '17.0'
  s.swift_version = '5.0'
  s.frameworks = 'Vision', 'ImageIO'
end
