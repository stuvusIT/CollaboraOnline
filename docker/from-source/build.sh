#! /bin/sh
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

# -- Available env vars --
# * DOCKER_HUB_REPO - which Docker Hub repo to use
# * DOCKER_HUB_TAG  - which Docker Hub tag to create
# * CORE_BRANCH  - which branch to build in core
# * COLLABORA_ONLINE_REPO - which git repo to clone online from
# * COLLABORA_ONLINE_BRANCH - which branch to build in online
# * CORE_BUILD_TARGET - which make target to run (in core repo)
# * ONLINE_EXTRA_BUILD_OPTIONS - extra build options for online
# * NO_DOCKER_IMAGE - if set, don't build the docker image itself, just do all the preps

# check we can sudo without asking a pwd
echo "Trying if sudo works without a password"
echo
echo "If you get a password prompt now, break, and fix your setup using 'sudo visudo'; add something like:"
echo "yourusername ALL=(ALL) NOPASSWD: /sbin/setcap"
echo
sudo echo "works"

DOCKER_HUB_REPO=$CI_REGISTRY_IMAGE

# Check env variables
if [ -z "$DOCKER_HUB_REPO" ]; then
  DOCKER_HUB_REPO="mydomain/collaboraonline"
fi;
if [ -z "$DOCKER_HUB_TAG" ]; then
  DOCKER_HUB_TAG="latest"
fi;
echo "Using Docker Hub Repository: '$DOCKER_HUB_REPO' with tag '$DOCKER_HUB_TAG'."

if [ -z "$CORE_BRANCH" ]; then
  CORE_BRANCH="distro/collabora/cp-6.4"
fi;
echo "Building core branch '$CORE_BRANCH'"

if [ -z "$COLLABORA_ONLINE_REPO" ]; then
  COLLABORA_ONLINE_REPO="https://github.com/CollaboraOnline/online.git"
fi;
if [ -z "$COLLABORA_ONLINE_BRANCH" ]; then
  COLLABORA_ONLINE_BRANCH="master"
fi;
echo "Building online branch '$COLLABORA_ONLINE_BRANCH' from '$COLLABORA_ONLINE_REPO'"

if [ -z "$CORE_BUILD_TARGET" ]; then
  CORE_BUILD_TARGET=""
fi;
echo "LOKit (core) build target: '$CORE_BUILD_TARGET'"


SRCDIR=$(realpath `dirname $0`)
INSTDIR="$SRCDIR/instdir"

if [ -z "$(lsb_release -si)" ]; then
  echo "WARNING: Unable to determine your distribution"
  echo "(Is lsb_release installed?)"
  echo "Using Ubuntu Dockerfile."
  HOST_OS="Ubuntu"
else
  HOST_OS=$(lsb_release -si)
fi
if ! [ -e "$SRCDIR/$HOST_OS" ]; then
  echo "There is no suitable Dockerfile for your host system: $HOST_OS."
  echo "Please fix this problem and re-run $0"
  exit 1
fi
BUILDDIR="$SRCDIR/builddir"

mkdir -p "$BUILDDIR"
cd "$BUILDDIR"

rm -rf "$INSTDIR" || true
mkdir -p "$INSTDIR"

##### build static poco #####

if test ! -f poco/lib/libPocoFoundation.a ; then
    wget https://github.com/pocoproject/poco/archive/poco-1.10.1-release.tar.gz
    tar -xzf poco-1.10.1-release.tar.gz
    cd poco-poco-1.10.1-release/
    ./configure --static --no-tests --no-samples --no-sharedlibs --cflags="-fPIC" --omit=Zip,Data,Data/SQLite,Data/ODBC,Data/MySQL,MongoDB,PDF,CppParser,PageCompiler,Redis,Encodings --prefix=$BUILDDIR/poco
    make -j 8
    make install
    cd ..
fi


##### cloning & updating #####

# core repo
if test ! -d core ; then
  git clone https://git.libreoffice.org/core || exit 1
fi

( cd core && git fetch --all && git checkout $CORE_BRANCH && ./g pull -r ) || exit 1


# online repo
if test ! -d online ; then
  git clone "$COLLABORA_ONLINE_REPO" online || exit 1
fi

( cd online && git fetch --all && git checkout -f $COLLABORA_ONLINE_BRANCH && git clean -f -d && git pull -r ) || exit 1

