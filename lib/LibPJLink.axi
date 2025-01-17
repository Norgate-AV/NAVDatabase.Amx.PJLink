PROGRAM_NAME='LibPJLink'

(***********************************************************)
#include 'NAVFoundation.Core.axi'

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


#IF_NOT_DEFINED __LIB_PJLINK__
#DEFINE __LIB_PJLINK__ 'LibPJLink'


DEFINE_CONSTANT

constant integer IP_PORT    = 4352

constant char HEADER[][2]    = { '%1', '%2' }
constant char DELIMITER = {NAV_CR_CHAR}

constant char COMMAND_POWER[4]       = 'POWR'
constant char COMMAND_INPUT[4]       = 'INPT'
constant char COMMAND_AV_MUTE[4]     = 'AVMT'
constant char COMMAND_LAMP[4]        = 'LAMP'

constant integer INPUT_DIGITAL_1    = 1
constant integer INPUT_DIGITAL_2    = 2
constant integer INPUT_DIGITAL_3    = 3
constant integer INPUT_DIGITAL_4    = 4
constant integer INPUT_DIGITAL_5    = 5
constant integer INPUT_DIGITAL_6    = 6
constant integer INPUT_DIGITAL_7    = 7
constant integer INPUT_DIGITAL_8    = 8
constant integer INPUT_DIGITAL_9    = 9

constant char INPUT_COMMANDS[][NAV_MAX_CHARS]   =   {
                                                        '31',
                                                        '32',
                                                        '33',
                                                        '34',
                                                        '35',
                                                        '36',
                                                        '37',
                                                        '38',
                                                        '39'
                                                    }

constant char INPUT_SNAPI_PARAMS[][NAV_MAX_CHARS]   =   {
                                                            'DIGITAL,1',
                                                            'DIGITAL,2',
                                                            'DIGITAL,3',
                                                            'DIGITAL,4',
                                                            'DIGITAL,5',
                                                            'DIGITAL,6',
                                                            'DIGITAL,7',
                                                            'DIGITAL,8',
                                                            'DIGITAL,9'
                                                        }
constant integer GET_POWER      = 1
constant integer GET_INPUT      = 2
constant integer GET_MUTE       = 3
constant integer GET_VOLUME     = 4
constant integer GET_LAMP       = 5

constant integer AUDIO_MUTE_ON      = 1
constant integer AUDIO_MUTE_OFF     = 2

constant integer MAX_VOLUME = 100
constant integer MIN_VOLUME = 0


define_function char[NAV_MAX_BUFFER] BuildProtocol(char header[], char cmd[], char value[]) {
    char payload[NAV_MAX_BUFFER]

    payload = "header, cmd, ' ', value"

    return payload
}


#END_IF // __LIB_PJLINK__
