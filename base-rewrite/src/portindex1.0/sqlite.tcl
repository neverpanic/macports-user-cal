# vim:et:ts=4:tw=100
# sqlite.tcl
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
package provide portindex::sqlite 1.0

package require portindex 1.0
package require stooop

namespace eval portindex::sqlite {
    ########################
    # PortIndex generation #
    ########################

    # The output directory for the PortIndex
    variable outdir

    # The output path for the PortIndex
    variable outpath

    # Temporary portindex file
    variable tempportindex

    # Copy of ${macports::prefix}
    variable save_prefix

    # Variable holding the SQLite database connection
    variable db

    # Timestamp of the last PortIndex update, to find out whether we need to re-parse a port.
    variable oldmtime

    # Updates the PortIndex. Consider this to start a transaction, run the Tcl block given in
    # $script and finish a transaction (which is what it does in the SQLite variant).
    namespace export update
    proc update {outdir script} {
        variable db

        init ${outdir}
        db transaction {
            eval ${script}

            # Bring out the garbage
            db eval {
                DELETE FROM portindex WHERE colorbit != 1;
                UPDATE portindex SET colorbit = 0;
            }
        }
        finish
    }

    # Initialize the database and create the required tables. This is only called after the database
    # has successfully been opened, so we can assume the connection to be open. We haven't ensured
    # the file to be writable yet, though…
    proc create_database {database} {
        if {[catch {
            db eval "
                CREATE TABLE IF NOT EXISTS $database.portindex_version (
                    version TEXT PRIMARY KEY
                );
                DELETE FROM $database.portindex_version;
                INSERT INTO $database.portindex_version (version) VALUES ('1.0');
                CREATE TABLE IF NOT EXISTS $database.maintainers (
                      port_id INTEGER NOT NULL
                    , maintainer TEXT NOT NULL
                    , PRIMARY KEY (port_id, maintainer)
                    , FOREIGN KEY (port_id) REFERENCES portindex (id)
                       ON DELETE CASCADE
                       ON UPDATE CASCADE
                );
                CREATE TABLE IF NOT EXISTS $database.platforms (
                      port_id INTEGER NOT NULL
                    , platform TEXT NOT NULL
                    , PRIMARY KEY (port_id, platform)
                    , FOREIGN KEY (port_id) REFERENCES portindex (id)
                       ON DELETE CASCADE
                       ON UPDATE CASCADE
                );
                CREATE TABLE IF NOT EXISTS $database.variants (
                      port_id INTEGER NOT NULL
                    , variant TEXT NOT NULL
                    , PRIMARY KEY (port_id, variant)
                    , FOREIGN KEY (port_id) REFERENCES portindex (id)
                       ON DELETE CASCADE
                       ON UPDATE CASCADE
                );
                CREATE TABLE IF NOT EXISTS $database.categories (
                      port_id INTEGER NOT NULL
                    , category TEXT NOT NULL
                    , PRIMARY KEY (port_id, category)
                    , FOREIGN KEY (port_id) REFERENCES portindex (id)
                       ON DELETE CASCADE
                       ON UPDATE CASCADE
                );
                CREATE TABLE IF NOT EXISTS $database.licenses (
                      port_id INTEGER NOT NULL
                    , license TEXT NOT NULL
                    , PRIMARY KEY (port_id, license)
                    , FOREIGN KEY (port_id) REFERENCES portindex (id)
                       ON DELETE CASCADE
                       ON UPDATE CASCADE
                );
                CREATE TABLE IF NOT EXISTS $database.dependencies (
                      port_id INTEGER NOT NULL
                    , type INTEGER NOT NULL
                    , dependency TEXT NOT NULL
                    , PRIMARY KEY (port_id, type, dependency)
                    , FOREIGN KEY (port_id) REFERENCES portindex (id)
                       ON DELETE CASCADE
                       ON UPDATE CASCADE
                );
                CREATE TABLE IF NOT EXISTS $database.portindex (
                      id INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL
                    , port TEXT COLLATE NOCASE UNIQUE NOT NULL
                    , parentport INTEGER
                    , epoch INTEGER NOT NULL
                    , version TEXT NOT NULL
                    , revision INTEGER NOT NULL
                    , homepage TEXT
                    , description TEXT COLLATE NOCASE
                    , long_description TEXT COLLATE NOCASE
                    , portdir TEXT
                    , replaced_by TEXT
                    , installs_libs BOOL
                    , mtime INTEGER
                    , colorbit BOOL
                    , FOREIGN KEY (parentport) REFERENCES portindex (id)
                       ON DELETE CASCADE
                       ON UPDATE CASCADE
                );
                CREATE INDEX IF NOT EXISTS $database.portindex_parentport
                    ON portindex (parentport);
                CREATE INDEX IF NOT EXISTS $database.portindex_portdir
                    ON portindex (portdir, parentport);
            "
        } result]} {
            set sqlerror [db errorcode]
            ui_error "Error code ${sqlerror} querying database ${database}: ${result}"
            exit 1
        }
    }

