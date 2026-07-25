#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html
#
Pod::Spec.new do |s|
  s.name             = 'ios_audio_equalizer'
  s.version          = '0.1.0'
  s.summary          = 'iOS multi-band equalizer for AVPlayer / just_audio'
  s.description      = <<-DESC
Applies a multi-band peaking EQ to AVPlayerItem playback via MTAudioProcessingTap.
                       DESC
  s.homepage         = 'https://github.com/Wiyam12/wiyamusic'
  s.license          = { :type => 'GPL-3.0' }
  s.author           = { 'WiyaMusic' => 'dev@wiyamusic.app' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*.{h,m,swift}'
  s.public_header_files = 'Classes/**/*.h'
  s.dependency 'Flutter'
  s.platform = :ios, '13.0'
  s.frameworks = 'AVFoundation', 'AudioToolbox', 'Accelerate'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
  s.swift_version = '5.0'
end
