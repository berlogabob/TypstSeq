#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html
# Run `pod lib lint typst_flutter.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'typst_flutter'
  s.version          = '1.0.0'
  s.summary          = 'Native Typst compiler for Flutter via Rust FFI.'
  s.description      = <<-DESC
    Embeds the Typst typesetting compiler natively in Flutter apps via Rust
    FFI. Compile Typst markup to PDF or rendered images on iOS with no WASM,
    no WebView, and no server required.
    Run `dart run typst_flutter:setup` once after `flutter pub get`.
  DESC
  s.homepage         = 'https://github.com/ajmalbuv/typst_flutter'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Ajmal' => 'ajmalbuv@gmail.com' }

  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.dependency 'Flutter'
  s.platform = :ios, '14.0'
  s.swift_version = '5.0'

  # ── Pre-built binary detection ──────────────────────────────────────────────
  #
  # When `dart run typst_flutter:setup` has been run, the XCFramework
  # is at {package_root}/.typst_flutter_prebuilt/ios/typst_flutter.xcframework.
  # __dir__ is the directory containing this podspec (the ios/ directory),
  # so we navigate one level up to the package root.

  # Keep the vendored artifact inside the iOS pod root. CocoaPods silently
  # ignores XCFramework paths that escape this directory with `..`.
  prebuilt_xcframework = 'typst_flutter/Frameworks/typst_flutter.xcframework'
  prebuilt_xcframework_on_disk = File.join(__dir__, prebuilt_xcframework)

  if File.exist?(prebuilt_xcframework_on_disk)
    # ── Pre-built path ────────────────────────────────────────────────────────
    s.preserve_paths = prebuilt_xcframework
    s.pod_target_xcconfig = {
      'DEFINES_MODULE' => 'YES',
      'OTHER_LDFLAGS[sdk=iphoneos*]' => '$(inherited) -force_load "$(PODS_TARGET_SRCROOT)/typst_flutter/Frameworks/typst_flutter.xcframework/ios-arm64/libtypst_flutter.a"',
      'OTHER_LDFLAGS[sdk=iphonesimulator*]' => '$(inherited) -force_load "$(PODS_TARGET_SRCROOT)/typst_flutter/Frameworks/typst_flutter.xcframework/ios-arm64_x86_64-simulator/libtypst_flutter.a"',
    }
  else
    # ── Cargokit fallback ─────────────────────────────────────────────────────
    # Builds the Rust crate from source. Requires Rust + rustup on the machine.
    s.script_phase = {
      :name               => 'Build Rust library (typst_flutter)',
      :script             => 'sh "$PODS_TARGET_SRCROOT/../../rust_builder/cargokit/build_pod.sh" ../rust typst_flutter',
      :execution_position => :before_compile,
      :input_files        => ['${BUILT_PRODUCTS_DIR}/cargokit_phony'],
      :output_files       => ['${BUILT_PRODUCTS_DIR}/libtypst_flutter.a'],
    }
    s.pod_target_xcconfig = {
      'DEFINES_MODULE'                       => 'YES',
      'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386',
      'OTHER_LDFLAGS' => '-force_load ${BUILT_PRODUCTS_DIR}/libtypst_flutter.a',
    }
  end
end
