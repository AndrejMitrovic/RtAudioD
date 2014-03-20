/**
    Realtime audio i/o C++ classes.

    RtAudio provides a common API (Application Programming Interface)
    for realtime audio input/output across Linux (native ALSA, Jack,
    and OSS), Macintosh OS X (CoreAudio and Jack), and Windows
    (DirectSound and ASIO) operating systems.

    RtAudio WWW site: http://www.music.mcgill.ca/~gary/rtaudio/

    RtAudio: realtime audio i/o C++ classes
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
module rtaudio.engine;

import core.stdc.string;
import core.sync.mutex;

import core.thread;

import std.conv;
import std.stdio;
import std.traits;
import std.typetuple;

import rtaudio.direct_sound;
import rtaudio.error;

wstring fromWStringz(const wchar* s)
{
    if (s is null) return null;

    wchar* ptr;
    for (ptr = cast(wchar*)s; *ptr; ++ptr) {}

    return to!wstring(s[0..ptr-s]);
}

///
enum RtAudioVersion = "4.0.12";

/// A list of possible underlying sample types.
alias SampleTypes = TypeTuple!(byte, short, S24, int, float, double);

/// A list of possible audio formats.
enum FormatTypes = EnumMembers!RtAudioFormat;

/// Get the underyling sample type of an RtAudioFormat.
alias GetSampleType(RtAudioFormat format)
    = SampleTypes[staticIndexOf!(format, FormatTypes)];

/// Get the RtAudioFormat of an underlying sample type.
enum GetFormatType(Type)
    = FormatTypes[staticIndexOf!(Type, SampleTypes)];

/**
    RtAudio data format type.

    Supports signed integers and floats.  Audio data fed to/from an
    RtAudio stream is assumed to $(B always) be in host byte order.  The
    internal routines will automatically take care of any necessary
    byte-swapping between the host format and the soundcard.  Thus,
    endianness is not a concern for the supported formats.
*/
enum RtAudioFormat : ulong
{
    int8    = 0x1,   /// 8-bit signed integer.
    int16   = 0x2,   /// 16-bit signed integer.
    int24   = 0x4,   /// 24-bit signed integer.
    int32   = 0x8,   /// 32-bit signed integer.
    float32 = 0x10,  /// Normalized between plus/minus 1.0.
    float64 = 0x20,  /// Normalized between plus/minus 1.0.
}

/**
    RtAudio stream option flags.

    The flags can be OR'ed together to allow a client to
    make changes to the default stream behavior.

    By default, RtAudio streams pass and receive audio data from the
    client in an interleaved format.  By passing the
    $(D non_interleaved) flag to the openStream() function, audio
    data will instead be presented in non-interleaved buffers.  In
    this case, each buffer argument in the RtAudioCallback function
    will point to a single array of data, with \c nFrames samples for
    each channel concatenated back-to-back.  For example, the first
    sample of data for the second channel would be located at index \c
    nFrames (assuming the \c buffer pointer was recast to the correct
    data type for the stream).

    Certain audio APIs offer a number of parameters that influence the
    I/O latency of a stream.  By default, RtAudio will attempt to set
    these parameters internally for robust (glitch-free) performance
    (though some APIs, like Windows Direct Sound, make this difficult).
    By passing the $(D minimize_latency) flag to the openStream()
    function, internal stream settings will be influenced in an attempt
    to minimize stream latency, though possibly at the expense of stream
    performance.

    If the $(D hog_device) flag is set, RtAudio will attempt to
    open the input and/or output stream device(s) for exclusive use.
    Note that this is not possible with all supported audio APIs.

    If the $(D schedule_realtime) flag is set, RtAudio will attempt
    to select realtime scheduling (round-robin) for the callback thread.

    If the $(D alsa_use_default) flag is set, RtAudio will attempt to
    open the "default" PCM device when using the ALSA API. Note that this
    will override any specified input or output device id.
*/
enum StreamFlags : uint
{
    non_interleaved   = 0x1,  // Use non-interleaved buffers (default = interleaved).
    minimize_latency  = 0x2,  // Attempt to set stream parameters for lowest possible latency.
    hog_device        = 0x4,  // Attempt grab device and prevent use by others.
    schedule_realtime = 0x8,  // Try to select realtime scheduling for callback thread.
    alsa_use_default  = 0x10, // Use the "default" PCM device (ALSA only).
}

/**
    RtAudio stream status (over- or underflow) flags.

    Notification of a stream over- or underflow is indicated by a
    non-zero stream status argument in the RtAudioCallback function.
    The stream status can be one of the following two options,
    depending on whether the stream is open for output and/or input.
*/
enum RtAudioStreamStatus : uint
{
    no_error         = 0,    /// There was no underflow/overflow.
    input_overflow   = 0x1,  /// Input data was discarded because of an overflow condition at the driver.
    output_underflow = 0x2,  /// The output buffer ran low, likely causing a gap in the output sound.
}

/**
    RtAudio callback function prototype.

    All RtAudio clients must create a function of type RtAudioCallback
    to read and/or write data from/to the audio stream.  When the
    underlying audio system is ready for new input or output data, this
    function will be invoked.

    Params:

    outputBuffer = For output (or duplex) streams, the client
          should write nFrames of audio sample frames into this
          buffer.  This argument should be recast to the datatype
          specified when the stream was opened. For input-only
          streams, this argument will be $(D null).

    inputBuffer = For input (or duplex) streams, this buffer will
          hold \c nFrames of input audio sample frames.  This
          argument should be recast to the datatype specified when the
          stream was opened.  For output-only streams, this argument
          will be $(D null).

    nFrames = The number of sample frames of input or output
          data in the buffers.  The actual buffer size in bytes is
          dependent on the data type and number of channels in use.

    streamTime = The number of seconds that have elapsed since the
          stream was started.

    status = If non-zero, this argument indicates a data overflow
          or underflow condition for the stream.  The particular
          condition can be determined by comparison with the
          RtAudioStreamStatus flags.

    userData = A pointer to optional data provided by the client
          when opening the stream (default = $(D null)).

    Returns:

    To continue normal stream operation, the RtAudioCallback function
    should return a value of zero.  To stop the stream and drain the
    output buffer, the function should return a value of one.  To abort
    the stream immediately, the client should return a value of two.
 */
alias RtAudioCallback = int function(
    void* outputBuffer,
    void* inputBuffer,
    uint nFrames,
    double streamTime,
    RtAudioStreamStatus status,
    void* userData);

/// RtAudio error callback function prototype.

/**
    \param type Type of error.
    \param errorText Error description.
 */
alias RtAudioErrorCallback = void function(RtErrorType type, string errorText);

/// Audio API specifier arguments.
enum Api
{
    UNSPECIFIED,  /** Search for a working compiled API. */
    LINUX_ALSA,   /** The Advanced Linux Sound Architecture API. */
    LINUX_PULSE,  /** The Linux PulseAudio API. */
    LINUX_OSS,    /** The Linux Open Sound System API. */
    UNIX_JACK,    /** The Jack Low-Latency Audio Server API. */
    MACOSX_CORE,  /** Macintosh OS-X Core Audio API. */
    WINDOWS_ASIO, /** The Steinberg Audio Stream I/O API. */
    WINDOWS_DS,   /** The Microsoft Direct Sound API. */
    RTAUDIO_DUMMY /** A compilable but non-functional API. */
}

/// The public device information structure for returning queried values.
struct DeviceInfo
{
    bool probed;                 /** true if the device capabilities were successfully probed. */
    string name;                 /** Character string device identifier. */
    uint outputChannels;         /** Maximum output channels supported by device. */
    uint inputChannels;          /** Maximum input channels supported by device. */
    uint duplexChannels;         /** Maximum simultaneous input/output channels supported by device. */
    bool isDefaultOutput;        /** true if this is the default output device. */
    bool isDefaultInput;         /** true if this is the default input device. */
    uint[] sampleRates;          /** Supported sample rates (queried from list of standard rates). */
    RtAudioFormat nativeFormats; /** Bit mask of supported data formats. */
}

/// The structure for specifying input or ouput stream parameters.
struct StreamParameters
{
    uint deviceId;     /** Device index (0 to getDeviceCount() - 1). */
    uint nChannels;    /** Number of channels. */
    uint firstChannel; /** First channel index on device (default = 0). */
}