cd core
# The following content has been copied from https://github.com/NixOS/nixpkgs/blob/master/pkgs/applications/office/libreoffice/default.nix
# Copyright (c) 2003-2021 Eelco Dolstra and the Nixpkgs/NixOS contributors
# 
# Permission is hereby granted, free of charge, to any person obtaining
# a copy of this software and associated documentation files (the
# "Software"), to deal in the Software without restriction, including
# without limitation the rights to use, copy, modify, merge, publish,
# distribute, sublicense, and/or sell copies of the Software, and to
# permit persons to whom the Software is furnished to do so, subject to
# the following conditions:
# 
# The above copyright notice and this permission notice shall be
# included in all copies or substantial portions of the Software.
# 
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
# EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
# MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
# NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
# LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
# OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
# WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

# unit test sd_tiledrendering seems to be fragile
# https://nabble.documentfoundation.org/libreoffice-5-0-failure-in-CUT-libreofficekit-tiledrendering-td4150319.html
echo > ./sd/CppunitTest_sd_tiledrendering.mk
sed -e /CppunitTest_sd_tiledrendering/d -i sd/Module_sd.mk
# Pivot chart tests. Fragile.
sed -e '/CPPUNIT_TEST(testRoundtrip)/d' -i chart2/qa/extras/PivotChartTest.cxx
sed -e '/CPPUNIT_TEST(testPivotTableMedianODS)/d' -i sc/qa/unit/pivottable_filters_test.cxx
# one more fragile test?
sed -e '/CPPUNIT_TEST(testTdf96536);/d' -i sw/qa/extras/uiwriter/uiwriter.cxx
# this I actually hate, this should be a data consistency test!
sed -e '/CPPUNIT_TEST(testTdf115013);/d' -i sw/qa/extras/uiwriter/uiwriter.cxx
# rendering-dependent test
sed -e '/CPPUNIT_ASSERT_EQUAL(11148L, pOleObj->GetLogicRect().getWidth());/d ' -i sc/qa/unit/subsequent_filters-test.cxx
# tilde expansion in path processing checks the existence of $HOME
sed -e 's@OString sSysPath("~/tmp");@& return ; @' -i sal/qa/osl/file/osl_File.cxx
# fails on systems using ZFS, see https://github.com/NixOS/nixpkgs/issues/19071
sed -e '/CPPUNIT_TEST(getSystemPathFromFileURL_005);/d' -i './sal/qa/osl/file/osl_File.cxx'
# rendering-dependent: on my computer the test table actually doesn't fit…
# interesting fact: test disabled on macOS by upstream
sed -re '/DECLARE_WW8EXPORT_TEST[(]testTableKeep, "tdf91083.odt"[)]/,+5d' -i ./sw/qa/extras/ww8export/ww8export.cxx
# Segfault on DB access — maybe temporarily acceptable for a new version of Fresh?
sed -e 's/CppunitTest_dbaccess_empty_stdlib_save//' -i ./dbaccess/Module_dbaccess.mk
# one more fragile test?
sed -e '/CPPUNIT_TEST(testTdf77014);/d' -i sw/qa/extras/uiwriter/uiwriter.cxx
# rendering-dependent tests
sed -e '/CPPUNIT_TEST(testCustomColumnWidthExportXLSX)/d' -i sc/qa/unit/subsequent_export-test.cxx
sed -e '/CPPUNIT_TEST(testColumnWidthExportFromODStoXLSX)/d' -i sc/qa/unit/subsequent_export-test.cxx
sed -e '/CPPUNIT_TEST(testChartImportXLS)/d' -i sc/qa/unit/subsequent_filters-test.cxx
sed -e '/CPPUNIT_TEST(testLegacyCellAnchoredRotatedShape)/d' -i sc/qa/unit/filters-test.cxx
sed -zre 's/DesktopLOKTest::testGetFontSubset[^{]*[{]/& return; /' -i desktop/qa/desktop_lib/test_desktop_lib.cxx
sed -z -r -e 's/DECLARE_OOXMLEXPORT_TEST[(]testFlipAndRotateCustomShape,[^)]*[)].[{]/& return;/' -i sw/qa/extras/ooxmlexport/xport7.cxx
sed -z -r -e 's/DECLARE_OOXMLEXPORT_TEST[(]tdf105490_negativeMargins,[^)]*[)].[{]/& return;/' -i sw/qa/extras/ooxmlexport/xport9.cxx
sed -z -r -e 's/DECLARE_OOXMLIMPORT_TEST[(]testTdf112443,[^)]*[)].[{]/& return;/' -i sw/qa/extras/ooxmlimport/ooxmlimport.cxx
sed -z -r -e 's/DECLARE_RTFIMPORT_TEST[(]testTdf108947,[^)]*[)].[{]/& return;/' -i sw/qa/extras/rtfimport/rtfimport.cxx
# not sure about this fragile test
sed -z -r -e 's/DECLARE_OOXMLEXPORT_TEST[(]testTDF87348,[^)]*[)].[{]/& return;/' -i sw/qa/extras/ooxmlexport/ooxmlexport7.cxx
# bunch of new Fresh failures. Sigh.
sed -e '/CPPUNIT_TEST(testDocumentLayout);/d' -i './sd/qa/unit/import-tests.cxx'
sed -e '/CPPUNIT_TEST(testErrorBarDataRangeODS);/d' -i './chart2/qa/extras/chart2export.cxx'
sed -e '/CPPUNIT_TEST(testLabelStringODS);/d' -i './chart2/qa/extras/chart2export.cxx'
sed -e '/CPPUNIT_TEST(testAxisNumberFormatODS);/d' -i './chart2/qa/extras/chart2export.cxx'
sed -e '/CPPUNIT_TEST(testBackgroundImage);/d' -i './sd/qa/unit/export-tests.cxx'
sed -e '/CPPUNIT_TEST(testFdo84043);/d' -i './sd/qa/unit/export-tests.cxx'
sed -e '/CPPUNIT_TEST(testTdf97630);/d' -i './sd/qa/unit/export-tests.cxx'
sed -e '/CPPUNIT_TEST(testTdf80020);/d' -i './sd/qa/unit/export-tests.cxx'
sed -e '/CPPUNIT_TEST(testTdf62176);/d' -i './sd/qa/unit/export-tests.cxx'
sed -e '/CPPUNIT_TEST(testTransparentBackground);/d' -i './sd/qa/unit/export-tests.cxx'
sed -e '/CPPUNIT_TEST(testEmbeddedPdf);/d' -i './sd/qa/unit/export-tests.cxx'
sed -e '/CPPUNIT_TEST(testEmbeddedText);/d' -i './sd/qa/unit/export-tests.cxx'
sed -e '/CPPUNIT_TEST(testTdf98477);/d' -i './sd/qa/unit/export-tests.cxx'
sed -e '/CPPUNIT_TEST(testAuthorField);/d' -i './sd/qa/unit/export-tests-ooxml2.cxx'
sed -e '/CPPUNIT_TEST(testTdf50499);/d' -i './sd/qa/unit/export-tests.cxx'
sed -e '/CPPUNIT_TEST(testTdf100926);/d' -i './sd/qa/unit/export-tests.cxx'
sed -e '/CPPUNIT_TEST(testPageWithTransparentBackground);/d' -i './sd/qa/unit/export-tests.cxx'
sed -e '/CPPUNIT_TEST(testTextRotation);/d' -i './sd/qa/unit/export-tests.cxx'
sed -e '/CPPUNIT_TEST(testTdf113818);/d' -i './sd/qa/unit/export-tests.cxx'
sed -e '/CPPUNIT_TEST(testTdf119629);/d' -i './sd/qa/unit/export-tests.cxx'
sed -e '/CPPUNIT_TEST(testTdf113822);/d' -i './sd/qa/unit/export-tests.cxx'
sed -e '/CPPUNIT_TEST(test);/d' -i './sc/qa/unit/subsequent_export-test.cxx'
sed -e '/CPPUNIT_TEST(testConditionalFormatExportODS);/d' -i './sc/qa/unit/subsequent_export-test.cxx'
sed -e '/CPPUNIT_TEST(testProtectionKeyODS_UTF16LErtlSHA1);/d' -i './sc/qa/unit/subsequent_export-test.cxx'
sed -e '/CPPUNIT_TEST(testProtectionKeyODS_UTF8SHA1);/d' -i './sc/qa/unit/subsequent_export-test.cxx'
sed -e '/CPPUNIT_TEST(testProtectionKeyODS_UTF8SHA256ODF12);/d' -i './sc/qa/unit/subsequent_export-test.cxx'
sed -e '/CPPUNIT_TEST(testProtectionKeyODS_UTF8SHA256W3C);/d' -i './sc/qa/unit/subsequent_export-test.cxx'
sed -e '/CPPUNIT_TEST(testProtectionKeyODS_XL_SHA1);/d' -i './sc/qa/unit/subsequent_export-test.cxx'
sed -e '/CPPUNIT_TEST(testColorScaleExportODS);/d' -i './sc/qa/unit/subsequent_export-test.cxx'
sed -e '/CPPUNIT_TEST(testDataBarExportODS);/d' -i './sc/qa/unit/subsequent_export-test.cxx'
sed -e '/CPPUNIT_TEST(testNamedRangeBugfdo62729);/d' -i './sc/qa/unit/subsequent_export-test.cxx'
sed -e '/CPPUNIT_TEST(testRichTextExportODS);/d' -i './sc/qa/unit/subsequent_export-test.cxx'
sed -e '/CPPUNIT_TEST(testFormulaRefSheetNameODS);/d' -i './sc/qa/unit/subsequent_export-test.cxx'
sed -e '/CPPUNIT_TEST(testCellValuesExportODS);/d' -i './sc/qa/unit/subsequent_export-test.cxx'
sed -e '/CPPUNIT_TEST(testCellNoteExportODS);/d' -i './sc/qa/unit/subsequent_export-test.cxx'
sed -e '/CPPUNIT_TEST(testFormatExportODS);/d' -i './sc/qa/unit/subsequent_export-test.cxx'
sed -e '/CPPUNIT_TEST(testEmbeddedChartODS);/d' -i './sc/qa/unit/subsequent_export-test.cxx'
sed -e '/CPPUNIT_TEST(testCellAnchoredGroupXLS);/d' -i './sc/qa/unit/subsequent_export-test.cxx'
sed -e '/CPPUNIT_TEST(testCeilingFloorODS);/d' -i './sc/qa/unit/subsequent_export-test.cxx'
sed -e '/CPPUNIT_TEST(testRelativePathsODS);/d' -i './sc/qa/unit/subsequent_export-test.cxx'
sed -e '/CPPUNIT_TEST(testSheetProtectionODS);/d' -i './sc/qa/unit/subsequent_export-test.cxx'
sed -e '/CPPUNIT_TEST(testSwappedOutImageExport);/d' -i './sc/qa/unit/subsequent_export-test.cxx'
sed -e '/CPPUNIT_TEST(testLinkedGraphicRT);/d' -i './sc/qa/unit/subsequent_export-test.cxx'
sed -e '/CPPUNIT_TEST(testImageWithSpecialID);/d' -i './sc/qa/unit/subsequent_export-test.cxx'
sed -e '/CPPUNIT_TEST(testAbsNamedRangeHTML);/d' -i './sc/qa/unit/subsequent_export-test.cxx'
sed -e '/CPPUNIT_TEST(testMoveCellAnchoredShapesODS);/d' -i './sc/qa/unit/subsequent_export-test.cxx'
sed -e '/CPPUNIT_TEST(testRefStringUnspecified);/d' -i './sc/qa/unit/subsequent_export-test.cxx'
sed -e '/CPPUNIT_TEST(testHeaderImageODS);/d' -i './sc/qa/unit/subsequent_export-test.cxx'
sed -e '/CPPUNIT_TEST(testTdf88657ODS);/d' -i './sc/qa/unit/subsequent_export-test.cxx'
sed -e '/CPPUNIT_TEST(testExponentWithoutSignFormatXLSX);/d' -i './sc/qa/unit/subsequent_export-test.cxx'
sed -e '/CPPUNIT_TEST(testHiddenRepeatedRowsODS);/d' -i './sc/qa/unit/subsequent_export-test.cxx'
sed -e '/CPPUNIT_TEST(testHyperlinkTargetFrameODS);/d' -i './sc/qa/unit/subsequent_export-test.cxx'
sed -e '/CPPUNIT_TEST(testTdf105739);/d' -i './sd/qa/unit/export-tests-ooxml2.cxx'
sed -e '/CPPUNIT_TEST(testPageBitmapWithTransparency);/d' -i './sd/qa/unit/export-tests-ooxml2.cxx'
sed -e '/CPPUNIT_TEST(testTdf115005);/d' -i './sd/qa/unit/export-tests-ooxml2.cxx'
sed -e '/CPPUNIT_TEST(testTdf115005_FallBack_Images_On);/d' -i './sd/qa/unit/export-tests-ooxml2.cxx'
sed -e '/CPPUNIT_TEST(testTdf115005_FallBack_Images_Off);/d' -i './sd/qa/unit/export-tests-ooxml2.cxx'
sed -e '/CPPUNIT_TEST(testTdf44774);/d' -i './sd/qa/unit/misc-tests.cxx'
sed -e '/CPPUNIT_TEST(testTdf38225);/d' -i './sd/qa/unit/misc-tests.cxx'
sed -e '/CPPUNIT_TEST(testAuthorField);/d' -i './sd/qa/unit/export-tests-ooxml2.cxx'
sed -e '/CPPUNIT_TEST(testAuthorField);/d' -i './sd/qa/unit/export-tests.cxx'
sed -e '/CPPUNIT_TEST(testFdo85554);/d' -i './sw/qa/extras/uiwriter/uiwriter.cxx'
sed -e '/CPPUNIT_TEST(testEmbeddedDataSource);/d' -i './sw/qa/extras/uiwriter/uiwriter.cxx'
sed -e '/CPPUNIT_TEST(testTdf96479);/d' -i './sw/qa/extras/uiwriter/uiwriter.cxx'
sed -e '/CPPUNIT_TEST(testInconsistentBookmark);/d' -i './sw/qa/extras/uiwriter/uiwriter.cxx'
sed -e "s/DECLARE_SW_ROUNDTRIP_TEST(\([_a-zA-Z0-9.]\+\)[, ].*, *\([_a-zA-Z0-9.]\+\))/class \\1: public \\2 { public: void verify() override; }; void \\1::verify() /" -i "sw/qa/extras/ooxmlexport/ooxmlexport9.cxx"
sed -e "s/DECLARE_SW_ROUNDTRIP_TEST(\([_a-zA-Z0-9.]\+\)[, ].*, *\([_a-zA-Z0-9.]\+\))/class \\1: public \\2 { public: void verify() override; }; void \\1::verify() /" -i "sw/qa/extras/ooxmlexport/ooxmlencryption.cxx"
sed -e "s/DECLARE_SW_ROUNDTRIP_TEST(\([_a-zA-Z0-9.]\+\)[, ].*, *\([_a-zA-Z0-9.]\+\))/class \\1: public \\2 { public: void verify() override; }; void \\1::verify() /" -i "sw/qa/extras/odfexport/odfexport.cxx"
sed -e "s/DECLARE_SW_ROUNDTRIP_TEST(\([_a-zA-Z0-9.]\+\)[, ].*, *\([_a-zA-Z0-9.]\+\))/class \\1: public \\2 { public: void verify() override; }; void \\1::verify() /" -i "sw/qa/extras/unowriter/unowriter.cxx"
# End MIT licensed section
cd ..

