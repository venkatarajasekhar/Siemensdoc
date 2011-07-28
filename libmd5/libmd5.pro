#
# This file was generated from libmd5.pro.in on Wed Jul 27 16:04:07 UTC 2011
#

TEMPLATE	= lib
CONFIG		= warn_on staticlib release
HEADERS		= md5.h md5_loc.h
SOURCES		= md5.c
win32:INCLUDEPATH          += .
win32-g++:TMAKE_CFLAGS     += -D__CYGWIN__ -DALL_STATIC
DESTDIR                    =  ../lib
TARGET                     =  md5
OBJECTS_DIR                =  ../objects

    TMAKE_CXXFLAGS += -D_LARGEFILE_SOURCE
