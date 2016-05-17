if WITHDOXYGEN
doc: Doxyfile all
	doxygen
endif

ACLOCAL_AMFLAGS = -I m4

AM_CXXFLAGS =
AM_CPPFLAGS = -I./src
lib_LTLIBRARIES = libapmoncpp.la
include_HEADERS = ./src/ApMon.h ./src/utils.h ./src/monitor_utils.h ./src/proc_utils.h ./src/mon_constants.h ./src/xdr.h

libapmoncpp_la_SOURCES = ./src/ApMon.cpp ./src/utils.cpp ./src/monitor_utils.cpp ./src/proc_utils.cpp ./src/mon_constants.cpp ./src/xdr.cpp

EXTRA_DIST = ApMon_win.dsp ApMon_win.dsw

libapmoncpp_la_LIBADD = -lpthread
libapmoncpp_la_LDFLAGS = -version-info 2:6:0

SUBDIRS	= . examples
