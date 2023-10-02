MODULE_NAME='mPJLink'   (
                            dev vdvObject,
                            dev dvPort
                        )

(***********************************************************)
#include 'NAVFoundation.ModuleBase.axi'
#include 'NAVFoundation.SocketUtils.axi'
#include 'NAVFoundation.ArrayUtils.axi'
#include 'md5.axi'

/*
 _   _                       _          ___     __
| \ | | ___  _ __ __ _  __ _| |_ ___   / \ \   / /
|  \| |/ _ \| '__/ _` |/ _` | __/ _ \ / _ \ \ / /
| |\  | (_) | | | (_| | (_| | ||  __// ___ \ V /
|_| \_|\___/|_|  \__, |\__,_|\__\___/_/   \_\_/
                 |___/

MIT License

Copyright (c) 2023 Norgate AV Services Limited

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
*/

(***********************************************************)
(*          DEVICE NUMBER DEFINITIONS GO BELOW             *)
(***********************************************************)
DEFINE_DEVICE

(***********************************************************)
(*               CONSTANT DEFINITIONS GO BELOW             *)
(***********************************************************)
DEFINE_CONSTANT

constant long TL_DRIVE    = 1
constant long TL_IP_CLIENT_CHECK = 2

constant integer POWER_STATE_ON    = 1
constant integer POWER_STATE_OFF= 2
constant integer POWER_STATE_LAMP_WARMING = 3
constant integer POWER_STATE_LAMP_COOLING = 4

constant integer INPUT_DIGITAL_1    = 1
constant integer INPUT_DIGITAL_2    = 2
constant integer INPUT_DIGITAL_3    = 3
constant integer INPUT_DIGITAL_4    = 4
constant integer INPUT_DIGITAL_5    = 5
constant integer INPUT_DIGITAL_6    = 6
constant integer INPUT_DIGITAL_7    = 7
constant integer INPUT_DIGITAL_8    = 8
constant integer INPUT_DIGITAL_9    = 9

constant char INPUT_COMMANDS[][NAV_MAX_CHARS]    = { '31',
                            '32',
                            '33',
                            '34',
                            '35',
                            '36',
                            '37',
                            '38',
                            '39' }

constant integer GET_POWER    = 1
constant integer GET_INPUT    = 2
constant integer GET_MUTE    = 3
constant integer GET_VOLUME    = 4
constant integer GET_LAMP    = 5

constant integer AUDIO_MUTE_ON    = 1
constant integer AUDIO_MUTE_OFF    = 2

constant integer MAX_VOLUME = 100
constant integer MIN_VOLUME = 0

constant integer DEFAULT_TCP_PORT    = 4352

constant char HEADER[][2]    = { '%1', '%2' }

(***********************************************************)
(*              DATA TYPE DEFINITIONS GO BELOW             *)
(***********************************************************)
DEFINE_TYPE

(***********************************************************)
(*               VARIABLE DEFINITIONS GO BELOW             *)
(***********************************************************)
DEFINE_VARIABLE
volatile _NAVDisplay uDisplay

volatile long ltIPClientCheck[] = { 3000 }

volatile integer iLoop
volatile integer iPollSequence = GET_POWER

volatile integer iRequiredPower
volatile integer iRequiredInput
volatile integer iRequiredAudioMute

volatile long ltDrive[] = { 200 }

volatile integer iSemaphore
volatile char cRxBuffer[NAV_MAX_BUFFER]

volatile integer iPowerBusy

volatile integer iCommandBusy
volatile integer iCommandLockOut

volatile _NAVSocketConnection uIPConnection

volatile integer iInputInitialized
volatile integer iAudioMuteInitialized

volatile integer iSecureCommandRequired
volatile integer iConnectionStarted
volatile char cMD5RandomNumber[255]
volatile char cMD5StringToEncode[255]

volatile integer iLampHours[2]

volatile char cPassword[NAV_MAX_CHARS] = 'JBMIAProjectorLink'

(***********************************************************)
(*               LATCHING DEFINITIONS GO BELOW             *)
(***********************************************************)
DEFINE_LATCHING