/// The structure for specifying stream options.
/**
   The following flags can be OR'ed together to allow a client to
   make changes to the default stream behavior:

   - \e RTAUDIO_NONINTERLEAVED:    Use non-interleaved buffers (default = interleaved).
   - \e RTAUDIO_MINIMIZE_LATENCY:  Attempt to set stream parameters for lowest possible latency.
   - \e RTAUDIO_HOG_DEVICE:        Attempt to grab device for exclusive use.
   - \e RTAUDIO_SCHEDULE_REALTIME: Attempt to select realtime scheduling for the callback thread.
   - \e RTAUDIO_ALSA_USE_DEFAULT:  Use the default PCM device (ALSA only).

   By default, RtAudio streams pass and receive audio data from the
   client in an interleaved format.  By passing the
   RTAUDIO_NONINTERLEAVED flag to the openStream() function, audio
   data will instead be presented in non-interleaved buffers.  In
   this case, each buffer argument in the RtAudioCallback function
   will point to a single array of data, with \c nFrames samples for
   each channel concatenated back-to-back.  For example, the first
   sample of data for the second channel would be located at index \c
   nFrames (assuming the \c buffer pointer was recast to the correct
   data type for the stream).

   Certain audio APIs offer a number of parameters that influence the
   I/O latency of a stream.  By default, RtAudio will attempt to set
   these parameters internally for robust (glitch-free) performance
   (though some APIs, like Windows Direct Sound, make this difficult).
   By passing the RTAUDIO_MINIMIZE_LATENCY flag to the openStream()
   function, internal stream settings will be influenced in an attempt
   to minimize stream latency, though possibly at the expense of stream
   performance.

   If the RTAUDIO_HOG_DEVICE flag is set, RtAudio will attempt to
   open the input and/or output stream device(s) for exclusive use.
   Note that this is not possible with all supported audio APIs.

   If the RTAUDIO_SCHEDULE_REALTIME flag is set, RtAudio will attempt
   to select realtime scheduling (round-robin) for the callback thread.
   The \c priority parameter will only be used if the RTAUDIO_SCHEDULE_REALTIME
   flag is set. It defines the thread's realtime priority.

   If the RTAUDIO_ALSA_USE_DEFAULT flag is set, RtAudio will attempt to
   open the "default" PCM device when using the ALSA API. Note that this
   will override any specified input or output device id.

   The \c numberOfBuffers parameter can be used to control stream
   latency in the Windows DirectSound, Linux OSS, and Linux Alsa APIs
   only.  A value of two is usually the smallest allowed.  Larger
   numbers can potentially result in more robust stream performance,
   though likely at the cost of stream latency.  The value set by the
   user is replaced during execution of the RtAudio.openStream()
   function by the value actually used by the system.

   The \c streamName parameter can be used to set the client name
   when using the Jack API.  By default, the client name is set to
   RtApiJack.  However, if you wish to create multiple instances of
   RtAudio with Jack, each instance must have a unique client name.
*/
struct StreamOptions
{
    StreamFlags flags; /** A bit-mask of stream flags */
    uint numberOfBuffers;     /** Number of stream buffers. */
    string streamName;        /** A stream name (currently used only in Jack). */
    int priority;             /** Scheduling priority of callback thread (only used with flag RTAUDIO_SCHEDULE_REALTIME). */
}

//
// RtAudio class declaration.
//
// RtAudio is a "controller" used to select an available audio i/o
// interface.  It presents a common API for the user to call but all
// functionality is implemented by the class RtApi and its
// subclasses.  RtAudio creates an instance of an RtApi subclass
// based on the user's API choice.  If no choice is made, RtAudio
// attempts to make a "logical" API selection.
//
class RtAudio
{
    /// A static function to determine the current RtAudio version.
    static string getVersion()
    {
        return RtAudioVersion;
    }

    /// A static function to determine the available compiled audio APIs.

    /**
       The values returned in the std.vector can be compared against
       the enumerated list values.  Note that there can be more than one
       API compiled for certain operating systems.
    */
    static void getCompiledApi(ref Api[] apis)
    {
        apis.clear();

        // The order here will control the order of RtAudio's API search in
        // the constructor.
        version (Posix)   apis ~= Api.UNIX_JACK;
        version (Posix)   apis ~= Api.LINUX_ALSA;
        version (Posix)   apis ~= Api.LINUX_PULSE;
        version (Posix)   apis ~= Api.LINUX_OSS;
        // version (Windows) apis ~= Api.WINDOWS_ASIO;  // todo later
        version (Windows) apis ~= Api.WINDOWS_DS;
        version (OSX)     apis ~= Api.MACOSX_CORE;
        apis ~= Api.RTAUDIO_DUMMY;
    }

    /**
       The constructor performs minor initialization tasks.  No exceptions
       can be thrown.

       If no API argument is specified and multiple API support has been
       compiled, the default order of use is JACK, ALSA, OSS (Linux
       systems) and ASIO, DS (Windows systems).
    */
    this(Api reqApi = Api.UNSPECIFIED)
    {
        if (reqApi != Api.UNSPECIFIED)
        {
            // Attempt to open the specified API.
            openRtApi(reqApi);

            if (_rtapi)
                return;

            // No compiled support for specified API value.  Issue a debug
            // warning and continue as if no API was specified.
            stderr.writeln("\nRtAudio: no compiled support for specified API argument!\n");
        }

        // Iterate through the compiled APIs and return as soon as we find
        // one with at least one device or we reach the end of the list.
        Api[] apis;
        getCompiledApi(apis);

        foreach (api; apis)
        {
            openRtApi(api);
            if (_rtapi.getDeviceCount())
                break;
        }

        if (_rtapi)
            return;

        // It should not be possible to get here because the preprocessor
        // definition __RTAUDIO_DUMMY__ is automatically defined if no
        // API-specific definitions are passed to the compiler. But just in
        // case something weird happens, we'll print _out an error message.
        assert(0, "\nRtAudio: no compiled API support found ... critical error!!\n\n");
    }

    /// Returns the audio API specifier for the current instance of RtAudio.
    Api getCurrentApi()
    {
        return _rtapi.getCurrentApi();
    }

    /// A public function that queries for the number of audio devices available.

    /**
       This function performs a system query of available devices each time it
       is called, thus supporting devices connected \e after instantiation. If
       a system error occurs during processing, a warning will be issued.
    */
    uint getDeviceCount()
    {
        return _rtapi.getDeviceCount();
    }

    /// Return an DeviceInfo structure for a specified device number.

    /**

       Any device integer between 0 and getDeviceCount() - 1 is valid.
       If an invalid argument is provided, an RtErrorType (type = INVALID_USE)
       will be thrown.  If a device is busy or otherwise unavailable, the
       structure member "probed" will have a value of "false" and all
       other members are undefined.  If the specified device is the
       current default input or output device, the corresponding
       "isDefault" member will have a value of "true".
    */
    DeviceInfo getDeviceInfo(uint device)
    {
        return _rtapi.getDeviceInfo(device);
    }

    /// A function that returns the index of the default output device.

    /**
       If the underlying audio API does not provide a "default
       device", or if no devices are available, the return value will be
       0.  Note that this is a valid device identifier and it is the
       client's responsibility to verify that a device is available
       before attempting to open a stream.
    */
    uint getDefaultOutputDevice()
    {
        return _rtapi.getDefaultOutputDevice();
    }

    /// A function that returns the index of the default input device.

    /**
       If the underlying audio API does not provide a "default
       device", or if no devices are available, the return value will be
       0.  Note that this is a valid device identifier and it is the
       client's responsibility to verify that a device is available
       before attempting to open a stream.
    */
    uint getDefaultInputDevice()
    {
        return _rtapi.getDefaultInputDevice();
    }

    /// A public function for opening a stream with the specified parameters.

    /**
       An RtErrorType (type = SYSTEM_ERROR) is thrown if a stream cannot be
       opened with the specified parameters or an error occurs during
       processing.  An RtErrorType (type = INVALID_USE) is thrown if any
       invalid device ID or channel number parameters are specified.

       \param outputParameters Specifies output stream parameters to use
             when opening a stream, including a device ID, number of channels,
             and starting channel number.  For input-only streams, this
             argument should be null.  The device ID is an index value between
             0 and getDeviceCount() - 1.
       \param inputParameters Specifies input stream parameters to use
             when opening a stream, including a device ID, number of channels,
             and starting channel number.  For output-only streams, this
             argument should be null.  The device ID is an index value between
             0 and getDeviceCount() - 1.
       \param format An RtAudioFormat specifying the desired sample data format.
       \param sampleRate The desired sample rate (sample frames per second).
       \param *bufferFrames A pointer to a value indicating the desired
             internal buffer size in sample frames.  The actual value
             used by the device is returned via the same pointer.  A
             value of zero can be specified, in which case the lowest
             allowable value is determined.
       \param callback A client-defined function that will be invoked
             when input data is available and/or output data is needed.
       \param userData An optional pointer to data that can be accessed
             from within the callback function.
       \param options An optional pointer to a structure containing various
             global stream options, including a list of OR'ed StreamFlags
             and a suggested number of stream buffers that can be used to
             control stream latency.  More buffers typically result in more
             robust performance, though at a cost of greater latency.  If a
             value of zero is specified, a system-specific median value is
             chosen.  If the RTAUDIO_MINIMIZE_LATENCY flag bit is set, the
             lowest allowable value is used.  The actual value used is
             returned via the structure argument.  The parameter is API dependent.
       \param errorCallback A client-defined function that will be invoked
             when an error has occured.
    */
    void openStream(StreamParameters* outputParameters,
                    StreamParameters* inputParameters,
                    RtAudioFormat format, uint sampleRate,
                    uint* bufferFrames, RtAudioCallback callback,
                    void* userData = null, StreamOptions* options = null, RtAudioErrorCallback errorCallback = null)
    {
        return _rtapi.openStream(outputParameters, inputParameters, format,
                                  sampleRate, bufferFrames, callback,
                                  userData, options, errorCallback);
    }

    /// A function that closes a stream and frees any associated stream memory.

    /**
       If a stream is not open, this function issues a warning and
       returns (no exception is thrown).
    */
    void closeStream()
    {
        return _rtapi.closeStream();
    }

    /// A function that starts a stream.

    /**
       An RtErrorType (type = SYSTEM_ERROR) is thrown if an error occurs
       during processing.  An RtErrorType (type = INVALID_USE) is thrown if a
       stream is not open.  A warning is issued if the stream is already
       running.
    */
    void startStream()
    {
        return _rtapi.startStream();
    }

    /// Stop a stream, allowing any samples remaining in the output queue to be played.

    /**
       An RtErrorType (type = SYSTEM_ERROR) is thrown if an error occurs
       during processing.  An RtErrorType (type = INVALID_USE) is thrown if a
       stream is not open.  A warning is issued if the stream is already
       stopped.
    */
    void stopStream()
    {
        return _rtapi.stopStream();
    }

    /// Stop a stream, discarding any samples remaining in the input/output queue.

    /**
       An RtErrorType (type = SYSTEM_ERROR) is thrown if an error occurs
       during processing.  An RtErrorType (type = INVALID_USE) is thrown if a
       stream is not open.  A warning is issued if the stream is already
       stopped.
    */
    void abortStream()
    {
        return _rtapi.abortStream();
    }

    /// Returns true if a stream is open and false if not.
    bool isStreamOpen() const
    {
        return _rtapi.isStreamOpen();
    }

    /// Returns true if the stream is running and false if it is stopped or not open.
    bool isStreamRunning() const
    {
        return _rtapi.isStreamRunning();
    }

    /// Returns the number of elapsed seconds since the stream was started.

    /**
       If a stream is not open, an RtErrorType (type = INVALID_USE) will be thrown.
    */
    double getStreamTime()
    {
        return _rtapi.getStreamTime();
    }

    /// Returns the internal stream latency in sample frames.

    /**
       The stream latency refers to delay in audio input and/or output
       caused by internal buffering by the audio system and/or hardware.
       For duplex streams, the returned value will represent the sum of
       the input and output latencies.  If a stream is not open, an
       RtErrorType (type = INVALID_USE) will be thrown.  If the API does not
       report latency, the return value will be zero.
    */
    long getStreamLatency()
    {
        return _rtapi.getStreamLatency();
    }

    /// Returns actual sample rate in use by the stream.

    /**
       On some systems, the sample rate used may be slightly different
       than that specified in the stream parameters.  If a stream is not
       open, an RtErrorType (type = INVALID_USE) will be thrown.
    */
    uint getStreamSampleRate()
    {
        return _rtapi.getStreamSampleRate();
    }

    /// Specify whether warning messages should be printed to stderr.
    void showWarnings(bool value = true)
    {
        _rtapi.showWarnings(value);
    }

protected:

    static private RtApi getRtApiInstance(Api api)
    {
        switch (api) with (Api)
        {
            version (Posix)     case UNIX_JACK:     return new RtApiJack();
            version (Posix)     case LINUX_ALSA:    return new RtApiAlsa();
            version (Posix)     case LINUX_PULSE:   return new RtApiPulse();
            version (Posix)     case LINUX_OSS:     return new RtApiOss();
            // version (Windows)   case WINDOWS_ASIO:  return new RtApiAsio();
            version (Windows)   case WINDOWS_DS:    return new RtApiDs();
            version (OSX)       case MACOSX_CORE:   return new RtApiCore();
            case RTAUDIO_DUMMY: return new RtApiDummy();
            default:            assert(0);
        }
    }

    void openRtApi(Api api)
    {
        if (_rtapi)
            destroy(_rtapi);

        _rtapi = getRtApiInstance(api);
    }

    RtApi _rtapi;
}

/// Makes Mutex final to de-virtualize member function calls.
final class StreamMutex : Mutex { }

// This global structure type is used to pass callback information
// between the private RtAudio stream structure and global callback
// handling functions.
struct CallbackInfo
{
    void* object;  // Used as a "this" pointer.
    Thread thread;
    void* callback;
    void* userData;
    void* errorCallback;
    void* apiInfo; // void pointer for API specific callback information
    bool isRunning;
    bool doRealtime;
    int priority;
}

//
// RtApi class declaration.
//
// Subclasses of RtApi contain all API- and OS-specific code necessary
// to fully implement the RtAudio API.
//
// Note that RtApi is an abstract base class and cannot be
// explicitly instantiated.  The class RtAudio will create an
// instance of an RtApi subclass (RtApiOss, RtApiAlsa,
// RtApiJack, RtApiCore, RtApiDs, or RtApiAsio).
//

align(1)
private struct S24
{
    ubyte[3] c3;

    void opAssign(int i)
    {
        c3[0] = (i & 0x000000ff);
        c3[1] = (i & 0x0000ff00) >> 8;
        c3[2] = (i & 0x00ff0000) >> 16;
    }

    this(const ref S24 v)
    {
        this = v;
    }

    this(const ref double d)
    {
        this = cast(int)d;
    }

    this(const ref float f)
    {
        this = cast(int)f;
    }

    this(const ref short s)
    {
        this = cast(int)s;
    }

    this(const ref char c)
    {
        this = cast(int)c;
    }

    int asInt()
    {
        int i = c3[0] | (c3[1] << 8) | (c3[2] << 16);

        if (i & 0x800000)
            i |= ~0xffffff;

        return i;
    }
}

/+ #if defined( HAVE_GETTIMEOFDAY )
  #include <sys/time.h>
#endif +/

//~ #include <sstream>

class RtApi
{
    this()
    {
        _stream = new typeof(_stream);
        _stream.state         = StreamState.STREAM_CLOSED;
        _stream.mode          = StreamMode.UNINITIALIZED;
        _stream.apiHandle     = null;
        _stream.userBuffer[0] = null;
        _stream.userBuffer[1] = null;
        _stream.mutex = new StreamMutex;
        showWarnings_ = true;
    }

    /* virtual */ abstract Api getCurrentApi();
    /* virtual */ abstract uint getDeviceCount();
    /* virtual */ abstract DeviceInfo getDeviceInfo(uint device);

    /* virtual */
    uint getDefaultInputDevice()
    {
        // Should be implemented in subclasses if possible.
        return 0;
    }

    /* virtual */
    uint getDefaultOutputDevice()
    {
        // Should be implemented in subclasses if possible.
        return 0;
    }


