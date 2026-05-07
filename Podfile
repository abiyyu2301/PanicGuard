platform :ios, '16.0'
use_frameworks!

# LiteRT-LM: No CocoaPods needed — dylibs are downloaded manually from
# https://github.com/google-ai-edge/LiteRT-LM/tree/main/prebuilt/ios_arm64
# and linked via OTHER_LDFLAGS in project.yml.
#
# Before building, run: ./scripts/download-litert-dylibs.sh
target 'PanicGuard' do
end

post_install do |installer|
  installer.pods_project.targets.each do |target|
    target.build_configurations.each do |config|
      config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '16.0'
    end
  end
end
