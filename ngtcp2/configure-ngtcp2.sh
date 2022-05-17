#!/bin/bash
# This script downlaods and builds the Mac, iOS and tvOS libraries 
# 
# NOTE: pkg-config is required
 
set -x
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
trap 'echo -e "${alert}** ERROR with Build - Check /tmp/*.log${alertdim}"' INT TERM EXIT

# --- Edit this to update default version ---
LIBRARY_NAME="ngtcp2"

LIB_BUILD="`pwd`/build"
BUILD_ARGS="${BUILD_ARGS:- -disable-shared --enable-lib-only}"

bulld_args_delegate() {
	if [ "$(type -t build_args)" = 'function' ]; then
		build_args $1
	else
		echo $BUILD_ARGS
	fi
}

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
    echo -e "  ${subbold}$0${normal} [-v ${dim}<library name>${normal}] [-s ${dim}<iOS SDK version>${normal}] [-t ${dim}<tvOS SDK version>${normal}] [-m] [-x] [-h]"
    echo
	echo "         -v   name of library (default $LIBRARY_NAME)"
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
            LIBRARY_NAME="${OPTARG}"
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

LIB_BUILD_VERSION="${LIBRARY_NAME}"
DEVELOPER=`xcode-select -print-path`

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
		./configure --prefix=/tmp/pkg_config --with-internal-glib >> "/tmp/${LIB_BUILD_VERSION}.log" 2>&1
		make -j${CORES} >> "/tmp/${LIB_BUILD_VERSION}.log" 2>&1
		make install >> "/tmp/${LIB_BUILD_VERSION}.log" 2>&1
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

buildMac()
{
	ARCH=$1

	TARGET="darwin-i386-cc"
	BUILD_MACHINE=`uname -m`
	export CC="${BUILD_TOOLS}/usr/bin/gcc -fembed-bitcode"
	export CFLAGS="-arch ${ARCH} -pipe -Os -gdwarf-2 -fembed-bitcode"
	export LDFLAGS="-arch ${ARCH}"

	export OPENSSL_CFLAGS="-I`pwd`/../../openssl/Mac/include"
	export OPENSSL_LIBS="-L`pwd`/../../openssl/Mac/lib -lssl -lcrypto"
	export LIBNGHTTP3_CFLAGS="-I../nghttp3/build/Mac/arm64/include"
	export LIBNGHTTP3_LIBS="-L../nghttp3/build/lib/Mac -lnghttp3"
	
	if [[ $ARCH == "x86_64" ]]; then
		TARGET="darwin64-x86_64-cc"
		MACOS_VER="${MACOS_X86_64_VERSION}"
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

	echo -e "${subbold}Building ${LIB_BUILD_VERSION} for ${archbold}${ARCH}${dim} (MacOS ${MACOS_VER})"

	pushd . > /dev/null
	
	if [[ $ARCH != ${BUILD_MACHINE} ]]; then
		# cross compile required
		if [[ "${ARCH}" == "arm64" || "${ARCH}" == "arm64e"  ]]; then
			./configure $(bulld_args_delegate Mac/${ARCH})  --prefix="${LIB_BUILD}/Mac/${ARCH}" --host="arm-apple-darwin" &> "/tmp/${LIB_BUILD_VERSION}-${ARCH}.log"
		else
			./configure $(bulld_args_delegate Mac/${ARCH}) --prefix="${LIB_BUILD}/Mac/${ARCH}" --host="${ARCH}-apple-darwin" &> "/tmp/${LIB_BUILD_VERSION}-${ARCH}.log"
		fi
	else
		./configure $(bulld_args_delegate Mac/${ARCH}) --prefix="${LIB_BUILD}/Mac/${ARCH}" &> "/tmp/${LIB_BUILD_VERSION}-${ARCH}.log"
	fi
	make -j${CORES} >> "/tmp/${LIB_BUILD_VERSION}-${ARCH}.log" 2>&1
	make install >> "/tmp/${LIB_BUILD_VERSION}-${ARCH}.log" 2>&1
	make clean >> "/tmp/${LIB_BUILD_VERSION}-${ARCH}.log" 2>&1
	popd > /dev/null

	# Clean up exports
	export CC=""
	export CXX=""
	export CFLAGS=""
	export LDFLAGS=""
	export CPPFLAGS=""

	export OPENSSL_CFLAGS=""
	export OPENSSL_LIBS=""
	export LIBNGHTTP3_CFLAGS=""
	export LIBNGHTTP3_LIBS=""
}

