#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
cd "${REPO_ROOT}"

FLUFFYCHAT_ORIG_GROUP="${FLUFFYCHAT_ORIG_GROUP:-im.fluffychat}"
FLUFFYCHAT_NEW_GROUP="${FLUFFYCHAT_NEW_GROUP:-}"
TIPA_OUTPUT_DIR="${TIPA_OUTPUT_DIR:-build/ios/tipa}"
TIPA_BASENAME="${TIPA_BASENAME:-fluffychat-ios-trollstore}"

if [[ -n "${FLUFFYCHAT_NEW_GROUP}" && "${FLUFFYCHAT_NEW_GROUP}" == *[[:space:]]* ]]; then
  echo "FLUFFYCHAT_NEW_GROUP must not contain whitespace." >&2
  exit 1
fi

if [[ -n "${FLUFFYCHAT_NEW_GROUP}" ]]; then
  export FLUFFYCHAT_ORIG_GROUP FLUFFYCHAT_NEW_GROUP

  perl -0pi -e '
    my $orig = quotemeta($ENV{FLUFFYCHAT_ORIG_GROUP});
    my $new = $ENV{FLUFFYCHAT_NEW_GROUP};
    s/group\.$orig\.app/group.$new.app/g;
  ' \
    "ios/FluffyChat Share/FluffyChat Share.entitlements" \
    "ios/Runner/Runner.entitlements" \
    "ios/Runner.xcodeproj/project.pbxproj"

  perl -0pi -e '
    my $orig = quotemeta($ENV{FLUFFYCHAT_ORIG_GROUP});
    my $new = $ENV{FLUFFYCHAT_NEW_GROUP};
    s/$orig\.app/$new.app/g;
  ' "ios/Runner.xcodeproj/project.pbxproj"
fi

flutter pub get
flutter build ios --release --no-codesign

app_path="${REPO_ROOT}/build/ios/iphoneos/Runner.app"
if [[ ! -d "${app_path}" ]]; then
  app_path="$(find "${REPO_ROOT}/build/ios/iphoneos" -mindepth 1 -maxdepth 1 -type d -name '*.app' | head -n 1)"
fi

if [[ -z "${app_path}" || ! -d "${app_path}" ]]; then
  echo "Unable to locate built .app bundle under build/ios/iphoneos." >&2
  exit 1
fi

rm -rf "${TIPA_OUTPUT_DIR}"
mkdir -p "${TIPA_OUTPUT_DIR}"

temp_dir="$(mktemp -d "${RUNNER_TEMP:-/tmp}/fluffychat-tipa.XXXXXX")"
trap 'rm -rf "${temp_dir}"' EXIT

mkdir -p "${temp_dir}/Payload"
ditto "${app_path}" "${temp_dir}/Payload/$(basename "${app_path}")"

tipa_path="${TIPA_OUTPUT_DIR}/${TIPA_BASENAME}.tipa"
rm -f "${tipa_path}" "${tipa_path}.sha256"
(
  cd "${temp_dir}"
  ditto -c -k --sequesterRsrc --keepParent Payload "${REPO_ROOT}/${tipa_path}"
)
shasum -a 256 "${tipa_path}" > "${tipa_path}.sha256"

ls -lah "${tipa_path}" "${tipa_path}.sha256"
