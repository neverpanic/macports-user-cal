# vim:et:ts=4:tw=80
# tcl.tcl
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
package provide portindex::tcl 1.0

namespace eval portindex::tcl {
    # The output directory for the PortIndex
    variable outdir

    # The output path for the PortIndex
    variable outpath

    # The quickindex structure containing offsets into the PortIndex tcl script
    variable qindex
    array set qindex {}

    # Temporary portindex file
    variable tempportindex

    # File descriptor pointing to the old temporary portindex, if any
    variable oldfd -1

    # File descriptor pointing to the new temporary portindex file
    variable fd

    # Copy of ${macports::prefix}
    variable save_prefix

    # Timestamp of the most recent modification in the ports tree, to be the
    # timestamp of the PortIndex
    variable newest

    # Timestamp of the last PortIndex update, to find out whether we need to
    # re-parse a port.
    variable oldmtime

    variable keepkeys
    array set keepkeys {
        categories          1
        depends_fetch       1
        depends_extract     1
        depends_build       1
        depends_lib         1
        depends_run         1
        description         1
        long_description    1
        homepage            1
        maintainers         1
        name                1
        platforms           1
        epoch               1
        version             1
        revision            1
        variants            1
        portdir             1
        portarchive         1
        replaced_by         1
        license             1
        installs_libs       1
    }

    # Updates the PortIndex. Consider this to start a transaction, run the
    # Tcl block given in $script and finish a transaction (which is what it does
    # in the SQLite variant). It's a little different in the Tcl variant, though.
    namespace export update
    proc update {outdir script} {
        init ${outdir}
        eval ${script}
        finish
    }

    # Initialize this PortIndex generator.
    # Sets any variables this specific implementation of the portindex needs
    # and opens a new temporary portindex file.
    proc init {outdir_param} {
        variable fd
        variable newest
        variable oldmtime
        variable oldfd
        variable outdir
        variable outpath
        variable qindex
        variable save_prefix
        variable tempportindex

        set outdir ${outdir_param}
        set outpath [file join ${outdir} PortIndex]

        # start by assuming we have no previous index, and are generating
        # a fresh one (so the timestamp of the old PortIndex is 0)
        set newest 0

        # open old index for comparison
        if {[file isfile $outpath] && [file isfile ${outpath}.quick]} {
            set oldmtime [file mtime $outpath]
            set newest $oldmtime
            if {![catch {set oldfd [open $outpath r]}] &&
                ![catch {set quickfd [open ${outpath}.quick r]}]} {
                if {![catch {set quicklist [read $quickfd]}]} {
                    foreach entry [split $quicklist "\n"] {
                        set qindex([lindex $entry 0]) [lindex $entry 1]
                    }
                }
                close $quickfd
            }
        }

        set tempportindex [mktemp "/tmp/mports.portindex.XXXXXXXX"]
        set fd [open ${tempportindex} w]
        set save_prefix ${macports::prefix}
    }

    # Helper function to write an entry in PortIndex type
    proc pindex_write_entry {name len line} {
        variable fd

        puts $fd [list $name $len]
        puts -nonewline $fd $line
    }

    # Helper function to read an entry from the previous PortIndex
    proc pindex_read_entry {nameref lenref lineref portname} {
        variable oldfd
        variable qindex

        upvar $nameref name
        upvar $lenref  len
        upvar $lineref line

        set offset $qindex([string tolower $portname])
        seek $oldfd $offset
        gets $oldfd line
        set name [lindex $line 0]
        set len [lindex $line 1]
        set line [read $oldfd $len]
    }

