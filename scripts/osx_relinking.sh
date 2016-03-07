#! /bin/sh
# WARNING!
# This rule modified the binary it was given, once modified the
# binary cannot be used with this rule again.
# If the binary is installed then it's important to call this
# rule before calling install rule for the binary.
# 
# The basic principle here is to ensure that the
# QT Libraries the binary (pmchart, pmtime etc) are linked agains
# are remapped (using XCode's install_name_tool) to a location
# where the Frameworks will be installed to, rather
# than the location that they are installed on the build machine

INSTALL_DIRECTORY_HIERARCHY () {
	d=$1
  while [ "$d" != "$2" -a "$d" != "/" -a "$d" != "." ] ; do \
    echo $d
    d=`dirname $d`
  done |\
  sort |\
  while read id; do \
    $INSTALL -m 755 -d $id || exit 1
  done
}

INSTALL_QT_RESOURCES () {
	printf "[Paths]\nPlugins=/Library/PCP/Plugins\n\n" > qt.conf
	$INSTALL -m 644 qt.conf $1/qt.conf
	rm qt.conf
	find frameworks -type d -name qt_menu.nib |\
  while read nib; do \
    $INSTALL -m 755 -d $1/qt_menu.nib || exit 1
    find $nib -type f |\ 
    while read nibs; do \
      f=`basename $nibs`
      $INSTALL -m 644 $nibs $1/qt_menu.nib/$f || exit 1
    done
  done
}

MAC_APPSUPPORT_DIR=/Library/PCP
MAC_FRAMEWORKS_DIR=$MAC_APPSUPPORT_DIR/Frameworks

PCP_BINARY=$1
INSTALL=$2
OSX_LIBRARY_FRAMEWORKS=$3 #/usr/local/opt/qt/lib   #/Library/Frameworks


otool -L $PCP_BINARY |
  awk '{if (NR != 1) {print $1}}' |
  egrep 'Qt.*\.framework' |
  while read qt; do
    echo "====" >> /tmp/foo
    QtLibrarySubPath=`echo $qt | sed -e 's/^.*lib\///'` # TODO This is assuming the QT framework is in a homebrew like 'lib' path
    QtLibraryFrameworkPath=`echo $qt | sed -e 's/\(^.*framework\)\/.*/\1/'`
    QtLibraryFrameworkName=`echo $QtLibrarySubPath | sed -e 's/\/.*//'`
    QtLibraryBasePath=`echo $qt | sed -e 's/Versions.*\///'`
    QtLibrary=`basename $QtLibraryBasePath`
    echo qt=$qt >> /tmp/foo 
    echo QtLibrarySubPath=$QtLibrarySubPath >> /tmp/foo
    echo QtLibraryFrameworkPath=$QtLibraryFrameworkPath >> /tmp/foo
    echo QtLibraryFrameworkName=$QtLibraryFrameworkName >> /tmp/foo
    echo QtLibraryBasePath=$QtLibraryBasePath >> /tmp/foo
    echo QtLibrary=$QtLibrary >> /tmp/foo
    mkdir -p $MAC_FRAMEWORKS_DIR
    $INSTALL -d $MAC_FRAMEWORKS_DIR
    INSTALL_DIRECTORY_HIERARCHY $QtLibraryFrameworkPath $MAC_FRAMEWORKS_DIR/
    INSTALL_DIRECTORY_HIERARCHY $MAC_FRAMEWORKS_DIR/$QtLibrary $MAC_APPSUPPORT_DIR # TODO Not quite clear why these 2 INSTALL_DIRECTORY_HIERARCHY are here...
    tdir=`dirname $qt`
    mkdir -p frameworks/$QtLibrarySubPath || exit 1
    chmod -R +w frameworks/$QtLibrarySubPath
    
    fwqt="frameworks/$QtLibrarySubPath/$QtLibrary"
    cp $OSX_LIBRARY_FRAMEWORKS/$QtLibrarySubPath frameworks/$QtLibrarySubPath || exit 1
    install_name_tool -change $qt $MAC_FRAMEWORKS_DIR/$QtLibrarySubPath $PCP_BINARY
    
    otool -L $fwqt |
      awk '{if (NR != 1) {print $1}}' |\
      egrep 'Qt.*\.framework' |
      while read dep; do \
        install_name_tool -change $dep $MAC_FRAMEWORKS_DIR/$dep $fwqt
      done
    $INSTALL $fwqt $MAC_FRAMEWORKS_DIR/$QtLibrary/$QtLibrary
    echo "----------" >> /tmp/foo
    if [ -d $MAC_FRAMEWORKS_DIR/$QtLibraryFrameworkName/Resources ] ; then \
        $INSTALL -d $MAC_FRAMEWORKS_DIR/$QtLibraryFrameworkName/Resources
        (cd $MAC_FRAMEWORKS_DIR/$QtLibraryFrameworkName; find Resources/ -type f) | \
      	while read rf; do \
      	    rfpath="$tdir/$rf"
            rfd=`dirname $rfpath`
      	    fwpath="frameworks/$rfpath"
            brfd=`basename $rfd`
      	    mkdir -p frameworks/$rfd || exit 1
            chmod -R +w frameworks/$rfd
      			echo rfpath=$rfpath >> /tmp/foo
      			echo rfd=$rfd >> /tmp/foo
      			echo fwpath=$fwpath >> /tmp/foo
      			echo brfd=$brfd >> /tmp/foo
      	    cp $OSX_LIBRARY_FRAMEWORKS/$rfpath $fwpath || exit 1
      	    [ $brfd != qt_menu.nib ] || continue;  \
      	    $INSTALL -d $MAC_FRAMEWORKS_DIR/$rfd || exit 1
      	    $INSTALL $fwpath $MAC_FRAMEWORKS_DIR/$rfpath
      	done
    fi
  done