buildCatalyst()
{
	ARCH=$1

	TARGET="darwin64-${ARCH}-cc"
	BUILD_MACHINE=`uname -m`

	export CC="${BUILD_TOOLS}/usr/bin/gcc"
    export CFLAGS="-arch ${ARCH} -pipe -Os -gdwarf-2 -fembed-bitcode -target ${ARCH}-apple-ios${CATALYST_IOS}-macabi "
    export LDFLAGS="-arch ${ARCH}"

	export OPENSSL_CFLAGS="-I`pwd`/../../openssl/Catalyst/include"
	export OPENSSL_LIBS="-L`pwd`/../../openssl/Catalyst/lib -lssl -lcrypto"
	export LIBNGHTTP3_CFLAGS="-I../nghttp3/build/Catalyst/arm64/include"
	export LIBNGHTTP3_LIBS="-L../nghttp3/build/lib/Catalyst -lnghttp3"

	if [[ $ARCH == "x86_64" ]]; then
		TARGET="darwin64-x86_64-cc"
		MACOS_VER="${MACOS_X86_64_VERSION}"
		if [ ${BUILD_MACHINE} == 'arm64' ]; then
   			# Apple ARM Silicon Build Machine Detected - cross compile
			TARGET="darwin64-x86_64-cc"
			MACOS_VER="${MACOS_X86_64_VERSION}"
			export CC="clang"
			export CXX="clang"
			export CFLAGS=" -Os -mmacosx-version-min=${MACOS_X86_64_VERSION} -arch ${ARCH} -gdwarf-2 -fembed-bitcode -target ${ARCH}-apple-ios${CATALYST_IOS}-macabi "
			export LDFLAGS=" -arch ${ARCH} -isysroot ${DEVELOPER}/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk "
			export CPPFLAGS=" -I.. -isysroot ${DEVELOPER}/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk "
		else
			# Apple x86_64 Build Machine Detected - native build
			export CFLAGS=" -mmacosx-version-min=${MACOS_X86_64_VERSION} -arch ${ARCH} -pipe -Os -gdwarf-2 -fembed-bitcode -target ${ARCH}-apple-ios${CATALYST_IOS}-macabi "
		fi
	fi
	if [[ $ARCH == "arm64" ]]; then
		TARGET="darwin64-arm64-cc"
		MACOS_VER="${MACOS_ARM64_VERSION}"
		if [ ${BUILD_MACHINE} == 'arm64' ]; then
   			# Apple ARM Silicon Build Machine Detected - native build
			TARGET="darwin64-arm64-cc"
			export CFLAGS=" -mmacosx-version-min=${MACOS_ARM64_VERSION} -arch ${ARCH} -pipe -Os -gdwarf-2 -fembed-bitcode -target ${ARCH}-apple-ios${CATALYST_IOS}-macabi "
		else
			# Apple x86_64 Build Machine Detected - cross compile
			TARGET="darwin64-arm64-cc"
			export CC="clang"
			export CXX="clang"
			export CFLAGS=" -Os -mmacosx-version-min=${MACOS_ARM64_VERSION} -arch ${ARCH} -gdwarf-2 -fembed-bitcode -target ${ARCH}-apple-ios${CATALYST_IOS}-macabi "
			export LDFLAGS=" -arch ${ARCH} -isysroot ${DEVELOPER}/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk "
			export CPPFLAGS=" -I.. -isysroot ${DEVELOPER}/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk "
		fi
	fi

	echo -e "${subbold}Building ${LIB_BUILD_VERSION} for ${archbold}${ARCH}${dim} (MacOS ${MACOS_VER} Catalyst iOS ${CATALYST_IOS})"

	pushd . > /dev/null
	

	# Cross compile required for Catalyst
	if [[ "${ARCH}" == "arm64" ]]; then
		./configure $(bulld_args_delegate Catalyst/${ARCH})  --prefix="${LIB_BUILD}/Catalyst/${ARCH}" --host="arm-apple-darwin" &> "/tmp/${LIB_BUILD_VERSION}-catalyst-${ARCH}.log"
	else
		./configure $(bulld_args_delegate Catalyst/${ARCH}) --prefix="${LIB_BUILD}/Catalyst/${ARCH}" --host="${ARCH}-apple-darwin" &> "/tmp/${LIB_BUILD_VERSION}-catalyst-${ARCH}.log"
	fi
	
	make -j${CORES} >> "/tmp/${LIB_BUILD_VERSION}-catalyst-${ARCH}.log" 2>&1
	make install >> "/tmp/${LIB_BUILD_VERSION}-catalyst-${ARCH}.log" 2>&1
	make clean >> "/tmp/${LIB_BUILD_VERSION}-catalyst-${ARCH}.log" 2>&1
	popd > /dev/null

	# Clean up exports
	export CC=""
	export CXX=""
	export CFLAGS=""
	export LDFLAGS=""
	export CPPFLAGS=""

	export OPENSSL_CFLAGS=""
	export OPENSSL_LIBS=""
	export LIBNGHTTP3_CFLAGS=""
	export LIBNGHTTP3_LIBS=""
}

