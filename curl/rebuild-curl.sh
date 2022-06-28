#!/bin/bash

set -e
# set -x

if [ -z "$1" ] || [ ! -d "$1" ] ;then
    echo $0 ARCHIVE_DIR
    exit 1
fi

ARCHIVE=$(cd "$1";pwd)

echo $ARCHIVE
MACOS_X86_64_VERSION=""
MACOS_ARM64_VERSION=""
CATALYST_IOS="13.0"
IOS_MIN_SDK_VERSION="8.0"
TVOS_MIN_SDK_VERSION="9.0"
LIBCURL="7.84.0"

if [ -z "${MACOS_X86_64_VERSION}" ]; then
	MACOS_X86_64_VERSION=$(sw_vers -productVersion)
fi
if [ -z "${MACOS_ARM64_VERSION}" ]; then
	MACOS_ARM64_VERSION=$(sw_vers -productVersion)
fi

OSARGS="-s ${IOS_MIN_SDK_VERSION} -t ${TVOS_MIN_SDK_VERSION} -i ${MACOS_X86_64_VERSION} -a ${MACOS_ARM64_VERSION}"

buildnghttp2="-n"
buildnghttp3="-k"
buildbrotli="-g"
buildzstd="-j"
catalyst=""

echo
echo -e "Building Curl"
./libcurl-build.sh -v "$LIBCURL" $disablebitcode $colorflag $buildnghttp2 $buildnghttp3 $buildbrotli $buildzstd $catalyst $OSARGS

pushd .. > /dev/null
# libraries for libcurl, libcrypto and libssl
cp curl/lib/libcurl_iOS.a $ARCHIVE/lib/iOS/libcurl.a
cp curl/lib/libcurl_iOS-simulator.a $ARCHIVE/lib/iOS-simulator/libcurl.a
cp curl/lib/libcurl_iOS-fat.a $ARCHIVE/lib/iOS-fat/libcurl.a
cp curl/lib/libcurl_tvOS.a $ARCHIVE/lib/tvOS/libcurl.a
cp curl/lib/libcurl_tvOS-simulator.a $ARCHIVE/lib/tvOS-simulator/libcurl.a
cp curl/lib/libcurl_Mac.a $ARCHIVE/lib/MacOS/libcurl.a

rm -rf $ARCHIVE/xcframework/libcurl.xcframework

if [ "$catalyst" == "-m" ]; then
	# Add catalyst libraries
	cp curl/lib/libcurl_Catalyst.a $ARCHIVE/lib/Catalyst/libcurl.a

	# Build XCFrameworks with Catalyst library
	xcodebuild -create-xcframework \
		-library $ARCHIVE/lib/iOS/libcurl.a \
		-library $ARCHIVE/lib/iOS-simulator/libcurl.a \
		-library $ARCHIVE/lib/tvOS/libcurl.a \
		-library $ARCHIVE/lib/tvOS-simulator/libcurl.a \
		-library $ARCHIVE/lib/Catalyst/libcurl.a \
		-output $ARCHIVE/xcframework/libcurl.xcframework
else
	# Build XCFrameworks
	xcodebuild -create-xcframework \
		-library $ARCHIVE/lib/iOS/libcurl.a \
		-library $ARCHIVE/lib/iOS-simulator/libcurl.a \
		-library $ARCHIVE/lib/tvOS/libcurl.a \
		-library $ARCHIVE/lib/tvOS-simulator/libcurl.a \
		-output $ARCHIVE/xcframework/libcurl.xcframework
fi


popd > /dev/null