    # Initialize this PortIndex generator.
    # Sets any variables this specific implementation of the portindex needs and opens a new
    # temporary portindex file.
    proc init {outdir_param} {
        package require sqlite3

        variable oldmtime 0
        variable outdir
        variable outpath
        variable save_prefix
        variable db

        global archive

        if {${archive} == "1"} {
            error "Archive mode is not supported by the SQLite PortIndex."
        }

        set outdir ${outdir_param}
        set outpath [file join ${outdir} PortIndex.db]

        if {[catch {sqlite3 db ${outpath}} result]} {
            ui_error "error opening database ${outpath}: ${result}"
            exit 1
        }

        # set 500ms busy timeout
        db timeout 500

        # create an in-memory database
        db eval {
            ATTACH DATABASE ':memory:' AS tmpdb;
        }
        create_database tmpdb

        if {[catch {set version [db onecolumn {SELECT version FROM main.portindex_version}]} result]} {
            switch -exact [db errorcode] {
                1 {
                    # SQLITE_ERROR, SQL error or missing database
                    if {[regexp {^no such table:} $result]} {
                        # Database hasn't been created yet.
                        create_database main
                    }
                }

                default {
                    ui_error "Error code [db errorcode] querying database: $result"
                    exit 1
                }
            }
        } else {
            # Create an in-memory copy of the database, for lookup speed.
            db eval {
                INSERT INTO tmpdb.portindex    SELECT * FROM main.portindex;
                INSERT INTO tmpdb.variants     SELECT * FROM main.variants;
                INSERT INTO tmpdb.categories   SELECT * FROM main.categories;
                INSERT INTO tmpdb.maintainers  SELECT * FROM main.maintainers;
                INSERT INTO tmpdb.platforms    SELECT * FROM main.platforms;
                INSERT INTO tmpdb.licenses     SELECT * FROM main.licenses;
                INSERT INTO tmpdb.dependencies SELECT * FROM main.dependencies;
            }
        }

        # query portindex for the maximum previous mtime
        try {
            set oldmtime [db onecolumn {SELECT MAX(mtime) FROM tmpdb.portindex}]
        }

        set save_prefix ${macports::prefix}
    }

    # Insert a list-type field into the portindex database. Examples for list-type fields are:
    # categories, variants, maintainers, licenses, and platforms. Parameters are the name of the
    # table holding the list, the name of the field (both in the portinfo array and in the database
    # table) and a reference to the portinfo array.
    proc insert_list {table field portinfofield portinforef} {
        variable db

        upvar $portinforef portinfo

        if {![info exists portinfo($portinfofield)]} {
            # if there's no categories, variants, etc.
            return
        }

        foreach value $portinfo($portinfofield) {
            db eval "
                INSERT INTO $table (
                      port_id
                    , $field
                ) VALUES (
                      :portinfo(id)
                    , :value
                )
            "
        }
    }

