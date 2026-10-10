# Install the unsigned IPA with your own Apple account

Use a Mac with Xcode and Python 3. Download `Halo-CE-iOS-unsigned.ipa` from
this fork's [Releases](https://github.com/bmanturner/halo-ce-universal/releases)
(or the `halo-ce-ios-unsigned` artifact of a successful iOS GitHub Actions
run, which needs a GitHub sign-in). The simulator ZIP cannot run on an iPhone.

The script signs locally using a certificate/private key already in your
Keychain and a provisioning profile issued for your account. It does not
sign in to Apple, create certificates, register devices, or bypass provisioning.
You do not need to send your device ID to this project's maintainer when
you use your own account.

## Set up signing once

1. Add your Apple account in **Xcode → Settings → Accounts**. Connect your
   iPhone, trust the Mac, and enable Developer Mode if requested.
2. If you do not already have a suitable iOS development profile, create a
   temporary iOS App project in Xcode. Select your team, enable automatic
   signing, and set a unique bundle identifier such as `com.yourname.haloce`.
   Build/run that temporary app on your phone so Xcode creates the identity
   and a profile covering the device. Then delete the temporary app from
   the phone before installing Halo with the same identifier.
3. Locate the temporary app's build product using **Products → Show in
   Finder**, then **Show Package Contents**. Copy its
   `embedded.mobileprovision` somewhere convenient. Alternatively, use an
   existing development or Ad Hoc `.mobileprovision` downloaded from Apple.
4. List available identities:

   ```sh
   security find-identity -v -p codesigning
   ```

   Use the matching **Apple Development** identity (or **Apple Distribution**
   identity for an Ad Hoc profile). Its private key must be in your Keychain,
   and its certificate must be included in the profile. An App Store profile
   cannot install this build directly on a phone.

## Sign and install

Check out `main` from `bmanturner/halo-ce-universal`.
From its root, run:

```sh
./tools/ios_resign.sh ~/Downloads/Halo-CE-iOS-unsigned.ipa \
  --identity 'Apple Development: Your Name (IDENTITY_ID)' \
  --profile ~/Downloads/embedded.mobileprovision \
  --bundle-id com.yourname.haloce \
  --device YOUR_DEVICE_UDID \
  --output ~/Downloads/Halo-signed.ipa
```

The exact identity name or its SHA-1 fingerprint is accepted. `--device`
is optional but recommended: it verifies that the supplied UDID is covered.
Use `xcrun devicectl list devices` or Xcode's Devices and Simulators window
to identify your phone. The output must not already exist.

The script checks profile expiry, platform, bundle ID, device and signing
certificate; updates the bundle ID; signs ANGLE/SDL frameworks and the app
inside-out; generates DER entitlements; verifies signatures; and writes a
new IPA plus a SHA-256 checksum. It never changes the downloaded IPA.
The shell entry point uses the adjacent `ios_resign.py`, so keep both files.

Install `Halo-signed.ipa` with Apple Configurator, or extract and install
the app with Xcode's command-line device tools:

```sh
mkdir -p ~/Downloads/Halo-signed-extracted
ditto -x -k ~/Downloads/Halo-signed.ipa ~/Downloads/Halo-signed-extracted
xcrun devicectl device install app --device YOUR_DEVICE_UDID \
  ~/Downloads/Halo-signed-extracted/Payload/HaloCE.app
xcrun devicectl device process launch --device YOUR_DEVICE_UDID com.yourname.haloce
```

On first launch, choose your own supported original Xbox Halo ISO/XISO.
No game image or maps are included in the IPA. Keep the same account and
bundle ID for updates to retain imported data. Renew the provisioning
profile and re-sign before it expires; a free Personal Team's validity and
device limits differ from paid developer membership. Back up saves before
uninstalling. Do not upload your signed IPA/profile or private key to this
repository; they contain your signing/device information.

The script has been checked against the CI-produced unsigned IPA using a
local development identity, including nested framework and app signature
verification. Personal Team provisioning and third-party sideloading tools
have not been tested for this port.

Apple references: [signing setup](https://developer.apple.com/documentation/xcode/running-your-app-on-simulated-or-physical-devices),
[provisioning profiles](https://developer.apple.com/documentation/technotes/tn3125-inside-code-signing-provisioning-profiles),
and [nested signatures and DER entitlements](https://developer.apple.com/documentation/xcode/using-the-latest-code-signature-format).