buildIOS()
{
	ARCH=$1
	BITCODE=$2

	pushd . > /dev/null
	
  
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

	export OPENSSL_CFLAGS="-I`pwd`/../../openssl/iOS/include"
	export OPENSSL_LIBS="-L`pwd`/../../openssl/iOS/lib -lssl -lcrypto"
	export LIBNGHTTP3_CFLAGS="-I../nghttp3/build/iOS/arm64/include"
	export LIBNGHTTP3_LIBS="-L../nghttp3/build/lib/iOS -lnghttp3"
  
	export $PLATFORM
	export CROSS_TOP="${DEVELOPER}/Platforms/${PLATFORM}.platform/Developer"
	export CROSS_SDK="${PLATFORM}${IOS_SDK_VERSION}.sdk"
	export BUILD_TOOLS="${DEVELOPER}"
	export CC="${BUILD_TOOLS}/usr/bin/gcc"
	export CFLAGS="-arch ${ARCH} -pipe -Os -gdwarf-2 -isysroot ${CROSS_TOP}/SDKs/${CROSS_SDK} -miphoneos-version-min=${IOS_MIN_SDK_VERSION} ${CC_BITCODE_FLAG}"
	export LDFLAGS="-arch ${ARCH} -isysroot ${CROSS_TOP}/SDKs/${CROSS_SDK}"
   
	echo -e "${subbold}Building ${LIB_BUILD_VERSION} for ${PLATFORM} ${IOS_SDK_VERSION} ${archbold}${ARCH}${dim} (iOS ${IOS_MIN_SDK_VERSION})"
	if [[ "${ARCH}" == "arm64" || "${ARCH}" == "arm64e"  ]]; then
		./configure $(bulld_args_delegate iOS/${ARCH})  --prefix="${LIB_BUILD}/iOS/${ARCH}" --host="arm-apple-darwin" &> "/tmp/${LIB_BUILD_VERSION}-iOS-${ARCH}-${BITCODE}.log"
	else
		./configure $(bulld_args_delegate iOS/${ARCH}) --prefix="${LIB_BUILD}/iOS/${ARCH}" --host="${ARCH}-apple-darwin" &> "/tmp/${LIB_BUILD_VERSION}-iOS-${ARCH}-${BITCODE}.log"
	fi

	make -j8 >> "/tmp/${LIB_BUILD_VERSION}-iOS-${ARCH}-${BITCODE}.log" 2>&1
	make install >> "/tmp/${LIB_BUILD_VERSION}-iOS-${ARCH}-${BITCODE}.log" 2>&1
	make clean >> "/tmp/${LIB_BUILD_VERSION}-iOS-${ARCH}-${BITCODE}.log" 2>&1
	popd > /dev/null

	# Clean up exports
	export CC=""
	export CXX=""
	export CFLAGS=""
	export LDFLAGS=""
	export CPPFLAGS=""

	export OPENSSL_CFLAGS=""
	export OPENSSL_LIBS=""
	export LIBNGHTTP3_CFLAGS=""
	export LIBNGHTTP3_LIBS=""
}