    void openStream(StreamParameters* outputParameters,
                    StreamParameters* inputParameters,
                    RtAudioFormat format, uint sampleRate,
                    uint* bufferFrames, RtAudioCallback callback,
                    void* userData, StreamOptions* options,
                    RtAudioErrorCallback errorCallback)
    {
        if (_stream.state != StreamState.STREAM_CLOSED)
        {
            errorText_ = "RtApi.openStream: a stream is already open!";
            error(RtErrorType.INVALID_USE);
            return;
        }

        if (outputParameters && outputParameters.nChannels < 1)
        {
            errorText_ = "RtApi.openStream: a non-null output StreamParameters structure cannot have an nChannels value less than one.";
            error(RtErrorType.INVALID_USE);
            return;
        }

        if (inputParameters && inputParameters.nChannels < 1)
        {
            errorText_ = "RtApi.openStream: a non-null input StreamParameters structure cannot have an nChannels value less than one.";
            error(RtErrorType.INVALID_USE);
            return;
        }

        if (outputParameters == null && inputParameters == null)
        {
            errorText_ = "RtApi.openStream: input and output StreamParameters structures are both null!";
            error(RtErrorType.INVALID_USE);
            return;
        }

        if (formatBytes(format) == 0)
        {
            errorText_ = "RtApi.openStream: 'format' parameter value is undefined.";
            error(RtErrorType.INVALID_USE);
            return;
        }

        uint nDevices  = getDeviceCount();
        uint oChannels = 0;

        if (outputParameters)
        {
            oChannels = outputParameters.nChannels;

            if (outputParameters.deviceId >= nDevices)
            {
                errorText_ = "RtApi.openStream: output device parameter value is invalid.";
                error(RtErrorType.INVALID_USE);
                return;
            }
        }

        uint iChannels = 0;

        if (inputParameters)
        {
            iChannels = inputParameters.nChannels;

            if (inputParameters.deviceId >= nDevices)
            {
                errorText_ = "RtApi.openStream: input device parameter value is invalid.";
                error(RtErrorType.INVALID_USE);
                return;
            }
        }

        clearStreamInfo();
        bool result;

        if (oChannels > 0)
        {
            result = probeDeviceOpen(outputParameters.deviceId, StreamMode.OUTPUT, oChannels, outputParameters.firstChannel,
                                     sampleRate, format, bufferFrames, options);

            if (result == false)
            {
                error(RtErrorType.SYSTEM_ERROR);
                return;
            }
        }

        if (iChannels > 0)
        {
            result = probeDeviceOpen(inputParameters.deviceId, StreamMode.INPUT, iChannels, inputParameters.firstChannel,
                                     sampleRate, format, bufferFrames, options);

            if (result == false)
            {
                if (oChannels > 0)
                    closeStream();
                error(RtErrorType.SYSTEM_ERROR);
                return;
            }
        }

        _stream.callbackInfo.callback      = cast(void*)callback;
        _stream.callbackInfo.userData      = userData;
        _stream.callbackInfo.errorCallback = cast(void*)errorCallback;

        if (options)
            options.numberOfBuffers = _stream.nBuffers;
        _stream.state = StreamState.STREAM_STOPPED;
    }

    /* virtual */
    void closeStream()
    {
        // MUST be implemented in subclasses!
        assert(0);
    }

    /* virtual */ void startStream();
    /* virtual */ void stopStream();
    /* virtual */ void abortStream();

    /* virtual */
    long getStreamLatency()
    {
        verifyStream();

        long totalLatency = 0;

        if (_stream.mode == StreamMode.OUTPUT || _stream.mode == StreamMode.DUPLEX)
            totalLatency = _stream.latency[0];

        if (_stream.mode == StreamMode.INPUT || _stream.mode == StreamMode.DUPLEX)
            totalLatency += _stream.latency[1];

        return totalLatency;
    }

    uint getStreamSampleRate()
    {
        verifyStream();

        return _stream.sampleRate;
    }


    /* virtual */
    double getStreamTime()
    {
        verifyStream();

        /+ #if defined( HAVE_GETTIMEOFDAY )

            // Return a very accurate estimate of the stream time by
            // adding in the elapsed time since the last tick.
            struct timeval then;
            struct timeval now;

            if (_stream.state != StreamState.STREAM_RUNNING || _stream.streamTime == 0.0)
                return _stream.streamTime;

            gettimeofday(&now, null);
            then = _stream.lastTickTimestamp;
            return _stream.streamTime +
                   ((now.tv_sec + 0.000001 * now.tv_usec) -
                    (then.tv_sec + 0.000001 * then.tv_usec));
        #else +/
            return _stream.streamTime;
        /+ #endif +/
    }


    bool isStreamOpen() const
    {
        return _stream.state != StreamState.STREAM_CLOSED;
    }

    bool isStreamRunning() const
    {
        return _stream.state == StreamState.STREAM_RUNNING;
    }

    void showWarnings(bool value)
    {
        showWarnings_ = value;
    }

protected:

    // Static variable definitions.
    enum uint MAX_SAMPLE_RATES = 14;

    static immutable uint[] SAMPLE_RATES = [
        4000, 5512, 8000, 9600, 11025, 16000, 22050,
        32000, 44100, 48000, 88200, 96000, 176400, 192000
    ];

    enum { FAILURE, SUCCESS }

    enum StreamState
    {
        STREAM_STOPPED,
        STREAM_STOPPING,
        STREAM_RUNNING,
        STREAM_CLOSED = -50
    }

    enum StreamMode
    {
        OUTPUT,
        INPUT,
        DUPLEX,
        UNINITIALIZED = -75
    }

    // A protected structure used for buffer conversion.
    struct ConvertInfo
    {
        int channels;
        int inJump, outJump;
        RtAudioFormat inFormat, outFormat;
        int[] inOffset;
        int[] outOffset;
    }

    // A protected structure for audio streams.
    class RtApiStream
    {
        uint[2] device;            // Playback and record, respectively.
        void* apiHandle;           // void pointer for API specific stream handle information
        StreamMode mode;           // OUTPUT, INPUT, or DUPLEX.
        StreamState state;         // STOPPED, RUNNING, or CLOSED
        ubyte*[2] userBuffer;       // Playback and record, respectively.
        ubyte* deviceBuffer;
        bool[2] doConvertBuffer;   // Playback and record, respectively.
        bool userInterleaved;
        bool[2] deviceInterleaved; // Playback and record, respectively.
        bool[2] doByteSwap;        // Playback and record, respectively.
        uint sampleRate;
        uint bufferSize;
        uint nBuffers;
        uint[2] nUserChannels;         // Playback and record, respectively.
        uint[2] nDeviceChannels;       // Playback and record channels, respectively.
        uint[2] channelOffset;         // Playback and record, respectively.
        ulong[2] latency;            // Playback and record, respectively.
        RtAudioFormat userFormat;
        RtAudioFormat[2] deviceFormat; // Playback and record, respectively.
        StreamMutex mutex;
        CallbackInfo callbackInfo;
        ConvertInfo[2] convertInfo;
        double streamTime;     // Number of elapsed seconds since the stream started.

        /+ #if defined(HAVE_GETTIMEOFDAY)
            struct timeval lastTickTimestamp;
        #endif +/

        this()
        {
            device[0] = 11111;
            device[1] = 11111;
        }
    }

    alias S24 Int24;
    alias short Int16;
    alias int Int32;
    alias float  Float32;
    alias double Float64;

    //~ std.ostringstream errorStream_;
    string errorText_;
    bool showWarnings_;
    RtApiStream _stream;

    /**
       Protected, api-specific method that attempts to open a device
       with the given parameters.  This function MUST be implemented by
       all subclasses.  If an error is encountered during the probe, a
       "warning" message is reported and FAILURE is returned. A
       successful probe is indicated by a return value of SUCCESS.
    */
    /* virtual */
    bool probeDeviceOpen(uint device, StreamMode mode, uint channels,
                         uint firstChannel, uint sampleRate,
                         RtAudioFormat format, uint* bufferSize,
                         StreamOptions* options)
    {
        // MUST be implemented in subclasses!
        assert(0);
    }


    /// A protected function used to increment the stream time.
    public void tickStreamTime()
    {
        // Subclasses that do not provide their own implementation of
        // getStreamTime should call this function once per buffer I/O to
        // provide basic stream time support.

        _stream.streamTime += _stream.bufferSize * 1.0 / _stream.sampleRate;

        /+ #if defined( HAVE_GETTIMEOFDAY )
            gettimeofday(&_stream.lastTickTimestamp, null);
        #endif +/
    }


    // This method can be modified to control the behavior of error
    // message printing.
    void error(RtErrorType type)
    {
        RtAudioErrorCallback errorCallback = cast(RtAudioErrorCallback)_stream.callbackInfo.errorCallback;

        if (errorCallback)
        {
            // abortStream() can generate new error messages. Ignore them. Just keep original one.
            static bool firstErrorOccured = false;

            if (firstErrorOccured)
                return;

            firstErrorOccured = true;
            string errorMessage = errorText_;

            if (type != RtErrorType.WARNING && _stream.state != StreamState.STREAM_STOPPED)
            {
                _stream.callbackInfo.isRunning = false; // exit from the thread
                abortStream();
            }

            errorCallback(type, errorMessage);
            firstErrorOccured = false;
            return;
        }

        if (type == RtErrorType.WARNING && showWarnings_ == true)
            stderr.writeln('\n', errorText_, "\n\n");
        else
        if (type != RtErrorType.WARNING)
            throw new RtError(errorText_, type);
    }

