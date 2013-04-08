SRCS=fastload.tcl\
	 autoconf.tcl\
	 macports.tcl\
	 priority.tcl\
	 private.tcl
OBJS=get_systemconfiguration_proxies.o\
	 sysctl.o\
	 tclglue.o

SHLIB_NAME=MacPorts$(SHLIB_SUFFIX)
NAME=macports2.0

INSTALLDIR=$(DESTDIR)$(datadir)/macports/Tcl/$(NAME)
INSTALLPKGLINK=$(TCL_PACKAGE_DIR)/$(NAME)

include ../../Mk/macports.autoconf.mk
include ../../Mk/macports.tea.mk

ifeq ($(OBJC_RUNTIME),APPLE_RUNTIME)
	LIBS+=-framework CoreFoundation -framework SystemConfiguration
endif

pkgIndex.tcl: $(SRCS)

distclean:: clean
	rm -f autoconf.tcl fastload.tcl

install:: all
	$(INSTALL) -d -o "$(DSTUSR)" -g "$(DSTGRP)" -m "$(DSTMODE)" "$(INSTALLDIR)"
	$(SILENT) set -x; for file in $(SRCS); do\
		$(INSTALL) -o "$(DSTUSR)" -g "$(DSTGRP)" -m 444 "$$file" "$(INSTALLDIR)/$$file";\
	done
	$(INSTALL) -o "$(DSTUSR)" -g "$(DSTGRP)" -m 444 tclIndex "$(INSTALLDIR)"
	$(SILENT) echo "$(TCL_PACKAGE_DIR)" > "$(DESTDIR)$(prefix)/var/macports/.tclpackage"
	$(SILENT) if test -z "$(DESTDIR)" -a "$(INSTALLPKGLINK)" != "$(INSTALLDIR)"; then \
		if test ! -L "$(INSTALLPKGLINK)"; then \
			if test ! -e "$(TCL_PACKAGE_DIR)"; then \
				$(INSTALL) -d -o "$(DSTUSR)" -g "$(DSTGRP)" -m "$(DSTMODE)" "$(TCL_PACKAGE_DIR)" || true; \
			fi; \
			if test -d "$(INSTALLPKGLINK)"; then \
				rm -vrf "$(INSTALLPKGLINK)" || true; \
			fi; \
			if test ! -e "$(INSTALLPKGLINK)"; then \
				ln -vs "$(INSTALLDIR)" "$(INSTALLPKGLINK)" || true; \
			fi; \
		fi; \
	fi