(***********************************************************)
(*       MUTUALLY EXCLUSIVE DEFINITIONS GO BELOW           *)
(***********************************************************)
DEFINE_MUTUALLY_EXCLUSIVE

(***********************************************************)
(*        SUBROUTINE/FUNCTION DEFINITIONS GO BELOW         *)
(***********************************************************)
(* EXAMPLE: DEFINE_FUNCTION <RETURN_TYPE> <NAME> (<PARAMETERS>) *)
(* EXAMPLE: DEFINE_CALL '<NAME>' (<PARAMETERS>) *)
define_function Send(char cPayload[]) {
    NAVLog(NAVFormatStandardLogMessage(NAV_STANDARD_LOG_MESSAGE_TYPE_STRING_TO, dvPort, cPayload))
    send_string dvPort, "cPayload"
}

define_function Build(char cHeader[], char cParam[]) {
    char cPayload[NAV_MAX_BUFFER]
    cPayload = "cHeader, cParam, NAV_CR"

    if (iSecureCommandRequired) {
    cPayload = "Encrypt(cMD5StringToEncode), cPayload"
    }

    Send(cPayload)
}

define_function SendQuery(integer iParam) {
    switch (iParam) {
    case GET_POWER: Build(HEADER[1], 'POWR ?')
    case GET_INPUT: Build(HEADER[1], 'INPT ?')
    case GET_MUTE: Build(HEADER[1], 'AVMT ?')
    case GET_VOLUME: Build(HEADER[1], '')
    case GET_LAMP: Build(HEADER[1], 'LAMP ?')
    }
}

define_function TimeOut() {
    cancel_wait 'CommsTimeOut'
    wait 300 'CommsTimeOut' {
    [vdvObject, DEVICE_COMMUNICATING] = false
    NAVClientSocketClose(dvPort.PORT)
    }
}

define_function SetPower(integer iParam) {
    switch (iParam) {
    case POWER_STATE_ON: { Build(HEADER[1], 'POWR 1') }
    case POWER_STATE_OFF: { Build(HEADER[1], 'POWR 0') }
    }
}

define_function SetInput(integer iParam) { Build(HEADER[1], "'INPT ', INPUT_COMMANDS[iParam]") }

define_function RampVolume(integer iParam) {
    switch (iParam) {
    case VOL_UP: {
        Build(HEADER[2], 'SVOL 1')
    }
    case VOL_DN: {
        Build(HEADER[2], 'SVOL 0')
    }
    }
}

define_function SetAudioMute(integer iParam) {
    switch (iParam) {
    case AUDIO_MUTE_ON: { Build(HEADER[1], 'AVMT 21') }
    case AUDIO_MUTE_OFF: { Build(HEADER[1], 'AVMT 20') }
    }
}

