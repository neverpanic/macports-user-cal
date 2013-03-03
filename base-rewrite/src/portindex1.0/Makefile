INSTALLDIR=	${DESTDIR}${datadir}/macports/Tcl/portindex1.0

SRCS=	portindex.tcl tcl.tcl sqlite.tcl

include ../../Mk/macports.autoconf.mk

.PHONY: test

all:: pkgIndex.tcl

pkgIndex.tcl: $(SRCS)
	$(SILENT) ../pkg_mkindex.sh . || ( rm -rf $@ && exit 1 )

clean::
	rm -f pkgIndex.tcl

install:: all
	$(INSTALL) -d -o ${DSTUSR} -g ${DSTGRP} -m ${DSTMODE} ${INSTALLDIR}
	$(SILENT)set -x; for file in ${SRCS}; do \
		$(INSTALL) -o ${DSTUSR} -g ${DSTGRP} -m 444 $$file ${INSTALLDIR}; \
	done
	$(INSTALL) -o ${DSTUSR} -g ${DSTGRP} -m 444 pkgIndex.tcl ${INSTALLDIR}