    # Update a list-type field in the portindex database. See insert_list for examples of list-type
    # fields. Parameters are the name of the table holding the list, the name of the field (both in
    # the portinfo array and in the database table) and a reference to the portinfo array.
    proc update_list {table field portinfofield portinforef} {
        variable db

        upvar $portinforef portinfo

        if {![info exists portinfo($portinfofield)]} {
            # we have an empty list
            # make sure the database is empty for this combination, too
            db eval "DELETE FROM $table WHERE port_id = :portinfo(id)"
            return
        }

        # Get old and new entries to generate a set of diffs
        set oldentries [db eval "SELECT $field FROM tmpdb.$table WHERE port_id = :portinfo(id)"]
        set newentries $portinfo($portinfofield)

        set added   [list]
        set deleted [list]

        # find out which elements have been removed or added
        foreach newentry $newentries {
            if {[lsearch -exact $oldentries $newentry] == -1} {
                lappend added $newentry
            }
        }
        foreach oldentry $oldentries {
            if {![lsearch -exact $newentries $oldentry] == -1} {
                lappend deleted $oldentry
            }
        }

        # and delete/add them
        foreach del $deleted {
            db eval "DELETE FROM $table WHERE port_id = :portinfo(id) AND $field = :del"
        }
        foreach add $added {
            db eval "
                INSERT INTO $table
                (
                      port_id
                    , $field
                ) VALUES (
                      :portinfo(id)
                    , :add
                )
            "
        }
    }

    # Call a given callback function a couple of times, once for each list-type field, passing the
    # required parameters.
    proc call_list_proc {callback portinforef} {
        upvar $portinforef portinfo

        eval $callback categories  category    categories  portinfo
        eval $callback licenses    license     license     portinfo
        eval $callback maintainers maintainer  maintainers portinfo
        eval $callback platforms   platform    platforms   portinfo
        eval $callback variants    variant     variants    portinfo
    }

    # Insert all dependencies into the portindex database. Parameter is a reference to the portinfo
    # array.
    proc insert_dependencies {portinforef} {
        variable db

        upvar $portinforef portinfo

        foreach type {fetch extract build lib run} {
            if {![info exists portinfo(depends_$type)]} {
                # if there's no categories, variants, etc.
                continue
            }

            foreach value $portinfo(depends_$type) {
                db eval {
                    INSERT INTO dependencies (
                          port_id
                        , type
                        , dependency
                    ) VALUES (
                          $portinfo(id)
                        , $type
                        , $value
                    )
                }
            }
        }
    }

    # Update dependencies in the portindex database. Parameter is a reference to the portinfo array.
    proc update_dependencies {portinforef} {
        variable db

        upvar $portinforef portinfo

        foreach type {fetch extract build lib run} {
            if {![info exists portinfo(depends_$type)]} {
                # we have an empty list
                # make sure the database is empty for this combination, too
                db eval {DELETE FROM dependencies WHERE port_id = $portinfo(id) AND type = $type}
                continue
            }

            # Get old and new entries to generate a set of diffs
            set oldentries [db eval {SELECT dependency FROM tmpdb.dependencies WHERE port_id = $portinfo(id) AND type = $type}]
            set newentries $portinfo(depends_$type)

            set added   [list]
            set deleted [list]

            # find out which elements have been removed or added
            foreach newentry $newentries {
                if {[lsearch -exact $oldentries $newentry] == -1} {
                    lappend added $newentry
                }
            }
            foreach oldentry $oldentries {
                if {![lsearch -exact $newentries $oldentry] == -1} {
                    lappend deleted $oldentry
                }
            }

            # and delete/add them
            foreach del $deleted {
                db eval {DELETE FROM dependencies WHERE port_id = $portinfo(id) AND type = $type AND dependency = $del}
            }
            foreach add $added {
                db eval {
                    INSERT INTO dependencies (
                          port_id
                        , type
                        , dependency
                    ) VALUES (
                          $portinfo(id)
                        , $type
                        , $add
                    )
                }
            }
        }
    }

