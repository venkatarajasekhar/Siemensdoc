#
# This file was generated from Makefile.in on Wed Jul 27 16:04:07 UTC 2011
#

DOXYGEN   = /home/perschak.t/cm/doxy-tool
TMAKEPATH = /home/perschak.t/cm/doxy-tool/tmake/lib/linux-g++
ENV       = env TMAKEPATH=$(TMAKEPATH)
TMAKE     = /home/perschak.t/cm/doxy-tool/tmake/bin/tmake
MAKE      = /usr/bin/make
PERL      = /usr/bin/perl
RM        = rm -f
CP        = cp
VERSION   = 1.7.4
INSTALL   = /usr/local
INSTTOOL  = /usr/bin/install
DOXYDOCS  = ..
DOCDIR    = $(INSTALL)/share/doc/packages/doxygen
QTDIR     = 
HAVE_DOT  = /usr/bin/dot
all: Makefile.libmd5 
	$(MAKE) -f Makefile.libmd5

clean: Makefile.libmd5 
	$(MAKE) -f Makefile.libmd5 clean

distclean: clean
	$(RM) -f Makefile.libmd5 libmd5.pro Makefile 

tmake:
	$(ENV) $(PERL) $(TMAKE) libmd5.pro >Makefile.libmd5

Makefile.libmd5: libmd5.pro
	$(ENV) $(PERL) $(TMAKE) libmd5.pro >Makefile.libmd5

install:
