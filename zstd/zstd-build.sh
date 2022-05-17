#!/bin/bash
# This script downlaods and builds the Mac, iOS and tvOS zstd libraries 
#
# Credits:
# Jason Cox, @jasonacox
#   https://github.com/jasonacox/Build-OpenSSL-cURL 
#
# zstd - https://github.com/facebook/zstd/
#

# 
# NOTE: pkg-config is required
 
# set -x
set -e

# Formatting
default="\033[39m"
wihte="\033[97m"
green="\033[32m"
red="\033[91m"
yellow="\033[33m"

bold="\033[0m${green}\033[1m"
subbold="\033[0m${green}"
archbold="\033[0m${yellow}\033[1m"
normal="${white}\033[0m"
dim="\033[0m${white}\033[2m"
alert="\033[0m${red}\033[1m"
alertdim="\033[0m${red}\033[2m"

# set trap to help debug build errors
trap 'echo -e "${alert}** ERROR with Build - Check /tmp/zstd*.log${alertdim}"; tail -5 /tmp/zstd*.log' INT TERM EXIT

# --- Edit this to update default version ---
ZSTD_VERNUM="1.5.2"

# Set defaults
VERSION="1.1.1i"				# OpenSSL version default
catalyst="0"

# Set minimum OS versions for target
MACOS_X86_64_VERSION=""			# Empty = use host version
MACOS_ARM64_VERSION=""			# Min supported is MacOS 11.0 Big Sur
CATALYST_IOS="13.0"				# Min supported is iOS 13.0 for Mac Catalyst
IOS_MIN_SDK_VERSION="8.0"
IOS_SDK_VERSION=""
TVOS_MIN_SDK_VERSION="9.0"
TVOS_SDK_VERSION=""

CORES=$(sysctl -n hw.ncpu)

if [ -z "${MACOS_X86_64_VERSION}" ]; then
	MACOS_X86_64_VERSION=$(sw_vers -productVersion)
fi
if [ -z "${MACOS_ARM64_VERSION}" ]; then
	MACOS_ARM64_VERSION=$(sw_vers -productVersion)
fi

CORES=$(sysctl -n hw.ncpu)

usage ()
{
	echo
	echo -e "${bold}Usage:${normal}"
	echo
    echo -e "  ${subbold}$0${normal} [-v ${dim}<zstd version>${normal}] [-s ${dim}<iOS SDK version>${normal}] [-t ${dim}<tvOS SDK version>${normal}] [-m] [-x] [-h]"
    echo
	echo "         -v   version of zstd (default $ZSTD_VERNUM)"
	echo "         -s   iOS min target version (default $IOS_MIN_SDK_VERSION)"
	echo "         -t   tvOS min target version (default $TVOS_MIN_SDK_VERSION)"
	echo "         -i   macOS 86_64 min target version (default $MACOS_X86_64_VERSION)"
	echo "         -a   macOS arm64 min target version (default $MACOS_ARM64_VERSION)"
	echo "         -m   compile Mac Catalyst library"
	echo "         -u   Mac Catalyst iOS min target version (default $CATALYST_IOS)"
	echo "         -x   disable color output"
	echo "         -h   show usage"	
	echo
	trap - INT TERM EXIT
	exit 127
}

while getopts "v:s:t:i:a:u:mxh\?" o; do
    case "${o}" in
        v)
            ZSTD_VERNUM="${OPTARG}"
            ;;
		s)
			IOS_MIN_SDK_VERSION="${OPTARG}"
			;;
		t)
			TVOS_MIN_SDK_VERSION="${OPTARG}"
			;;
		i)
			MACOS_X86_64_VERSION="${OPTARG}"
			;;
		a)
			MACOS_ARM64_VERSION="${OPTARG}"
			;;
        m)
            catalyst="1"
            ;;
		u)
			catalyst="1"
			CATALYST_IOS="${OPTARG}"
			;;
        x)
            bold=""
            subbold=""
            normal=""
            dim=""
            alert=""
            alertdim=""
            archbold=""
            ;;
        *)
            usage
            ;;
    esac
done
shift $((OPTIND-1))

ZSTD_VERSION="zstd-${ZSTD_VERNUM}"
DEVELOPER=`xcode-select -print-path`

ZSTD="${PWD}/../zstd"

# Semantic Version Comparison
version_lte() {
    [  "$1" = "`echo -e "$1\n$2" | sort -V | head -n1`" ]
}
if version_lte $MACOS_ARM64_VERSION 11.0; then
        MACOS_ARM64_VERSION="11.0"      # Min support for Apple Silicon is 11.0
