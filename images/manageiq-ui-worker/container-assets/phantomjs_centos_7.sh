# ----------------------------------------------------------------------------
#
# Package	: Phantomjs
# Version	: 2.1.1
# Source repo	: https://github.com/ariya/phantomjs/
# Tested on	: centos_7
# Script License: Apache License, Version 2 or later
# Maintainer	: Priya Seth <sethp@us.ibm.com>
#
# Disclaimer: This script has been tested in non-root mode on given
# ==========  platform using the mentioned version of the package.
#             It may not work as expected with newer versions of the
#             package and/or distribution. In such case, please
#             contact "Maintainer" of this script.
#
# ----------------------------------------------------------------------------

#!/bin/bash

# Install all dependencies.
sudo yum -y update
sudo yum -y install gcc gcc-c++ make flex bison gperftools-libs \
    ruby openssl-devel freetype-devel fontconfig-devel libicu-devel \
    sqlite-devel libpng-devel libjpeg-devel wget git tar gzip libwebp-devel

# Clone and build missing dependencies from source.
wrkdir=`pwd`
wget http://ftp.gnu.org/pub/gnu/gperf/gperf-3.0.4.tar.gz
tar -xzf gperf-3.0.4.tar.gz
cd $wrkdir/gperf-3.0.4 && ./configure && make && sudo make install

# Clone PhantomJS code and build it.
cd $wrkdir
git clone git://github.com/ariya/phantomjs.git
cd $wrkdir/phantomjs && git checkout 2.1.1 && \
   git submodule init && git submodule update && ./build.py -c && \
   sudo cp bin/phantomjs /usr/bin
echo "phantomjs build completed."
