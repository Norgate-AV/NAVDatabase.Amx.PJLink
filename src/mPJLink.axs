MODULE_NAME='mPJLink'   (
                            dev vdvObject,
                            dev dvPort
                        )

(***********************************************************)
#DEFINE USING_NAV_MODULE_BASE_CALLBACKS
#DEFINE USING_NAV_MODULE_BASE_PROPERTY_EVENT_CALLBACK
#DEFINE USING_NAV_MODULE_BASE_PASSTHRU_EVENT_CALLBACK
#DEFINE USING_NAV_STRING_GATHER_CALLBACK
#DEFINE USING_NAV_LOGIC_ENGINE_EVENT_CALLBACK
#include 'NAVFoundation.LogicEngine.axi'
#include 'NAVFoundation.ModuleBase.axi'
#include 'NAVFoundation.SocketUtils.axi'
#include 'NAVFoundation.StringUtils.axi'
#include 'NAVFoundation.Cryptography.Md5.axi'
#include 'LibPJLink.axi'

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

constant long TL_SOCKET_CHECK   = 1

constant long TL_SOCKET_CHECK_INTERVAL[] = { 3000 }


(***********************************************************)
(*              DATA TYPE DEFINITIONS GO BELOW             *)
(***********************************************************)
DEFINE_TYPE

(***********************************************************)
(*               VARIABLE DEFINITIONS GO BELOW             *)
(***********************************************************)
DEFINE_VARIABLE

volatile _NAVProjector object

volatile integer pollSequence = GET_POWER

volatile integer secureCommandRequired
volatile integer connectionStarted

volatile char md5Seed[255]

volatile _NAVCredential credential = { '', 'JBMIAProjectorLink' }


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

define_function SendString(char payload[]) {
    payload = "payload, NAV_CR"

    if (secureCommandRequired) {
        payload = "NAVMd5GetHash(GetMd5Message(credential, md5Seed)), payload"
    }

    NAVErrorLog(NAV_LOG_LEVEL_DEBUG,
                NAVFormatStandardLogMessage(NAV_STANDARD_LOG_MESSAGE_TYPE_STRING_TO,
                                            dvPort,
                                            payload))

    send_string dvPort, "payload"
}


define_function SendQuery(integer query) {
    switch (query) {
        case GET_POWER:     { SendString(BuildProtocol(HEADER[1], COMMAND_POWER, '?')) }
        case GET_INPUT:     { SendString(BuildProtocol(HEADER[1], COMMAND_INPUT, '?')) }
        case GET_MUTE:      { SendString(BuildProtocol(HEADER[1], COMMAND_AV_MUTE, '?')) }
        case GET_LAMP:      { SendString(BuildProtocol(HEADER[1], COMMAND_LAMP, '?')) }
        default:            { SendQuery(GET_POWER) }
    }
}


define_function CommunicationTimeOut(integer timeout) {
    cancel_wait 'TimeOut'

    module.Device.IsCommunicating = true

    wait (timeout * 10) 'TimeOut' {
        module.Device.IsCommunicating = false
    }
}


define_function Reset() {
    module.Device.SocketConnection.IsConnected = false
    module.Device.IsCommunicating = false
    module.Device.IsInitialized = false

    connectionStarted = false

    NAVLogicEngineStop()
}


define_function SetPower(integer state) {
    switch (state) {
        case NAV_POWER_STATE_ON:    { SendString(BuildProtocol(HEADER[1], COMMAND_POWER, '1')) }
        case NAV_POWER_STATE_OFF:   { SendString(BuildProtocol(HEADER[1], COMMAND_POWER, '0')) }
    }
}


define_function SetInput(integer input) {
    SendString(BuildProtocol(HEADER[1], COMMAND_INPUT, INPUT_COMMANDS[input]))
}


// define_function RampVolume(integer direction) {
//     switch (direction) {
//         case VOL_UP: {
//             SendString(BuildProtocol(HEADER[2], 'SVOL', '1'))
//         }
//         case VOL_DN: {
//             SendString(BuildProtocol(HEADER[2], 'SVOL', '0'))
//         }
//     }
// }


define_function SetVideoMute(integer state) {
    switch (state) {
        case NAV_MUTE_STATE_ON:     { SendString(BuildProtocol(HEADER[1], COMMAND_AV_MUTE, '21')) }
        case NAV_MUTE_STATE_OFF:    { SendString(BuildProtocol(HEADER[1], COMMAND_AV_MUTE, '20')) }
    }
}


