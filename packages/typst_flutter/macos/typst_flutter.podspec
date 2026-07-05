#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint typst_flutter.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'typst_flutter'
  s.version          = '1.0.0'
  s.summary          = 'Typst compiler natively in Flutter via Rust FFI.'
  s.description      = <<-DESC
    Embeds the Typst typesetting compiler natively in Flutter apps via Rust
    FFI. Compile Typst markup to PDF or rendered images on macOS with no WASM,
    no WebView, and no server required.
    Run `dart run typst_flutter:setup` once after `flutter pub get`.
  DESC
  s.homepage         = 'https://github.com/ajmalbuv/typst_flutter'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Ajmal' => 'ajmalbuv@gmail.com' }

  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.dependency 'FlutterMacOS'

  s.platform = :osx, '10.15'
  s.swift_version = '5.0'

  # ── Pre-built binary detection ──────────────────────────────────────────────
  #
  # When `dart run typst_flutter:setup` has been run, the static lib is at:
  #   {package_root}/.typst_flutter_prebuilt/macos/libtypst_flutter.a
  # __dir__ is the directory containing this podspec (the macos/ directory).

  prebuilt_lib = File.join(
    __dir__, '../.typst_flutter_prebuilt/macos/libtypst_flutter.a'
  )

  if File.exist?(prebuilt_lib)
    # ── Pre-built path ──────────────────────────────────────────────────────
    s.pod_target_xcconfig = {
      'DEFINES_MODULE' => 'YES',
      'OTHER_LDFLAGS'  => "-force_load \"#{prebuilt_lib}\"",
    }
  else
    # ── No Cargokit fallback on macOS CMake path ────────────────────────────
    # Emit a clear build error rather than a silent link failure.
    raise <<~MSG

      ╔══════════════════════════════════════════════════════════════════╗
      ║  typst_flutter: libtypst_flutter.a not found!                   ║
      ║                                                                  ║
      ║  Run once from your app root, then re-run `pod install`:        ║
      ║    ./tool/setup_typst_native.sh                                  ║
      ╚══════════════════════════════════════════════════════════════════╝
    MSG
  end
end