    # Callback returned by the portindex::tcl::callback procedure
    # Actually decides whether to re-evluate a Portfile and writes the index
    # file
    proc pindex {portdir} {
        variable fd
        variable oldfd
        variable newest
        variable oldmtime
        variable qindex
        variable outdir
        variable save_prefix
        variable keepkeys

        global target directory archive stats full_reindex ui_options port_options

        # try to reuse the existing entry if it's still valid
        if {$full_reindex != "1" &&
            $archive != "1" &&
            [info exists qindex([string tolower [file tail $portdir]])]} {
            try {
                set mtime [file mtime [file join $directory $portdir Portfile]]
                if {$oldmtime >= $mtime} {
                    if {[info exists ui_options(ports_debug)]} {
                        puts "Reusing existing entry for $portdir"
                    }

                    # Read the old entry, write it to the new file and increase
                    # the skipped counter
                    pindex_read_entry name len line [file tail $portdir]
                    pindex_write_entry $name $len $line
                    portindex::inc_skipped

                    # also reuse the entries for its subports
                    array set portinfo $line
                    if {![info exists portinfo(subports)]} {
                        return
                    }
                    foreach sub $portinfo(subports) {
                        pindex_read_entry name len line $sub
                        pindex_write_entry $name $len $line
                        portindex::inc_skipped
                    }

                    return
                }
            } catch {*} {
                throw
                ui_warn "failed to open old entry for ${portdir}, making a new one"
            }
        }

        portindex::inc_total
        set prefix {\${prefix}}
        if {[catch {set interp [mportopen file://[file join $directory $portdir] $port_options]} result]} {
            puts stderr "Failed to parse file $portdir/Portfile: $result"
            # revert the prefix.
            set prefix $save_prefix
            portindex::inc_failed
        } else {
            # revert the prefix.
            set prefix $save_prefix
            array set portinfo [mportinfo $interp]
            mportclose $interp
            set portinfo(portdir) $portdir
            puts "Adding port $portdir"
            if {$archive == "1"} {
                if {![file isdirectory [file join $outdir [file dirname $portdir]]]} {
                    if {[catch {file mkdir [file join $outdir [file dirname $portdir]]} result]} {
                        puts stderr "$result"
                        exit 1
                    }
                }
                set portinfo(portarchive) [file join [file dirname $portdir] [file tail $portdir]].tgz
                cd [file join $directory [file dirname $portinfo(portdir)]]
                puts "Archiving port $portinfo(name) to [file join $outdir $portinfo(portarchive)]"
                set tar [macports::findBinary tar $macports::autoconf::tar_path]
                set gzip [macports::findBinary gzip $macports::autoconf::gzip_path]
                if {[catch {exec $tar -cf - [file tail $portdir] | $gzip -c >[file join $outdir $portinfo(portarchive)]} result]} {
                    puts stderr "Failed to create port archive $portinfo(portarchive): $result"
                    exit 1
                }
            }

            foreach availkey [array names portinfo] {
                # store list of subports for top-level ports only
                if {![info exists keepkeys($availkey)] && $availkey != "subports"} {
                    unset portinfo($availkey)
                }
            }
            set output "[array get portinfo]\n"
            set len [string length $output]

            pindex_write_entry $portinfo(name) $len $output

            set mtime [file mtime [file join $directory $portdir Portfile]]
            if {$mtime > $newest} {
                set newest $mtime
            }

            # now index this portfile's subports (if any)
            if {![info exists portinfo(subports)]} {
                return
            }
            foreach sub $portinfo(subports) {
                portindex::inc_total
                set prefix {\${prefix}}
                if {[catch {set interp [mportopen file://[file join $directory $portdir] [concat $port_options subport $sub]]} result]} {
                    puts stderr "Failed to parse file $portdir/Portfile with subport '${sub}': $result"
                    set prefix $save_prefix
                    portindex::inc_failed
                } else {
                    set prefix $save_prefix
                    array unset portinfo
                    array set portinfo [mportinfo $interp]
                    mportclose $interp
                    set portinfo(portdir) $portdir
                    puts "Adding subport $sub"
                    foreach availkey [array names portinfo] {
                        if {![info exists keepkeys($availkey)]} {
                            unset portinfo($availkey)
                        }
                    }
                    set output "[array get portinfo]\n"
                    set len [string length $output]
                    pindex_write_entry $portinfo(name) $len $output
                }
            }
        }
    }

    # Returns a callback suitable to be passed to mporttraverse, which will
    # generate the portindex of this specific type.
    namespace export callback
    proc callback {} {
        return [namespace code {pindex}]
    }

    # Replaces the previously live PortIndex using the newly generated one.
    # This should be atomic, if possible
    proc finish {} {
        variable fd
        variable newest
        variable oldfd
        variable outpath
        variable tempportindex

        if {${oldfd} != -1} {
            close $oldfd
        }
        close $fd

        file rename -force ${tempportindex} ${outpath}
        file mtime ${outpath} ${newest}

        generate_quickindex ${outpath}
    }

    # Generate PortIndex.quick storing offsets into PortIndex
    proc generate_quickindex {outpath} {
        if {[catch {set indexfd [open ${outpath} r]} result]} {
            ui_warn "Can't open index file: $::errorInfo"
            return -code error
        }
        if {[catch {set quickfd [open ${outpath}.quick w]} result]} {
            ui_warn "Can't open quick index file: $::errorInfo"
            return -code error
        }

        try {
            set offset [tell $indexfd]
            set quicklist ""
            while {[gets $indexfd line] >= 0} {
                if {[llength $line] != 2} {
                    continue
                }
                set name [lindex $line 0]
                append quicklist "[string tolower $name] ${offset}\n"

                set len [lindex $line 1]
                read $indexfd $len
                set offset [tell $indexfd]
            }
            puts -nonewline $quickfd $quicklist
        } catch {*} {
            ui_warn "It looks like your PortIndex file $outpath may be corrupt."
            throw
        } finally {
            close $indexfd
            close $quickfd
        }
        
        if {[info exists quicklist]} {
            return $quicklist
        } else {
            ui_warn "Failed to generate quick index for: $outpath"
            return -code error
        }
    }
}