fi

# Check to see if pkg-config is already installed
if (type "pkg-config" > /dev/null 2>&1 ) ; then
	echo "  pkg-config already installed"
else
	echo -e "${alertdim}** WARNING: pkg-config not installed... attempting to install.${dim}"

	# Check to see if Brew is installed
	if (type "brew" > /dev/null 2>&1 ) ; then
		echo "  brew installed - using to install pkg-config"
		brew install pkg-config
	else
		# Build pkg-config from Source
		echo "  Downloading pkg-config-0.29.2.tar.gz"
		curl -LOs https://pkg-config.freedesktop.org/releases/pkg-config-0.29.2.tar.gz
		echo "  Building pkg-config"
		tar xfz pkg-config-0.29.2.tar.gz
		pushd pkg-config-0.29.2 > /dev/null
		./configure-cmake --prefix=/tmp/pkg_config --with-internal-glib >> "/tmp/${ZSTD_VERSION}.log" 2>&1
		make -j${CORES} >> "/tmp/${ZSTD_VERSION}.log" 2>&1
		make install >> "/tmp/${ZSTD_VERSION}.log" 2>&1
		PATH=$PATH:/tmp/pkg_config/bin
		popd > /dev/null
	fi

	# Check to see if installation worked
	if (type "pkg-config" > /dev/null 2>&1 ) ; then
		echo "  SUCCESS: pkg-config installed"
	else
		echo -e "${alert}** FATAL ERROR: pkg-config failed to install - exiting.${normal}"
		exit 1
	fi
fi 

# Check to see if cmake is already installed
if (type "cmake" > /dev/null 2>&1 ) ; then
	echo "  cmake already installed"
else
	echo -e "${alertdim}** WARNING: cmake not installed... attempting to install.${dim}"

	# Check to see if Brew is installed
	if (type "brew" > /dev/null 2>&1 ) ; then
		echo "  brew installed - using to install cmake"
		brew install cmake
	fi

	# Check to see if installation worked
	if (type "cmake" > /dev/null 2>&1 ) ; then
		echo "  SUCCESS: cmake installed"
	else
		echo -e "${alert}** FATAL ERROR: cmake failed to install - exiting.${normal}"
		exit 1
	fi
fi

if [ ! -f ios.toolchain.cmake ]; then
	echo -e "${alertdim}** WARNING: ios-cmake not installed... attempting to install.${dim}"
	curl -Ls https://github.com/leetal/ios-cmake/archive/refs/tags/4.2.0.tar.gz -o ios-cmake-4.2.0.tar.gz
	tar xvzf ios-cmake-4.2.0.tar.gz
	cp ios-cmake-4.2.0/ios.toolchain.cmake .

	if [ ! -f ios.toolchain.cmake ]; then
		echo -e "${alert}** FATAL ERROR: ios-cmake failed to install - exiting.${normal}"
		exit 1
	fi
fi


