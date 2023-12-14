#!/bin/sh

BUILD_DIR=script_build

# Remove old build dir
if [ -d $BUILD_DIR ] ; then
	rm -rf $BUILD_DIR
fi

# Make and enter build dir
mkdir $BUILD_DIR && cd $BUILD_DIR

echo ""
echo "==================="
echo "=== libglibutil ==="
echo "==================="
echo ""

git clone --depth=1 https://github.com/waydroid/libglibutil.git
cd libglibutil
echo "3.0 (native)" > debian/source/format
gbp buildpackage -uc -us --git-debian-branch=bullseye --git-ignore-new
cd ..
sudo dpkg -i libglibutil_*_*.deb libglibutil-dev_*_*.deb
if [ $? != 0 ] ; then
	exit 1
fi

echo ""
echo "=================="
echo "=== libgbinder ==="
echo "=================="
echo ""

git clone --depth=1 https://github.com/waydroid/libgbinder.git
cd libgbinder
echo "3.0 (native)" > debian/source/format
gbp buildpackage -uc -us --git-debian-branch=bullseye --git-ignore-new
cd ..
sudo dpkg -i libgbinder_*_*.deb libgbinder-tools_*_*.deb libgbinder-dev_*_*.deb
if [ $? != 0 ] ; then
	exit 1
fi

echo ""
echo "======================"
echo "=== gbinder-python ==="
echo "======================"
echo ""

git clone --depth=1 https://github.com/waydroid/gbinder-python.git
cd gbinder-python
echo "3.0 (native)" > debian/source/format
EMAIL=email@example.com gbp dch --debian-branch=bullseye --upstream-branch=bullseye
sed -i '1s/(unknown)/(1.1.1)/' debian/changelog
gbp buildpackage -uc -us --git-debian-branch=bullseye --git-ignore-new
cd ..
sudo dpkg -i python3-gbinder_*_*.deb
if [ $? != 0 ] ; then
	exit 1
fi

echo ""
echo "================"
echo "=== waydroid ==="
echo "================"
echo ""

git clone --depth=1 https://github.com/waydroid/waydroid.git
cd waydroid
gbp buildpackage -uc -us --git-debian-branch=main
cd ..
sudo dpkg -i waydroid_*_all.deb
if [ $? != 0 ] ; then
	exit 1
fi

