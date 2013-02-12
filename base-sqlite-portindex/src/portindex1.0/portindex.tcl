# et:ts=4:tw=80
# portindex.tcl
# $Id$
#
# Copyright (c) 2004-2013 The MacPorts Project
# Copyright (c) 2002-2004 Apple Inc.
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
#
# standard package load
package provide portindex 1.0

package require portindex::tcl 1.0
package require portindex::sqlite 1.0

namespace eval portindex {
	# The type of the PortIndex implementation
	variable portindex_type ""

	# Number of total ports processed in this index operation
	variable count_total  0
	# Number of ports that were processed but failed
	variable count_failed 0
	# Number of ports that were skipped, because they were current
	variable count_skip   0
	
	# Sets the type of the PortIndex. This needs to be called before calling
	# any other procedure in this namespace. Valid values for type are at the
	# moment: sqlite, tcl.
	proc set_portindex_type {type} {
		variable portindex_type

		switch -exact ${type} {
			tcl -
			sqlite {
				# do nothing, those are valid types
			}
			default {
				error "portindex::set_portindex_type called with invalid type \
					${type}. Valid types are: sqlite, tcl."
			}
		}

		if {${portindex_type} != ""} {
			namespace forget ${portindex_type}::*
		}
		namespace import ${type}::*
		set portindex_type ${type}
	}

	# Increase the number of ports in total. Call this once for every port
	# processed from the portindex implementation
	proc inc_total {{amount 1}} {
		variable count_total
		incr count_total ${amount}
	}

	# Increase the number of failed ports. Call this once for every port that
	# fails to process form the portindex implementation
	proc inc_failed {{amount 1}} {
		variable count_failed
		incr count_failed ${amount}
	}

	# Increase the number of skipped ports. Call this once from the portindex
	# implementation for every port you skip because its info seems to be
	# current.
	proc inc_skipped {{amount 1}} {
		variable count_skip
		incr count_skip ${amount}
	}

	# Get some statistics about the portindex operation. This may be called
	# after portindex::finish and will return an array (in list format) with
	# the fields total, failed and skipped. E.g., you can use this like this:
	#   array set statistics [portindex::statistics]
	proc statistics {} {
		variable count_failed
		variable count_skip
		variable count_total

		array set statistics {}
		set statistics(total)   ${count_total}
		set statistics(failed)  ${count_failed}
		set statistics(skipped) ${count_skip}

		return [array get statistics]
	}
}