#IF_DEFINED USING_NAV_STRING_GATHER_CALLBACK
define_function NAVStringGatherCallback(_NAVStringGatherResult args) {
    stack_var char data[NAV_MAX_BUFFER]
    stack_var char delimiter[NAV_MAX_CHARS]

    data = args.Data
    delimiter = args.Delimiter

    NAVErrorLog(NAV_LOG_LEVEL_DEBUG,
                NAVFormatStandardLogMessage(NAV_STANDARD_LOG_MESSAGE_TYPE_PARSING_STRING_FROM,
                                            dvPort,
                                            data))

    data = NAVStripRight(data, length_array(delimiter))

    select {
        active (NAVStartsWith(data, 'PJLINK')): {
            data = NAVStripLeft(data, 7);

            secureCommandRequired = atoi(remove_string(data, ' ', 1));

            if (secureCommandRequired) {
                md5Seed = data;
            }

            connectionStarted = true;
        }
        active (true): {
            stack_var char cmd[NAV_MAX_CHARS]

            data = NAVStripLeft(data, 2)

            cmd = NAVStripRight(remove_string(data, '=', 1), 1)

            if (NAVContains(data, 'OK')) {
                // Ignore command acknowledgements
                return
            }

            switch (cmd) {
                case COMMAND_POWER: {
                    switch (data) {
                        case '0': {
                            object.Display.PowerState.Actual = NAV_POWER_STATE_OFF
                        }
                        case '1': {
                            object.Display.PowerState.Actual = NAV_POWER_STATE_ON

                            select {
                                active (!object.Display.Input.Initialized): {
                                    pollSequence = GET_INPUT
                                }
                                active (!object.Display.VideoMute.Initialized): {
                                    pollSequence = GET_MUTE
                                }
                                active (true): {
                                    pollSequence = GET_LAMP
                                }
                            }
                        }
                        case '2': {
                            object.Display.PowerState.Actual = NAV_POWER_STATE_LAMP_COOLING
                            pollSequence = GET_LAMP
                        }
                        case '3': {
                            object.Display.PowerState.Actual = NAV_POWER_STATE_LAMP_WARMING
                            pollSequence = GET_LAMP
                        }
                    }
                }
                case COMMAND_INPUT: {
                    stack_var integer input

                    input = NAVFindInArrayString(INPUT_COMMANDS, data)

                    if (input) {
                        object.Display.Input.Actual = input
                        object.Display.Input.Initialized = true
                    }

                    pollSequence = GET_POWER
                }
                case COMMAND_AV_MUTE: {
                    switch (data) {
                        case '11': {  }
                        case '21': { object.Display.VideoMute.Actual = NAV_MUTE_STATE_ON }
                        case '31': { object.Display.VideoMute.Actual = NAV_MUTE_STATE_ON }
                        case '30': { object.Display.VideoMute.Actual = NAV_MUTE_STATE_OFF }
                    }

                    object.Display.VideoMute.Initialized = true
                    pollSequence = GET_POWER
                }
                case COMMAND_LAMP: {
                    stack_var integer hours

                    if (NAVContains(data, ' ')) {
                        hours = atoi(NAVStripRight(remove_string(data, ' ', 1), 1))

                        if (object.LampHours[1].Actual != hours) {
                            object.LampHours[1].Actual = hours
                            send_string vdvObject, "'LAMPTIME-', itoa(object.LampHours[1].Actual)"
                        }

                        remove_string(data, ' ', 1)
                        hours = atoi(NAVStripRight(remove_string(data, ' ', 1), 1))

                        if (object.LampHours[2].Actual != hours) {
                            object.LampHours[2].Actual = hours
                            send_string vdvObject, "'LAMPTIME-', itoa(object.LampHours[2].Actual)"
                        }
                    }
                    else {
                        hours = atoi(data)

                        if (object.LampHours[1].Actual != hours) {
                            object.LampHours[1].Actual = hours
                            send_string vdvObject, "'LAMPTIME-', itoa(object.LampHours[1].Actual)"
                        }
                    }

                    pollSequence = GET_POWER
                }
            }
        }
    }
}
#END_IF


