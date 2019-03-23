#!/bin/sh

# Build the portable Git for Windows.

die () {
	echo "$*" >&1
	exit 1
}

output_directory="$HOME"
include_pdbs=
while test $# -gt 0
do
	case "$1" in
	--output)
		shift
		output_directory="$1"
		;;
	--output=*)
		output_directory="${1#*=}"
		;;
	--include-pdbs)
		include_pdbs=t
		;;
	-*)
		die "Unknown option: $1"
		;;
	*)
		break
	esac
	shift
done

test $# -gt 0 ||
die "Usage: $0 [--output=<directory>] <version> [optional components]"

test -d "$output_directory" ||
die "Directory inaccessible: '$output_directory'"

ARCH="$(uname -m)"
case "$ARCH" in
i686)
	BITNESS=32
	MD_ARG=128M
	;;
x86_64)
	BITNESS=64
	MD_ARG=256M
	;;
*)
	die "Unhandled architecture: $ARCH"
	;;
esac
VERSION=$1
shift
TARGET="$output_directory"/PortableMSYS2-"$VERSION"-"$BITNESS"-bit.7z.exe
OPTS7="-m0=lzma -mx=9 -md=$MD_ARG -mfb=273 -ms=256M "
TMPPACK=/tmp.7z
SCRIPT_PATH="$(cd "$(dirname "$0")" && pwd)"

case "$SCRIPT_PATH" in
*" "*)
	die "This script cannot handle spaces in $SCRIPT_PATH"
	;;
esac

# Generate a couple of files dynamically

cp "$SCRIPT_PATH/../LICENSE.txt" "$SCRIPT_PATH/root/" ||
die "Could not copy license file"

# TODO this is in vc as is root/usr
mkdir -p "$SCRIPT_PATH/root/etc" ||
die "Could not make etc/ directory"

mkdir -p "$SCRIPT_PATH/root/tmp" ||
die "Could not make tmp/ directory"

mkdir -p "$SCRIPT_PATH/root/bin" ||
die "Could not make bin/ directory"

cp /cmd/git.exe "$SCRIPT_PATH/root/bin/git.exe" &&
cp /mingw$BITNESS/share/git/compat-bash.exe "$SCRIPT_PATH/root/bin/bash.exe" &&
cp /mingw$BITNESS/share/git/compat-bash.exe "$SCRIPT_PATH/root/bin/sh.exe" ||
die "Could not install bin/ redirectors"

cp "$SCRIPT_PATH/../post-install.bat" "$SCRIPT_PATH/root/" ||
die "Could not copy post-install script"

mkdir -p "$SCRIPT_PATH/root/mingw$BITNESS/etc" &&
cp /mingw$BITNESS/etc/gitconfig \
	"$SCRIPT_PATH/root/mingw$BITNESS/etc/gitconfig" &&
git config -f "$SCRIPT_PATH/root/mingw$BITNESS/etc/gitconfig" \
	credential.helper manager ||
die "Could not configure Git-Credential-Manager as default"
test 64 != $BITNESS ||
git config -f "$SCRIPT_PATH/root/mingw$BITNESS/etc/gitconfig" --unset pack.packSizeLimit

# Make a list of files to include
echo Generating file list
LIST="$(ARCH=$ARCH BITNESS=$BITNESS \
	PACKAGE_VERSIONS_FILE="$SCRIPT_PATH"/root/etc/package-versions.txt \
	sh "$SCRIPT_PATH"/../make-file-list-msys2.sh "$@" |
	grep -v "^mingw$BITNESS/etc/gitconfig$")" ||
die "Could not generate file list"

rm -rf "$SCRIPT_PATH/root/mingw$BITNESS/libexec/git-core" &&
mkdir -p "$SCRIPT_PATH/root/mingw$BITNESS/libexec/git-core" &&
ln $(echo "$LIST" | sed -n "s|^mingw$BITNESS/bin/[^/]*\.dll$|/&|p") \
	"$SCRIPT_PATH/root/mingw$BITNESS/libexec/git-core/" ||
die "Could not copy .dll files into libexec/git-core/"

# TODO there are few extra untacked files under /root. Can't figure how they got there
# TODO check for any unwanted pdbs
test -z "$include_pdbs" || {
	find "$SCRIPT_PATH/root" -name \*.pdb -exec rm {} \; &&
	"$SCRIPT_PATH"/../please.sh bundle-pdbs \
		--arch=$ARCH --unpack="$SCRIPT_PATH"/root
} ||
die "Could not unpack .pdb files"

# 7-Zip will strip absolute paths completely... therefore, we can add another
# root directory like this:

LIST="$LIST $SCRIPT_PATH/root/*"

# Make the self-extracting package

type 7za > /dev/null ||
pacman -Sy --noconfirm p7zip ||
die "Could not install 7-Zip"

echo "Creating archive" &&
(cd / && 7za a $OPTS7 $TMPPACK $LIST) &&
(cat "$SCRIPT_PATH/../7-Zip/7zSD.sfx" &&
 echo ';!@Install@!UTF-8!' &&
 echo 'Title="Portable MSYS2 for Windows '$BITNESS'-bit"' &&
 echo 'BeginPrompt="This archive extracts a minimal MSYS2 for Windows '$BITNESS'-bit"' &&
 echo 'CancelPrompt="Do you want to cancel the portable MSYS2 installation?"' &&
 echo 'ExtractDialogText="Please, wait..."' &&
 echo 'ExtractPathText="Where do you want to install portable MSYS2?"' &&
 echo 'ExtractTitle="Extracting..."' &&
 echo 'GUIFlags="8+32+64+256+4096"' &&
 echo 'GUIMode="1"' &&
 echo 'InstallPath="%%S\\PortableMSYS2"' &&
 echo 'OverwriteMode="0"' &&
 echo "RunProgram=\"git-bash.exe --needs-console --hide --no-cd --command=post-install.bat\"" &&
 echo ';!@InstallEnd@!' &&
 cat "$TMPPACK") > "$TARGET" &&
echo "Success! You will find the new installer at \"$TARGET\"." &&
echo "It is a self-extracting .7z archive." &&
rm $TMPPACK