buildMac()
{
	ARCH=$1

	TARGET="darwin-i386-cc"
	BUILD_MACHINE=`uname -m`
	export CC="${BUILD_TOOLS}/usr/bin/gcc"
	export CFLAGS="-arch ${ARCH} -pipe -Os -gdwarf-2 -fembed-bitcode"
	export LDFLAGS="-arch ${ARCH}"
	export PASSTHRU="-G Xcode -DCMAKE_TOOLCHAIN_FILE=$ZSTD/ios.toolchain.cmake -DARCHS=$ARCH"

	if [[ $ARCH == "x86_64" ]]; then
		TARGET="darwin64-x86_64-cc"
		MACOS_VER="${MACOS_X86_64_VERSION}"
		export PASSTHRU="$PASSTHRU -DPLATFORM=MAC -DDEPLOYMENT_TARGET=${MACOS_X86_64_VERSION}"
		if [ ${BUILD_MACHINE} == 'arm64' ]; then
   			# Apple ARM Silicon Build Machine Detected - cross compile
			export CC="clang"
			export CXX="clang"
			export CFLAGS=" -Os -mmacosx-version-min=${MACOS_X86_64_VERSION} -arch ${ARCH} -gdwarf-2 -fembed-bitcode "
			export LDFLAGS=" -arch ${ARCH} -isysroot ${DEVELOPER}/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk "
			export CPPFLAGS=" -I.. -isysroot ${DEVELOPER}/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk "
		else
			# Apple x86_64 Build Machine Detected - native build
			export CFLAGS=" -mmacosx-version-min=${MACOS_X86_64_VERSION} -arch ${ARCH} -pipe -Os -gdwarf-2 -fembed-bitcode"
		fi
	fi
	if [[ $ARCH == "arm64" ]]; then
		TARGET="darwin64-arm64-cc"
		MACOS_VER="${MACOS_ARM64_VERSION}"
		export PASSTHRU="$PASSTHRU -DPLATFORM=MAC_ARM64 -DDEPLOYMENT_TARGET=${MACOS_ARM64_VERSION}"
		if [ ${BUILD_MACHINE} == 'arm64' ]; then
   			# Apple ARM Silicon Build Machine Detected 
			export CFLAGS=" -mmacosx-version-min=${MACOS_ARM64_VERSION} -arch ${ARCH} -pipe -Os -gdwarf-2 -fembed-bitcode"
		else
			# Apple x86_64 Build Machine Detected - cross compile
			TARGET="darwin64-arm64-cc"
			export CC="clang"
			export CXX="clang"
			export CFLAGS=" -Os -mmacosx-version-min=${MACOS_ARM64_VERSION} -arch ${ARCH} -gdwarf-2 -fembed-bitcode "
			export LDFLAGS=" -arch ${ARCH} -isysroot ${DEVELOPER}/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk "
			export CPPFLAGS=" -I.. -isysroot ${DEVELOPER}/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk "
		fi
	fi

	echo -e "${subbold}Building ${ZSTD_VERSION} for ${archbold}${ARCH}${dim} (MacOS ${MACOS_VER})"

	mkdir -p "${ZSTD_VERSION}"/build/cmake/a
	pushd "${ZSTD_VERSION}"/build/cmake/a > /dev/null

	if [[ $ARCH != ${BUILD_MACHINE} ]]; then
		# cross compile required
		if [[ "${ARCH}" == "arm64" || "${ARCH}" == "arm64e"  ]]; then
			cmake $PASSTHRU ..  &> "/tmp/${ZSTD_VERSION}-${ARCH}.log"
		else
			cmake $PASSTHRU .. &> "/tmp/${ZSTD_VERSION}-${ARCH}.log"
		fi
	else
		cmake $PASSTHRU .. &> "/tmp/${ZSTD_VERSION}-${ARCH}.log"
	fi

	cmake --build . --config Release --target libzstd_static >> "/tmp/${ZSTD_VERSION}-${ARCH}.log" 2>&1

	TARGET_DIR=${ZSTD}/Mac/${ARCH}
	mkdir -p ${TARGET_DIR}/lib
	cp `find lib -name "libzstd.a"` ${TARGET_DIR}/lib
	mkdir -p ${TARGET_DIR}/include/zstd
	cp ../../../lib/*.h ${TARGET_DIR}/include/zstd
	rm -rf * >> "/tmp/${ZSTD_VERSION}-${ARCH}.log" 2>&1
	popd > /dev/null

	# Clean up exports
	export CC=""
	export CXX=""
	export CFLAGS=""
	export LDFLAGS=""
	export CPPFLAGS=""
}

buildCatalyst()
{
	ARCH=$1

	TARGET="darwin64-${ARCH}-cc"
	BUILD_MACHINE=`uname -m`

	export CC="${BUILD_TOOLS}/usr/bin/gcc"
    export CFLAGS="-arch ${ARCH} -pipe -Os -gdwarf-2 -fembed-bitcode"
    export LDFLAGS="-arch ${ARCH}"
	export PASSTHRU="-G Xcode -DCMAKE_TOOLCHAIN_FILE=$ZSTD/ios.toolchain.cmake -DARCHS=$ARCH -DDEPLOYMENT_TARGET=${CATALYST_IOS}"

	if [[ $ARCH == "x86_64" ]]; then
		TARGET="darwin64-x86_64-cc"
		MACOS_VER="${MACOS_X86_64_VERSION}"
		export PASSTHRU="$PASSTHRU -DPLATFORM=MAC_CATALYST"
		if [ ${BUILD_MACHINE} == 'arm64' ]; then
   			# Apple ARM Silicon Build Machine Detected - cross compile
			TARGET="darwin64-x86_64-cc"
			MACOS_VER="${MACOS_X86_64_VERSION}"
			export CC="clang"
			export CXX="clang"
			export CFLAGS=" -Os -mmacosx-version-min=${MACOS_X86_64_VERSION} -arch ${ARCH} -gdwarf-2 -fembed-bitcode"
			export LDFLAGS=" -arch ${ARCH} -isysroot ${DEVELOPER}/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk "
			export CPPFLAGS=" -I.. -isysroot ${DEVELOPER}/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk "
		else
			# Apple x86_64 Build Machine Detected - native build
			export CFLAGS=" -mmacosx-version-min=${MACOS_X86_64_VERSION} -arch ${ARCH} -pipe -Os -gdwarf-2 -fembed-bitcode"
		fi
	fi
	if [[ $ARCH == "arm64" ]]; then
		TARGET="darwin64-arm64-cc"
		MACOS_VER="${MACOS_ARM64_VERSION}"
		export PASSTHRU="$PASSTHRU -DPLATFORM=MAC_CATALYST_ARM64"
		if [ ${BUILD_MACHINE} == 'arm64' ]; then
   			# Apple ARM Silicon Build Machine Detected - native build
			TARGET="darwin64-arm64-cc"
			export CFLAGS=" -mmacosx-version-min=${MACOS_ARM64_VERSION} -arch ${ARCH} -pipe -Os -gdwarf-2 -fembed-bitcode"
		else
			# Apple x86_64 Build Machine Detected - cross compile
			TARGET="darwin64-arm64-cc"
			export CC="clang"
			export CXX="clang"
			export CFLAGS=" -Os -mmacosx-version-min=${MACOS_ARM64_VERSION} -arch ${ARCH} -gdwarf-2 -fembed-bitcode"
			export LDFLAGS=" -arch ${ARCH} -isysroot ${DEVELOPER}/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk "
			export CPPFLAGS=" -I.. -isysroot ${DEVELOPER}/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk "
		fi
	fi

	echo -e "${subbold}Building ${ZSTD_VERSION} for ${archbold}${ARCH}${dim} (MacOS ${MACOS_VER} Catalyst iOS ${CATALYST_IOS})"

	mkdir -p "${ZSTD_VERSION}"/build/cmake/a
	pushd "${ZSTD_VERSION}"/build/cmake/a > /dev/null

	# Cross compile required for Catalyst
	if [[ "${ARCH}" == "arm64" ]]; then
		cmake $PASSTHRU .. &> "/tmp/${ZSTD_VERSION}-catalyst-${ARCH}.log"
	else
		cmake $PASSTHRU .. &> "/tmp/${ZSTD_VERSION}-catalyst-${ARCH}.log"
	fi
	
	cmake --build . --config Release --target libzstd_static >> "/tmp/${ZSTD_VERSION}-catalyst-${ARCH}.log" 2>&1

	TARGET_DIR=${ZSTD}/Catalyst/${ARCH}
	mkdir -p ${TARGET_DIR}/lib
	cp `find lib -name "libzstd.a"` ${TARGET_DIR}/lib
	mkdir -p ${TARGET_DIR}/include/zstd
	cp ../../../lib/*.h ${TARGET_DIR}/include/zstd

	rm -rf * >> "/tmp/${ZSTD_VERSION}-catalyst-${ARCH}.log" 2>&1
	popd > /dev/null

	# Clean up exports
	export CC=""
	export CXX=""
	export CFLAGS=""
	export LDFLAGS=""
	export CPPFLAGS=""
}

buildIOS()
{
	ARCH=$1
	BITCODE=$2

	mkdir -p "${ZSTD_VERSION}"/build/cmake/a
	pushd "${ZSTD_VERSION}"/build/cmake/a > /dev/null
  
	if [[ "${ARCH}" == "i386" || "${ARCH}" == "x86_64" ]]; then
		PLATFORM="iPhoneSimulator"
	else
		PLATFORM="iPhoneOS"
	fi

        if [[ "${BITCODE}" == "nobitcode" ]]; then
                CC_BITCODE_FLAG=""
        else
                CC_BITCODE_FLAG="-fembed-bitcode"
        fi
  
	export $PLATFORM
	export CROSS_TOP="${DEVELOPER}/Platforms/${PLATFORM}.platform/Developer"
	export CROSS_SDK="${PLATFORM}${IOS_SDK_VERSION}.sdk"
	export BUILD_TOOLS="${DEVELOPER}"
	export CC="${BUILD_TOOLS}/usr/bin/gcc"
	export CFLAGS="-arch ${ARCH} -pipe -Os -gdwarf-2 -isysroot ${CROSS_TOP}/SDKs/${CROSS_SDK} -miphoneos-version-min=${IOS_MIN_SDK_VERSION} ${CC_BITCODE_FLAG}"
	export LDFLAGS="-arch ${ARCH} -isysroot ${CROSS_TOP}/SDKs/${CROSS_SDK}"
	export PASSTHRU="-G Xcode -DCMAKE_TOOLCHAIN_FILE=$ZSTD/ios.toolchain.cmake"
   	export PASSTHRU="$PASSTHRU -DARCHS=$ARCH -DPLATFORM=OS -DDEPLOYMENT_TARGET=${IOS_MIN_SDK_VERSION}"
	echo -e "${subbold}Building ${ZSTD_VERSION} for ${PLATFORM} ${IOS_SDK_VERSION} ${archbold}${ARCH}${dim} (iOS ${IOS_MIN_SDK_VERSION})"
	
	if [[ "${ARCH}" == "arm64" || "${ARCH}" == "arm64e"  ]]; then
		cmake $PASSTHRU .. &> "/tmp/${ZSTD_VERSION}-iOS-${ARCH}-${BITCODE}.log"
	else
		cmake $PASSTHRU .. &> "/tmp/${ZSTD_VERSION}-iOS-${ARCH}-${BITCODE}.log"
	fi

	cmake --build . --config Release --target libzstd_static >> "/tmp/${ZSTD_VERSION}-iOS-${ARCH}-${BITCODE}.log" 2>&1

	TARGET_DIR=${ZSTD}/iOS/$ARCH
	mkdir -p ${TARGET_DIR}/lib
	cp `find lib -name "libzstd.a"` ${TARGET_DIR}/lib
	mkdir -p ${TARGET_DIR}/include/zstd
	cp ../../../lib/*.h ${TARGET_DIR}/include/zstd

	rm -rf * >> "/tmp/${ZSTD_VERSION}-iOS-${ARCH}-${BITCODE}.log" 2>&1
	popd > /dev/null

	# Clean up exports
	export CC=""
	export CXX=""
	export CFLAGS=""
	export LDFLAGS=""
	export CPPFLAGS=""
}

buildIOSsim()
{
	ARCH=$1
	BITCODE=$2

	mkdir -p "${ZSTD_VERSION}"/build/cmake/a
	pushd "${ZSTD_VERSION}"/build/cmake/a > /dev/null
  
  	PLATFORM="iPhoneSimulator"
	export $PLATFORM

	TARGET="darwin-i386-cc"
	RUNTARGET=""
	MIPHONEOS="${IOS_MIN_SDK_VERSION}"


	if [[ $ARCH != "i386" ]]; then
		TARGET="darwin64-${ARCH}-cc"
		RUNTARGET="-target ${ARCH}-apple-ios${IOS_MIN_SDK_VERSION}-simulator"
			# e.g. -target arm64-apple-ios11.0-simulator
	fi


	if [[ "${BITCODE}" == "nobitcode" ]]; then
			CC_BITCODE_FLAG=""
	else
			CC_BITCODE_FLAG="-fembed-bitcode"
	fi

	export PASSTHRU="-G Xcode -DCMAKE_TOOLCHAIN_FILE=$ZSTD/ios.toolchain.cmake"
	export PASSTHRU="$PASSTHRU -DDEPLOYMENT_TARGET=${IOS_MIN_SDK_VERSION} -DARCHS=$ARCH"

	if [[ $ARCH = "i386" ]]; then
		export PASSTHRU="$PASSTHRU -DPLATFORM=SIMULATOR"
	elif [[ $ARCH = "x86_64" ]]; then
		export PASSTHRU="$PASSTHRU -DPLATFORM=SIMULATOR64"
	elif [[ $ARCH = "arm64" ]]; then
		export PASSTHRU="$PASSTHRU -DPLATFORM=SIMULATORARM64"
	fi
  
	export $PLATFORM
	export CROSS_TOP="${DEVELOPER}/Platforms/${PLATFORM}.platform/Developer"
	export CROSS_SDK="${PLATFORM}${IOS_SDK_VERSION}.sdk"
	export BUILD_TOOLS="${DEVELOPER}"
	export CC="${BUILD_TOOLS}/usr/bin/gcc"
	export CFLAGS="-arch ${ARCH} -pipe -Os -gdwarf-2 -isysroot ${CROSS_TOP}/SDKs/${CROSS_SDK} -miphoneos-version-min=${MIPHONEOS} ${CC_BITCODE_FLAG} ${RUNTARGET}  "
	export LDFLAGS="-arch ${ARCH} -isysroot ${CROSS_TOP}/SDKs/${CROSS_SDK}"
	
   
	echo -e "${subbold}Building ${ZSTD_VERSION} for ${PLATFORM} ${IOS_SDK_VERSION} ${archbold}${ARCH}${dim} (iOS ${IOS_MIN_SDK_VERSION})"
	if [[ "${ARCH}" == "arm64" || "${ARCH}" == "arm64e"  ]]; then
		cmake $PASSTHRU .. &> "/tmp/${ZSTD_VERSION}-iOS-${ARCH}-${BITCODE}.log"
	else
		cmake $PASSTHRU .. &> "/tmp/${ZSTD_VERSION}-iOS-${ARCH}-${BITCODE}.log"
	fi

	cmake --build . --config Release --target libzstd_static >> "/tmp/${ZSTD_VERSION}-iOS-${ARCH}-${BITCODE}.log" 2>&1

	TARGET_DIR=${ZSTD}/iOS-simulator/$ARCH
	mkdir -p ${TARGET_DIR}/lib
	cp `find lib -name "libzstd.a"` ${TARGET_DIR}/lib
	mkdir -p ${TARGET_DIR}/include/zstd
	cp ../../../lib/*.h ${TARGET_DIR}/include/zstd

	rm -rf * >> "/tmp/${ZSTD_VERSION}-iOS-${ARCH}-${BITCODE}.log" 2>&1
	popd > /dev/null

	# Clean up exports
	export CC=""
	export CXX=""
	export CFLAGS=""
	export LDFLAGS=""
	export CPPFLAGS=""
}

buildTVOS()
{
	ARCH=$1

	mkdir -p "${ZSTD_VERSION}"/build/cmake/a
	pushd "${ZSTD_VERSION}"/build/cmake/a > /dev/null
  
	if [[ "${ARCH}" == "i386" || "${ARCH}" == "x86_64" ]]; then
		PLATFORM="AppleTVSimulator"
	else
		PLATFORM="AppleTVOS"
	fi

	export $PLATFORM
	export CROSS_TOP="${DEVELOPER}/Platforms/${PLATFORM}.platform/Developer"
	export CROSS_SDK="${PLATFORM}${TVOS_SDK_VERSION}.sdk"
	export BUILD_TOOLS="${DEVELOPER}"
	export CC="${BUILD_TOOLS}/usr/bin/gcc"
	export CFLAGS="-arch ${ARCH} -pipe -Os -gdwarf-2 -isysroot ${CROSS_TOP}/SDKs/${CROSS_SDK} -mtvos-version-min=${TVOS_MIN_SDK_VERSION} -fembed-bitcode"
	export LDFLAGS="-arch ${ARCH} -isysroot ${CROSS_TOP}/SDKs/${CROSS_SDK} ${ZSTDLIB}"
	export LC_CTYPE=C

	export PASSTHRU="-G Xcode -DCMAKE_TOOLCHAIN_FILE=$ZSTD/ios.toolchain.cmake"
	export PASSTHRU="$PASSTHRU -DDEPLOYMENT_TARGET=${TVOS_MIN_SDK_VERSION} -DARCHS=$ARCH -DPLATFORM=TVOS"
  
	echo -e "${subbold}Building ${ZSTD_VERSION} for ${PLATFORM} ${TVOS_SDK_VERSION} ${archbold}${ARCH}${dim} (tvOS ${TVOS_MIN_SDK_VERSION})"

	# Patch apps/speed.c to not use fork() since it's not available on tvOS
	# LANG=C sed -i -- 's/define HAVE_FORK 1/define HAVE_FORK 0/' "./apps/speed.c"

	# Patch Configure to build for tvOS, not iOS
	# LANG=C sed -i -- 's/D\_REENTRANT\:iOS/D\_REENTRANT\:tvOS/' "./configure-cmake"
	# chmod u+x ./configure-cmake
	
	cmake $PASSTHRU .. &> "/tmp/${ZSTD_VERSION}-tvOS-${ARCH}.log"
	# LANG=C sed -i -- 's/define HAVE_FORK 1/define HAVE_FORK 0/' "config.h"

	# add -isysroot to CC=
	#sed -ie "s!^CFLAG=!CFLAG=-isysroot ${CROSS_TOP}/SDKs/${CROSS_SDK} -mtvos-version-min=${TVOS_MIN_SDK_VERSION} !" "Makefile"

	cmake --build . --config Release --target libzstd_static >> "/tmp/${ZSTD_VERSION}-tvOS-${ARCH}-${BITCODE}.log" 2>&1

	TARGET_DIR=${ZSTD}/tvOS/$ARCH
	mkdir -p ${TARGET_DIR}/lib
	cp `find lib -name "libzstd.a"` ${TARGET_DIR}/lib
	mkdir -p ${TARGET_DIR}/include/zstd
	cp ../../../lib/*.h ${TARGET_DIR}/include/zstd

	rm -rf * >> "/tmp/${ZSTD_VERSION}-tvOS-${ARCH}-${BITCODE}.log" 2>&1

	popd > /dev/null

	# Clean up exports
	export CC=""
	export CXX=""
	export CFLAGS=""
	export LDFLAGS=""
	export CPPFLAGS=""
}

buildTVOSsim()
{
	ARCH=$1

	mkdir -p "${ZSTD_VERSION}"/build/cmake/a
	pushd "${ZSTD_VERSION}"/build/cmake/a > /dev/null

	PLATFORM="AppleTVSimulator"

	TARGET="darwin64-${ARCH}-cc"
	RUNTARGET="-target ${ARCH}-apple-tvos${TVOS_MIN_SDK_VERSION}-simulator"

	export $PLATFORM
	export SYSROOT=$(xcrun --sdk appletvsimulator --show-sdk-path)
	export BUILD_TOOLS="${DEVELOPER}"
	export CC="${BUILD_TOOLS}/usr/bin/gcc"
	export CFLAGS="-arch ${ARCH} -pipe -Os -gdwarf-2 -isysroot ${SYSROOT} -mtvos-version-min=${TVOS_MIN_SDK_VERSION} -fembed-bitcode ${RUNTARGET}"
	export LDFLAGS="-arch ${ARCH} -isysroot ${SYSROOT} ${ZSTDLIB}"
	export LC_CTYPE=C

	export PASSTHRU="-G Xcode -DCMAKE_TOOLCHAIN_FILE=$ZSTD/ios.toolchain.cmake"
	export PASSTHRU="$PASSTHRU -DDEPLOYMENT_TARGET=${TVOS_MIN_SDK_VERSION} -DARCHS=$ARCH -DPLATFORM=SIMULATOR_TVOS"

	echo -e "${subbold}Building ${ZSTD_VERSION} for ${PLATFORM} ${TVOS_SDK_VERSION} ${archbold}${ARCH}${dim} (tvOS Simulator ${TVOS_MIN_SDK_VERSION})"

	# Patch apps/speed.c to not use fork() since it's not available on tvOS
	# LANG=C sed -i -- 's/define HAVE_FORK 1/define HAVE_FORK 0/' "./apps/speed.c"

	# Patch Configure to build for tvOS, not iOS
	# LANG=C sed -i -- 's/D\_REENTRANT\:iOS/D\_REENTRANT\:tvOS/' "./configure-cmake"
	# chmod u+x ./configure-cmake

	if [[ "${ARCH}" == "arm64" ]]; then
		cmake $PASSTHRU .. &> "/tmp/${ZSTD_VERSION}-tvOS-simulator${ARCH}.log"
	else
		cmake $PASSTHRU .. &> "/tmp/${ZSTD_VERSION}-tvOS-simulator${ARCH}.log"
	fi

	# LANG=C sed -i -- 's/define HAVE_FORK 1/define HAVE_FORK 0/' "config.h"

	# add -isysroot to CC=
	#sed -ie "s!^CFLAG=!CFLAG=-isysroot ${CROSS_TOP}/SDKs/${CROSS_SDK} -mtvos-version-min=${TVOS_MIN_SDK_VERSION} !" "Makefile"


	cmake --build . --config Release --target libzstd_static >> "/tmp/${ZSTD_VERSION}-tvOS-${ARCH}-${BITCODE}.log" 2>&1

	TARGET_DIR=${ZSTD}/tvOS-simulator/$ARCH
	mkdir -p ${TARGET_DIR}/lib
	cp `find lib -name "libzstd.a"` ${TARGET_DIR}/lib
	mkdir -p ${TARGET_DIR}/include/zstd
	cp ../../../lib/*.h ${TARGET_DIR}/include/zstd

	rm -rf * >> "/tmp/${ZSTD_VERSION}-tvOS-${ARCH}-${BITCODE}.log" 2>&1

	popd > /dev/null

	# Clean up exports
	export CC=""
	export CXX=""
	export CFLAGS=""
	export LDFLAGS=""
	export CPPFLAGS=""
}

echo -e "${bold}Cleaning up${dim}"
rm -rf include/zstd/* lib/*
rm -fr Mac
rm -fr iOS
rm -fr tvOS
rm -fr Catalyst

mkdir -p lib
mkdir -p Mac
mkdir -p iOS
mkdir -p tvOS
mkdir -p Catalyst

rm -rf "/tmp/${ZSTD_VERSION}-*"
rm -rf "/tmp/${ZSTD_VERSION}-*.log"

rm -rf "${ZSTD_VERSION}"

if [ ! -e ${ZSTD_VERSION}.tar.gz ]; then
	echo "Downloading ${ZSTD_VERSION}.tar.gz"
	curl -Ls https://github.com/facebook/zstd/releases/download/v${ZSTD_VERNUM}/zstd-${ZSTD_VERNUM}.tar.gz -o "${ZSTD_VERSION}.tar.gz"
else
	echo "Using ${ZSTD_VERSION}.tar.gz"
fi

echo "Unpacking zstd"
tar xfz "${ZSTD_VERSION}.tar.gz"

echo -e "${bold}Building Mac libraries${dim}"
buildMac "x86_64"
buildMac "arm64"

lipo \
        "${ZSTD}/Mac/x86_64/lib/libzstd.a" \
		"${ZSTD}/Mac/arm64/lib/libzstd.a" \
        -create -output "${ZSTD}/lib/libzstd_Mac.a"

if [ $catalyst == "1" ]; then
echo -e "${bold}Building Catalyst libraries${dim}"
buildCatalyst "x86_64"
buildCatalyst "arm64"

lipo \
        "${ZSTD}/Catalyst/x86_64/lib/libzstd.a" \
		"${ZSTD}/Catalyst/arm64/lib/libzstd.a" \
        -create -output "${ZSTD}/lib/libzstd_Catalyst.a"
fi

echo -e "${bold}Building iOS libraries (bitcode)${dim}"
buildIOS "armv7" "bitcode"
buildIOS "armv7s" "bitcode"
buildIOS "arm64" "bitcode"
buildIOS "arm64e" "bitcode"


buildIOSsim "x86_64" "bitcode"
buildIOSsim "arm64" "bitcode"
buildIOSsim "i386" "bitcode"

lipo \
	"${ZSTD}/iOS/armv7/lib/libzstd.a" \
	"${ZSTD}/iOS/armv7s/lib/libzstd.a" \
	"${ZSTD}/iOS-simulator/i386/lib/libzstd.a" \
	"${ZSTD}/iOS/arm64/lib/libzstd.a" \
	"${ZSTD}/iOS/arm64e/lib/libzstd.a" \
	"${ZSTD}/iOS-simulator/x86_64/lib/libzstd.a" \
	-create -output "${ZSTD}/lib/libzstd_iOS-fat.a"

lipo \
	"${ZSTD}/iOS/armv7/lib/libzstd.a" \
	"${ZSTD}/iOS/armv7s/lib/libzstd.a" \
	"${ZSTD}/iOS/arm64/lib/libzstd.a" \
	"${ZSTD}/iOS/arm64e/lib/libzstd.a" \
	-create -output "${ZSTD}/lib/libzstd_iOS.a"

lipo \
	"${ZSTD}/iOS-simulator/i386/lib/libzstd.a" \
	"${ZSTD}/iOS-simulator/x86_64/lib/libzstd.a" \
	"${ZSTD}/iOS-simulator/arm64/lib/libzstd.a" \
	-create -output "${ZSTD}/lib/libzstd_iOS-simulator.a"


echo -e "${bold}Building tvOS libraries${dim}"
buildTVOS "arm64"

lipo \
        "${ZSTD}/tvOS/arm64/lib/libzstd.a" \
        -create -output "${ZSTD}/lib/libzstd_tvOS.a"

buildTVOSsim "x86_64"
buildTVOSsim "arm64"

lipo \
        "${ZSTD}/tvOS/arm64/lib/libzstd.a" \
        "${ZSTD}/tvOS-simulator/x86_64/lib/libzstd.a" \
        -create -output "${ZSTD}/lib/libzstd_tvOS-fat.a"

lipo \
	"${ZSTD}/tvOS-simulator/x86_64/lib/libzstd.a" \
	"${ZSTD}/tvOS-simulator/arm64/lib/libzstd.a" \
	-create -output "${ZSTD}/lib/libzstd_tvOS-simulator.a"

echo -e "${bold}Cleaning up${dim}"
rm -rf /tmp/${ZSTD_VERSION}-*
rm -rf ${ZSTD_VERSION}

#reset trap
trap - INT TERM EXIT

echo -e "${normal}Done"

