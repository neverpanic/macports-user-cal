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
package require macports::priority 2.0

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
    # List of port trees that can be used to install software. An entry in this
    # list is a tuple of the source URI and a list of flags for this source.
    # Currently valid flags are default and nosync.
    variable sources [list]

    ##
    # The default port tree in the same format as the \c sources variable.
    variable default_source {}

    ##
    # A list of variant specifications the user configured to be requested on
    # every port that will be installed. This value can be configured using the
    # \c variants_conf setting, which usually defaults to \c variants.conf.
    variable default_variants
    array set default_variants {}

    ##
    # A map of MacPorts settings, mapping keys to correpsonding values. Do not
    # modify or access this map directly, but use \c macports::option, \c
    # macports::set_option and \c macports::option_bool to query and set
    # entries.
    variable global_options
    array set global_options {}

    ##
    # Initialize private variables and other state. If you allocate any
    # resources here, make sure to free them again in \c private::release.
    proc init {} {
        # Ensure that the macports user directory (i.e. ~/.macports) exists, if
        # $HOME is defined. Also save $HOME for later use before replacing it
        # with a custom home directory.
        init_home

        # Load configuration from files
        init_configuration
    }

    ##
    # Teardown method cleaning up any resources allocated in \c private::init.
    proc release {} {
    }

    ##
    # Initialize macports::option user_home with the path to the calling user's
    # home and set the $HOME environment variable so commands using it will not
    # clutter the user's home, but instead a temporary path created by
    # MacPorts.
    proc init_home {} {
        if {[info exists env(HOME)]} {
            macports::set_option user_home $env(HOME)
            macports::set_option build_user_dir [file normalize [macports::autoconf build_user_dir]]
        } elseif {[info exists env(SUDO_USER)] && [get_os_platform] == "darwin"} {
            macports::set_option user_home \
                [exec dscl -q . -read /Users/$env(SUDO_USER) NFSHomeDirectory | cut -f 2 -d { }]
            macports::set_option build_user_dir \
                [file join [macports::option user_home] [macports::autoconf build_user_subdir]]
        } elseif {[exec id -u] != 0 && [get_os_platform] == "darwin"} {
            macports::set_option user_home \
                [exec dscl -q . -read /Users/[exec id -un] NFSHomeDirectory | cut -f 2 -d { }]
            macports::set_option build_user_dir \
                [file join [macports::option user_home] [macports::autoconf build_user_subdir]]
        } else {
            # Otherwise define the user directory as a directory that will never exist
            macports::set_option user_home      "/dev/null/NO_HOME_DIR"
            macports::set_option build_user_dir "/dev/null/NO_HOME_DIR"
        }
    }

    ##
    # Locate and load any configuration files.
    proc init_configuration {} {
        variable bootstrap_options
        variable user_options

        # Run configuration files in conf_path and build_user_dir
        set global_conf_file "[macports::autoconf conf_path]/macports.conf"
        set user_conf_file "[macports::option build_user_dir]/macports.conf"
        load_config_file $bootstrap_options $global_conf_file
        load_config_file $bootstrap_options $user_conf_file

        # Load the user configuration file, if it exists
        load_config_file $user_options "[macports::option build_user_dir]/user.conf"

        # Load the sources.conf and thus the available port trees
        load_sources

        # Load the variants.conf holding the default user-selected variants
        load_variants_conf
    }

    ##
    # Load a given configuration file and process its options, if they are in
    # valid_options. Will raise a warning when a file exists but could not be
    # opened for reading, or a file contains an invalid option.
    #
    # @param[in] valid_options list of valid configuration options for the
    #                          given configuration file. A warning is
    #                          generated, if a configuration option was not in
    #                          the list of accepted options.
    # @param[in] file name of a possible configuration file. Will be ignored if
    #                 it doesn't exist.
    # @return 1, if the file doesn't exist or could not be opened, 0 otherwise.
    proc load_config_file {valid_options file} {
        if {![file exists $file]} {
            return 1
        }
        if {[catch {set fd [open $file r]} result]} {
            macports::msg $macports::priority::warn \
                "Could not open configuration file %s for reading: %s" \
                $file $result
            return 1
        }
        set lineno 0
        while {[gets $fd line] >= 0} {
            incr lineno
            set line [string trim $line]
            if {[regexp {^#|^$} $line]} {
                # ignore comment lines
                continue
            }
            if {[regexp {^(\w+)(?:[ \t]+(.*))?$} $line match option val] == 1} {
                if {[lsearch -exact $valid_options $option] >= 0} {
                    macports::set_option $option [string trim $val]
                } else {
                    macports::msg $macports::priority::warn \
                        "Ignoring unknown configuration option `%s' in configuration file %s:%d." \
                        $option $file $lineno
                }
            }
        }
        close $fd
        return 0
    }

    ##
    # Load the list of sources from the sources_conf specified in MacPorts
    # options and initializes the \c sources and \c default_source variables.
    # Throws after printing an error message, if the \c sources_conf isn't set
    # or empty or the file cannot be opened. Also prints an error message and
    # throws, if no sources are configured.
    proc load_sources {} {
        variable sources
        variable default_source

        if {[macports::option sources_conf] == {}} {
            macports::msg $macports::priority::error \
                "sources_conf must be set in %s or %s." \
                $global_conf_file $user_conf_file
            error "sources_conf not set"
        }

        # Load sources_conf
        if {[catch {set fd [open [macports::option sources_conf] r]} result]} {
            macports::msg $macports::priority::error \
                "Can't open sources_conf %s: %s." \
                [macports::option sources_conf] $result
            error "error opening sources_conf"
        }

        set lineno 0
        while {[gets $fd line] >= 0} {
            incr lineno
            set line [string trim $line]
            if {[regexp {^#|^$} $line]} {
                # ignore comment lines
                continue
            }
            if {[regexp {^(\w+://\S+)(?:\s+\[(\w+(?:, *\w+)*)\])?\s*$} $line -> url flags]} {
                set flags [split $flags ", "]
                foreach flag $flags {
                    switch -exact $flag {
                        {nosync} {}
                        {default} {
                            if {$default_source != {}} {
                                macports::msg $macports::priority::warning \
                                    "Multiple default sources specified in %s:%d." \
                                    [macports::option sources_conf] $lineno
                            }
                            set default_source [concat [list $url] $flags]
                         }
                         default {
                            macports::msg $macports::priority::warning \
                                "Invalid source flag `%s' in %s:%d." \
                                $flag [macports::option sources_conf] $lineno
                         }
                    }
                }
                lappend sources [concat [list $url] $flags]
            } else {
                macports::msg $macports::priority::warning \
                    "Ignoring invalid source `%s' in %s:%d." \
                    $line [macports::option sources_conf] $lineno
            }
        }
        close $fd

        # Throw an error when no sources are defined.
        if {[llength $sources] == 0} {
            macports::msg $macports::priority::error \
                "No sources are defined in %s. Cannot continue without a ports tree." \
                [macports::option sources_conf]
            error "no port sources available"
        }

        # Make sure the default port source is defined. Otherwise
        # macports::getportresourcepath fails when the first source doesn't
        # contain _resources.
        if {$default_source == {}} {
            macports::msg $macports::priority::warning \
                "No default port source specified in %s, using last source as default." \
                [macports::option sources_conf]
            set default_source [lindex $sources end]
        }
    }

    ##
    # Load the default variants from variants.conf as specified in
    # macports.conf. If variants.conf does not exist, print a debug message, if
    # is contains invalid content, print a warning. Prints a warning if the file
    # exists, but can not be opened.
    #
    # @return 1, if the file doesn't exist or cannot be opened, 0 otherwise
    proc load_variants_conf {} {
        variable default_variants

        set variants_conf [macports::option variants_conf]
        # check whether variants_conf is set
        if {$variants_conf == {}} {
            return 1
        }
        # check whether the file exists
        if {![file exists $variants_conf]} {
            macports::msg $macports::priority::debug \
                "Variant configuration file %s specified by variants_conf does not exist, ignoring." \
                $variants_conf
            return 1
        }
        # try to open variants.conf
        if {[catch {set fd [open $variants_conf r]} result]} {
            macports::msg $macports::priority::warning \
                "Could not open variant configuration file %s: %s." \
                $variants_conf $result
            return 1
        }

        set lineno 0
        while {[gets $fd line] >= 0} {
            incr lineno
            set line [string trim $line]
            if {[regexp {^#|^$} $line]} {
                # ignore comment lines
                continue
            }
            foreach arg [split $line " \t"] {
                if {[regexp {^(\+|-)([-A-Za-z0-9_]+)$} $arg -> sign opt]} {
                    # previously duplicate values were ignored, but if I specify
                    # +ipv6 -ipv6 it makes more sense to use the latter and
                    # print a warning.
                    if {[info exists default_variants($opt)]} {
                        macports::msg $macports::priority::warning \
                            "Variant %s specified multiple times, using last definition in %s:%d." \
                            $opt $variants_conf $lineno
                    }
                    set default_variants($opt) $sign
                } else {
                    macports::msg $macports::priority::warning \
                        "Ignoring invalid variant configuration `%s' in %s:%d." \
                        $arg $variants_conf $lineno
                }
            }
        }

        close $fd
        return 0
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

    variable ui_prefix {---> }
    variable current_phase {main}
}
