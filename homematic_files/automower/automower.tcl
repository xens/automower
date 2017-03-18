#!/bin/tclsh

#Automower Steuerung Version 7.0
#
# zu übergebende Parameter:
# 1 = Debug-Mode (0 = Kein Logging / 1 = Logging des letzten Status-/Steuerbefehls / 2 = Komplettes Logging   => Default = 1
# 2 = Statusabfrage-Frequenz (in Minuten)  => Default = 5
# 3 = Connection-Timeout (in ms)  => Default = 500
# 4 = Wait between Retries (in ms)  => Default = 200
# 5 = Statusabfrage: Anzahl Retries  => Default = 5
# 6 = Steuerbefehl: Anzahl Retries  => Default = 10
# 7 = Adresse (IP & Port) des Matchport B/G
#


#only run once, check if locking port 60 is opened
if {[catch {socket -server unknown -myaddr 127.0.0.1 60} locksock]} then {
  exit 0
}

source /etc/config/addons/automower/daemonize.tcl

load tclrega.so

proc Write_Logfile {data mode} {
	set fileId [open "/etc/config/addons/automower/automower.log" $mode]
	fconfigure $fileId -buffering none
	puts $fileId $data
	close $fileId
}	

proc Write_Hexfile {data} {
	set fileId [open "/etc/config/addons/automower/automower.hex" "w"]
	fconfigure $fileId -translation binary -buffering none
	puts -nonewline $fileId [binary format H* $data]
	close $fileId
}	

proc Read_Hexfile {} {
	set fileId [open "/etc/config/addons/automower/automower.hex" "r"]
	fconfigure $fileId -translation binary -buffering none
	set data [read -nonewline $fileId]
	close $fileId
	binary scan $data H* data
	return [string toupper [string range $data 10 19]]
}	

#Ermittlung ob Automower-Steuerbefehl anliegt / Rückgabe: Steuerbefehl
proc Check_Automowercommand {} {
	array set values [rega_script "var v1 = dom.GetObject('Automower Steuerung').Value().ToString();"]
	if {$values(v1) == "0"} {
		return ""
	} else {
		array set values [rega_script "var v1 = dom.GetObject('Automower Steuerung').ValueList().StrValueByIndex(';',dom.GetObject('Automower Steuerung').Value()).ToString();"]
		return $values(v1)
	}
}

#Automower Steuerungsprozedur
proc Automower_Command {debug_mode command maxwait_connect maxtries maxwait_between_tries matchport} {
	if {$debug_mode == 1} {Write_Logfile "###########[clock format [clock sec] -format %H:%M:%S]: START COMMAND" "w"}
	if {$debug_mode == 2} {Write_Logfile "###########[clock format [clock sec] -format %H:%M:%S]: START COMMAND" "a"}

	#Initialisierung
	set result_string "OK"
	set try_success "FALSE"
	set hexin "UNKNOWN_COMMAND"
	set tries 0
	set automower_status ""
	set automower_command_status ""

	if {$debug_mode != 0} {Write_Logfile "[clock format [clock sec] -format %H:%M:%S]: Before Command" "a"}

	switch $command {
		"R_STATUS" {set hexin "0F01F10000"}
		"R_SEKUNDE" {set hexin "0F36B10000"}
		"R_MINUTE" {set hexin "0F36B30000"}
		"R_STUNDE" {set hexin "0F36B50000"}
		"R_TAG" {set hexin "0F36B70000"}
		"R_MONAT" {set hexin "0F36B90000"}
		"R_JAHR" {set hexin "0F36BD0000"}
		"R_TIMERSTATUS" {set hexin "0F4A4E0000"}
		"R_WOCHEN-TIMER1-START-STD" {set hexin "0F4A380000"}
		"R_WOCHEN-TIMER1-START-MIN" {set hexin "0F4A390000"}
		"R_WOCHEN-TIMER1-STOP-STD" {set hexin "0F4A3A0000"}
		"R_WOCHEN-TIMER1-STOP-MIN" {set hexin "0F4A3B0000"}
		"R_WOCHENEND-TIMER1-START-STD" {set hexin "0F4A3C0000"}
		"R_WOCHENEND-TIMER1-START-MIN" {set hexin "0F4A3D0000"}
		"R_WOCHENEND-TIMER1-STOP-STD" {set hexin "0F4A3E0000"}
		"R_WOCHENEND-TIMER1-STOP-MIN" {set hexin "0F4A3F0000"}
		"R_WOCHEN-TIMER2-START-STD" {set hexin "0F4A400000"}
		"R_WOCHEN-TIMER2-START-MIN" {set hexin "0F4A410000"}
		"R_WOCHEN-TIMER2-STOP-STD" {set hexin "0F4A420000"}
		"R_WOCHEN-TIMER2-STOP-MIN" {set hexin "0F4A430000"}
		"R_WOCHENEND-TIMER2-START-STD" {set hexin "0F4A440000"}
		"R_WOCHENEND-TIMER2-START-MIN" {set hexin "0F4A450000"}
		"R_WOCHENEND-TIMER2-STOP-STD" {set hexin "0F4A460000"}
		"R_WOCHENEND-TIMER2-STOP-MIN" {set hexin "0F4A470000"}
		"R_TIMER-TAGE" {set hexin "0F4A500000"}
		"R_MAEHZEIT" {set hexin "0F00380000"}
		"R_VIERECKMODUS-STATUS" {set hexin "0F01380000"}
		"R_VIERECKMODUS-PROZENT" {set hexin "0F01340000"}
		"R_VIERECKMODUS-REFERENZ" {set hexin "0F01370000"}
		"R_AKKU-LADEZEIT_MIN" {set hexin "0F01EC0000"}
		"R_AKKU-KAPAZITAET_MA" {set hexin "0F01EB0000"}
		"R_AKKU-KAPAZITAET_MAH" {set hexin "0F01EF0000"}
		"R_AKKU-KAPAZITAET-SUCHSTART_MAH" {set hexin "0F01F00000"}
		"R_AKKU-KAPAZITAET-GENUTZT_MAH" {set hexin "0F2EE00000"}
		"R_AKKU-SPANNUNG_MV" {set hexin "0F2EF40000"}
		"R_AKKU-TEMPERATUR-AKTUELL" {set hexin "0F02330000"}
		"R_AKKU-TEMPERATUR-LADEN" {set hexin "0F02350000"}
		"R_AKKU-LETZTER-LADEVORGANG_MIN" {set hexin "0F02340000"}
		"R_AKKU-NAECHSTE_TEMPERATURMESSUNG_SEK" {set hexin "0F02360000"}
		"R_GESCHWINDIGKEIT-MESSERMOTOR" {set hexin "0F2EEA0000"}
		"R_GESCHWINDIGKEIT-RECHTS" {set hexin "0F24BF0000"}
		"R_GESCHWINDIGKEIT-LINKS" {set hexin "0F24C00000"}
		"R_FIRMWARE-VERSION" {set hexin "0F33900000"}
		"R_SPRACHDATEI-VERSION" {set hexin "0F3AC00000"}
		"W_TIMERAKTIV" {set hexin "0FCA4E0000"}
		"W_TIMERINAKTIV" {set hexin "0FCA4E0001"}
		"W_MODE_HOME" {set hexin "0F812C0003"}
		"W_MODE_MAN" {set hexin "0F812C0000"}
		"W_MODE_AUTO" {set hexin "0F812C0001"}
		"W_MODE_DEMO" {set hexin "0F812C0004"}
		"W_KEY_0" {set hexin "0F805F0000"}
		"W_KEY_1" {set hexin "0F805F0001"}
		"W_KEY_2" {set hexin "0F805F0002"}
		"W_KEY_3" {set hexin "0F805F0003"}
		"W_KEY_4" {set hexin "0F805F0004"}
		"W_KEY_5" {set hexin "0F805F0005"}
		"W_KEY_6" {set hexin "0F805F0006"}
		"W_KEY_7" {set hexin "0F805F0007"}
		"W_KEY_8" {set hexin "0F805F0008"}
		"W_KEY_9" {set hexin "0F805F0009"}
		"W_PRG_A" {set hexin "0F805F000A"}
		"W_PRG_B" {set hexin "0F805F000B"}
		"W_PRG_C" {set hexin "0F805F000C"}
		"W_KEY_HOME" {set hexin "0F805F000D"}
		"W_KEY_MANAUTO" {set hexin "0F805F000E"}
		"W_KEY_C" {set hexin "0F805F000F"}
		"W_KEY_UP" {set hexin "0F805F0010"}
		"W_KEY_DOWN" {set hexin "0F805F0011"}
		"W_KEY_YES" {set hexin "0F805F0012"}
	}
	#Prüfen, ob ein gültiges Kommando übergeben wurde
	if {$hexin == "UNKNOWN_COMMAND"} {set result_string "#[clock format [clock sec] -format %H:%M:%S]: Unknown Command"}
	if {$debug_mode != 0} {Write_Logfile "[clock format [clock sec] -format %H:%M:%S]: $command" "a"}
	if {$debug_mode != 0} {Write_Logfile "[clock format [clock sec] -format %H:%M:%S]: After Command" "a"}
	
	#Prüfen, ob bisher alles ok
	if {$result_string == "OK"} {
		#Übergebene Anzahl Versuche durchführen bis maximal definierte Versuchsanzahl erreicht oder letzter Versuch erfolgreich war
		for {set tries 0} {$tries < $maxtries && $try_success == "FALSE" } {incr tries} {
		
			#Result je Versuch initialisieren
			set result_string "OK"

			#Input-HexString per socat senden und empfangen
			if {$debug_mode != 0} {Write_Logfile "[clock format [clock sec] -format %H:%M:%S]: Before socat" "a"}
			Write_Hexfile $hexin
			catch {exec /etc/config/addons/automower/socat open:/etc/config/addons/automower/automower.hex,ignoreeof TCP:$matchport,readbytes=5,connect-timeout=[expr $maxwait_connect / 1000.0]} msg
			if {$debug_mode != 0} {Write_Logfile "[clock format [clock sec] -format %H:%M:%S]: After socat: $msg" "a"}
			
			#Output-Hexstring lesen
			set hexout [Read_Hexfile]
			
			#Prüfen, ob socat grundsätzlich erfolgreich war
            # Check whether socat was basically successful
			if {$debug_mode != 0} {Write_Logfile "[clock format [clock sec] -format %H:%M:%S]: Before Check (IN=$hexin / OUT=$hexout)" "a"}
			if {$msg != "" || [string length $hexout] != 10} {
				set result_string "#[clock format [clock sec] -format %H:%M:%S]: Socat-Error /$command"
			} else {
	
				#Ermitteln, ob es sich um einen Read oder Write Befehl handelt
                #Determine whether it is a read or write command
				if {([string range $hexin 2 2] == "8" || [string range $hexin 2 2] == "9" ||[string range $hexin 2 2] == "A" ||[string range $hexin 2 2] == "B" ||[string range $hexin 2 2] == "C" ||[string range $hexin 2 2] == "D" ||[string range $hexin 2 2] == "E" ||[string range $hexin 2 2] == "F")} {
					#Write: Prüfen, ob Byte 1-5 (Byte 4 und 5 vertauscht) der Rückgabe vom Automower mit den Input-Bytes übereinstimmen
                    #Write: Check whether byte 1-5 (bytes 4 and 5 interchanged) of the return from the automower match the input bytes
					if {([string range $hexout 0 5] == [string range $hexin 0 5]) && ([string range $hexout 8 9] == [string range $hexin 6 7]) && ([string range $hexout 6 7] == [string range $hexin 8 9])} {
						#Byte 4 und 4 tauschen und als Dezimalwert zurückgeben
                        #Byte 4 and 4 and return as a decimal value
						set final_result [expr 0x[concat [string range $hexout 8 9][string range $hexout 6 7]]]
					} else {
						set result_string "#[clock format [clock sec] -format %H:%M:%S]: Write-Error /$command"
						if {$debug_mode != 0} {Write_Logfile "[clock format [clock sec] -format %H:%M:%S]: Write-Error (IN= $hexin / OUT= $hexout)" "a"}
					}
				} else {
					#Read: Prüfen, ob Byte 1-3 der Rückgabe vom Automower mit den Input-Bytes übereinstimmen
					if {[string range $hexout 0 5] == [string range $hexin 0 5]} {
						#Byte 4 und 4 tauschen und als Dezimalwert zurückgeben
						set final_result [expr 0x[concat [string range $hexout 8 9][string range $hexout 6 7]]]
					} else {
						set result_string "#[clock format [clock sec] -format %H:%M:%S]: Read-Error /$command"
						if {$debug_mode != 0} {Write_Logfile "[clock format [clock sec] -format %H:%M:%S]: Read-Error (IN=$hexin / OUT=$hexout)" "a"}
					}	
				}
				if {$debug_mode != 0} {Write_Logfile "[clock format [clock sec] -format %H:%M:%S]: After Returnstring" "a"}
			}	
						
			#Wenn Kommunikation fehlerfrei war, dann Loop beenden, sonst laut festgelegtem Wert bis zum nächsten Versuch warten
			if {$result_string == "OK"} {
				set try_success "TRUE"
			} else {
				#x ms Warten
				after $maxwait_between_tries
			}				
			if {$debug_mode != 0} {Write_Logfile "[clock format [clock sec] -format %H:%M:%S]: After Wait-Between-Tries: $result_string" "a"}
		}
	}
	
	#Prüfen, ob OK oder Fehler und die entsprechenden Rückgabewerte aufbereiten
	if {$result_string == "OK"} {
		set automower_command_status "OK/[clock format [clock sec] -format %H:%M:%S]: $command"
		#Prüfen, ob es sich um eine Statusabfrage oder einen sonstigen Befehl handelt
		if {$command == "R_STATUS"} {
			#Statuscodes in Klartext umwandeln
			switch $final_result {
				"6" {set automower_status "[clock format [clock sec] -format %H:%M:%S]: Linker Radmotor blockiert"}
				"12" {set automower_status "[clock format [clock sec] -format %H:%M:%S]: Kein Schleifensignal"}
				"16" {set automower_status "[clock format [clock sec] -format %H:%M:%S]: Außerhalb"}
				"18" {set automower_status "[clock format [clock sec] -format %H:%M:%S]: Niedrige Batteriespannung"}
				"26" {set automower_status "[clock format [clock sec] -format %H:%M:%S]: Ladestation blockiert"}
				"34" {set automower_status "[clock format [clock sec] -format %H:%M:%S]: Mäher hochgehoben"}
				"52" {set automower_status "[clock format [clock sec] -format %H:%M:%S]: Kein Kontakt zur Ladestation"}
				"54" {set automower_status "[clock format [clock sec] -format %H:%M:%S]: Pin abgelaufen"}
				"1000" {set automower_status "[clock format [clock sec] -format %H:%M:%S]: Aus LS ausfahren"}
				"1002" {set automower_status "[clock format [clock sec] -format %H:%M:%S]: Mähen"}
				"1006" {set automower_status "[clock format [clock sec] -format %H:%M:%S]: Mähwerk starten"}
				"1008" {set automower_status "[clock format [clock sec] -format %H:%M:%S]: Mähwerk gestartet"}
				"1012" {set automower_status "[clock format [clock sec] -format %H:%M:%S]: Signal starte Mähwerk"}
				"1014" {set automower_status "[clock format [clock sec] -format %H:%M:%S]: Laden"}
				"1016" {set automower_status "[clock format [clock sec] -format %H:%M:%S]: in LS wartend"}
				"1024" {set automower_status "[clock format [clock sec] -format %H:%M:%S]: aus LS einfahren"}
				"1036" {set automower_status "[clock format [clock sec] -format %H:%M:%S]: Viereckmodus"}
				"1038" {set automower_status "[clock format [clock sec] -format %H:%M:%S]: Festgefahren"}
				"1040" {set automower_status "[clock format [clock sec] -format %H:%M:%S]: Kollision"}
				"1042" {set automower_status "[clock format [clock sec] -format %H:%M:%S]: Suchen"}
				"1044" {set automower_status "[clock format [clock sec] -format %H:%M:%S]: Stop"}
				"1048" {set automower_status "[clock format [clock sec] -format %H:%M:%S]: Andocken"}
				"1050" {set automower_status "[clock format [clock sec] -format %H:%M:%S]: aus LS ausfahren"}
				"1052" {set automower_status "[clock format [clock sec] -format %H:%M:%S]: Fehler"}
				"1056" {set automower_status "[clock format [clock sec] -format %H:%M:%S]: Wartet (Modus Manuell/Home)"}
				"1058" {set automower_status "[clock format [clock sec] -format %H:%M:%S]: Begrenzung folgen"}
				"1060" {set automower_status "[clock format [clock sec] -format %H:%M:%S]: N-Signal gefunden"}
				"1062" {set automower_status "[clock format [clock sec] -format %H:%M:%S]: Festgefahren"}
				"1064" {set automower_status "[clock format [clock sec] -format %H:%M:%S]: Suchen"}
				"1070" {set automower_status "[clock format [clock sec] -format %H:%M:%S]: Suchschleife folgen"}
				"1072" {set automower_status "[clock format [clock sec] -format %H:%M:%S]: Schleife folgen"}
			}
			#Falls kein bekannter Code ermittelt werden konnte, den Code selbst zurückgeben
			if {$automower_status == ""} {set automower_status "[clock format [clock sec] -format %H:%M:%S]: ?$final_result?"}
			#Automowerstatus und Befehlsstatus an Systemvariablen zurückgeben
			rega_script "var v1 = dom.GetObject('Automower Status L-Status').State('$automower_command_status');"
			rega_script "var v1 = dom.GetObject('Automower Status L-Status-Error').State('0');"
			rega_script "var v1 = dom.GetObject('Automower Status').State('$automower_status');"
			rega_script "var v1 = dom.GetObject('Automower Status-Code').State('$final_result');"
			
			if {$debug_mode != 0} {Write_Logfile "[clock format [clock sec] -format %H:%M:%S]: After RegaScript 1" "a"}
		} else {
			#Prüfen, ob es sich um einen Read-Befehl handelt, falls ja, den entsprechenden Rückgabewert zurückliefern
			if {[string range $command 0 1] == "R_"} {
				#Status und Ergebnis zurückgeben
				set automower_command_status "OK/[clock format [clock sec] -format %H:%M:%S]: $command= $final_result"
			} else {
				#nur Status zurückgeben
				set automower_command_status "OK/[clock format [clock sec] -format %H:%M:%S]: $command"
			}	
			rega_script "var v1 = dom.GetObject('Automower Steuerung L-Status').State('$automower_command_status');"
			rega_script "var v1 = dom.GetObject('Automower Steuerung L-Status-Error').State('0');"
			if {$debug_mode != 0} {Write_Logfile "[clock format [clock sec] -format %H:%M:%S]: After RegaScript 2" "a"}
		}
	} else {
		set automower_command_status $result_string
		#Status an entsprechende Systemvariable zurückgeben
		if {$command == "R_STATUS"} {
			rega_script "var v1 = dom.GetObject('Automower Status L-Status').State('$automower_command_status');"
			rega_script "var v1 = dom.GetObject('Automower Status L-Status-Error').State('1');"
			if {$debug_mode != 0} {Write_Logfile "[clock format [clock sec] -format %H:%M:%S]: After RegaScript 3" "a"}
		} else {
			rega_script "var v1 = dom.GetObject('Automower Steuerung L-Status').State('$automower_command_status');"
			rega_script "var v1 = dom.GetObject('Automower Steuerung L-Status-Error').State('1');"
			if {$debug_mode != 0} {Write_Logfile "[clock format [clock sec] -format %H:%M:%S]: After RegaScript 4" "a"}
		}
	}
	if {$debug_mode != 0} {Write_Logfile "###########[clock format [clock sec] -format %H:%M:%S]: END COMMAND" "a"}
	if {$debug_mode != 0} {Write_Logfile " " "a"}
}	

#
# Main
#

#Anzahl übergebener Argumente auf 7 vorhandene prüfen
if {$argc != 7} {
	puts stderr "#wrong number of arguments"
	exit 2
}

set debug_mode [lindex $argv 0]
set wait_between_status_requests [lindex $argv 1]
set connection_timeout [lindex $argv 2]
set wait_between_retries [lindex $argv 3]
set status_retries [lindex $argv 4]
set command_retries [lindex $argv 5]
set matchport [lindex $argv 6]

set automowercommand ""
set automowerstatus 1
set last_stoptime [clock seconds]

if {$debug_mode == 2} {Write_Logfile "###########[clock format [clock sec] -format %H:%M:%S]: START" "w"}

#Systemvariable "Automower Daemon Modus" automatisch auf "Aktiv" setzen
rega_script "var v1 = dom.GetObject('Automower Daemon Modus').State(true);"
rega_script "var v1 = dom.GetObject('Automower Status').State('');"
rega_script "var v1 = dom.GetObject('Automower Status-Code').State('0');"
rega_script "var v1 = dom.GetObject('Automower Status L-Status').State('');"
rega_script "var v1 = dom.GetObject('Automower Status L-Status-Error').State('0');"
rega_script "var v1 = dom.GetObject('Automower Steuerung').State(0);"
rega_script "var v1 = dom.GetObject('Automower Steuerung L-Status').State('');"
rega_script "var v1 = dom.GetObject('Automower Steuerung L-Status-Error').State('0');"

#Daemon solange laufen lassen, wie Systemvariable "Automower Daemon Modus" = "Aktiv"
array set AutomowerDaemonModus [rega_script "var v1 = dom.GetObject('Automower Daemon Modus').Value().ToString();"]
while {$AutomowerDaemonModus(v1) == "true"} {
	#Nach jeweils [wait_between_status_requests] Minuten den Status des Automower ermitteln
	if {$automowerstatus == 1} {
		#Automowerstatus ermitteln
		Automower_Command $debug_mode "R_STATUS" $connection_timeout $status_retries $wait_between_retries $matchport
	}

	if {$automowercommand != ""} {
		#Automowersteuerbefehl verarbeiten
		Automower_Command $debug_mode $automowercommand $connection_timeout $command_retries $wait_between_retries $matchport

		#Automowersteuerbefehl zurücksetzen
		rega_script "var v1 = dom.GetObject('Automower Steuerung').State(0);"
	}
	
	#Insgesamt [wait_between_status_requests] Minuten bis zur nächsten Statusabfrage warten bzw. im Abstand von 1 Sekunde prüfen, ob ein Steuerbefehl ansteht oder der Daemon beendet werden soll
	set actual_stoptime [clock seconds]
	set automowercommand [Check_Automowercommand]
	array set AutomowerDaemonModus [rega_script "var v1 = dom.GetObject('Automower Daemon Modus').Value().ToString();"]
	while {($actual_stoptime - $last_stoptime) < [expr $wait_between_status_requests * 60.0] && $automowercommand == "" && $AutomowerDaemonModus(v1) == "true"} {
		#1 Sekunde warten
		after 1000
		set actual_stoptime [clock seconds]
		set automowercommand [Check_Automowercommand]
		array set AutomowerDaemonModus [rega_script "var v1 = dom.GetObject('Automower Daemon Modus').Value().ToString();"]
	}
	if {($actual_stoptime - $last_stoptime) >= [expr $wait_between_status_requests * 60.0]} {
		set last_stoptime $actual_stoptime
		set automowerstatus 1
	} else {
		set automowerstatus 0	
	}
}	
#Systemvariablen entsprechend Inaktivität setzen
rega_script "var v1 = dom.GetObject('Automower Status').State('#Deaktiviert#');"
rega_script "var v1 = dom.GetObject('Automower Status-Code').State('0');"
rega_script "var v1 = dom.GetObject('Automower Status L-Status').State('');"
rega_script "var v1 = dom.GetObject('Automower Status L-Status-Error').State('0');"
rega_script "var v1 = dom.GetObject('Automower Steuerung').State(0);"
rega_script "var v1 = dom.GetObject('Automower Steuerung L-Status').State('');"
rega_script "var v1 = dom.GetObject('Automower Steuerung L-Status-Error').State('0');"

if {[file exists /var/run/automower.tcl.pid]} then {
	catch {
		set f [open /var/run/automower.tcl.pid]
		set filepid [read $f]
		close $f
		if {[pid] == $filepid} then {
			file delete /var/run/automower.tcl.pid
		}
	}
}
close $locksock

if {$debug_mode == 2} {Write_Logfile "###########[clock format [clock sec] -format %H:%M:%S]: END" "a"}