buildIOSsim()
{
	ARCH=$1
	BITCODE=$2

	pushd . > /dev/null
	
  
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

	export OPENSSL_CFLAGS="-I`pwd`/../../openssl/iOS-simulator/include"
	export OPENSSL_LIBS="-L`pwd`/../../openssl/iOS-simulator/lib -lssl -lcrypto"
	export LIBNGHTTP3_CFLAGS="-I../nghttp3/build/iOS-simulator/arm64/include"
	export LIBNGHTTP3_LIBS="-L../nghttp3/build/lib/iOS-simulator -lnghttp3"
  
	export $PLATFORM
	export CROSS_TOP="${DEVELOPER}/Platforms/${PLATFORM}.platform/Developer"
	export CROSS_SDK="${PLATFORM}${IOS_SDK_VERSION}.sdk"
	export BUILD_TOOLS="${DEVELOPER}"
	export CC="${BUILD_TOOLS}/usr/bin/gcc"
	export CFLAGS="-arch ${ARCH} -pipe -Os -gdwarf-2 -isysroot ${CROSS_TOP}/SDKs/${CROSS_SDK} -miphoneos-version-min=${MIPHONEOS} ${CC_BITCODE_FLAG} ${RUNTARGET}  "
	export LDFLAGS="-arch ${ARCH} -isysroot ${CROSS_TOP}/SDKs/${CROSS_SDK}"
   
	echo -e "${subbold}Building ${LIB_BUILD_VERSION} for ${PLATFORM} ${IOS_SDK_VERSION} ${archbold}${ARCH}${dim} (iOS ${IOS_MIN_SDK_VERSION})"
	if [[ "${ARCH}" == "arm64" || "${ARCH}" == "arm64e"  ]]; then
	./configure $(bulld_args_delegate iOS-simulator/${ARCH})  --prefix="${LIB_BUILD}/iOS-simulator/${ARCH}" --host="arm-apple-darwin" &> "/tmp/${LIB_BUILD_VERSION}-iOS-${ARCH}-${BITCODE}.log"
	else
	./configure $(bulld_args_delegate iOS-simulator/${ARCH}) --prefix="${LIB_BUILD}/iOS-simulator/${ARCH}" --host="${ARCH}-apple-darwin" &> "/tmp/${LIB_BUILD_VERSION}-iOS-${ARCH}-${BITCODE}.log"
	fi

	make -j8 >> "/tmp/${LIB_BUILD_VERSION}-iOS-${ARCH}-${BITCODE}.log" 2>&1
	make install >> "/tmp/${LIB_BUILD_VERSION}-iOS-${ARCH}-${BITCODE}.log" 2>&1
	make clean >> "/tmp/${LIB_BUILD_VERSION}-iOS-${ARCH}-${BITCODE}.log" 2>&1
	popd > /dev/null

	# Clean up exports
	export CC=""
	export CXX=""
	export CFLAGS=""
	export LDFLAGS=""
	export CPPFLAGS=""

	export OPENSSL_CFLAGS=""
	export OPENSSL_LIBS=""
	export LIBNGHTTP3_CFLAGS=""
	export LIBNGHTTP3_LIBS=""
}

