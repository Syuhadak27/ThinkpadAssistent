#!/usr/bin/env bash
#
# build_release.sh — Build Release + zip + tanda tangan Sparkle (Ed25519).
#
# Cara pakai:  ./build_release.sh
# Versi dibaca dari CFBundleShortVersionString pada app hasil build (TIDAK di-hardcode).
# Kunci privat TIDAK pernah disalin ke repo; default lokasi:
#   ~/Documents/ThinkpadAssistent-PrivateKey.txt
#
set -euo pipefail

cd "$(dirname "$0")"

PROJECT="ThinkpadAssistant.xcodeproj"
SCHEME="${SCHEME:-ThinkpadAssistant}"
CONFIGURATION="Release"
DERIVED_DATA="${DERIVED_DATA:-build}"
APP_NAME="ThinkpadAssistant"
PRIVATE_KEY="${SPARKLE_PRIVATE_KEY:-$HOME/Documents/ThinkpadAssistent-PrivateKey.txt}"
SPARKLE_VERSION="${SPARKLE_VERSION:-2.10.1}"
SIGN_UPDATE="${SPARKLE_SIGN_UPDATE:-}"
CACHE_DIR="${HOME}/.cache/ThinkpadAssistent/sparkle-${SPARKLE_VERSION}"

echo "==> 1/4 Build ${SCHEME} (${CONFIGURATION})"
xcodebuild \
  -project "${PROJECT}" \
  -scheme "${SCHEME}" \
  -configuration "${CONFIGURATION}" \
  -destination 'platform=macOS' \
  -derivedDataPath "${DERIVED_DATA}" \
  -quiet \
  CODE_SIGN_IDENTITY=- \
  CODE_SIGN_STYLE=Manual \
  DEVELOPMENT_TEAM= \
  PROVISIONING_PROFILE_SPECIFIER= \
  ONLY_ACTIVE_ARCH=NO \
  ARCHS='x86_64 arm64'

APP="${DERIVED_DATA}/Build/Products/${CONFIGURATION}/${APP_NAME}.app"
if [ ! -d "${APP}" ]; then
  echo "ERROR: app tidak ditemukan di ${APP}" >&2
  exit 1
fi

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${APP}/Contents/Info.plist")"
BUILD_NUMBER="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "${APP}/Contents/Info.plist")"
echo "    Versi: ${VERSION} (build ${BUILD_NUMBER})"

echo "==> 2/4 Buat zip ThinkpadAssistent-${VERSION}.zip"
ZIP_NAME="ThinkpadAssistent-${VERSION}.zip"
rm -f "${ZIP_NAME}"
ditto -c -k --keepParent "${APP}" "${ZIP_NAME}"
LENGTH="$(stat -f%z "${ZIP_NAME}")"

echo "==> 3/4 Siapkan sign_update (Sparkle ${SPARKLE_VERSION})"
if [ -z "${SIGN_UPDATE}" ] || [ ! -x "${SIGN_UPDATE}" ]; then
  mkdir -p "${CACHE_DIR}"
  if [ ! -x "${CACHE_DIR}/sign_update" ]; then
    echo "    Mengunduh tool sign_update ke ${CACHE_DIR} ..."
    curl --fail --location --retry 3 --silent --show-error \
      -o "${CACHE_DIR}/Sparkle-${SPARKLE_VERSION}.tar.xz" \
      "https://github.com/sparkle-project/Sparkle/releases/download/${SPARKLE_VERSION}/Sparkle-${SPARKLE_VERSION}.tar.xz"
    tar -xJf "${CACHE_DIR}/Sparkle-${SPARKLE_VERSION}.tar.xz" -C "${CACHE_DIR}" bin/sign_update
    mv "${CACHE_DIR}/bin/sign_update" "${CACHE_DIR}/sign_update"
    rm -rf "${CACHE_DIR}/bin"
    chmod +x "${CACHE_DIR}/sign_update"
  fi
  SIGN_UPDATE="${CACHE_DIR}/sign_update"
fi

if [ ! -f "${PRIVATE_KEY}" ]; then
  echo "ERROR: private key tidak ditemukan: ${PRIVATE_KEY}" >&2
  echo "       Generate dengan: sparkle/bin/generate_keys --account ThinkpadAssistent -x \"${PRIVATE_KEY}\"" >&2
  exit 1
fi
chmod 600 "${PRIVATE_KEY}" 2>/dev/null || true

echo "==> 4/4 Tanda tangani zip"
SIGNATURE="$("${SIGN_UPDATE}" --ed-key-file "${PRIVATE_KEY}" -p "${ZIP_NAME}")"

cat <<EOF

SELESAI. Tempelkan ke appcast.xml (item untuk versi ${VERSION}):

  <enclosure
    url="https://github.com/Syuhadak27/ThinkpadAssistent/releases/download/v${VERSION}/ThinkpadAssistent-${VERSION}.zip"
    sparkle:version="${BUILD_NUMBER}"
    sparkle:shortVersionString="${VERSION}"
    sparkle:edSignature="${SIGNATURE}"
    type="application/octet-stream"
    length="${LENGTH}" />

Ringkasan:
  File zip : $(pwd)/${ZIP_NAME}
  Size     : ${LENGTH} bytes
  Signature: ${SIGNATURE}

Jangan commit private key. Upload zip ke GitHub Releases tag v${VERSION},
lalu update appcast.xml dan push ke branch main.
EOF