#IF_DEFINED USING_NAV_LOGIC_ENGINE_EVENT_CALLBACK
define_function NAVLogicEngineEventCallback(_NAVLogicEngineEvent args) {
    if (!connectionStarted) {
        return;
    }

    if (secureCommandRequired && !length_array(md5Seed)) {
        return;
    }

    if (!module.Device.SocketConnection.IsConnected) {
        return;
    }

    switch (args.Name) {
        case NAV_LOGIC_ENGINE_EVENT_QUERY: {
            SendQuery(pollSequence)
            return
        }
        case NAV_LOGIC_ENGINE_EVENT_ACTION: {
            if (module.CommandBusy) {
                return
            }

            if (object.Display.PowerState.Required && (object.Display.PowerState.Required == object.Display.PowerState.Actual)) { object.Display.PowerState.Required = 0; return }
            if (object.Display.Input.Required && (object.Display.Input.Required == object.Display.Input.Actual)) { object.Display.Input.Required = 0; return }
            if (object.Display.VideoMute.Required && (object.Display.VideoMute.Required == object.Display.VideoMute.Actual)) { object.Display.VideoMute.Required = 0; return }

            if (object.Display.PowerState.Required && (object.Display.PowerState.Required != object.Display.PowerState.Actual)) {
                SetPower(object.Display.PowerState.Required)
                module.CommandBusy = true
                wait 80 module.CommandBusy = false
                pollSequence = GET_POWER
                return
            }

            if (object.Display.Input.Required && (object.Display.PowerState.Actual == NAV_POWER_STATE_ON) && (object.Display.Input.Required != object.Display.Input.Actual)) {
                SetInput(object.Display.Input.Required)
                module.CommandBusy = true
                wait 10 module.CommandBusy = false
                pollSequence = GET_INPUT
                return
            }

            if (object.Display.VideoMute.Required && (object.Display.PowerState.Actual == NAV_POWER_STATE_ON) && (object.Display.VideoMute.Required != object.Display.VideoMute.Actual)) {
                SetVideoMute(object.Display.VideoMute.Required)
                module.CommandBusy = true
                wait 10 module.CommandBusy = false
                pollSequence = GET_MUTE;
                return
            }
        }
    }
}
#END_IF


define_function MaintainSocketConnection() {
    if (module.Device.SocketConnection.IsConnected) {
        return
    }

    NAVClientSocketOpen(dvPort.PORT,
                        module.Device.SocketConnection.Address,
                        module.Device.SocketConnection.Port,
                        IP_TCP)
}


define_function char[NAV_MAX_BUFFER] GetMd5Message(_NAVCredential credential, char md5Seed[]) {
    return "credential.Username, ':', credential.Password, ':', md5Seed"
}


define_function SocketConnectionReset() {
    NAVTimelineStop(TL_SOCKET_CHECK)

    NAVClientSocketClose(dvPort.PORT)

    NAVTimelineStart(TL_SOCKET_CHECK, TL_SOCKET_CHECK_INTERVAL, TIMELINE_ABSOLUTE, TIMELINE_REPEAT)
}


#IF_DEFINED USING_NAV_MODULE_BASE_PROPERTY_EVENT_CALLBACK
define_function NAVModulePropertyEventCallback(_NAVModulePropertyEvent event) {
    if (event.Device != vdvObject) {
        return
    }

    switch (event.Name) {
        case NAV_MODULE_PROPERTY_EVENT_IP_ADDRESS: {
            module.Device.SocketConnection.Address = NAVTrimString(event.Args[1])
            SocketConnectionReset()
        }
        // case NAV_MODULE_PROPERTY_EVENT_USERNAME: {
        //     credential.Username = NAVTrimString(event.Args[1])
        // }
        case NAV_MODULE_PROPERTY_EVENT_PASSWORD: {
            credential.Password = NAVTrimString(event.Args[1])
        }
    }
}
#END_IF


#IF_DEFINED USING_NAV_MODULE_BASE_PASSTHRU_EVENT_CALLBACK
define_function NAVModulePassthruEventCallback(_NAVModulePassthruEvent event) {
    if (event.Device != vdvObject) {
        return
    }

    SendString(event.Payload)
}
#END_IF


define_function HandleSnapiMessage(_NAVSnapiMessage message, tdata data) {
    switch (message.Header) {
        case 'POWER': {
            switch (message.Parameter[1]) {
                case 'ON': {
                    object.Display.PowerState.Required = NAV_POWER_STATE_ON
                }
                case 'OFF': {
                    object.Display.PowerState.Required = NAV_POWER_STATE_OFF
                    object.Display.Input.Required = 0
                }
            }
        }
        case 'MUTE': {
            if (object.Display.PowerState.Actual != NAV_POWER_STATE_ON) {
                return
            }

            switch (message.Parameter[1]) {
                case 'ON': {
                    object.Display.VideoMute.Required = NAV_MUTE_STATE_ON
                }
                case 'OFF': {
                    object.Display.VideoMute.Required = NAV_MUTE_STATE_OFF
                }
            }
        }
        case 'INPUT': {
            stack_var integer input
            stack_var char inputCommand[NAV_MAX_CHARS]

            NAVTrimStringArray(message.Parameter)
            inputCommand = NAVArrayJoinString(message.Parameter, ',')

            input = NAVFindInArrayString(INPUT_SNAPI_PARAMS, inputCommand)

            if (input <= 0) {
                NAVErrorLog(NAV_LOG_LEVEL_WARNING,
                            "'mPJLink => Invalid input: ', inputCommand")

                return
            }

            object.Display.PowerState.Required = NAV_POWER_STATE_ON
            object.Display.Input.Required = input
        }
    }
}


