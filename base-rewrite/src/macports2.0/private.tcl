# -*- coding: utf-8; mode: tcl; tab-width: 4; indent-tabs-mode: nil; c-basic-offset: 4 -*- vim:fenc=utf-8:filetype=tcl:et:sw=4:ts=4:sts=4
# private.tcl
# $Id: macports.tcl 103550 2013-02-28 21:20:37Z cal@macports.org $
#
# Copyright (c) 2002 - 2003 Apple Inc.
# Copyright (c) 2004 - 2005 Paul Guyot, <pguyot@kallisys.net>.
# Copyright (c) 2004 - 2006 Ole Guldberg Jensen <olegb@opendarwin.org>.
# Copyright (c) 2004 - 2005 Robert Shaw <rshaw@opendarwin.org>
# Copyright (c) 2013        Clemens Lang <cal@macports.org>
# Copyright (c) 2004 - 2013 The MacPorts Project
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

package provide macports::private 2.0

package require macports::autoconf 2.0

##
# \warning
# All contents of this package are private implementation details of MacPorts.
# If you are writing code outside the macports 2.0 package you should NOT use
# anything from this file. If you desperately need something only available
# here, please ask on the mailing list first and consider refactoring code.
#
# All variables and procedures are subject to change without notice.
namespace eval macports::private {
	##
	# Callback function to be called for all messages printed using
	# ui_$priority, where $priority is one of the macports::priority::*
	# constants. Default: none.
	variable ui_callback {}

	##
	# Initialize private variables and other state. If you allocate any
	# resources here, make sure to free them again in \c private::release.
	proc init {} {
	}

	##
	# Teardown method cleaning up any resources allocated in \c private::init.
	proc release {} {
	}

	##
	# Initialize macports::user_home with the path to the calling user's home
	# and set the $HOME environment variable so commands using it will not
	# clutter the user's home, but instead a temporary path created by
	# MacPorts.
	proc init_home {} {
		if {[info exists env(HOME)]} {
			set macports::user_home $env(HOME)
			set macports::macports_user_dir \
				[file normalize $macports::autoconf::macports_user_dir]
		} elseif {[info exists env(SUDO_USER)] && [get_os_platform] == "darwin"} {
			set macports::user_home \
				[exec dscl -q . -read /Users/$env(SUDO_USER) NFSHomeDirectory | cut -d ' ' -f 2]
			set macports::macports_user_dir \
				[file join $macports::user_home $macports::autoconf::macports_user_subdir]
		} elseif {[exec id -u] != 0 && [get_os_platform] == "darwin"} {
			set macports::user_home \
				[exec dscl -q . -read /Users/[exec id -un] NFSHomeDirectory | cut -d ' ' -f 2]
			set macports::macports_user_dir \
				[file join $macports::user_home $macports::autoconf::macports_user_subdir]
		} else {
			# Otherwise define the user directory as a directory that will never exist
			set macports::user_home         "/dev/null/NO_HOME_DIR"
			set macports::macports_user_dir "/dev/null/NO_HOME_DIR"
		}
	}

	##
	# Returns an architecture string from the \c $::tcl_platform array after
	# some mangling to bring it to a canonical format.
	#
	# @return \c powerpc on systems with a PPC CPU, i386 on systems with
	#          a Intel CPU. Return value on other systems is undefined at the
	#          moment.
	proc get_os_arch {} {
		if {[info exists macports::os_arch]} {
			return $macports::os_arch
		}
		switch -exact -- $::tcl_platform(machine) {
			x86_64 -
			i686 -
			i586 {
				return i386
			}
			{Power Macintosh} {
				return powerpc
			}
		}
		return $::tcl_platform(machine)
	}

	##
	# Returns the OS version from the \c $::tcl_platform array.
	#
	# @return a version string representing the OS X version, e.g. \c 12.2.0
	#         for OS X 10.8.2 (because Mountain Lion is darwin 12)
	proc get_os_version {} {
		if {[info exists macports::os_version]} {
			return $macports::os_version
		}
		return $::tcl_platform(osVersion)
	}

