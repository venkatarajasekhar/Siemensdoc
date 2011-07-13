#
# This file was generated from Makefile.in on Die Apr 26 12:58:08 CEST 2011
#

DOXYGEN   = /home/ben/Projects/doctool/doxygen_patched
TMAKEPATH = /home/ben/Projects/doctool/doxygen_patched/tmake/lib/linux-g++
ENV       = env TMAKEPATH=$(TMAKEPATH)
TMAKE     = /home/ben/Projects/doctool/doxygen_patched/tmake/bin/tmake
MAKE      = /usr/bin/make
PERL      = /usr/bin/perl
RM        = rm -f
CP        = cp
VERSION   = 1.7.4
INSTALL   = /home/ben/Projects/doctool/exec
INSTTOOL  = /usr/bin/install
DOXYDOCS  = ..
DOCDIR    = $(INSTALL)/share/doc/packages/doxygen
QTDIR     = /home/ben/Projects/doctool/mydoxydev/qt

all clean depend distclean: Makefile.doxyapp 
	$(MAKE) -f Makefile.doxyapp $@

distclean: clean
	$(RM) -rf Makefile doxyapp.pro Makefile.doxyapp

tmake:
	$(ENV) $(PERL) $(TMAKE) doxyapp.pro >Makefile.doxyapp

strip:
	strip doxyapp

Makefile.doxyapp: doxyapp.pro
	$(ENV) $(PERL) $(TMAKE) doxyapp.pro >Makefile.doxyapp

install:
