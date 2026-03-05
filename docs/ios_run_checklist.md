# iOS Run Checklist (QRTags)

## What is already configured
- iOS deployment target is set to `13.0`.
- iOS permissions are present for:
  - Camera (`NSCameraUsageDescription`)
  - Photo library read (`NSPhotoLibraryUsageDescription`)
  - Photo library add (`NSPhotoLibraryAddUsageDescription`)
  - Face ID (`NSFaceIDUsageDescription`)
- Firebase plist is included at:
  - `ios/Runner/GoogleService-Info.plist`

## Required on a Mac (Xcode)
1. Install prerequisites:
   - Xcode (latest stable)
   - CocoaPods (`sudo gem install cocoapods`)
2. In project root:
   - `flutter clean`
   - `flutter pub get`
   - `cd ios`
   - `pod repo update`
   - `pod install`
3. Open `ios/Runner.xcworkspace` in Xcode.
4. In Xcode, set:
   - Signing Team
   - Bundle Identifier
5. If you change Bundle Identifier, download a matching `GoogleService-Info.plist` from Firebase and replace `ios/Runner/GoogleService-Info.plist`.
6. Build/run:
   - Debug on device: `flutter run -d <ios-device-id>`
   - Release build: `flutter build ios --release`

## Notes
- Current scanner dependencies support iOS `13.0+`.
- iOS builds cannot be produced from Windows; a Mac is required for final iOS build/signing.