define_function Process() {
    stack_var char cTemp[NAV_MAX_BUFFER]
    iSemaphore = true
    NAVLog("'Processing String From ', NAVStringSurroundWith(NAVDeviceToString(dvPort), '[', ']'), '-[', cRxBuffer, ']'")
    while (length_array(cRxBuffer) && NAVContains(cRxBuffer, "NAV_CR")) {
    cTemp = remove_string(cRxBuffer, "NAV_CR", 1)

    if (length_array(cTemp)) {
        NAVLog(NAVFormatStandardLogMessage(NAV_STANDARD_LOG_MESSAGE_TYPE_PARSING_STRING_FROM, dvPort, cTemp))
        cTemp = NAVStripCharsFromRight(cTemp, 1)    //Remove delimiter
        select {
        active (NAVStartsWith(cTemp, 'PJLINK')): {
            //Connection Started
            cTemp = NAVStripCharsFromLeft(cTemp, 7);
            iSecureCommandRequired = atoi(remove_string(cTemp, ' ', 1));
            if (iSecureCommandRequired) {
            cMD5RandomNumber = cTemp;
            cMD5StringToEncode = "cMD5RandomNumber, cPassword"
            }

            iConnectionStarted = 1;
            iLoop = 0;
            Drive();
        }
        active (1): {
            stack_var char cAtt[NAV_MAX_CHARS]
            cTemp = NAVStripCharsFromLeft(cTemp, 2)    //Remove header
            cAtt = NAVStripCharsFromRight(remove_string(cTemp, '=', 1), 1);
            switch (cAtt) {
            case 'POWR': {
                if (!NAVContains(cTemp, 'OK')) {
                switch (atoi(cTemp)) {
                    case 0: { uDisplay.PowerState.Actual = POWER_STATE_OFF; }
                    case 1: {
                    uDisplay.PowerState.Actual = POWER_STATE_ON;
                    select {
                        active (!iInputInitialized): {
                        iPollSequence = GET_INPUT;
                        }
                        /*
                        case(!iVideoMuteInitialized): {
                        iPollSequence = GET_MUTE;
                        }
                        */
                        active (!iAudioMuteInitialized): {
                        iPollSequence = GET_MUTE;
                        }
                        active (1): {
                        iPollSequence = GET_LAMP;
                        }
                    }
                    }
                    case 2: {    //Cooling
                    uDisplay.PowerState.Actual = POWER_STATE_LAMP_COOLING
                    iPollSequence = GET_LAMP;
                    }
                    case 3: {    //Warming
                    uDisplay.PowerState.Actual = POWER_STATE_LAMP_WARMING
                    iPollSequence = GET_LAMP;
                    }
                }
                }
            }
            case 'INPT': {
                if (!NAVContains(cTemp, 'OK')) {
                uDisplay.Input.Actual = NAVFindInArraySTRING(INPUT_COMMANDS, cTemp)
                iInputInitialized = 1;
                iPollSequence = GET_POWER;
                }
            }
            case 'AVMT': {
                if (!NAVContains(cTemp, 'OK')) {
                switch (cTemp) {
                    case '11': {  }
                    case '21': { uDisplay.Volume.Mute.Actual = AUDIO_MUTE_ON; }
                    case '31': { uDisplay.Volume.Mute.Actual = AUDIO_MUTE_ON; }
                    case '30': { uDisplay.Volume.Mute.Actual = AUDIO_MUTE_OFF; }
                }

                //iVideoMuteInitialized = 1;
                iAudioMuteInitialized = 1;
                iPollSequence = GET_POWER;
                }
            }
            case 'LAMP': {
                stack_var integer iTemp
                if (NAVContains(cTemp, ' ')) {
                iTemp = atoi(NAVStripCharsFromRight(remove_string(cTemp, ' ', 1), 1));
                if (iLampHours[1] <> iTemp) {
                    iLampHours[1] = iTemp;
                    send_string vdvObject,"'LAMPTIME-',itoa(iLampHours[1])"
                }

                remove_string(cTemp, ' ', 1);    //Ignore Lamp Power Status
                iTemp = atoi(NAVStripCharsFromRight(remove_string(cTemp, ' ', 1), 1));
                if (iLampHours[2] <> iTemp) {
                    iLampHours[2] = iTemp;
                    send_string vdvObject,"'LAMPTIME-',itoa(iLampHours[1])"
                }
                }else {
                iTemp = atoi(cTemp);
                if (iLampHours[1] <> iTemp) {
                    iLampHours[1] = iTemp;
                    send_string vdvObject,"'LAMPTIME-',itoa(iLampHours[1])"
                }
                }

                iPollSequence = GET_POWER;
            }
            }
        }
        }
    }
    }

    iSemaphore = false
}

