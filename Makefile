#
# This file was generated from Makefile.in on Tue Aug 30 06:59:37 UTC 2011
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

all: src/version.cpp 
	$(MAKE) -C qtools
	$(MAKE) -C libmd5
	$(MAKE) -C src

doxywizard_install:

#all: src/version.cpp doxywizard 
#	cd qtools ; $(MAKE)
#	cd src ; $(MAKE)

DESTDIR = 

clean: FORCE
	cd examples ; $(MAKE) clean
	cd doc ; $(MAKE) clean
	cd qtools ; $(MAKE) clean
	cd src ; $(MAKE) clean
	cd libmd5 ; $(MAKE) clean
	cd addon/doxywizard ; $(MAKE) clean
	cd addon/doxmlparser/src ; $(MAKE) clean
	cd addon/doxmlparser/test ; $(MAKE) clean
	cd addon/doxmlparser/examples/metrics ; $(MAKE) clean
	-rm -f bin/doxy*
	-rm -f objects/*.o

distclean: clean
	cd src ; $(MAKE) distclean
	cd libmd5 ; $(MAKE) distclean
	cd addon/doxywizard ; $(MAKE) distclean
	cd addon/doxmlparser/src ; $(MAKE) distclean
	cd addon/doxmlparser/test ; $(MAKE) distclean
	cd addon/doxmlparser/examples/metrics ; $(MAKE) distclean
	cd addon/doxyapp ; $(MAKE) distclean
	-rm -f lib/lib*
	-rm -f bin/doxy*
	-rm -f html
	-rm -f latex
	-rm -f objects/*.o
	-rm -f src/Makefile.doxygen src/Makefile.libdoxygen 
	-rm -f src/Makefile.doxytag src/Makefile.libdoxycfg
	-rm -f libmd5/Makefile.libmd5
	-rm -f Makefile qtools/Makefile src/Makefile examples/Makefile doc/Makefile 
	-rm -f .makeconfig .tmakeconfig
	-rm -f src/doxygen.pro src/libdoxygen.pro src/doxytag.pro qtools/qtools.pro src/libdoxycfg.pro libmd5/libmd5.pro
	-rm -f src/version.cpp
	-rm -r addon/doxywizard/Makefile
	-rm -f addon/doxywizard/doxywizard.pro
	-rm -f VERSION
	-rm -f packages/rpm/doxygen.spec

DATE=$(shell date "+%B %Y")

MAN1DIR = man/man1

install: doxywizard_install 
	$(INSTTOOL) -d $(DESTDIR)/$(INSTALL)/bin
	$(INSTTOOL) -m 755 bin/doxygen    $(DESTDIR)/$(INSTALL)/bin
	$(INSTTOOL) -m 755 bin/doxytag    $(DESTDIR)/$(INSTALL)/bin
	$(INSTTOOL) -d $(DESTDIR)/$(INSTALL)/$(MAN1DIR)
	cat doc/doxygen.1    | sed -e "s/DATE/$(DATE)/g" -e "s/VERSION/$(VERSION)/g" > doxygen.1 
	$(INSTTOOL) -m 644 doxygen.1 $(DESTDIR)/$(INSTALL)/$(MAN1DIR)/doxygen.1
	rm doxygen.1
	cat doc/doxytag.1    | sed -e "s/DATE/$(DATE)/g" -e "s/VERSION/$(VERSION)/g" > doxytag.1
	$(INSTTOOL) -m 644 doxytag.1 $(DESTDIR)/$(INSTALL)/$(MAN1DIR)/doxytag.1
	rm doxytag.1

install_docs: 
	$(INSTTOOL) -d $(DESTDIR)/$(DOCDIR)
	$(MAKE) -C examples
	$(MAKE) -C doc 
	$(MAKE) -C latex 
	$(INSTTOOL) -m 644 latex/doxygen_manual.pdf $(DESTDIR)/$(DOCDIR)
	cp -r examples $(DESTDIR)/$(DOCDIR)
	cp -r html $(DESTDIR)/$(DOCDIR)

docs: FORCE
	cd examples ; $(MAKE)
	cd doc ; $(MAKE)

pdf: docs
	cd latex ; $(MAKE)

DISTFILES =  Doxyfile libmd5 addon tmake doc examples bin lib objects \
             qtools src configure configure.bin Makefile.in Makefile.win_nmake.in \
             Makefile.win_make.in INSTALL LANGUAGE.HOWTO LICENSE PLATFORMS \
             VERSION packages winbuild

archive: clean
	tar zcvf dx`date +%y%m%d`.tgz $(DISTFILES)

DISTDIR = doxygen-`echo $(VERSION) | tr - _`

dist: clean
	rm -rf $(DISTDIR)
	mkdir $(DISTDIR)
	cp -a $(DISTFILES) README $(DISTDIR)
	find $(DISTDIR) \( -name ".svn" \) -print0 | xargs -0 rm -rf
	tar zcvf $(DISTDIR).src.tar.gz $(DISTDIR)
	rm -rf $(DISTDIR)

src/version.cpp: Makefile
	echo "char versionString[]=\"$(VERSION)\";" > src/version.cpp

addon/doxywizard/version.cpp: Makefile
	echo "char versionString[]=\"$(VERSION)\";" > addon/doxywizard/version.cpp

DISTDIR = doxygen-`echo $(VERSION) | tr - _`
rpm: dist
	gzip -df $(DISTDIR).src.tar.gz
	mkdir $(DISTDIR)
	mkdir $(DISTDIR)/packages
	mkdir $(DISTDIR)/packages/rpm
	cp packages/rpm/doxygen.spec $(DISTDIR)/packages/rpm
	rm -rf $(DISTDIR)
	gzip -9v $(DISTDIR).src.tar
	rpmbuild -ta $(DISTDIR).src.tar.gz

rpmsrc: dist
	gzip -df $(DISTDIR).src.tar.gz
	mkdir $(DISTDIR)
	mkdir $(DISTDIR)/packages
	mkdir $(DISTDIR)/packages/rpm
	cp packages/rpm/doxygen.spec $(DISTDIR)/packages/rpm
	tar -rvf $(DISTDIR).src.tar $(DISTDIR)/packages/rpm/doxygen.spec
	rm -rf $(DISTDIR)
	gzip -9v $(DISTDIR).src.tar
	rpmbuild -ts $(DISTDIR).src.tar.gz

rpmbinary: dist
	gzip -df $(DISTDIR).src.tar.gz
	mkdir $(DISTDIR)
	mkdir $(DISTDIR)/packages
	mkdir $(DISTDIR)/packages/rpm
	cp packages/rpm/doxygen.spec $(DISTDIR)/packages/rpm
	tar -rvf $(DISTDIR).src.tar $(DISTDIR)/packages/rpm/doxygen.spec
	rm -rf $(DISTDIR)
	gzip -9v $(DISTDIR).src.tar
	rpmbuild -tb $(DISTDIR).src.tar.gz


ctags:
	ctags -f tags src addon/doxywizard qtools

FORCE:

