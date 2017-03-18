#!/usr/bin/python
# -*- coding: utf-8 -*-
# Send / Read data over serial port to the mower

import serial

class automower:
    def __init__(self):
        self.port = '/dev/pts/20'
        self.portSpeed = '9600'
        self.portRtscts=True
        self.portDsrdtr=True
        self.getTimer="\x0F\x4A\x50\x00\x00"
        self.getVolt="\x0F\x2E\xF4\x00\x00"
        self.getFirmwareVersion="\x0F\x33\x90\x00\x00"
        self.getYear="\x0F\x36\xBD\x00\x00"
        self.getMonth="\x0F\x36\xB9\x00\x00"
        self.getDay="\x0F\x36\xB7\x00\x00"
        self.getStatus="\x0F\x01\xF1\x00\x00"
        self.setGoHome="\x0F\x80\x5F\x00\x0D"
        self.setKeyUp="\x0F\x80\x5F\x00\x10"
        self.setKeyYes="\x0F\x80\x5F\x00\x12"

    def sendAutomower(self):
        # Send a command to the mower
        try:
            ser = serial.Serial(self.port, self.portSpeed, rtscts=self.portRtscts, dsrdtr=self.portDsrdtr)
            ser.write(self.setGoHome)
            #output=ser.read(5)
            ser.close()             # close port
        except:
            print("Serial port: %s not found" % (self.port))

mower=automower()
mower.sendAutomower()