    void verifyStream()
    {
        if (_stream.state == StreamState.STREAM_CLOSED)
        {
            errorText_ = "RtApi. a stream is not open!";
            error(RtErrorType.INVALID_USE);
        }
    }

    void clearStreamInfo()
    {
        _stream.mode                       = StreamMode.UNINITIALIZED;
        _stream.state                      = StreamState.STREAM_CLOSED;
        _stream.sampleRate                 = 0;
        _stream.bufferSize                 = 0;
        _stream.nBuffers                   = 0;
        _stream.userFormat                 = RtAudioFormat.init;
        _stream.userInterleaved            = true;
        _stream.streamTime                 = 0.0;
        _stream.apiHandle                  = null;
        _stream.deviceBuffer               = null;
        _stream.callbackInfo.callback      = null;
        _stream.callbackInfo.userData      = null;
        _stream.callbackInfo.isRunning     = false;
        _stream.callbackInfo.errorCallback = null;

        for (int i = 0; i < 2; i++)
        {
            _stream.device[i] = 11111;
            _stream.doConvertBuffer[i]   = false;
            _stream.deviceInterleaved[i] = true;
            _stream.doByteSwap[i]        = false;
            _stream.nUserChannels[i]     = 0;
            _stream.nDeviceChannels[i]   = 0;
            _stream.channelOffset[i]     = 0;
            _stream.deviceFormat[i]      = RtAudioFormat.init;
            _stream.latency[i]    = 0;
            _stream.userBuffer[i] = null;
            _stream.convertInfo[i].channels  = 0;
            _stream.convertInfo[i].inJump    = 0;
            _stream.convertInfo[i].outJump   = 0;
            _stream.convertInfo[i].inFormat  = RtAudioFormat.init;
            _stream.convertInfo[i].outFormat = RtAudioFormat.init;
            _stream.convertInfo[i].inOffset.clear();
            _stream.convertInfo[i].outOffset.clear();
        }
    }

    uint formatBytes(RtAudioFormat format)
    {
        if (format == RtAudioFormat.int16)
            return 2;
        else if (format == RtAudioFormat.int32 || format == RtAudioFormat.float32)
            return 4;
        else if (format == RtAudioFormat.float64)
            return 8;
        else if (format == RtAudioFormat.int24)
            return 3;
        else if (format == RtAudioFormat.int8)
            return 1;

        errorText_ = "RtApi.formatBytes: undefined format.";
        error(RtErrorType.WARNING);

        return 0;
    }

    void setConvertInfo(StreamMode mode, uint firstChannel)
    {
        if (mode == StreamMode.INPUT)   // convert device to user buffer
        {
            _stream.convertInfo[mode].inJump    = _stream.nDeviceChannels[1];
            _stream.convertInfo[mode].outJump   = _stream.nUserChannels[1];
            _stream.convertInfo[mode].inFormat  = _stream.deviceFormat[1];
            _stream.convertInfo[mode].outFormat = _stream.userFormat;
        }
        else // convert user to device buffer
        {
            _stream.convertInfo[mode].inJump    = _stream.nUserChannels[0];
            _stream.convertInfo[mode].outJump   = _stream.nDeviceChannels[0];
            _stream.convertInfo[mode].inFormat  = _stream.userFormat;
            _stream.convertInfo[mode].outFormat = _stream.deviceFormat[0];
        }

        if (_stream.convertInfo[mode].inJump < _stream.convertInfo[mode].outJump)
            _stream.convertInfo[mode].channels = _stream.convertInfo[mode].inJump;
        else
            _stream.convertInfo[mode].channels = _stream.convertInfo[mode].outJump;

        // Set up the interleave/deinterleave offsets.
        if (_stream.deviceInterleaved[mode] != _stream.userInterleaved)
        {
            if ( ( mode == StreamMode.OUTPUT && _stream.deviceInterleaved[mode] ) ||
                 ( mode == StreamMode.INPUT && _stream.userInterleaved ) )
            {
                for (int k = 0; k < _stream.convertInfo[mode].channels; k++)
                {
                    _stream.convertInfo[mode].inOffset.push_back(k * _stream.bufferSize);
                    _stream.convertInfo[mode].outOffset.push_back(k);
                    _stream.convertInfo[mode].inJump = 1;
                }
            }
            else
            {
                for (int k = 0; k < _stream.convertInfo[mode].channels; k++)
                {
                    _stream.convertInfo[mode].inOffset.push_back(k);
                    _stream.convertInfo[mode].outOffset.push_back(k * _stream.bufferSize);
                    _stream.convertInfo[mode].outJump = 1;
                }
            }
        }
        else // no (de)interleaving
        {
            if (_stream.userInterleaved)
            {
                for (int k = 0; k < _stream.convertInfo[mode].channels; k++)
                {
                    _stream.convertInfo[mode].inOffset.push_back(k);
                    _stream.convertInfo[mode].outOffset.push_back(k);
                }
            }
            else
            {
                for (int k = 0; k < _stream.convertInfo[mode].channels; k++)
                {
                    _stream.convertInfo[mode].inOffset.push_back(k * _stream.bufferSize);
                    _stream.convertInfo[mode].outOffset.push_back(k * _stream.bufferSize);
                    _stream.convertInfo[mode].inJump  = 1;
                    _stream.convertInfo[mode].outJump = 1;
                }
            }
        }

        // Add channel offset.
        if (firstChannel > 0)
        {
            if (_stream.deviceInterleaved[mode])
            {
                if (mode == StreamMode.OUTPUT)
                {
                    for (int k = 0; k < _stream.convertInfo[mode].channels; k++)
                        _stream.convertInfo[mode].outOffset[k] += firstChannel;
                }
                else
                {
                    for (int k = 0; k < _stream.convertInfo[mode].channels; k++)
                        _stream.convertInfo[mode].inOffset[k] += firstChannel;
                }
            }
            else
            {
                if (mode == StreamMode.OUTPUT)
                {
                    for (int k = 0; k < _stream.convertInfo[mode].channels; k++)
                        _stream.convertInfo[mode].outOffset[k] += ( firstChannel * _stream.bufferSize );
                }
                else
                {
                    for (int k = 0; k < _stream.convertInfo[mode].channels; k++)
                        _stream.convertInfo[mode].inOffset[k] += ( firstChannel * _stream.bufferSize );
                }
            }
        }
    }