define_function Drive() {
    if (!iConnectionStarted) {
    return;
    }

    if (iSecureCommandRequired && !length_array(cMD5StringToEncode)) {
    return;
    }

    if (!uIPConnection.IsConnected) {
    return;
    }

    iLoop++
    switch (iLoop) {
    case 5:
    case 10: {
        SendQuery(iPollSequence); return
    }
    case 15: {
        iLoop = 0; return
    }
    default: {
        if (iCommandLockOut) { return }
        if (iRequiredPower && (iRequiredPower == uDisplay.PowerState.Actual)) { iRequiredPower = 0; return }
        if (iRequiredInput && (iRequiredInput == uDisplay.Input.Actual)) { iRequiredInput = 0; return }
        if (iRequiredAudioMute && (iRequiredAudioMute == uDisplay.Volume.Mute.Actual)) { iRequiredAudioMute = 0; return }

        if (iRequiredPower && (iRequiredPower <> uDisplay.PowerState.Actual)) {
        iCommandBusy = true
        SetPower(iRequiredPower)
        iCommandLockOut = true
        wait 80 iCommandLockOut = false
        iPollSequence = GET_POWER
        return
        }

        if (iRequiredInput && (uDisplay.PowerState.Actual == POWER_STATE_ON) && (iRequiredInput <> uDisplay.Input.Actual)) {
        iCommandBusy = true
        SetInput(iRequiredInput)
        iCommandLockOut = true
        wait 10 iCommandLockOut = false
        iPollSequence = GET_INPUT
        return
        }

        if (iRequiredAudioMute && (uDisplay.PowerState.Actual == POWER_STATE_ON) && (iRequiredAudioMute <> uDisplay.Volume.Mute.Actual)) {
        iCommandBusy = true
        SetAudioMute(iRequiredAudioMute);
        iCommandLockOut = true
        wait 10 iCommandLockOut = false
        iPollSequence = GET_MUTE;
        return
        }

        if ([vdvObject, VOL_UP]) { RampVolume(VOL_UP) }
        if ([vdvObject, VOL_DN]) { RampVolume(VOL_DN) }
    }
    }
}

define_function MaintainIPConnection() {
    if (!uIPConnection.IsConnected) {
    NAVClientSocketOpen(dvPort.port, uIPConnection.Address, uIPConnection.Port, IP_TCP)
    }
}

(***********************************************************)
(*                STARTUP CODE GOES BELOW                  *)
(***********************************************************)
DEFINE_START {
    create_buffer dvPort,cRxBuffer
    uIPConnection.Port = DEFAULT_TCP_PORT

}
(***********************************************************)
(*                THE EVENTS GO BELOW                      *)
(***********************************************************)
DEFINE_EVENT
data_event[dvPort] {
    online: {
    uIPConnection.IsConnected = true
    NAVLog("'PJLINK_ONLINE<', NAVStringSurroundWith(NAVDeviceToString(data.device), '[', ']'), '>'")

    if (!timeline_active(TL_DRIVE)) {
        NAVTimelineStart(TL_DRIVE, ltDrive, TIMELINE_ABSOLUTE, TIMELINE_REPEAT)
    }
    }
    string: {
    [vdvObject, DEVICE_COMMUNICATING] = true
    [vdvObject, DATA_INITIALIZED] = true
    TimeOut()
    NAVLog(NAVFormatStandardLogMessage(NAV_STANDARD_LOG_MESSAGE_TYPE_STRING_FROM, data.device, data.text))
    if (!iSemaphore) { Process() }
    }
    offline: {
    if (data.device.number == 0) {
        uIPConnection.IsConnected = false
        NAVClientSocketClose(data.device.port)
        iConnectionStarted = false
        NAVLog("'PJLINK_OFFLINE<', NAVStringSurroundWith(NAVDeviceToString(data.device), '[', ']'), '>'")
    }
    }
    onerror: {
    if (data.device.number == 0) {
        uIPConnection.IsConnected = false
        //NAVClientSocketClose(data.device.port)
        NAVLog("'PJLINK_ONERROR<', NAVStringSurroundWith(NAVDeviceToString(data.device), '[', ']'), '>'")
    }
    }
}