##### LOKit (core) #####

# build
if [ "$CORE_BRANCH" == "distro/collabora/cp-6.4" ]; then
  ( cd core && ./autogen.sh --with-distro=CPLinux-LOKit --disable-epm --without-package-format ) || exit 1
else
  ( cd core && ./autogen.sh --with-distro=LibreOfficeOnline ) || exit 1
fi
( cd core && make $CORE_BUILD_TARGET ) || exit 1

# copy stuff
mkdir -p "$INSTDIR"/opt/
cp -a core/instdir "$INSTDIR"/opt/lokit

##### loolwsd & loleaflet #####

# build
( cd online && ./autogen.sh ) || exit 1
( cd online && ./configure --prefix=/usr --sysconfdir=/etc --localstatedir=/var --enable-silent-rules --with-lokit-path="$BUILDDIR"/core/include --with-lo-path=/opt/lokit --with-poco-includes=$BUILDDIR/poco/include --with-poco-libs=$BUILDDIR/poco/lib $ONLINE_EXTRA_BUILD_OPTIONS) || exit 1
( cd online && make -j 8) || exit 1

# copy stuff
( cd online && DESTDIR="$INSTDIR" make install ) || exit 1

# Create new docker image
if [ -z "$NO_DOCKER_IMAGE" ]; then
  cd "$SRCDIR"
  cp ../from-packages/scripts/start-collabora-online.sh .
  docker build --no-cache -t $DOCKER_HUB_REPO:$DOCKER_HUB_TAG -f $HOST_OS . || exit 1
else
  echo "Skipping docker image build"
fi;
