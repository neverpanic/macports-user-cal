#!/bin/sh
# -*- coding: utf-8; mode: tcl; tab-width: 4; indent-tabs-mode: nil; c-basic-offset: 4 -*- vim:fenc=utf-8:filetype=tcl:et:sw=4:ts=4:sts=4
# Run the Tcl interpreter \
exec @TCLSH@ "$0" "$@"

# Traverse through all ports, creating an index and archiving port directories
# if requested
# $Id$

source [file join "@macports_tcl_dir@" macports1.0 macports_fastload.tcl]
package require macports
package require Pextlib
package require portindex


# Globals
set archive 0
set full_reindex 0
array set ui_options        [list]
array set global_options    [list]
array set global_variations [list]
set port_options            [list]

# Pass global options into mportinit
mportinit ui_options global_options global_variations

# Standard procedures
proc print_usage args {
    global argv0
    puts "Usage: $argv0 \[-adf\] \[-p plat_ver_arch\] \[-o output directory\] \[directory\]"
    puts "-a:\tArchive port directories (for remote sites). Requires -o option"
    puts "-d:\tOutput debugging information"
    puts "-f:\tDo a full re-index instead of updating"
    puts "-o:\tOutput all files to specified directory"
    puts "-p:\tPretend to be on another platform"
    puts "-s:\tGenerate SQLite-based PortIndex, disables generation of Tcl-based index"
}

# default index types is Tcl
set index_type tcl

for {set i 0} {$i < $argc} {incr i} {
    set arg [lindex $argv $i]
    switch -regex -- $arg {
        {^-.+} {
            if {$arg == "-a"} { # Turn on archiving
                set archive 1
            } elseif {$arg == "-d"} { # Turn on debug output
                set ui_options(ports_debug) yes
            } elseif {$arg == "-o"} { # Set output directory
                incr i
                set outdir [file join [pwd] [lindex $argv $i]]
            } elseif {$arg == "-p"} { # Set platform
                incr i
                set platlist [split [lindex $argv $i] _]
                set os_platform [lindex $platlist 0]
                set os_major [lindex $platlist 1]
                set os_arch [lindex $platlist 2]
                if {$os_platform == "macosx"} {
                    lappend port_options os.subplatform $os_platform os.universal_supported yes
                    set os_platform darwin
                }
                lappend port_options os.platform $os_platform os.major $os_major os.arch $os_arch
            } elseif {$arg == "-f"} { # Completely rebuild index
                set full_reindex 1
            } elseif {$arg == "-s"} { # Use SQLite, disable Tcl index
                set index_type sqlite
            } else {
                puts stderr "Unknown option: $arg"
                print_usage
                exit 1
            }
        }
        default {
            set directory [file join [pwd] $arg]
        }
    }
}

if {$archive == 1 && ![info exists outdir]} {
    puts stderr "You must specify an output directory with -o when using the -a option"
    print_usage
    exit 1
}

if {![info exists directory]} {
    set directory .
}

# cd to input directory
if {[catch {cd $directory} result]} {
    puts stderr "$result"
    exit 1
} else {
    set directory [pwd]
}

# Set output directory to full path
if {[info exists outdir]} {
    if {[catch {file mkdir $outdir} result]} {
        puts stderr "$result"
        exit 1
    }
    if {[catch {cd $outdir} result]} {
        puts stderr "$result"
        exit 1
    } else {
        set outdir [pwd]
    }
} else {
    set outdir $directory
}

portindex::set_portindex_type ${index_type}

puts "Creating ${index_type} port index in $outdir"
portindex::update ${outdir} [namespace code {mporttraverse [portindex::callback] $directory}]

array set stats [portindex::statistics]
puts "\nTotal number of ports parsed:\t$stats(total)\
      \nPorts successfully parsed:\t[expr $stats(total) - $stats(failed)]\
      \nPorts failed:\t\t\t$stats(failed)\
      \nUp-to-date ports skipped:\t$stats(skipped)\n"
