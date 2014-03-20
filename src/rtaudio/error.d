/*
    Copyright (c) 2001-2013 Gary P. Scavone

    Permission is hereby granted, free of charge, to any person
    obtaining a copy of this software and associated documentation files
    (the "Software"), to deal in the Software without restriction,
    including without limitation the rights to use, copy, modify, merge,
    publish, distribute, sublicense, and/or sell copies of the Software,
    and to permit persons to whom the Software is furnished to do so,
    subject to the following conditions:

    The above copyright notice and this permission notice shall be
    included in all copies or substantial portions of the Software.

    Any person wishing to distribute modifications to the Software is
    asked to send the modifications to the original developer so that
    they can be incorporated into the canonical version.  This is,
    however, not a binding provision of this license.

    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
    EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
    MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
    IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR
    ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF
    CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
    WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
*/
module rtaudio.error;

/// Possible RtError types.
enum RtErrorType
{
    WARNING,           /** A non-critical error. */
    DEBUG_WARNING,     /** A non-critical error which might be useful for debugging. */
    UNSPECIFIED,       /** The default, unspecified error type. */
    NO_DEVICES_FOUND,  /** No devices found on system. */
    INVALID_DEVICE,    /** An invalid device ID was specified. */
    MEMORY_ERROR,      /** An error occured during memory allocation. */
    INVALID_PARAMETER, /** An invalid parameter was specified to a function. */
    INVALID_USE,       /** The function was called incorrectly. */
    DRIVER_ERROR,      /** A system driver error occured. */
    SYSTEM_ERROR,      /** A system error occured. */
    THREAD_ERROR       /** A thread error occured. */
}

/**
    Exception handling class for RtAudio.

    The RtError class is quite simple but it does allow errors to be
    "caught" by RtError.Type. See the RtAudio and RtMidi
    documentation to know which methods can throw an RtError.
*/
class RtError : Exception
{
    this(string message, RtErrorType type = RtErrorType.UNSPECIFIED, string file = __FILE__, size_t line = __LINE__)
    {
        super(message, file, line);
        this.type = type;
    }

    ///
    const(RtErrorType) type;
}
