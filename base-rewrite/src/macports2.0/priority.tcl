# -*- coding: utf-8; mode: tcl; tab-width: 4; indent-tabs-mode: nil; c-basic-offset: 4 -*- vim:fenc=utf-8:filetype=tcl:et:sw=4:ts=4:sts=4
# priority.tcl
# $Id$
#
# Copyright (c) 2013 Clemens Lang <cal@macports.org>
# Copyright (c) 2013 The MacPorts Project
# All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions
# are met:
# 1. Redistributions of source code must retain the above copyright
#    notice, this list of conditions and the following disclaimer.
# 2. Redistributions in binary form must reproduce the above copyright
#    notice, this list of conditions and the following disclaimer in the
#    documentation and/or other materials provided with the distribution.
# 3. Neither the name of Apple Inc. nor the names of its contributors
#    may be used to endorse or promote products derived from this software
#    without specific prior written permission.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
# AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
# ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE
# LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
# CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
# SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
# INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
# CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
# ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
# POSSIBILITY OF SUCH DAMAGE.

package provide macports::priority 2.0

##
# Priorities for messages passed to the client in order of decreasing severity.
# Since the values of these constants are numeric, you can (and should use) this
# as a filter for verbosity. E.g., if a user requests all output up to the
# notice level, you can use
#
# \code
# if {$priority <= $macports::priority::notice} {}
# \endcode
#
# as condition to filter other messages. This allows an simple implementation of
# the \c --quiet and \c --verbose flags. Note that MacPorts internally always
# keeps all messages in a logfile, even if you filter them.
#
# This is part of the public API. You can use this in your application. Please
# do not rely on the exact numerical values of the variables in this namespace
# (as opposed to their relation to each other, which you can safely rely on).
namespace eval macports::priority {
	##
	# Priority used for critical error conditions. MacPorts will usually
	# abort the operation it was executing at the time when then error
	# occured.
	#
	# \par Example
	# If you try to search for a port, but your port index is corrupt or
	# missing, MacPorts cannot continue and will abort with this priority.
	variable error 1

	##
	# Priority used when possibly undesired conditions arise, but MacPorts
	# can still continue in a reasonable way.
	#
	# \par Example
	# MacPorts will warn you using this priority if your port trees have not
	# been synced in a long time.
	variable warning 2

	##
	# Priority describing information that might be relevant for the user,
	# but does not affect execution of the current operation.
	#
	# \par Example
	# If a port installed a startup item you can use to control a daemon
	# using \c launchctl(1) MacPorts will notify you using this priority.
	variable notice 3

	##
	# Priority for progress information and information about what MacPorts
	# is currently doing. This is probably not relevant for the average user
	# and should be hidden. You should however display messages tagged with
	# this priority when the \c --verbose flag was specified.
	#
	# \par Example
	# port checksum prints the checksums recorded in the Portfile and the
	# checksums of the downloaded distfile using this priority.
	variable info 4

	##
	# Priority for internal debugging information of MacPorts. Use this when
	# reporting and/or hunting bugs in MacPorts itself or a port.
	#
	# \warning
	# Displaying this priority will generate a lot of output!
	#
	# \par Example
	# Every command execution will be printed using this priority.
	variable debug 5
}
