#!/usr/bin/tclsh
# -*- coding: utf-8; mode: tcl; tab-width: 4; indent-tabs-mode: nil; c-basic-offset: 4 -*- vim:fenc=utf-8:ft=tcl:et:sw=4:ts=4:sts=4
# $Id$
#
# Copyright (c) 2011,2013 The MacPorts Project
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are
# met:
#
# 1. Redistributions of source code must retain the above copyright
#    notice, this list of conditions and the following disclaimer.
# 2. Redistributions in binary form must reproduce the above copyright
#    notice, this list of conditions and the following disclaimer in the
#    documentation and/or other materials provided with the distribution.
# 3. Neither the name of The MacPorts Project nor the names of its
#    contributors may be used to endorse or promote products derived from
#    this software without specific prior written permission.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
# "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
# LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
# A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
# OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
# SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
# LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
# DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
# THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
# (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
# OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

set VERSION 0.1
set prefix /opt/local

if {[catch {source ${prefix}/share/macports/Tcl/macports1.0/macports_fastload.tcl} result]} {
    puts stderr "Error: $result"
    exit 1
}

package require macports
if {[catch {mportinit} result]} {
    puts stderr "Error: $result"
    exit 1
}

proc usage {} {
    ui_msg "Usage: $::argv0 \[submit|show\]"
}

proc read_config {} {
    global prefix stats_url stats_id
    set conf_path "${prefix}/etc/macports/stats.conf"
    if {[file isfile $conf_path]} {
        set fd [open $conf_path r]
        while {[gets $fd line] >= 0} {
            set optname [lindex $line 0]
            if {$optname eq "stats_url"} {
                set stats_url [lindex $line 1]
            }
        }
        close $fd
    }

    set uuid_path "${prefix}/var/macports/stats-uuid"
    if {[file isfile $uuid_path]} {
        set fd [open $uuid_path r]
        gets $fd stats_id
        close $fd
        if {[string length $stats_id] == 0} {
            puts stderr "UUID file ${uuid_path} seems to be empty. Abort."
        }
    } else {
        puts stderr "UUID file ${uuid_path} missing. Abort."
        exit 1
    }
}

# extraction of gcc version
proc getgccinfo {} {
    # Find gcc in path
    if {[catch {set gccpath [macports::binaryInPath "gcc"]}] != 0} {
        # Failed
        ui_msg "$::errorInfo"
        return none
    }

    # Call gcc -v - Note that output will be on stderr not stdout
    # This succeeds if catch returns nonzero
    if { [catch { exec $gccpath -v } gccinfo] == 0} {
        # Failed
        ui_msg "$::errorInfo"
        return none
    }

    # Extract version
    if {[regexp {gcc version ([0-9.]+)} $gccinfo - gcc_v] == 1} {
        # Set gcc version
        return $gcc_v
    } else {
        # ui_warn "gcc exists but could not read version information"
        # Don't warn since that's the default now that gcc -> clang
        return none
    }
}

###### JSON Encoding helper procs ######

# Return JSON encoding of a flat "key":"value" dictionary
proc json_encode_dict { data } {
    upvar 1 $data db

    set size [dict size $db]
    set i 1

    # Initialize the JSON string string
    set json "\{"

    dict for {key values} $db {
        set line "\"$key\":\"[dict get $db $key]\""

        # Check if there are any subsequent items
        if {$i < $size} {
            set line "$line, "
        } 

        # Add line to the JSON string
        set json "$json$line"

        incr i
    }

    set json "$json\}"

    return $json
}

# Encodes a list of strings as a JSON array
proc json_encode_list { data } {    
    set size [llength $data]
    set i 1

    set json "\["

    foreach item $data {
        set json "$json$data"

        # Check if there are any subsequent items
        if {$i < $size} {
            set json "$json, "
        }

        incr i
    }

    set json "$json \]"

    return $json
}

# Encode a port (from a portlist entry) as a JSON object
proc json_encode_port { port_info } {
    upvar 1 $port_info port

    set first true

    set json "\{"
    foreach name [array names port] {

        # Skip empty strings
        if {$port($name) eq ""} {
            continue
        }

        # Prepend a comma if this isn't the first item that has been processed
        if {!$first} {
            # Add a comma
            set json "$json, "
       } else {
           set first false
       }

        # Format the entry as "name_string":"value"
        set entry "\"$name\":\"$port($name)\"" 
        set json "$json$entry"
    }

    set json "$json\}"

    return $json
}