    # Helper function to write an entry
    # Given an array reference to portinfo (portinforef), the mtime of the portfile and the parent
    # port (if this port is a subport), insert an entry into the index.
    proc pindex_write_entry {portinforef mtime {parentport {}}} {
        variable db

        upvar $portinforef portinfo

        set portinfo(id) [db onecolumn {SELECT id FROM tmpdb.portindex WHERE port = $portinfo(name)}]

        if {$portinfo(id) == ""} {
            # new entry, just dump it into the database
            db eval {
                INSERT INTO portindex
                (
                    port
                  , parentport
                  , epoch
                  , version
                  , revision
                  , homepage
                  , description
                  , long_description
                  , portdir
                  , replaced_by
                  , installs_libs
                  , mtime
                  , colorbit
                ) VALUES (
                    $portinfo(name)
                  , $parentport
                  , $portinfo(epoch)
                  , $portinfo(version)
                  , $portinfo(revision)
                  , $portinfo(homepage)
                  , $portinfo(description)
                  , $portinfo(long_description)
                  , $portinfo(portdir)
                  , $portinfo(replaced_by)
                  , $portinfo(installs_libs)
                  , $mtime
                  , 1
                )
            }
            set portinfo(id) [db last_insert_rowid]
            call_list_proc insert_list portinfo
            insert_dependencies portinfo
        } else {
            # update the existing entry
            db eval {
                UPDATE portindex
                SET
                      parentport        = $parentport
                    , epoch             = $portinfo(epoch)
                    , version           = $portinfo(version)
                    , revision          = $portinfo(revision)
                    , homepage          = $portinfo(homepage)
                    , description       = $portinfo(description)
                    , long_description  = $portinfo(long_description)
                    , portdir           = $portinfo(portdir)
                    , replaced_by       = $portinfo(replaced_by)
                    , installs_libs     = $portinfo(installs_libs)
                    , mtime             = $mtime
                    , colorbit          = 1
                WHERE
                    id                  = $portinfo(id)
            }
            call_list_proc update_list portinfo
            update_dependencies portinfo
        }
    }

    # Callback returned by the portindex::tcl::callback procedure
    # Actually decides whether to re-evluate a Portfile and writes the index file
    proc pindex {portdir} {
        variable db
        variable oldmtime
        variable qindex
        variable outdir
        variable save_prefix
        variable keepkeys

        global directory full_reindex ui_options port_options

        set mtime [file mtime [file join $directory $portdir Portfile]]

        # try to reuse the existing entry if it's still valid
        if {$full_reindex != "1"} {
            set port_id [db onecolumn {SELECT id FROM tmpdb.portindex WHERE portdir = $portdir AND parentport = ""}]
            if {$port_id != ""} {
                if {$oldmtime >= $mtime} {
                    if {[info exists ui_options(ports_debug)]} {
                        puts "Reusing existing entry for $portdir"
                    }

                    # Re-using an entry in SQLite-based PortIndex is as easy as doing nothing.
                    # We need to mark the entries as valid to prevent them from being garbage
                    # collected, though.
                    # We'll do this for this port and all its subports at once.
                    db eval {UPDATE portindex SET colorbit = 1 WHERE portdir = $portdir}

                    # Add the number of changes entries to the skip count
                    portindex::inc_skipped [db changes]

                    return
                }
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

            pindex_write_entry portinfo $mtime
            set parentport $portinfo(id)

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

                    pindex_write_entry portinfo $mtime $parentport
                }
            }
        }
    }

    # Returns a callback suitable to be passed to mporttraverse, which will generate the portindex
    # of this specific type.
    namespace export callback
    proc callback {} {
        return [namespace code {pindex}]
    }

    # Cleanup procedure called at the end of portindex::update
    proc finish {} {
        variable db

        db eval {
            DETACH DATABASE tmpdb
        }
        db close
    }

    #####################
    # PortIndex reading #
    #####################

    stooop::class reader {
        # Open a new PortIndex. This will only be called if seems_like_valid_portindex returned 1,
        # so assuming the checks done there came back positive should be safe.
        proc reader {this path} ::portindex::reader {} {
            package require sqlite3

            set ($this,path) $path
            set ($this,database) [file join ${path} PortIndex.db]

            if {[catch {sqlite3 ($this,db) $($this,database)} result]} {
                error "error opening SQLite PortIndex database $($this,database): ${result}"
            }
        }

        # Close a PortIndex and release all resources associated with it.
        proc ~reader {this} {
            ($this,db) close
        }

        # Return a timestamp indicating when the PortIndex was last generated (and thus, when this
        # tree was last updated)
        proc get_mtime {this} {
            # use the mtime of the database file, not largest mtime in the index; some users might
            # legitly have indices that will not be modified at all for a long time (e.g., user
            # portfile trees)
            return [file mtime $($this,database)]
        }

        # Checks whether a given path looks like a SQLite-indexed ports tree.
        # Returns 1 if the given path seems to match, 0 otherwise. Never throws errors.
        proc seems_like_valid_portindex {path} {
            set database [file join ${path} PortIndex.db]

            return [file exists ${database}]
        }
    }
}
