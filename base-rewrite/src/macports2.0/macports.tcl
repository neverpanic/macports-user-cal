# -*- coding: utf-8; mode: tcl; tab-width: 4; indent-tabs-mode: nil; c-basic-offset: 4 -*- vim:fenc=utf-8:filetype=tcl:et:sw=4:ts=4:sts=4
# macports.tcl
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

package provide macports 2.0

package require macports::private 2.0
package require macports::priority 2.0

package require msgcat 1.4.2

##
# This is the MacPorts core. It provides all API calls for all features present
# in MacPorts and is supposed to be used from a MacPorts client. The `port`
# command line tool is an example of such a client, but you could write others,
# e.g. GUI-based clients using this API.
# 
# MacPorts core in turn uses a couple of other libraries you shouldn't have to
# worry about if your intention is using MacPorts. They are just documented here
# for MacPorts-internal purposes. They are:
# \li <tt>port 1.0</tt>, which is the API usable from within Portfiles
# \li <tt>portindex 1.0</tt>, providing a fast and searchable database of the
#     ports available in the ports tree
# \li <tt>package 1.0</tt>, implementing a couple of functions to create and
#     manage binary packages
# \li <tt>pextlib 1.0</tt>, a collection of useful C functions exported via
#     a Tcl interface for use in various parts of MacPorts
# \li <tt>registry 2.0</tt>, which is used to keep track of all installed ports
#     and their relations (e.g., dependencies) and <tt>cregistry</tt>, an
#     SQLite-based implementation of the registry storage API
# \li <tt>machista 1.0</tt>, a library that supports querying metadata of Mach-O
#     binaries
# \li <tt>darwintracelib 1.0</tt>, the implementation of the trace mode features
#     in MacPorts providing isolation for builds
namespace eval macports {
    ##
    # Holds the architecture of the current system. Valid values are
    # \li \c powerpc, for Power Macintosh systems
    # \li \c i386, for Intel systems (\c i586, \c i686, \c x86_64)
    variable os_arch [private::get_os_arch]

    ##
    # Contains the OS version, e.g. 12.2.0 for OS X 10.8.2 (remember Mountain
    # Lion is darwin12)
    variable os_version [private::get_os_version]

    ##
    # Convenience variable holding the first part of \c os_version
    variable os_major [private::get_os_major]

    ##
    # The endianess of the system, either \c little, or \c big, depending on the
    # CPU type.
    variable os_endian [private::get_os_endian]

    ##
    # The name of the OS of the current system in lowercase. See the output of
    # <tt>uname -s</tt> on your system for possible values.
    variable os_platform [private::get_os_platform]

    ##
    # The OS X version number with two digits, e.g. 10.8 for Mountain Lion.
    # Empty on platforms other than darwin.
    variable macosx_version [private::get_macosx_version]

    ##
    # The home directory of the user executing MacPorts, or a non-existant
    # directory, if the executing user could not be determined.
    variable user_home

    ##
    # Initializes MacPorts and sets all required internal variables.
    #
    # \warning
    # Call this before calling any other method in this namespace. If you call
    # other methods or read variables without calling \c init first, the result
    # is undefined.
    proc init {} {
        # set the system encoding to utf-8
        encoding system utf-8

        # initialize private data structures
        private::init

        # Ensure that the macports user directory (i.e. ~/.macports) exists, if
        # $HOME is defined. Also save $HOME for later use before replacing it
        # with a custom home directory.
        private::init_home

        # Load configuration from files
        private::init_configuration
    }

    ##
    # Register a callback for UI communication with the client. If a callback
    # was previously registered, it is replaced.
    #
    # @param[in] callback A callback function, accepting two parameters,
    #                     priority and message. It will be called for every
    #                     message MacPorts (or a Portfile) tries to pass to the
    #                     user. Clients should appropriately filter by priority
    #                     and display the message to the user.
    proc register_ui_callback {callback} {
        set private::ui_callback $callback
    }

    ##
    # Frees all resources associated with this instance of MacPorts core, closes
    # all files and releases all locks that might still be held. Just must call
    # this after using this API.
    #
    # \warning
    # Not calling this procedure might lead to memory leaks and inconsistent
    # data in internal state files of MacPorts (e.g., the port registry).
    proc release {} {}

    ##
    # Accessor method for boolean UI settings
    #
    # @param[in] key a key identifying the setting to be queried
    # @return 1, if the option is set, 0 otherwise
    proc ui_bool {key} {
        return [util::bool [ui $key]]
    }

    ##
    # Acessor method for UI settings
    #
    # @param[in] key a key identifying the setting to be queried
    # @return the setting's value, if it exists or an empty value, if there is
    #         no setting by that name
    proc ui {key} {
        if {[info exists private::ui_options($key)]} {
            return $private::ui_options($key)
        }
        return {}
    }

    ##
    # Setter method for UI settings
    #
    # @param[in] key a key identifying the setting to be changed
    # @param[in] value the new value to be associated with the given key
    # @return the old value of the setting, if any. An empty value, if the key
    #         wasn't associated with a value before
    proc set_ui {key value} {
        set old [ui $key]
        set private::ui_options($key) $value
        return $old
    }

    ##
    # Accessor method for boolean MacPorts settings
    #
    # @param[in] key a key indentifying the setting to be queried
    # @return 1, if the option is set, 0 otherwise
    proc option_bool {key} {
        return [util::bool [option $key]]
    }

    ##
    # Acessor method for MacPorts settings
    #
    # @param[in] key a key identifying the setting to be queried
    # @return the setting's value, if it exists or an empty value, if there is
    #         no setting by that name
    proc option {key} {
        if {[info exists private::global_options($key)]} {
            return $private::global_options($key)
        }
        return {}
    }

    ##
    # Setter method for MacPorts settings
    #
    # @param[in] key a key identifying the setting to be changed
    # @param[in] value the new value to be associated with the key
    # @return the setting's old value, if any, or an empty value, if the
    #         setting was previously unset
    proc set_option {key value} {
        set old [option $key]
        set private::global_options($key) $value
        return $old
    }

    ##
    # Acessor method for compile-time settings set by autoconf
    #
    # @param[in] key a key identifying the setting to be queried
    # @return the setting's value, if it exists or an empty value, if there is
    #         no setting by that name
    proc autoconf {key} {
        if {[info exists autoconf::$key]} {
            return [set autoconf::$key]
        }
        return {}
    }

    ##
    # Print a (translatable) message to the client of this API and log the
    # message. The logged message will not be translated. After translation, the
    # message will be passed to the callback registered using \c
    # register_ui_callback. No priority filtering is done in this function;
    # callbacks are expected to filter on their own based on their current
    # settings (which might change at runtime).
    #
    # @param[in] priority one of the constants in \c macports::priority, setting
    #                     the severity of the message.
    # @param[in] message a string containing \c printf style placeholders that
    #                    is subject to localization. For each placeholder used,
    #                    a value must be passed in the variadic argument list.
    # @param[in] args list of variadic arguments used to fill in the
    #                 placeholders in the message.
    proc msg {priority message args} {
        set localized [::msgcat::mc $message]
        if {$private::ui_callback != {}} {
            eval $private::ui_callback $priority $localized {*}$args
        } else {
            # TODO: Remove this after debugging!
            puts "$priority: [format $localized {*}$args]"
        }
    }
}