    void convertBuffer(ubyte* outBuffer, ubyte* inBuffer, ref ConvertInfo info)
    {
        // This function does format conversion, input/output channel compensation, and
        // data interleaving/deinterleaving.  24-bit integers are assumed to occupy
        // the lower three bytes of a 32-bit integer.

        // Clear our device buffer when in/out duplex device channels are different
        if (outBuffer == _stream.deviceBuffer && _stream.mode == StreamMode.DUPLEX &&
            ( _stream.nDeviceChannels[0] < _stream.nDeviceChannels[1] ) )
            memset(outBuffer, 0, _stream.bufferSize * info.outJump * formatBytes(info.outFormat) );

        int j;

        if (info.outFormat == RtAudioFormat.float64)
        {
            Float64  scale;
            Float64* _out = cast(Float64*)outBuffer;

            if (info.inFormat == RtAudioFormat.int8)
            {
                byte* _in = cast(byte*)inBuffer;
                scale = 1.0 / 127.5;

                for (uint i = 0; i < _stream.bufferSize; i++)
                {
                    for (j = 0; j < info.channels; j++)
                    {
                        _out[info.outOffset[j]]  = cast(Float64)_in[info.inOffset[j]];
                        _out[info.outOffset[j]] += 0.5;
                        _out[info.outOffset[j]] *= scale;
                    }

                    _in  += info.inJump;
                    _out += info.outJump;
                }
            }
            else if (info.inFormat == RtAudioFormat.int16)
            {
                Int16* _in = cast(Int16*)inBuffer;
                scale = 1.0 / 32767.5;

                for (uint i = 0; i < _stream.bufferSize; i++)
                {
                    for (j = 0; j < info.channels; j++)
                    {
                        _out[info.outOffset[j]]  = cast(Float64)_in[info.inOffset[j]];
                        _out[info.outOffset[j]] += 0.5;
                        _out[info.outOffset[j]] *= scale;
                    }

                    _in  += info.inJump;
                    _out += info.outJump;
                }
            }
            else if (info.inFormat == RtAudioFormat.int24)
            {
                Int24* _in = cast(Int24*)inBuffer;
                scale = 1.0 / 8388607.5;

                for (uint i = 0; i < _stream.bufferSize; i++)
                {
                    for (j = 0; j < info.channels; j++)
                    {
                        _out[info.outOffset[j]]  = cast(Float64)(_in[info.inOffset[j]].asInt());
                        _out[info.outOffset[j]] += 0.5;
                        _out[info.outOffset[j]] *= scale;
                    }

                    _in  += info.inJump;
                    _out += info.outJump;
                }
            }
            else if (info.inFormat == RtAudioFormat.int32)
            {
                Int32* _in = cast(Int32*)inBuffer;
                scale = 1.0 / 2147483647.5;

                for (uint i = 0; i < _stream.bufferSize; i++)
                {
                    for (j = 0; j < info.channels; j++)
                    {
                        _out[info.outOffset[j]]  = cast(Float64)_in[info.inOffset[j]];
                        _out[info.outOffset[j]] += 0.5;
                        _out[info.outOffset[j]] *= scale;
                    }

                    _in  += info.inJump;
                    _out += info.outJump;
                }
            }
            else if (info.inFormat == RtAudioFormat.float32)
            {
                Float32* _in = cast(Float32*)inBuffer;

                for (uint i = 0; i < _stream.bufferSize; i++)
                {
                    for (j = 0; j < info.channels; j++)
                    {
                        _out[info.outOffset[j]] = cast(Float64)_in[info.inOffset[j]];
                    }

                    _in  += info.inJump;
                    _out += info.outJump;
                }
            }
            else if (info.inFormat == RtAudioFormat.float64)
            {
                // Channel compensation and/or (de)interleaving only.
                Float64* _in = cast(Float64*)inBuffer;

                for (uint i = 0; i < _stream.bufferSize; i++)
                {
                    for (j = 0; j < info.channels; j++)
                    {
                        _out[info.outOffset[j]] = _in[info.inOffset[j]];
                    }

                    _in  += info.inJump;
                    _out += info.outJump;
                }
            }
        }
        else if (info.outFormat == RtAudioFormat.float32)
        {
            Float32  scale;
            Float32* _out = cast(Float32*)outBuffer;

            if (info.inFormat == RtAudioFormat.int8)
            {
                byte* _in = cast(byte*)inBuffer;
                scale = cast(Float32)( 1.0 / 127.5 );

                for (uint i = 0; i < _stream.bufferSize; i++)
                {
                    for (j = 0; j < info.channels; j++)
                    {
                        _out[info.outOffset[j]]  = cast(Float32)_in[info.inOffset[j]];
                        _out[info.outOffset[j]] += 0.5;
                        _out[info.outOffset[j]] *= scale;
                    }

                    _in  += info.inJump;
                    _out += info.outJump;
                }
            }
            else if (info.inFormat == RtAudioFormat.int16)
            {
                Int16* _in = cast(Int16*)inBuffer;
                scale = cast(Float32)( 1.0 / 32767.5 );

                for (uint i = 0; i < _stream.bufferSize; i++)
                {
                    for (j = 0; j < info.channels; j++)
                    {
                        _out[info.outOffset[j]]  = cast(Float32)_in[info.inOffset[j]];
                        _out[info.outOffset[j]] += 0.5;
                        _out[info.outOffset[j]] *= scale;
                    }

                    _in  += info.inJump;
                    _out += info.outJump;
                }
            }
            else if (info.inFormat == RtAudioFormat.int24)
            {
                Int24* _in = cast(Int24*)inBuffer;
                scale = cast(Float32)( 1.0 / 8388607.5 );

                for (uint i = 0; i < _stream.bufferSize; i++)
                {
                    for (j = 0; j < info.channels; j++)
                    {
                        _out[info.outOffset[j]]  = cast(Float32)(_in[info.inOffset[j]].asInt());
                        _out[info.outOffset[j]] += 0.5;
                        _out[info.outOffset[j]] *= scale;
                    }

                    _in  += info.inJump;
                    _out += info.outJump;
                }
            }
            else if (info.inFormat == RtAudioFormat.int32)
            {
                Int32* _in = cast(Int32*)inBuffer;
                scale = cast(Float32)( 1.0 / 2147483647.5 );

                for (uint i = 0; i < _stream.bufferSize; i++)
                {
                    for (j = 0; j < info.channels; j++)
                    {
                        _out[info.outOffset[j]]  = cast(Float32)_in[info.inOffset[j]];
                        _out[info.outOffset[j]] += 0.5;
                        _out[info.outOffset[j]] *= scale;
                    }

                    _in  += info.inJump;
                    _out += info.outJump;
                }
            }
            else if (info.inFormat == RtAudioFormat.float32)
            {
                // Channel compensation and/or (de)interleaving only.
                Float32* _in = cast(Float32*)inBuffer;

                for (uint i = 0; i < _stream.bufferSize; i++)
                {
                    for (j = 0; j < info.channels; j++)
                    {
                        _out[info.outOffset[j]] = _in[info.inOffset[j]];
                    }

                    _in  += info.inJump;
                    _out += info.outJump;
                }
            }
            else if (info.inFormat == RtAudioFormat.float64)
            {
                Float64* _in = cast(Float64*)inBuffer;

                for (uint i = 0; i < _stream.bufferSize; i++)
                {
                    for (j = 0; j < info.channels; j++)
                    {
                        _out[info.outOffset[j]] = cast(Float32)_in[info.inOffset[j]];
                    }

                    _in  += info.inJump;
                    _out += info.outJump;
                }
            }
        }
        else if (info.outFormat == RtAudioFormat.int32)
        {
            Int32* _out = cast(Int32*)outBuffer;

            if (info.inFormat == RtAudioFormat.int8)
            {
                byte* _in = cast(byte*)inBuffer;

                for (uint i = 0; i < _stream.bufferSize; i++)
                {
                    for (j = 0; j < info.channels; j++)
                    {
                        _out[info.outOffset[j]]   = cast(Int32)_in[info.inOffset[j]];
                        _out[info.outOffset[j]] <<= 24;
                    }

                    _in  += info.inJump;
                    _out += info.outJump;
                }
            }
            else if (info.inFormat == RtAudioFormat.int16)
            {
                Int16* _in = cast(Int16*)inBuffer;

                for (uint i = 0; i < _stream.bufferSize; i++)
                {
                    for (j = 0; j < info.channels; j++)
                    {
                        _out[info.outOffset[j]]   = cast(Int32)_in[info.inOffset[j]];
                        _out[info.outOffset[j]] <<= 16;
                    }

                    _in  += info.inJump;
                    _out += info.outJump;
                }
            }
            else if (info.inFormat == RtAudioFormat.int24)
            {
                Int24* _in = cast(Int24*)inBuffer;

                for (uint i = 0; i < _stream.bufferSize; i++)
                {
                    for (j = 0; j < info.channels; j++)
                    {
                        _out[info.outOffset[j]]   = cast(Int32)_in[info.inOffset[j]].asInt();
                        _out[info.outOffset[j]] <<= 8;
                    }

                    _in  += info.inJump;
                    _out += info.outJump;
                }
            }
            else if (info.inFormat == RtAudioFormat.int32)
            {
                // Channel compensation and/or (de)interleaving only.
                Int32* _in = cast(Int32*)inBuffer;

                for (uint i = 0; i < _stream.bufferSize; i++)
                {
                    for (j = 0; j < info.channels; j++)
                    {
                        _out[info.outOffset[j]] = _in[info.inOffset[j]];
                    }

                    _in  += info.inJump;
                    _out += info.outJump;
                }
            }
            else if (info.inFormat == RtAudioFormat.float32)
            {
                Float32* _in = cast(Float32*)inBuffer;

                for (uint i = 0; i < _stream.bufferSize; i++)
                {
                    for (j = 0; j < info.channels; j++)
                    {
                        _out[info.outOffset[j]] = cast(Int32)(_in[info.inOffset[j]] * 2147483647.5 - 0.5);
                    }

                    _in  += info.inJump;
                    _out += info.outJump;
                }
            }
            else if (info.inFormat == RtAudioFormat.float64)
            {
                Float64* _in = cast(Float64*)inBuffer;

                for (uint i = 0; i < _stream.bufferSize; i++)
                {
                    for (j = 0; j < info.channels; j++)
                    {
                        _out[info.outOffset[j]] = cast(Int32)(_in[info.inOffset[j]] * 2147483647.5 - 0.5);
                    }

                    _in  += info.inJump;
                    _out += info.outJump;
                }
            }
        }
        else if (info.outFormat == RtAudioFormat.int24)
        {
            Int24* _out = cast(Int24*)outBuffer;

            if (info.inFormat == RtAudioFormat.int8)
            {
                byte* _in = cast(byte*)inBuffer;

                for (uint i = 0; i < _stream.bufferSize; i++)
                {
                    for (j = 0; j < info.channels; j++)
                    {
                        _out[info.outOffset[j]] = cast(Int32)(_in[info.inOffset[j]] << 16);

                        //_out[info.outOffset[j]] <<= 16;
                    }

                    _in  += info.inJump;
                    _out += info.outJump;
                }
            }
            else if (info.inFormat == RtAudioFormat.int16)
            {
                Int16* _in = cast(Int16*)inBuffer;

                for (uint i = 0; i < _stream.bufferSize; i++)
                {
                    for (j = 0; j < info.channels; j++)
                    {
                        _out[info.outOffset[j]] = cast(Int32)(_in[info.inOffset[j]] << 8);

                        //_out[info.outOffset[j]] <<= 8;
                    }

                    _in  += info.inJump;
                    _out += info.outJump;
                }
            }
            else if (info.inFormat == RtAudioFormat.int24)
            {
                // Channel compensation and/or (de)interleaving only.
                Int24* _in = cast(Int24*)inBuffer;

                for (uint i = 0; i < _stream.bufferSize; i++)
                {
                    for (j = 0; j < info.channels; j++)
                    {
                        _out[info.outOffset[j]] = _in[info.inOffset[j]];
                    }

                    _in  += info.inJump;
                    _out += info.outJump;
                }
            }
            else if (info.inFormat == RtAudioFormat.int32)
            {
                Int32* _in = cast(Int32*)inBuffer;

                for (uint i = 0; i < _stream.bufferSize; i++)
                {
                    for (j = 0; j < info.channels; j++)
                    {
                        _out[info.outOffset[j]] = cast(Int32)(_in[info.inOffset[j]] >> 8);

                        //_out[info.outOffset[j]] >>= 8;
                    }

                    _in  += info.inJump;
                    _out += info.outJump;
                }
            }
            else if (info.inFormat == RtAudioFormat.float32)
            {
                Float32* _in = cast(Float32*)inBuffer;

                for (uint i = 0; i < _stream.bufferSize; i++)
                {
                    for (j = 0; j < info.channels; j++)
                    {
                        _out[info.outOffset[j]] = cast(Int32)(_in[info.inOffset[j]] * 8388607.5 - 0.5);
                    }

                    _in  += info.inJump;
                    _out += info.outJump;
                }
            }
            else if (info.inFormat == RtAudioFormat.float64)
            {
                Float64* _in = cast(Float64*)inBuffer;

                for (uint i = 0; i < _stream.bufferSize; i++)
                {
                    for (j = 0; j < info.channels; j++)
                    {
                        _out[info.outOffset[j]] = cast(Int32)(_in[info.inOffset[j]] * 8388607.5 - 0.5);
                    }

                    _in  += info.inJump;
                    _out += info.outJump;
                }
            }
        }
        else if (info.outFormat == RtAudioFormat.int16)
        {
            Int16* _out = cast(Int16*)outBuffer;

            if (info.inFormat == RtAudioFormat.int8)
            {
                byte* _in = cast(byte*)inBuffer;

                for (uint i = 0; i < _stream.bufferSize; i++)
                {
                    for (j = 0; j < info.channels; j++)
                    {
                        _out[info.outOffset[j]]   = cast(Int16)_in[info.inOffset[j]];
                        _out[info.outOffset[j]] <<= 8;
                    }

                    _in  += info.inJump;
                    _out += info.outJump;
                }
            }
            else if (info.inFormat == RtAudioFormat.int16)
            {
                // Channel compensation and/or (de)interleaving only.
                Int16* _in = cast(Int16*)inBuffer;

                for (uint i = 0; i < _stream.bufferSize; i++)
                {
                    for (j = 0; j < info.channels; j++)
                    {
                        _out[info.outOffset[j]] = _in[info.inOffset[j]];
                    }

                    _in  += info.inJump;
                    _out += info.outJump;
                }
            }
            else if (info.inFormat == RtAudioFormat.int24)
            {
                Int24* _in = cast(Int24*)inBuffer;

                for (uint i = 0; i < _stream.bufferSize; i++)
                {
                    for (j = 0; j < info.channels; j++)
                    {
                        _out[info.outOffset[j]] = cast(Int16)(_in[info.inOffset[j]].asInt() >> 8);
                    }

                    _in  += info.inJump;
                    _out += info.outJump;
                }
            }
            else if (info.inFormat == RtAudioFormat.int32)
            {
                Int32* _in = cast(Int32*)inBuffer;

                for (uint i = 0; i < _stream.bufferSize; i++)
                {
                    for (j = 0; j < info.channels; j++)
                    {
                        _out[info.outOffset[j]] = cast(Int16)((_in[info.inOffset[j]] >> 16) & 0x0000ffff);
                    }

                    _in  += info.inJump;
                    _out += info.outJump;
                }
            }
            else if (info.inFormat == RtAudioFormat.float32)
            {
                Float32* _in = cast(Float32*)inBuffer;

                for (uint i = 0; i < _stream.bufferSize; i++)
                {
                    for (j = 0; j < info.channels; j++)
                    {
                        _out[info.outOffset[j]] = cast(Int16)(_in[info.inOffset[j]] * 32767.5 - 0.5);
                    }

                    _in  += info.inJump;
                    _out += info.outJump;
                }
            }
            else if (info.inFormat == RtAudioFormat.float64)
            {
                Float64* _in = cast(Float64*)inBuffer;

                for (uint i = 0; i < _stream.bufferSize; i++)
                {
                    for (j = 0; j < info.channels; j++)
                    {
                        _out[info.outOffset[j]] = cast(Int16)(_in[info.inOffset[j]] * 32767.5 - 0.5);
                    }

                    _in  += info.inJump;
                    _out += info.outJump;
                }
            }
        }
        else if (info.outFormat == RtAudioFormat.int8)
        {
            byte* _out = cast(byte*)outBuffer;

            if (info.inFormat == RtAudioFormat.int8)
            {
                // Channel compensation and/or (de)interleaving only.
                byte* _in = cast(byte*)inBuffer;

                for (uint i = 0; i < _stream.bufferSize; i++)
                {
                    for (j = 0; j < info.channels; j++)
                    {
                        _out[info.outOffset[j]] = _in[info.inOffset[j]];
                    }

                    _in  += info.inJump;
                    _out += info.outJump;
                }
            }

            if (info.inFormat == RtAudioFormat.int16)
            {
                Int16* _in = cast(Int16*)inBuffer;

                for (uint i = 0; i < _stream.bufferSize; i++)
                {
                    for (j = 0; j < info.channels; j++)
                    {
                        _out[info.outOffset[j]] = cast(byte)((_in[info.inOffset[j]] >> 8) & 0x00ff);
                    }

                    _in  += info.inJump;
                    _out += info.outJump;
                }
            }
            else if (info.inFormat == RtAudioFormat.int24)
            {
                Int24* _in = cast(Int24*)inBuffer;

                for (uint i = 0; i < _stream.bufferSize; i++)
                {
                    for (j = 0; j < info.channels; j++)
                    {
                        _out[info.outOffset[j]] = cast(byte)(_in[info.inOffset[j]].asInt() >> 16);
                    }

                    _in  += info.inJump;
                    _out += info.outJump;
                }
            }
            else if (info.inFormat == RtAudioFormat.int32)
            {
                Int32* _in = cast(Int32*)inBuffer;

                for (uint i = 0; i < _stream.bufferSize; i++)
                {
                    for (j = 0; j < info.channels; j++)
                    {
                        _out[info.outOffset[j]] = cast(byte)((_in[info.inOffset[j]] >> 24) & 0x000000ff);
                    }

                    _in  += info.inJump;
                    _out += info.outJump;
                }
            }
            else if (info.inFormat == RtAudioFormat.float32)
            {
                Float32* _in = cast(Float32*)inBuffer;

                for (uint i = 0; i < _stream.bufferSize; i++)
                {
                    for (j = 0; j < info.channels; j++)
                    {
                        _out[info.outOffset[j]] = cast(byte)(_in[info.inOffset[j]] * 127.5 - 0.5);
                    }

                    _in  += info.inJump;
                    _out += info.outJump;
                }
            }
            else if (info.inFormat == RtAudioFormat.float64)
            {
                Float64* _in = cast(Float64*)inBuffer;

                for (uint i = 0; i < _stream.bufferSize; i++)
                {
                    for (j = 0; j < info.channels; j++)
                    {
                        _out[info.outOffset[j]] = cast(byte)(_in[info.inOffset[j]] * 127.5 - 0.5);
                    }

                    _in  += info.inJump;
                    _out += info.outJump;
                }
            }
        }
    }

