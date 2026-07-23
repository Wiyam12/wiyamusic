#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html
#
Pod::Spec.new do |s|
  s.name             = 'receive_sharing_intent'
  s.version          = '1.4.5'
  s.summary          = 'A flutter plugin that enables flutter apps to receive sharing photos from other apps.'
  s.description      = <<-DESC
A flutter plugin that enables flutter apps to receive sharing photos from other apps.
                       DESC
  s.homepage         = 'https://github.com/KasemJaffer/receive_sharing_intent'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Kasem Jaffer' => 'email@example.com' }
  s.source           = { :path => '.' }
  s.source_files = 'receive_sharing_intent/Sources/receive_sharing_intent/**/*.swift'
  s.dependency 'Flutter'
  s.platform = :ios, '13.0'

  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.0'
end