buildTVOS()
{
	ARCH=$1

	pushd . > /dev/null
  
	if [[ "${ARCH}" == "i386" || "${ARCH}" == "x86_64" ]]; then
		PLATFORM="AppleTVSimulator"
	else
		PLATFORM="AppleTVOS"
	fi

	export OPENSSL_CFLAGS="-I`pwd`/../../openssl/tvOS/include"
	export OPENSSL_LIBS="-L`pwd`/../../openssl/tvOS/lib -lssl -lcrypto"
	export LIBNGHTTP3_CFLAGS="-I../nghttp3/build/tvOS/arm64/include"
	export LIBNGHTTP3_LIBS="-L../nghttp3/build/lib/tvOS -lnghttp3"

	export $PLATFORM
	export CROSS_TOP="${DEVELOPER}/Platforms/${PLATFORM}.platform/Developer"
	export CROSS_SDK="${PLATFORM}${TVOS_SDK_VERSION}.sdk"
	export BUILD_TOOLS="${DEVELOPER}"
	export CC="${BUILD_TOOLS}/usr/bin/gcc"
	export CFLAGS="-arch ${ARCH} -pipe -Os -gdwarf-2 -isysroot ${CROSS_TOP}/SDKs/${CROSS_SDK} -mtvos-version-min=${TVOS_MIN_SDK_VERSION} -fembed-bitcode"
	export LDFLAGS="-arch ${ARCH} -isysroot ${CROSS_TOP}/SDKs/${CROSS_SDK} ${LIB_BUILDLIB}"
	export LC_CTYPE=C
  
	echo -e "${subbold}Building ${LIB_BUILD_VERSION} for ${PLATFORM} ${TVOS_SDK_VERSION} ${archbold}${ARCH}${dim} (tvOS ${TVOS_MIN_SDK_VERSION})"

	# Patch apps/speed.c to not use fork() since it's not available on tvOS
	# LANG=C sed -i -- 's/define HAVE_FORK 1/define HAVE_FORK 0/' "./apps/speed.c"

	# Patch Configure to build for tvOS, not iOS
	# LANG=C sed -i -- 's/D\_REENTRANT\:iOS/D\_REENTRANT\:tvOS/' "./Configure"
	# chmod u+x ./Configure
	
	./configure $(bulld_args_delegate tvOS/${ARCH})  --prefix="${LIB_BUILD}/tvOS/${ARCH}" --host="arm-apple-darwin" &> "/tmp/${LIB_BUILD_VERSION}-tvOS-${ARCH}.log"

	make -j8 >> "/tmp/${LIB_BUILD_VERSION}-tvOS-${ARCH}.log" 2>&1
	make install  >> "/tmp/${LIB_BUILD_VERSION}-tvOS-${ARCH}.log" 2>&1
	make clean >> "/tmp/${LIB_BUILD_VERSION}-tvOS-${ARCH}.log" 2>&1
	popd > /dev/null

	# Clean up exports
	export CC=""
	export CXX=""
	export CFLAGS=""
	export LDFLAGS=""
	export CPPFLAGS=""

	export OPENSSL_CFLAGS=""
	export OPENSSL_LIBS=""
	export LIBNGHTTP3_CFLAGS=""
	export LIBNGHTTP3_LIBS=""
}