    //static inline uint16_t bswap_16(uint16_t x) { return (x>>8) | (x<<8); }
    //static inline uint32_t bswap_32(uint32_t x) { return (bswap_16(x&0xffff)<<16) | (bswap_16(x>>16)); }
    //static inline uint64_t bswap_64(uint64_t x) { return (((unsigned long long)bswap_32(x&0xffffffffull))<<32) | (bswap_32(x>>32)); }

    void byteSwapBuffer(byte* buffer, uint samples, RtAudioFormat format)
    {
        byte  val;
        byte* ptr;

        ptr = buffer;

        if (format == RtAudioFormat.int16)
        {
            for (uint i = 0; i < samples; i++)
            {
                // Swap 1st and 2nd bytes.
                val        = *(ptr);
                *(ptr)     = *(ptr + 1);
                *(ptr + 1) = val;

                // Increment 2 bytes.
                ptr += 2;
            }
        }
        else if (format == RtAudioFormat.int32 ||
                 format == RtAudioFormat.float32)
        {
            for (uint i = 0; i < samples; i++)
            {
                // Swap 1st and 4th bytes.
                val        = *(ptr);
                *(ptr)     = *(ptr + 3);
                *(ptr + 3) = val;

                // Swap 2nd and 3rd bytes.
                ptr       += 1;
                val        = *(ptr);
                *(ptr)     = *(ptr + 1);
                *(ptr + 1) = val;

                // Increment 3 more bytes.
                ptr += 3;
            }
        }
        else if (format == RtAudioFormat.int24)
        {
            for (uint i = 0; i < samples; i++)
            {
                // Swap 1st and 3rd bytes.
                val        = *(ptr);
                *(ptr)     = *(ptr + 2);
                *(ptr + 2) = val;

                // Increment 2 more bytes.
                ptr += 2;
            }
        }
        else if (format == RtAudioFormat.float64)
        {
            for (uint i = 0; i < samples; i++)
            {
                // Swap 1st and 8th bytes
                val        = *(ptr);
                *(ptr)     = *(ptr + 7);
                *(ptr + 7) = val;

                // Swap 2nd and 7th bytes
                ptr       += 1;
                val        = *(ptr);
                *(ptr)     = *(ptr + 5);
                *(ptr + 5) = val;

                // Swap 3rd and 6th bytes
                ptr       += 1;
                val        = *(ptr);
                *(ptr)     = *(ptr + 3);
                *(ptr + 3) = val;

                // Swap 4th and 5th bytes
                ptr       += 1;
                val        = *(ptr);
                *(ptr)     = *(ptr + 1);
                *(ptr + 1) = val;

                // Increment 5 more bytes.
                ptr += 5;
            }
        }
    }


}

