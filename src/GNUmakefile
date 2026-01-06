#
# Copyright (c) 2012-2020 Red Hat.
# Copyright (c) 2000,2004,2012 Silicon Graphics, Inc.  All Rights Reserved.
# 
# This program is free software; you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by the
# Free Software Foundation; either version 2 of the License, or (at your
# option) any later version.
# 
# This program is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY
# or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License
# for more details.
# 

TOPDIR = ..
include $(TOPDIR)/src/include/builddefs
-include ./GNUlocaldefs

INCLUDE_SUBDIR = include
PMNS_SUBDIR = pmns
LIBPCP_SUBDIR = libpcp libpcp_static
LIBS_SUBDIRS = \
	libpcp_pmda \
	libpcp_trace \
	libpcp_pmcd \
	libpcp_gui \
	libpcp_mmv \
	libpcp_import \
	libpcp_archive \
	libpcp_qed \
	libpcp_qmc \
	libpcp_qwt \
	libpcp_web \
	libpcp_fault \
	#

# ABI compatibility (libpcp.so.3)
#
LIBS_SUBDIRS += libpcp3

# ones that generate .static executables and may be used later on
# in the build (Phase 5: split these out to fix newhelp.static race condition)
#
TOOLS_SUBDIRS = \
	pmcpp \
	newhelp \
	pmieconf \
	pcp-reboot-init \
	#

# and all the rest ...
#
OTHER_SUBDIRS = \
	pminfo \
	pmprobe \
	bashrc \
	zshrc \
	dbpmda \
	genpmda \
	pcp \
	pcp2arrow \
	pcp2elasticsearch \
	pcp2graphite \
	pcp2influxdb \
	pcp2json \
	pcp2openmetrics \
	pcp2opentelemetry \
	pcp2spark \
	pcp2xlsx \
	pcp2xml \
	pcp2zabbix \
	pmafm \
	pmfind \
	pmcd \
	pmcd_wait \
	pmchart \
	pmclient \
	pmconfig \
	pmdas \
	pmdate \
	pmdbg \
	pmdumptext \
	pmerr \
	pmgenmap \
	pmgetopt \
	pmhostname \
	pmie \
	pmiestatus \
	pmjson \
	pmlc \
	pmlock \
	pmlogcheck \
	pmlogconf \
	pmlogdump \
	pmlogextract \
	pmlogger \
	pmlogreduce \
	pmloglabel \
	pmlogmv \
	pmlogpaste \
	pmlogpush \
	pmlogrewrite \
	pmlogredact \
	pmlogsize \
	pmlogsummary \
	pmpost \
	pmproxy \
	pmquery \
	pmrep \
	pmsearch \
	pmseries \
	pmstat \
	pmstore \
	pmsocks \
	pmtrace \
	pmsignal \
	pmsleep \
	pmsnap \
	pmtime \
	pmval \
	pmview \
	perl \
	python \
	procmemstat \
	autofsd-probe \
	telnet-probe \
	collectl2pcp \
	guidellm2pcp \
	vllmbench2pcp \
	iostat2pcp \
	mrtg2pcp \
	sar2pcp \
	sheet2pcp \
	ganglia2pcp \
	win32ctl \
	zabbix-agent \
	pmpython \
	discover \
	derived \
	selinux \
	find-filter \
	ctl-tools \
	runaspcp \
	pmcheck \
	indomcachectl \
	pmlogbasename \
	pmlogcompress \
	#

SUBDIRS = \
	$(INCLUDE_SUBDIR) \
	$(LIBPCP_SUBDIR) \
	$(PMNS_SUBDIR) \
	$(LIBS_SUBDIRS) \
	$(TOOLS_SUBDIRS) \
	$(OTHER_SUBDIRS)

default :: default_pcp

include $(BUILDRULES)

# Phase 3: Modern parallel build pattern
# Declare subdirectories as phony targets to enable parallel builds
.PHONY: $(SUBDIRS)

# Use target-specific variables to pass the correct target to subdirectories
default_pcp: TARGET = default_pcp
default_pcp: $(SUBDIRS)

install :: default_pcp install_pcp

install_pcp: TARGET = install_pcp
install_pcp: $(SUBDIRS)

# Pattern rule for building each subdirectory
# The + prefix enables jobserver coordination for parallel builds across recursive make
$(SUBDIRS):
	+@if [ -d "$@" -a -f "$@/GNUmakefile" ]; then \
		echo === $@ ===; \
		$(MAKE) $(MAKEOPTS) -C $@ $(TARGET) || exit $$?; \
	fi

# Dependency chain - controls build order while allowing parallelism within stages
# Stage 1: include
# Stage 2: libpcp, then libpcp_static (they share source, cannot run in parallel)
# Stage 3: pmns
# Stage 4: all LIBS_SUBDIRS (13 libraries can build in parallel)
# Stage 5: TOOLS_SUBDIRS and most OTHER_SUBDIRS build in parallel
# Stage 6: pmdas waits for TOOLS_SUBDIRS (needs newhelp.static)
$(LIBPCP_SUBDIR): $(INCLUDE_SUBDIR)
libpcp_static: libpcp  # libpcp_static uses symlinks to libpcp source, must build after
$(PMNS_SUBDIR): $(LIBPCP_SUBDIR)
$(LIBS_SUBDIRS): $(PMNS_SUBDIR)
$(TOOLS_SUBDIRS): $(LIBS_SUBDIRS)
$(OTHER_SUBDIRS): $(LIBS_SUBDIRS)
pmdas: $(TOOLS_SUBDIRS)  # Phase 5: pmdas specifically needs newhelp.static from TOOLS_SUBDIRS