buildTVOSsim()
{
	ARCH=$1

	pushd . > /dev/null

	PLATFORM="AppleTVSimulator"

	TARGET="darwin64-${ARCH}-cc"
	RUNTARGET="-target ${ARCH}-apple-tvos${TVOS_MIN_SDK_VERSION}-simulator"

	export OPENSSL_CFLAGS="-I`pwd`/../../openssl/tvOS-simulator/include"
	export OPENSSL_LIBS="-L`pwd`/../../openssl/tvOS-simulator/lib -lssl -lcrypto"
	export LIBNGHTTP3_CFLAGS="-I../nghttp3/build/tvOS-simulator/arm64/include"
	export LIBNGHTTP3_LIBS="-L../nghttp3/build/lib/tvOS-simulator -lnghttp3"

	export $PLATFORM
	export SYSROOT=$(xcrun --sdk appletvsimulator --show-sdk-path)
	export BUILD_TOOLS="${DEVELOPER}"
	export CC="${BUILD_TOOLS}/usr/bin/gcc"
	export CFLAGS="-arch ${ARCH} -pipe -Os -gdwarf-2 -isysroot ${SYSROOT} -mtvos-version-min=${TVOS_MIN_SDK_VERSION} -fembed-bitcode ${RUNTARGET}"
	export LDFLAGS="-arch ${ARCH} -isysroot ${SYSROOT} ${LIB_BUILDLIB}"
	export LC_CTYPE=C

	echo -e "${subbold}Building ${LIB_BUILD_VERSION} for ${PLATFORM} ${TVOS_SDK_VERSION} ${archbold}${ARCH}${dim} (tvOS Simulator ${TVOS_MIN_SDK_VERSION})"

	# Patch apps/speed.c to not use fork() since it's not available on tvOS
	# LANG=C sed -i -- 's/define HAVE_FORK 1/define HAVE_FORK 0/' "./apps/speed.c"

	# Patch Configure to build for tvOS, not iOS
	# LANG=C sed -i -- 's/D\_REENTRANT\:iOS/D\_REENTRANT\:tvOS/' "./Configure"
	# chmod u+x ./Configure

	if [[ "${ARCH}" == "arm64" ]]; then
	./configure $(bulld_args_delegate tvOS-simulator/${ARCH})  --prefix="${LIB_BUILD}/tvOS-simulator/${ARCH}" --host="arm-apple-darwin" &> "/tmp/${LIB_BUILD_VERSION}-tvOS-simulator${ARCH}.log"
	else
	./configure $(bulld_args_delegate tvOS-simulator/${ARCH})  --prefix="${LIB_BUILD}/tvOS-simulator/${ARCH}" --host="${ARCH}-apple-darwin" &> "/tmp/${LIB_BUILD_VERSION}-tvOS-simulator${ARCH}.log"
	fi

	LANG=C sed -i -- 's/define HAVE_FORK 1/define HAVE_FORK 0/' "config.h"

	# add -isysroot to CC=
	#sed -ie "s!^CFLAG=!CFLAG=-isysroot ${CROSS_TOP}/SDKs/${CROSS_SDK} -mtvos-version-min=${TVOS_MIN_SDK_VERSION} !" "Makefile"

	make -j8 >> "/tmp/${LIB_BUILD_VERSION}-tvOS-${ARCH}.log" 2>&1
	make install  >> "/tmp/${LIB_BUILD_VERSION}-tvOS-${ARCH}.log" 2>&1
	make clean >> "/tmp/${LIB_BUILD_VERSION}-tvOS-${ARCH}.log" 2>&1
	popd > /dev/null

	# Clean up exports
	export CC=""
	export CXX=""
	export CFLAGS=""
	export LDFLAGS=""
	export CPPFLAGS=""

	export OPENSSL_CFLAGS=""
	export OPENSSL_LIBS=""
	export LIBNGHTTP3_CFLAGS=""
	export LIBNGHTTP3_LIBS=""
}

echo -e "${bold}Cleaning up${dim}"
rm -rf "${LIB_BUILD}"

mkdir -p "${LIB_BUILD}/lib"
mkdir -p "${LIB_BUILD}/Mac"
mkdir -p "${LIB_BUILD}/iOS"
mkdir -p "${LIB_BUILD}/tvOS"
mkdir -p "${LIB_BUILD}/Catalyst"