version (OSX)
{
    //~ #include <CoreAudio/AudioHardware.h>

    class RtApiCore : RtApi
    {
        this();
        ~this();
        Api getCurrentApi()
        {
            return RtAudio.MACOSX_CORE;
        }

        uint getDeviceCount();
        DeviceInfo getDeviceInfo(uint device);
        uint getDefaultOutputDevice();
        uint getDefaultInputDevice();
        void closeStream();
        void startStream();
        void stopStream();
        void abortStream();
        long getStreamLatency();

        // This function is intended for internal use only.  It must be
        // public because it is called by the internal callback handler,
        // which is not a member of RtAudio.  External use of this function
        // will most likely produce highly undesireable results!
        bool callbackEvent(AudioDeviceID deviceId,
                           const AudioBufferList* inBufferList,
                           const AudioBufferList* outBufferList);

    private:

        bool probeDeviceOpen(uint device, StreamMode mode, uint channels,
                             uint firstChannel, uint sampleRate,
                             RtAudioFormat format, uint* bufferSize,
                             StreamOptions* options);
        static string getErrorCode(OSStatus code);
    }
}

version (Posix)
{
    /// Supported on Linux and OSX
    class RtApiJack : RtApi
    {
        this();
        ~this();
        Api getCurrentApi()
        {
            return RtAudio.UNIX_JACK;
        }

        uint getDeviceCount();
        DeviceInfo getDeviceInfo(uint device);
        void closeStream();
        void startStream();
        void stopStream();
        void abortStream();
        long getStreamLatency();

        // This function is intended for internal use only.  It must be
        // public because it is called by the internal callback handler,
        // which is not a member of RtAudio.  External use of this function
        // will most likely produce highly undesireable results!
        bool callbackEvent(ulong nframes);

    private:

        bool probeDeviceOpen(uint device, StreamMode mode, uint channels,
                             uint firstChannel, uint sampleRate,
                             RtAudioFormat format, uint* bufferSize,
                             StreamOptions* options);
    }
}

version (linux)
{
    class RtApiAlsa : RtApi
    {
        this();
        ~this();
        Api getCurrentApi()
        {
            return RtAudio.LINUX_ALSA;
        }

        uint getDeviceCount();
        DeviceInfo getDeviceInfo(uint device);
        void closeStream();
        void startStream();
        void stopStream();
        void abortStream();

        // This function is intended for internal use only.  It must be
        // public because it is called by the internal callback handler,
        // which is not a member of RtAudio.  External use of this function
        // will most likely produce highly undesireable results!
        void callbackEvent();

    private:

        DeviceInfo[] devices_;
        void saveDeviceInfo();
        bool probeDeviceOpen(uint device, StreamMode mode, uint channels,
                             uint firstChannel, uint sampleRate,
                             RtAudioFormat format, uint* bufferSize,
                             StreamOptions* options);
    }

    class RtApiPulse : RtApi
    {
        ~this();
        Api getCurrentApi()
        {
            return RtAudio.LINUX_PULSE;
        }

        uint getDeviceCount();
        DeviceInfo getDeviceInfo(uint device);
        void closeStream();
        void startStream();
        void stopStream();
        void abortStream();

        // This function is intended for internal use only.  It must be
        // public because it is called by the internal callback handler,
        // which is not a member of RtAudio.  External use of this function
        // will most likely produce highly undesireable results!
        void callbackEvent();

    private:

        DeviceInfo[] devices_;
        void saveDeviceInfo();
        bool probeDeviceOpen(uint device, StreamMode mode, uint channels,
                             uint firstChannel, uint sampleRate,
                             RtAudioFormat format, uint* bufferSize,
                             StreamOptions* options);
    }

    class RtApiOss : RtApi
    {
        this();
        ~this();
        Api getCurrentApi()
        {
            return RtAudio.LINUX_OSS;
        }

        uint getDeviceCount();
        DeviceInfo getDeviceInfo(uint device);
        void closeStream();
        void startStream();
        void stopStream();
        void abortStream();

        // This function is intended for internal use only.  It must be
        // public because it is called by the internal callback handler,
        // which is not a member of RtAudio.  External use of this function
        // will most likely produce highly undesireable results!
        void callbackEvent();

    private:

        bool probeDeviceOpen(uint device, StreamMode mode, uint channels,
                             uint firstChannel, uint sampleRate,
                             RtAudioFormat format, uint* bufferSize,
                             StreamOptions* options);
    }

}

class RtApiDummy : RtApi
{
    this()
    {
        //~ errorText_ = "RtApiDummy: This class provides no functionality.";
        //~ error(RtErrorType.WARNING);
    }

    override Api getCurrentApi()
    {
        return Api.RTAUDIO_DUMMY;
    }

    override uint getDeviceCount()
    {
        return 0;
    }

    override DeviceInfo getDeviceInfo(uint /*device*/)
    {
        DeviceInfo info;
        return info;
    }

    override void closeStream()
    {
    }

    override void startStream()
    {
    }

    override void stopStream()
    {
    }

    override void abortStream()
    {
    }

private:

    bool probeDeviceOpen(uint /*device*/, StreamMode /*mode*/, uint /*channels*/,
                         uint /*firstChannel*/, uint /*sampleRate*/,
                         RtAudioFormat /*format*/, uint* /*bufferSize*/,
                         StreamOptions* /*options*/)
    {
        return false;
    }
}