(***********************************************************)
(*                STARTUP CODE GOES BELOW                  *)
(***********************************************************)
DEFINE_START {
    create_buffer dvPort, module.RxBuffer.Data
    module.Device.SocketConnection.Socket = dvPort.PORT
    module.Device.SocketConnection.Port = IP_PORT
}

(***********************************************************)
(*                THE EVENTS GO BELOW                      *)
(***********************************************************)
DEFINE_EVENT

data_event[dvPort] {
    online: {
        if (data.device.number == 0) {
            module.Device.SocketConnection.IsConnected = true
        }

        NAVLogicEngineStart()
    }
    string: {
        CommunicationTimeOut(30)

        NAVErrorLog(NAV_LOG_LEVEL_DEBUG,
                    NAVFormatStandardLogMessage(NAV_STANDARD_LOG_MESSAGE_TYPE_STRING_FROM,
                                                data.device,
                                                data.text))
        select {
            active(true): {
                NAVStringGather(module.RxBuffer, "NAV_CR")
            }
        }
    }
    offline: {
        if (data.device.number == 0) {
            NAVClientSocketClose(data.device.port)
            Reset()
        }
    }
    onerror: {
        if (data.device.number == 0) {
            Reset()
        }

        NAVErrorLog(NAV_LOG_LEVEL_ERROR,
                    "'mPJLink => OnError: ', NAVGetSocketError(type_cast(data.number))")
    }
}


data_event[vdvObject] {
    online: {
        NAVCommand(data.device, "'PROPERTY-RMS_MONITOR_ASSET_PROPERTY,MONITOR_ASSET_DESCRIPTION,Video Projector'")
        NAVCommand(data.device, "'PROPERTY-RMS_MONITOR_ASSET_PROPERTY,MONITOR_ASSET_MANUFACTURER_URL,PJLink'")
        NAVCommand(data.device, "'PROPERTY-RMS_MONITOR_ASSET_PROPERTY,MONITOR_ASSET_MANUFACTURER_NAME,PJLink'")
    }
    command: {
        stack_var _NAVSnapiMessage message

        NAVParseSnapiMessage(data.text, message)

        HandleSnapiMessage(message, data)
    }
}


channel_event[vdvObject, 0] {
    on: {
        switch (channel.channel) {
            case POWER: {
                if (object.Display.PowerState.Required) {
                    switch (object.Display.PowerState.Required) {
                        case NAV_POWER_STATE_ON: {
                            object.Display.PowerState.Required = NAV_POWER_STATE_OFF
                            object.Display.Input.Required = 0
                        }
                        case NAV_POWER_STATE_OFF: {
                            object.Display.PowerState.Required = NAV_POWER_STATE_ON
                        }
                    }
                }
                else {
                    switch (object.Display.PowerState.Actual) {
                        case NAV_POWER_STATE_ON: {
                            object.Display.PowerState.Required = NAV_POWER_STATE_OFF
                            object.Display.Input.Required = 0
                        }
                        case NAV_POWER_STATE_OFF: {
                            object.Display.PowerState.Required = NAV_POWER_STATE_ON
                        }
                    }
                }
            }
            case PWR_ON: {
                object.Display.PowerState.Required = NAV_POWER_STATE_ON
            }
            case PWR_OFF: {
                object.Display.PowerState.Required = NAV_POWER_STATE_OFF
                object.Display.Input.Required = 0
            }
        }
    }
}


timeline_event[TL_SOCKET_CHECK] {
    MaintainSocketConnection()
}


timeline_event[TL_NAV_FEEDBACK] {
    [vdvObject, NAV_IP_CONNECTED]	= (module.Device.SocketConnection.IsConnected)
    [vdvObject, DEVICE_COMMUNICATING] = (module.Device.IsCommunicating)
    [vdvObject, DATA_INITIALIZED] = (module.Device.IsInitialized)

    [vdvObject, LAMP_WARMING_FB]    = (object.Display.PowerState.Actual == NAV_POWER_STATE_LAMP_WARMING)
    [vdvObject, LAMP_COOLING_FB]    = (object.Display.PowerState.Actual == NAV_POWER_STATE_LAMP_COOLING)
    [vdvObject, POWER_FB]           = (object.Display.PowerState.Actual == NAV_POWER_STATE_ON)
    [vdvObject, PIC_MUTE_FB]        = (object.Display.VideoMute.Actual == NAV_MUTE_STATE_ON)
}


(***********************************************************)
(*                     END OF PROGRAM                      *)
(*        DO NOT PUT ANY CODE BELOW THIS COMMENT           *)
(***********************************************************)
