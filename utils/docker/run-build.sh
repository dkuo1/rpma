#!/usr/bin/env bash
#
# SPDX-License-Identifier: BSD-3-Clause
# Copyright 2016-2020, Intel Corporation
#

#
# run-build.sh - is called inside a Docker container,
#                starts rpma build with tests.
#

set -e

if [ "$WORKDIR" == "" ]; then
	echo "Error: WORKDIR is not set"
	exit 1
fi

./prepare-for-build.sh

EXAMPLE_TEST_DIR="/tmp/rpma_example_build"
PREFIX=/usr
TEST_DIR=${RPMA_TEST_DIR:-${DEFAULT_TEST_DIR}}
CHECK_CSTYLE=${CHECK_CSTYLE:-ON}
CC=${CC:-gcc}

function sudo_password() {
	echo $USERPASS | sudo -Sk $*
}

function upload_codecov() {
	printf "\n$(tput setaf 1)$(tput setab 7)COVERAGE ${FUNCNAME[0]} START$(tput sgr 0)\n"

	# set proper gcov command
	clang_used=$(cmake -LA -N . | grep CMAKE_C_COMPILER | grep clang | wc -c)
	if [[ $clang_used > 0 ]]; then
		gcovexe="llvm-cov gcov"
	else
		gcovexe="gcov"
	fi

	# run gcov exe, using their bash (remove parsed coverage files, set flag and exit 1 if not successful)
	# we rely on parsed report on codecov.io; the output is quite long, hence it's disabled using -X flag
	/opt/scripts/codecov -c -F $1 -Z -x "$gcovexe" -X "gcovout"

	printf "check for any leftover gcov files\n"
	leftover_files=$(find . -name "*.gcov" | wc -l)
	if [[ $leftover_files > 0 ]]; then
		# display found files and exit with error (they all should be parsed)
		find . -name "*.gcov"
		return 1
	fi

	printf "$(tput setaf 1)$(tput setab 7)COVERAGE ${FUNCNAME[0]} END$(tput sgr 0)\n\n"
}

function compile_example_standalone() {
	rm -rf $EXAMPLE_TEST_DIR
	mkdir $EXAMPLE_TEST_DIR
	cd $EXAMPLE_TEST_DIR

	cmake $1

	# exit on error
	if [[ $? != 0 ]]; then
		cd -
		return 1
	fi

	make -j$(nproc)
	cd -
}

echo
echo "##################################################################"
echo "### Verify build and install (in dir: ${PREFIX}) ($CC, DEBUG)"
echo "##################################################################"

mkdir -p $WORKDIR/build
cd $WORKDIR/build

CC=$CC \
cmake .. -DCMAKE_BUILD_TYPE=Debug \
	-DTEST_DIR=$TEST_DIR \
	-DCMAKE_INSTALL_PREFIX=$PREFIX \
	-DCOVERAGE=$COVERAGE \
	-DCHECK_CSTYLE=${CHECK_CSTYLE} \
	-DDEVELOPER_MODE=1

make -j$(nproc)
make -j$(nproc) doc
ctest --output-on-failure
sudo_password -S make -j$(nproc) install

if [ "$COVERAGE" == "1" ]; then
	upload_codecov tests
fi

# Create a PR with generated docs
if [ "$AUTO_DOC_UPDATE" == "1" ]; then
	echo "Running auto doc update"
	../utils/docker/run-doc-update.sh
fi

# Test standalone compilation of all examples
EXAMPLES=$(ls -1 $WORKDIR/examples/)
for e in $EXAMPLES; do
	DIR=$WORKDIR/examples/$e
	[ ! -d $DIR ] && continue
	[ ! -f $DIR/CMakeLists.txt ] && continue
	echo
	echo "###########################################################"
	echo "### Testing standalone compilation of example: $e"
	echo "### (with librpma installed from DEBUG sources)"
	echo "###########################################################"
	compile_example_standalone $DIR
done

# Uninstall libraries
cd $WORKDIR/build
sudo_password -S make uninstall

cd $WORKDIR
rm -rf $WORKDIR/build

echo
echo "##################################################################"
echo "### Verify build and install (in dir: ${PREFIX}) ($CC, RELEASE)"
echo "##################################################################"

mkdir -p $WORKDIR/build
cd $WORKDIR/build

CC=$CC \
cmake .. -DCMAKE_BUILD_TYPE=Release \
	-DTEST_DIR=$TEST_DIR \
	-DCMAKE_INSTALL_PREFIX=$PREFIX \
	-DCPACK_GENERATOR=$PACKAGE_MANAGER \
	-DCHECK_CSTYLE=${CHECK_CSTYLE} \
	-DDEVELOPER_MODE=1

make -j$(nproc)
make -j$(nproc) doc
ctest --output-on-failure
# Do not install the library from sources here,
# because it will be installed from the packages below.

echo "##############################################################"
echo "### Making and testing packages (RELEASE version) ..."
echo "##############################################################"

make -j$(nproc) package

find . -iname "librpma*.$PACKAGE_MANAGER"

if [ $PACKAGE_MANAGER = "deb" ]; then
	echo "$ dpkg-deb --info ./librpma*.deb"
	dpkg-deb --info ./librpma*.deb

	echo "$ dpkg-deb -c ./librpma*.deb"
	dpkg-deb -c ./librpma*.deb

	echo "$ sudo -S dpkg -i ./librpma*.deb"
	echo $USERPASS | sudo -S dpkg -i ./librpma*.deb || /bin/bash -i

elif [ $PACKAGE_MANAGER = "rpm" ]; then
	echo "$ rpm -q --info ./librpma*.rpm"
	rpm -q --info ./librpma*.rpm && true

	echo "$ rpm -q --list ./librpma*.rpm"
	rpm -q --list ./librpma*.rpm && true

	echo "$ sudo -S rpm -ivh --force *.rpm"
	echo $USERPASS | sudo -S rpm -ivh --force *.rpm
fi

# Test standalone compilation of all examples
EXAMPLES=$(ls -1 $WORKDIR/examples/)
for e in $EXAMPLES; do
	DIR=$WORKDIR/examples/$e
	[ ! -d $DIR ] && continue
	[ ! -f $DIR/CMakeLists.txt ] && continue
	echo
	echo "###########################################################"
	echo "### Testing standalone compilation of example: $e"
	echo "### (with librpma installed from RELEASE packages)"
	echo "###########################################################"
	compile_example_standalone $DIR
done

cd $WORKDIR
rm -rf $WORKDIR/build
