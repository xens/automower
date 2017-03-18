
set scriptname [lindex [file split $argv0] end]
if {[file exists /tmp/$scriptname.stop]} then {exit 0}

set daemonize 0
if {[file exists /tmp/$scriptname.pid]} then {
  catch {
    set f [open /tmp/$scriptname.pid]
    set filepid [read $f]
    close $f
    if {[pid] != $filepid} then {
      catch {exec kill $filepid}
      set daemonize 1
    }
  }
} else {
  set daemonize 1
}

if {$daemonize && ![regexp -- "-nodaemonize" $argv dummy]} then {
  eval exec /sbin/daemonize -p /tmp/$scriptname.pid -o /tmp/$scriptname.stdout -e /tmp/$scriptname.stderr /bin/tclsh $argv0 $argv
  exit 0
}