rm -rf "/tmp/${LIBRARY_NAME}-*"
rm -rf "/tmp/${LIBRARY_NAME}-*.log"


echo -e "${bold}Building Mac libraries${dim}"
buildMac "x86_64"
buildMac "arm64"

lipo \
        "${LIB_BUILD}/Mac/x86_64/lib/lib${LIBRARY_NAME}.a" \
		"${LIB_BUILD}/Mac/arm64/lib/lib${LIBRARY_NAME}.a" \
        -create -output "${LIB_BUILD}/lib/lib${LIBRARY_NAME}_Mac.a"

if [ $catalyst == "1" ]; then
    echo -e "${bold}Building Catalyst libraries${dim}"
    buildCatalyst "x86_64"
    buildCatalyst "arm64"

    lipo \
            "${LIB_BUILD}/Catalyst/x86_64/lib/lib${LIBRARY_NAME}.a" \
            "${LIB_BUILD}/Catalyst/arm64/lib/lib${LIBRARY_NAME}.a" \
            -create -output "${LIB_BUILD}/lib/lib${LIBRARY_NAME}_Catalyst.a"
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
	"${LIB_BUILD}/iOS/armv7/lib/lib${LIBRARY_NAME}.a" \
	"${LIB_BUILD}/iOS/armv7s/lib/lib${LIBRARY_NAME}.a" \
	"${LIB_BUILD}/iOS-simulator/i386/lib/lib${LIBRARY_NAME}.a" \
	"${LIB_BUILD}/iOS/arm64/lib/lib${LIBRARY_NAME}.a" \
	"${LIB_BUILD}/iOS/arm64e/lib/lib${LIBRARY_NAME}.a" \
	"${LIB_BUILD}/iOS-simulator/x86_64/lib/lib${LIBRARY_NAME}.a" \
	-create -output "${LIB_BUILD}/lib/lib${LIBRARY_NAME}_iOS-fat.a"

lipo \
	"${LIB_BUILD}/iOS/armv7/lib/lib${LIBRARY_NAME}.a" \
	"${LIB_BUILD}/iOS/armv7s/lib/lib${LIBRARY_NAME}.a" \
	"${LIB_BUILD}/iOS/arm64/lib/lib${LIBRARY_NAME}.a" \
	"${LIB_BUILD}/iOS/arm64e/lib/lib${LIBRARY_NAME}.a" \
	-create -output "${LIB_BUILD}/lib/lib${LIBRARY_NAME}_iOS.a"

lipo \
	"${LIB_BUILD}/iOS-simulator/i386/lib/lib${LIBRARY_NAME}.a" \
	"${LIB_BUILD}/iOS-simulator/x86_64/lib/lib${LIBRARY_NAME}.a" \
	"${LIB_BUILD}/iOS-simulator/arm64/lib/lib${LIBRARY_NAME}.a" \
	-create -output "${LIB_BUILD}/lib/lib${LIBRARY_NAME}_iOS-simulator.a"

echo -e "${bold}Building tvOS libraries${dim}"
buildTVOS "arm64"

lipo \
        "${LIB_BUILD}/tvOS/arm64/lib/lib${LIBRARY_NAME}.a" \
        -create -output "${LIB_BUILD}/lib/lib${LIBRARY_NAME}_tvOS.a"

buildTVOSsim "x86_64"
buildTVOSsim "arm64"

lipo \
        "${LIB_BUILD}/tvOS/arm64/lib/lib${LIBRARY_NAME}.a" \
        "${LIB_BUILD}/tvOS-simulator/x86_64/lib/lib${LIBRARY_NAME}.a" \
        -create -output "${LIB_BUILD}/lib/lib${LIBRARY_NAME}_tvOS-fat.a"