# Encode portlist as a JSON array of port objects
proc json_encode_portlist { portlist } {
    set json "\["
    set first true

    foreach i $portlist {
        array set port $i

        set encoded [json_encode_port port]

        # Prepend a comma if this isn't the first item that has been processed
        if {!$first} {
            # Add a comma
            set json "$json, "
       } else {
           set first false
       }

        # Append encoded json object
        set json "$json$encoded"
    }

    set json "$json\]"

    return $json
}

# Top level container for os and port data
# Returns a JSON Object with three  
proc json_encode_stats {id os_dict ports_dict} {
    upvar 1 $os_dict os
    upvar 1 $ports_dict ports

    set os_json [json_encode_dict os]
    set active_ports_json [json_encode_portlist [dict get $ports "active"]]
    set inactive_ports_json [json_encode_portlist [dict get $ports "inactive"]]

    set json "\{"
    set json "$json \"id\":\"$id\","
    set json "$json \"os\":$os_json,"
    set json "$json \"active_ports\":$active_ports_json,"
    set json "$json \"inactive_ports\":$inactive_ports_json"
    set json "$json\}"

    return $json
}

proc split_variants {variants} {
    set result {}
    set l [regexp -all -inline -- {([-+])([[:alpha:]_]+[\w\.]*)} $variants]
    foreach { match sign variant } $l {
        lappend result $variant $sign
    }
    return $result
}

proc get_installed_ports {active} {
    set ilist {}
    if { [catch {set ilist [registry::installed]} result] } {
        if {$result != "Registry error: No ports registered as installed."} {
            ui_debug "$::errorInfo"
            return -code error "registry::installed failed: $result"
        }
    }

    set results {}
    foreach i $ilist {
        set iactive [lindex $i 4]

        if {(${active} == "yes") == (${iactive} != 0)} {
            set iname [lindex $i 0]
            set iversion [lindex $i 1]
            set irevision [lindex $i 2]
            set ivariants [split_variants [lindex $i 3]]
            lappend results [list name $iname version "${iversion}_${irevision}" variants $ivariants]
        }
    }

    return $results
}


proc action_stats {subcommands} {
    global stats_url stats_id

    # Build dictionary of os information
    dict set os macports_version [macports::version]
    dict set os osx_version ${macports::macosx_version}
    dict set os os_arch ${macports::os_arch} 
    dict set os os_platform ${macports::os_platform}
    dict set os build_arch ${macports::build_arch}
    dict set os gcc_version [getgccinfo]
    dict set os xcode_version ${macports::xcodeversion}

    # Build dictionary of port information 
    dict set ports active   [get_installed_ports yes]
    dict set ports inactive [get_installed_ports no]

    # If no subcommands are given (subcommands is empty) print out OS information
    if {$subcommands eq ""} {
        # Print information from os dictionary
        dict for {key values} $os {
            puts "$key: [dict get $os $key]"
        }
        return 0
    }

    # Make sure there aren't too many subcommands
    if {[llength $subcommands] > 1} {
        ui_error "Please select only one subcommand."
        usage
        return 1
    }

    if {![info exists stats_url]} {
        ui_error "Configuration variable stats_url is not set"
        return 1
    }
    if {![info exists stats_id]} {
        ui_error "Configuration variable stats_id is not set"
        return 1
    }

    set json [json_encode_stats $stats_id os ports]

    # Get the subcommand
    set cmd [lindex $subcommands 0]

    switch $cmd {
        submit {
            ui_notice "Submitting to $stats_url"

            if {[catch {curl post "submission\[data\]=$json" $stats_url} value]} {
                ui_error "$::errorInfo"
                return 1
            }
        }
        show {
            ui_notice "Would submit to $stats_url"
            ui_msg "submission\[data\]=$json"
        }
        default {
            puts "Unknown subcommand."
            usage
            return 1
        }
    }

   return 0
}

read_config
action_stats $argv