	##
	# Returns the major version number of the OS version from the \c
	# $::tcl_platform array.
	#
	# @return the result of \c get_os_version cut off at the first dot
	proc get_os_major {} {
		if {[info exists macports::os_major]} {
			return $macports::os_major
		}
		return [lindex [split [get_os_version] .] 0]
	}

	##
	# Returns the endianess of the system from the \c $::tcl_platform array.
	# Valid return values are either \c little or \c big.
	#
	# @return one of the strings \c little and \c big
	proc get_os_endian {} {
		if {[info exists macports::os_endian]} {
			return $macports::os_endian
		}
		return [string map {Endian {}} $::tcl_platform(byteOrder)]
	}

	##
	# Returns the platform (i.e., the OS name) of the current system in
	# lowercase. Some common values are:
	# \li \c darwin, for OS X
	# \li \c freebsd, for Free BSD
	# \li \c linux, for Linux
	#
	# @return the value of <tt>uname -s</tt> in lowercase
	proc get_os_platform {} {
		if {[info exists macports::os_platform]} {
			return $macports::os_platform
		}
		return [string tolower $::tcl_platform(os)]
	}

	##
	# Returns the OS X version number with two digits of accuracy, e.g. "10.8"
	# on Mountain Lion systems. On systems other than darwin, returns an empty
	# string.
	#
	# @return OS X version number or empty string
	proc get_macosx_version {} {
		if {[info exists macports::macosx_version]} {
			return $macports::macosx_version
		}
		if {[get_os_platform] != "darwin"} {
			return {}
		}
		return [expr 10.0 + ([get_os_major] - 4) / 10.0]
	}

	variable bootstrap_options [list\
		portdbpath\
		libpath\
		binpath\
		auto_path\
		extra_env\
		sources_conf\
		prefix\
		portdbformat\
		portarchivetype\
		portautoclean\
		porttrace\
		portverbose\
		keeplogs\
		destroot_umask\
		variants_conf\
		rsync_server\
		rsync_options\
		rsync_dir\
		startupitem_type\
		startupitem_install\
		place_worksymlink\
		xcodeversion\
		xcodebuildcmd\
		configureccache\
		ccache_dir\
		ccache_size\
		configuredistcc\
		configurepipe\
		buildnicevalue\
		buildmakejobs\
		applications_dir\
		frameworks_dir\
		developer_dir\
		universal_archs\
		build_arch\
		macosx_deployment_target\
		macportsuser\
		proxy_override_env\
		proxy_http\
		proxy_https\
		proxy_ftp\
		proxy_rsync\
		proxy_skip\
		master_site_local\
		patch_site_local\
		archive_site_local\
		buildfromsource\
		revupgrade_autorun\
		revupgrade_mode\
		revupgrade_check_id_loadcmds\
		host_blacklist\
		preferred_hosts\
		packagemaker_path\
		default_compilers\
	]

	variable user_options [list]

	variable portinterp_options [concat user_options [list\
		portdbpath\
		porturl\
		portpath\
		portbuildpath\
		auto_path\
		prefix\
		prefix_frozen\
		portsharepath\
		registry.path\
		registry.format\
		user_home\
		portarchivetype\
		archivefetch_pubkeys\
		portautoclean\
		porttrace\
		keeplogs\
		portverbose\
		destroot_umask\
		rsync_server\
		rsync_options\
		rsync_dir\
		startupitem_type\
		startupitem_install\
		place_worksymlink\
		macportsuser\
		configureccache\
		ccache_dir\
		ccache_size\
		configuredistcc\
		configurepipe\
		buildnicevalue\
		buildmakejobs\
		applications_dir\
		current_phase\
		frameworks_dir\
		developer_dir\
		universal_archs\
		build_arch\
		os_arch\
		os_endian\
		os_version\
		os_major\
		os_platform\
		macosx_version\
		macosx_deployment_target\
		packagemaker_path\
		default_compilers\
	]]

	variable deferred_options [list\
		xcodeversion\
		xcodebuildcmd\
		developer_dir\
	]

	variable open_ports {}

	variable ui_priorities {error warn msg notice info debug any}
	variable ui_prefix {---> }
	variable current_phase {main}
}