lipo \
	"${LIB_BUILD}/tvOS-simulator/x86_64/lib/lib${LIBRARY_NAME}.a" \
	"${LIB_BUILD}/tvOS-simulator/arm64/lib/lib${LIBRARY_NAME}.a" \
	-create -output "${LIB_BUILD}/lib/lib${LIBRARY_NAME}_tvOS-simulator.a"

echo -e "${bold}Cleaning up${dim}"
rm -rf /tmp/${LIB_BUILD_VERSION}-*


mkdir -p $LIB_BUILD/xcframework
mkdir -p $LIB_BUILD/lib/Mac
mkdir -p $LIB_BUILD/lib/iOS
mkdir -p $LIB_BUILD/lib/iOS-simulator
mkdir -p $LIB_BUILD/lib/tvOS
mkdir -p $LIB_BUILD/lib/tvOS-simulator
mkdir -p $LIB_BUILD/lib/Catalyst

build_xc()
{
	libname="$1"

	cp ${LIB_BUILD}/lib/lib${libname}_iOS.a $LIB_BUILD/lib/iOS/lib${libname}.a
	cp ${LIB_BUILD}/lib/lib${libname}_iOS-simulator.a $LIB_BUILD/lib/iOS-simulator/lib${libname}.a
	cp ${LIB_BUILD}/lib/lib${libname}_tvOS.a $LIB_BUILD/lib/tvOS/lib${libname}.a
	cp ${LIB_BUILD}/lib/lib${libname}_tvOS-simulator.a $LIB_BUILD/lib/tvOS-simulator/lib${libname}.a
	cp ${LIB_BUILD}/lib/lib${libname}_Mac.a $LIB_BUILD/lib/Mac/lib${libname}.a
	if [ "$catalyst" == "1" ]; then
		cp ${libname}/lib/lib${libname}_Catalyst.a $LIB_BUILD/lib/Catalyst/lib${libname}.a
		xcodebuild -create-xcframework \
			-library $LIB_BUILD/lib/iOS/lib${libname}.a \
            -headers $LIB_BUILD/iOS/arm64/include \
			-library $LIB_BUILD/lib/iOS-simulator/lib${libname}.a \
            -headers $LIB_BUILD/iOS-simulator/arm64/include \
			-library $LIB_BUILD/lib/tvOS/lib${libname}.a \
            -headers $LIB_BUILD/tvOS/arm64/include \
			-library $LIB_BUILD/lib/tvOS-simulator/lib${libname}.a \
            -headers $LIB_BUILD/tvOS-simulator/arm64/include \
			-library $LIB_BUILD/lib/Catalyst/lib${libname}.a \
            -headers $LIB_BUILD/Catalyst/arm64/include \
            -library $LIB_BUILD/lib/Mac/lib${libname}.a \
            -headers $LIB_BUILD/Mac/arm64/include \
			-output $LIB_BUILD/xcframework/lib${libname}.xcframework
	else
		xcodebuild -create-xcframework \
			-library $LIB_BUILD/lib/iOS/lib${libname}.a \
            -headers $LIB_BUILD/iOS/arm64/include \
			-library $LIB_BUILD/lib/iOS-simulator/lib${libname}.a \
            -headers $LIB_BUILD/iOS-simulator/arm64/include \
			-library $LIB_BUILD/lib/tvOS/lib${libname}.a \
            -headers $LIB_BUILD/tvOS/arm64/include \
			-library $LIB_BUILD/lib/tvOS-simulator/lib${libname}.a \
            -headers $LIB_BUILD/tvOS-simulator/arm64/include \
            -library $LIB_BUILD/lib/Mac/lib${libname}.a \
            -headers $LIB_BUILD/Mac/arm64/include \
			-output $LIB_BUILD/xcframework/lib${libname}.xcframework
	fi

}

build_xc ${LIBRARY_NAME}

#reset trap
trap - INT TERM EXIT

echo -e "${normal}Done"