data_event[vdvObject] {
    command: {
    stack_var char cCmdHeader[NAV_MAX_CHARS]
    stack_var char cCmdParam[3][NAV_MAX_CHARS]
    NAVLog(NAVFormatStandardLogMessage(NAV_STANDARD_LOG_MESSAGE_TYPE_COMMAND_FROM, data.device, data.text))
    cCmdHeader = DuetParseCmdHeader(data.text)
    cCmdParam[1] = DuetParseCmdParam(data.text)
    cCmdParam[2] = DuetParseCmdParam(data.text)
    cCmdParam[3] = DuetParseCmdParam(data.text)
    switch (cCmdHeader) {
        case 'PROPERTY': {
        switch (cCmdParam[1]) {
            case 'IP_ADDRESS': {
            uIPConnection.Address = cCmdParam[2]
            NAVTimelineStart(TL_IP_CLIENT_CHECK, ltIPClientCheck, TIMELINE_ABSOLUTE, TIMELINE_REPEAT)
            }
            case 'PASSWORD': {
            cPassword = cCmdParam[2]
            if (length_array(cMD5RandomNumber)) {
                cMD5StringToEncode = "cMD5RandomNumber, cPassword"
            }
            }
        }
        }
        //case 'PASSTHRU': { Build(cCmdParam[1]) }
        case 'POWER': {
        switch (cCmdParam[1]) {
            case 'ON': { iRequiredPower = POWER_STATE_ON; Drive() }
            case 'OFF': { iRequiredPower = POWER_STATE_OFF; iRequiredInput = 0; Drive() }
        }
        }
        case 'INPUT': {
        switch (cCmdParam[1]) {
            case 'DIGITAL': {
            iRequiredPower = POWER_STATE_ON
            iRequiredInput = atoi(cCmdParam[2])
            Drive()
            }
        }
        }
    }
    }
}

channel_event[vdvObject,0] {
    on: {
    switch (channel.channel) {
        case POWER: {
        if (iRequiredPower) {
            switch (iRequiredPower) {
            case POWER_STATE_ON: { iRequiredPower = POWER_STATE_OFF; iRequiredInput = 0; Drive() }
            case POWER_STATE_OFF: { iRequiredPower = POWER_STATE_ON; Drive() }
            }
        }else {
            switch (uDisplay.PowerState.Actual) {
            case POWER_STATE_ON: { iRequiredPower = POWER_STATE_OFF; iRequiredInput = 0; Drive() }
            case POWER_STATE_OFF: { iRequiredPower = POWER_STATE_ON; Drive() }
            }
        }
        }
        case PWR_ON: { iRequiredPower = POWER_STATE_ON; Drive() }
        case PWR_OFF: { iRequiredPower = POWER_STATE_OFF; iRequiredInput = 0; Drive() }
        //case PIC_MUTE: { SetShutter(![vdvControl,PIC_MUTE_FB]) }
        case VOL_MUTE: {
        if (uDisplay.PowerState.Actual == POWER_STATE_ON) {
            if (iRequiredAudioMute) {
            switch (iRequiredAudioMute) {
                case AUDIO_MUTE_ON: { iRequiredAudioMute = AUDIO_MUTE_OFF; Drive() }
                case AUDIO_MUTE_OFF: { iRequiredAudioMute = AUDIO_MUTE_ON; Drive() }
            }
            }else {
            switch (uDisplay.Volume.Mute.Actual) {
                case AUDIO_MUTE_ON: { iRequiredAudioMute = AUDIO_MUTE_OFF; Drive() }
                case AUDIO_MUTE_OFF: { iRequiredAudioMute = AUDIO_MUTE_ON; Drive() }
            }
            }
        }
        }
    }
    }
}

timeline_event[TL_DRIVE] { Drive() }

define_event timeline_event[TL_IP_CLIENT_CHECK] { MaintainIPConnection() }

timeline_event[TL_NAV_FEEDBACK] {
    [vdvObject, VOL_MUTE_FB] = (uDisplay.Volume.Mute.Actual == AUDIO_MUTE_ON)
    [vdvObject, POWER_FB] = (uDisplay.PowerState.Actual == POWER_STATE_ON)
    [vdvObject, LAMP_WARMING_FB]    = (uDisplay.PowerState.Actual == POWER_STATE_LAMP_WARMING)
    [vdvObject, LAMP_COOLING_FB]    = (uDisplay.PowerState.Actual == POWER_STATE_LAMP_COOLING)
}

(***********************************************************)
(*                     END OF PROGRAM                      *)
(*        DO NOT PUT ANY CODE BELOW THIS COMMENT           *)
(***********************************************************)

