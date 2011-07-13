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
#
# 
#
# Copyright (C) 1997-2000 by Dimitri van Heesch.
# 
# Permission to use, copy, modify, and distribute this software and its
# documentation under the terms of the GNU General Public License is hereby 
# granted. No representations are made about the suitability of this software 
# for any purpose. It is provided "as is" without express or implied warranty.
# See the GNU General Public License for more details.
# 
# Documents produced by Doxygen are derivative works derived from the
# input used in their production; they are not affected by this license.
# 

all: Makefile.qtools Makefile
	$(MAKE) -f Makefile.qtools    $@

Makefile.qtools: qtools.pro 
	$(ENV) $(PERL) $(TMAKE) qtools.pro >Makefile.qtools

tmake: 
	$(ENV) $(PERL) $(TMAKE) qtools.pro >Makefile.qtools

clean: Makefile.qtools 
	$(MAKE) -f Makefile.qtools    clean 

distclean: clean

FORCE:
