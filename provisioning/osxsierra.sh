#!/bin/sh
############################################################
# OSX - Sierra
# TODO
# * pcpqa user doesn't exist in the image, so the qA script can't run
# * this error is displayed during provisionning
#  				==> osxsierra: sed: 1: "/etc/hosts": extra characters at the end of h command
#
# * tar/gnutar hell still, or it could be something to do with the rsync..?
# * pkg-build is still missing ...
#     * maybe using https://www.vagrantup.com/docs/provisioning/file.html to copy the Pkgbuild app?
############################################################

# Ensure OSX has a `vagrant:vagrant` style user:group
# otherwise rsync doesn't work properly...
VAGRANT_GID=$(id -u vagrant)
sudo dscl . -create /Groups/vagrant
sudo dscl . -create /Groups/vagrant PrimaryGroupID $VAGRANT_GID
sudo dscl . -create /Users/vagrant PrimaryGroupID $VAGRANT_GID


# TODO replace this with an updated base-box
sudo -H -u vagrant brew update
sudo -H -u vagrant brew upgrade
sudo -H -u vagrant brew install --universal coreutils automake libmicrohttpd pixman libpng xz
sudo -H -u vagrant brew install pkg-config cairo qt pyqt5
sudo -H -u vagrant brew install gnu-tar --with-default-names

cd /vagrant
export PKG_CONFIG=/usr/local/bin/pkg-config
sudo ./Makepkgs
