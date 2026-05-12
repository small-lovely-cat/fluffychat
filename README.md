![Screenshot](https://github.com/krille-chan/fluffychat/blob/main/assets/banner_transparent.png?raw=true)

> 这是一个FluffyChat的修改版本，引入了Noto Color Emoji字体用于解决低版本设备无法渲染最新emoji表情问题，引入Tencent Soter、androidx.biometric（android平台）实现了带有生物识别解锁的应用锁，引入了AliPDns（android平台）用于改善网络访问质量。

[FluffyChat](https://fluffy.chat) is an open source, nonprofit and cute [[matrix](https://matrix.org)] client written in [Flutter](https://flutter.dev). The goal of the app is to create an easy to use instant messenger which is open source and accessible for everyone.

### Links:

- 🌐 [[Weblate] Translate FluffyChat into your language](https://hosted.weblate.org/projects/fluffychat/)
- 🌍 [[m] Join the community](https://matrix.to/#/#fluffy-space:matrix.org)
- 📰 [[Mastodon] Get updates on social media](https://troet.cafe/@krille)
- 🖥️ [[Famedly] Server hosting and professional support](https://famedly.com/kontakt)
- 💝 [[Liberapay] Support FluffyChat development](https://de.liberapay.com/KrilleChritzelius)

<a href='https://ko-fi.com/C1C86VN53' target='_blank'><img height='36' style='border:0px;height:36px;' src='https://storage.ko-fi.com/cdn/kofi5.png?v=3' border='0' alt='Buy Me a Coffee at ko-fi.com' /></a>

### Screenshots:

<img src="https://github.com/krille-chan/fluffychat-website/blob/main/src/assets/screenshots/mobile.png?raw=true" height="300">
<img src="https://github.com/krille-chan/fluffychat-website/blob/main/src/assets/screenshots/desktop.png?raw=true" height="300">

# Features

- 📩 Send all kinds of messages, images and files
- 🎙️ Voice messages
- 📍 Location sharing
- 🔔 Push notifications
- 💬 Unlimited private and public group chats
- 📣 Public channels with thousands of participants
- 🛠️ Feature rich group moderation including all matrix features
- 🔍 Discover and join public groups
- 🌙 Dark mode
- 🎨 Material You design
- 📟 Hides complexity of Matrix IDs behind simple QR codes
- 😄 Custom emotes and stickers
- 🌌 Spaces
- 🔄 Compatible with Element, Nheko, NeoChat and all other Matrix apps
- 🔐 End to end encryption
- 🔒 Encrypted chat backup
- 😀 Emoji verification & cross signing

... and much more.


# Installation

Please visit the website for installation instructions:

- https://fluffy.chat

# How to build

1. To build FluffyChat you need [Flutter](https://flutter.dev) and [Rust](https://www.rust-lang.org/tools/install)

2. Clone the repo:
```
git clone https://github.com/krille-chan/fluffychat.git
cd fluffychat
```
3. Choose your target platform below and enable support for it.

4. Debug with: `flutter run`

### Android

* Build with: `flutter build apk`

### iOS / iPadOS

* Have a Mac with Xcode installed, and set up for Xcode-managed app signing
* If you want automatic app installation to connected devices, make sure you have Apple Configurator installed, with the Automation Tools (`cfgutil`) enabled
* Set a few environment variables
    * FLUFFYCHAT_NEW_TEAM: the Apple Developer team that your certificates should live under
    * FLUFFYCHAT_NEW_GROUP: the group you want App IDs and such to live under (ie: com.example.fluffychat)
    * FLUFFYCHAT_INSTALL_IPA: set to `1` if you want the IPA to be deployed to connected devices after building, otherwise unset
* Run `./scripts/build-ios.sh`

#### GitHub Actions TrollStore `.tipa`

`iOS TIPA Build` uses `macos-latest` together with
`flutter build ios --release --no-codesign` to produce an unsigned `.tipa`
package suitable for import into TrollStore.

Optional `workflow_dispatch` inputs:

- `upload_to_release`: also publish the generated `.tipa` and checksum to GitHub Releases
- `bundle_id_base`: optional bundle identifier base that replaces `im.fluffychat`
  during the build, useful when you do not want the TrollStore build to clash
  with the App Store bundle identifier

Artifacts:

- `build/ios/tipa/*.tipa`
- `build/ios/tipa/*.sha256`

Local equivalent:

```bash
bash ./scripts/build-ios-tipa.sh
```

### Web

* Build with:
```bash
./scripts/prepare-web.sh # To install Vodozemac
flutter build web --release
```

* Optionally configure by serving a `config.json` at the same path as fluffychat.
  An example can be found at `config.sample.json`. All values there are optional.
  **Please only the values, you really need**. If you e.g. only want
  to change the default homeserver, then only modify the `defaultHomeserver` key.

#### GitHub Actions Web 发布

`Web Build` 工作流使用 `web-build` environment，并将打包后的 `build/web`
产物发布到 GitHub Releases。

可选的 `web-build` environment secrets：

- `WEB_BUILD_CONFIG_JSON`：CI 中写入的原始 `config.json` 内容，随后会复制到 `build/web/config.json`。
- `WEB_BUILD_BASE_HREF`：可选，对应 `flutter build web --base-href`。
- `WEB_BUILD_CANVASKIT_URL`：可选，用于覆盖 `FLUTTER_WEB_CANVASKIT_URL`，默认值为 `canvaskit/`。
- `WEB_BUILD_PWA_STRATEGY`：可选，对应 `flutter build web --pwa-strategy`。
- `WEB_BUILD_DART_DEFINES`：可选，按换行分隔的 `KEY=VALUE` 列表，会作为 `--dart-define` 传入。
- `WEB_BUILD_EXTRA_ARGS`：可选，额外的 `flutter build web` 参数。

### Desktop (Linux, Windows, macOS)

* Enable Desktop support in Flutter: https://flutter.dev/desktop

#### Install custom dependencies (Linux)

```bash
sudo apt install libjsoncpp1 libsecret-1-dev libsecret-1-0 librhash0 libwebkit2gtk-4.0-dev lld
```

* Build with one of these:
```bash
flutter build linux --release
flutter build windows --release
flutter build macos --release
```

## How to run integration tests

You need to have docker installed locally! Run the preparation script before every test run:

```sh
./scripts/prepare_integration_test.sh
```

Then run all tests with:

```sh
flutter test integration_test/mobile_test.dart
```


# Special thanks

* <a href="https://github.com/fabiyamada">Fabiyamada</a> is a graphics designer and has made the fluffychat logo and the banner. Big thanks for her great designs.

* <a href="https://github.com/advocatux">Advocatux</a> has made the Spanish translation with great love and care. He always stands by my side and supports my work with great commitment.

* Thanks to MTRNord and Sorunome for developing.

* Also thanks to all translators and testers! With your help, fluffychat is now available in more than 12 languages.

* <a href="https://github.com/madsrh/WoodenBeaver">WoodenBeaver</a> sound theme for the notification sound.

* The Matrix Foundation for making and maintaining the [emoji translations](https://github.com/matrix-org/matrix-spec/blob/main/data-definitions/sas-emoji.json) used for emoji verification, licensed Apache 2.0
