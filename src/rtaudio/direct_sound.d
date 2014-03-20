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
module rtaudio.direct_sound;

import core.thread;

import core.stdc.stdlib;
import core.sync.mutex;
import core.stdc.string;

import std.array;
import std.algorithm;
import std.concurrency;
import std.conv;
import std.exception;
import std.stdio;
import std.string;

import win32.basetsd;
import win32.basetyps;
import win32.mmsystem : timeBeginPeriod, timeEndPeriod;
import win32.objbase;
import win32.winbase;
import win32.windef;
import win32.winuser;

import win32.directx.dsound8;

import rtaudio.engine;
import rtaudio.error;

// The function completed successfully
enum DS_OK = S_OK;

/** Missing definitions in win32.directx.dsound. */
extern(Windows) export HRESULT DirectSoundCreate(LPCGUID pcGuidDevice, LPDIRECTSOUND* ppDS8, LPUNKNOWN pUnkOuter);
enum DSCAPS_PRIMARYSTEREO = 0x00000002;
enum DSCAPS_PRIMARY8BIT   = 0x00000004;
enum DSCAPS_PRIMARY16BIT  = 0x00000008;

/* defines for dwFormat field of WAVEINCAPS and WAVEOUTCAPS */
enum WAVE_INVALIDFORMAT = 0x00000000;        /* invalid format */
enum WAVE_FORMAT_1M08   = 0x00000001;        /* 11.025 kHz, Mono,   8-bit  */
enum WAVE_FORMAT_1S08   = 0x00000002;        /* 11.025 kHz, Stereo, 8-bit  */
enum WAVE_FORMAT_1M16   = 0x00000004;        /* 11.025 kHz, Mono,   16-bit */
enum WAVE_FORMAT_1S16   = 0x00000008;        /* 11.025 kHz, Stereo, 16-bit */
enum WAVE_FORMAT_2M08   = 0x00000010;        /* 22.05  kHz, Mono,   8-bit  */
enum WAVE_FORMAT_2S08   = 0x00000020;        /* 22.05  kHz, Stereo, 8-bit  */
enum WAVE_FORMAT_2M16   = 0x00000040;        /* 22.05  kHz, Mono,   16-bit */
enum WAVE_FORMAT_2S16   = 0x00000080;        /* 22.05  kHz, Stereo, 16-bit */
enum WAVE_FORMAT_4M08   = 0x00000100;        /* 44.1   kHz, Mono,   8-bit  */
enum WAVE_FORMAT_4S08   = 0x00000200;        /* 44.1   kHz, Stereo, 8-bit  */
enum WAVE_FORMAT_4M16   = 0x00000400;        /* 44.1   kHz, Mono,   16-bit */
enum WAVE_FORMAT_4S16   = 0x00000800;        /* 44.1   kHz, Stereo, 16-bit */
enum WAVE_FORMAT_44M08  = 0x00000100;        /* 44.1   kHz, Mono,   8-bit  */
enum WAVE_FORMAT_44S08  = 0x00000200;        /* 44.1   kHz, Stereo, 8-bit  */
enum WAVE_FORMAT_44M16  = 0x00000400;        /* 44.1   kHz, Mono,   16-bit */
enum WAVE_FORMAT_44S16  = 0x00000800;        /* 44.1   kHz, Stereo, 16-bit */
enum WAVE_FORMAT_48M08  = 0x00001000;        /* 48     kHz, Mono,   8-bit  */
enum WAVE_FORMAT_48S08  = 0x00002000;        /* 48     kHz, Stereo, 8-bit  */
enum WAVE_FORMAT_48M16  = 0x00004000;        /* 48     kHz, Mono,   16-bit */
enum WAVE_FORMAT_48S16  = 0x00008000;        /* 48     kHz, Stereo, 16-bit */
enum WAVE_FORMAT_96M08  = 0x00010000;        /* 96     kHz, Mono,   8-bit  */
enum WAVE_FORMAT_96S08  = 0x00020000;        /* 96     kHz, Stereo, 8-bit  */
enum WAVE_FORMAT_96M16  = 0x00040000;        /* 96     kHz, Mono,   16-bit */
enum WAVE_FORMAT_96S16  = 0x00080000;        /* 96     kHz, Stereo, 16-bit */

enum DSBCAPS_PRIMARYBUFFER       = 0x00000001;
enum DSBCAPS_STATIC              = 0x00000002;
enum DSBCAPS_LOCHARDWARE         = 0x00000004;
enum DSBCAPS_LOCSOFTWARE         = 0x00000008;
enum DSBCAPS_CTRL3D              = 0x00000010;
enum DSBCAPS_CTRLFREQUENCY       = 0x00000020;
enum DSBCAPS_CTRLPAN             = 0x00000040;
enum DSBCAPS_CTRLVOLUME          = 0x00000080;
enum DSBCAPS_CTRLPOSITIONNOTIFY  = 0x00000100;
enum DSBCAPS_CTRLFX              = 0x00000200;
enum DSBCAPS_STICKYFOCUS         = 0x00004000;
enum DSBCAPS_GLOBALFOCUS         = 0x00008000;
enum DSBCAPS_GETCURRENTPOSITION2 = 0x00010000;
enum DSBCAPS_MUTE3DATMAXDISTANCE = 0x00020000;
enum DSBCAPS_LOCDEFER            = 0x00040000;
enum DSBCAPS_TRUEPLAYPOSITION    = 0x00080000;

enum DSCBLOCK_ENTIREBUFFER = 0x00000001;
enum DSCBSTATUS_CAPTURING  = 0x00000001;
enum DSCBSTATUS_LOOPING    = 0x00000002;
enum DSCBSTART_LOOPING     = 0x00000001;
enum DSBPN_OFFSETSTOP      = 0xFFFFFFFF;
enum DS_CERTIFIED          = 0x00000000;
enum DS_UNCERTIFIED        = 0x00000001;

enum DSCAPS_PRIMARYMONO     = 0x00000001;
enum DSCAPS_CONTINUOUSRATE  = 0x00000010;
enum DSCAPS_EMULDRIVER      = 0x00000020;
enum DSCAPS_CERTIFIED       = 0x00000040;
enum DSCAPS_SECONDARYMONO   = 0x00000100;
enum DSCAPS_SECONDARYSTEREO = 0x00000200;
enum DSCAPS_SECONDARY8BIT   = 0x00000400;
enum DSCAPS_SECONDARY16BIT  = 0x00000800;
enum DSSCL_NORMAL           = 0x00000001;
enum DSSCL_PRIORITY         = 0x00000002;
enum DSSCL_EXCLUSIVE        = 0x00000003;
enum DSSCL_WRITEPRIMARY     = 0x00000004;

void RtlFillMemory(PVOID dest, SIZE_T len, BYTE fill)
{
    memset(dest, fill, len);
}

void RtlZeroMemory(PVOID dest, SIZE_T len)
{
    RtlFillMemory(dest, len, 0);
}

alias memmove RtlMoveMemory;
alias memcpy  RtlCopyMemory;

alias RtlMoveMemory MoveMemory;
alias RtlCopyMemory CopyMemory;
alias RtlFillMemory FillMemory;
alias RtlZeroMemory ZeroMemory;

enum MINIMUM_DEVICE_BUFFER_SIZE = 32768;

enum _FACDS = 0x878;   /* DirectSound's facility code */

auto MAKE_DSHRESULT(C) (C code)
{
    return MAKE_HRESULT(1, _FACDS, code);
}

// The call succeeded, but we had to substitute the 3D algorithm
enum DS_NO_VIRTUALIZATION = MAKE_HRESULT(0, _FACDS, 10);

// The call failed because resources (such as a priority level)
// were already being used by another caller
enum DSERR_ALLOCATED = MAKE_DSHRESULT(10);

// The control (vol, pan, etc.) requested by the caller is not available
enum DSERR_CONTROLUNAVAIL = MAKE_DSHRESULT(30);

// An invalid parameter was passed to the returning function
enum DSERR_INVALIDPARAM = E_INVALIDARG;

// This call is not valid for the current state of this object
enum DSERR_INVALIDCALL = MAKE_DSHRESULT(50);

// An undetermined error occurred inside the DirectSound subsystem
enum DSERR_GENERIC = E_FAIL;

// The caller does not have the priority level required for the function to
// succeed
enum DSERR_PRIOLEVELNEEDED = MAKE_DSHRESULT(70);

// Not enough free memory is available to complete the operation
enum DSERR_OUTOFMEMORY = E_OUTOFMEMORY;

// The specified WAVE format is not supported
enum DSERR_BADFORMAT = MAKE_DSHRESULT(100);

// The function called is not supported at this time
enum DSERR_UNSUPPORTED = E_NOTIMPL;

// No sound driver is available for use
enum DSERR_NODRIVER = MAKE_DSHRESULT(120);

// This object is already initialized
enum DSERR_ALREADYINITIALIZED = MAKE_DSHRESULT(130);

// This object does not support aggregation
enum DSERR_NOAGGREGATION = CLASS_E_NOAGGREGATION;

// The buffer memory has been lost, and must be restored
enum DSERR_BUFFERLOST = MAKE_DSHRESULT(150);

// Another app has a higher priority level, preventing this call from
// succeeding
enum DSERR_OTHERAPPHASPRIO = MAKE_DSHRESULT(160);

// This object has not been initialized
enum DSERR_UNINITIALIZED = MAKE_DSHRESULT(170);

// The requested COM interface is not available
enum DSERR_NOINTERFACE = E_NOINTERFACE;

// Access is denied
enum DSERR_ACCESSDENIED = E_ACCESSDENIED;

// Tried to create a DSBCAPS_CTRLFX buffer shorter than DSBSIZE_FX_MIN milliseconds
enum DSERR_BUFFERTOOSMALL = MAKE_DSHRESULT(180);

// Attempt to use DirectSound 8 functionality on an older DirectSound object
enum DSERR_DS8_REQUIRED = MAKE_DSHRESULT(190);

// A circular loop of send effects was detected
enum DSERR_SENDLOOP = MAKE_DSHRESULT(200);

// The GUID specified in an audiopath file does not match a valid MIXIN buffer
enum DSERR_BADSENDBUFFERGUID = MAKE_DSHRESULT(210);

// The object requested was not found (numerically equal to DMUS_E_NOT_FOUND)
enum DSERR_OBJECTNOTFOUND = MAKE_DSHRESULT(4449);

// The effects requested could not be found on the system, or they were found
// but in the wrong order, or in the wrong hardware/software locations.
enum DSERR_FXUNAVAILABLE = MAKE_DSHRESULT(220);

pragma(lib, "winmm.lib");

alias const(DSCBUFFERDESC)*LPCDSCBUFFERDESC;

alias LPDIRECTSOUNDCAPTUREBUFFER = IDirectSoundCaptureBuffer;

struct DSCCAPS
{
    DWORD dwSize;
    DWORD dwFlags;
    DWORD dwFormats;
    DWORD dwChannels;
}


alias LPDSCCAPS = DSCCAPS *;

struct DSCBCAPS
{
    DWORD dwSize;
    DWORD dwFlags;
    DWORD dwBufferBytes;
    DWORD dwReserved;
}


alias LPDSCBCAPS = DSCBCAPS *;

extern (Windows) interface IDirectSoundCaptureBuffer : IUnknown
{
    // IDirectSoundCaptureBuffer methods
    HRESULT GetCaps(LPDSCBCAPS pDSCBCaps);
    HRESULT GetCurrentPosition(LPDWORD pdwCapturePosition, LPDWORD pdwReadPosition);
    HRESULT GetFormat(LPWAVEFORMATEX pwfxFormat, DWORD dwSizeAllocated, LPDWORD pdwSizeWritten);
    HRESULT GetStatus(LPDWORD pdwStatus);
    HRESULT Initialize(LPDIRECTSOUNDCAPTURE pDirectSoundCapture, LPCDSCBUFFERDESC pcDSCBufferDesc);
    HRESULT Lock(DWORD dwOffset, DWORD dwBytes, LPVOID* ppvAudioPtr1, LPDWORD pdwAudioBytes1,
                 LPVOID* ppvAudioPtr2, LPDWORD pdwAudioBytes2, DWORD dwFlags);
    HRESULT Start(DWORD dwFlags);
    HRESULT Stop();
    HRESULT Unlock(LPVOID pvAudioPtr1, DWORD dwAudioBytes1, LPVOID pvAudioPtr2, DWORD dwAudioBytes2);
}

extern (Windows) interface IDirectSoundCapture : IUnknown
{
    HRESULT CreateCaptureBuffer(LPCDSCBUFFERDESC pcDSCBufferDesc, LPDIRECTSOUNDCAPTUREBUFFER* ppDSCBuffer, LPUNKNOWN pUnkOuter);
    HRESULT GetCaps(LPDSCCAPS pDSCCaps);
    HRESULT Initialize(LPCGUID pcGuidDevice);
}

alias LPDIRECTSOUNDCAPTURE = IDirectSoundCapture;

extern (Windows) alias LPDSENUMCALLBACKW = BOOL function(LPGUID, LPCWSTR, LPCWSTR, LPVOID);
extern (Windows) HRESULT DirectSoundEnumerateW(LPDSENUMCALLBACKW pDSEnumCallback, LPVOID pContext);
extern (Windows) HRESULT DirectSoundCaptureCreate(LPCGUID pcGuidDevice, LPDIRECTSOUNDCAPTURE* ppDSC, LPUNKNOWN pUnkOuter);

alias DirectSoundEnumerate = DirectSoundEnumerateW;

extern(Windows) HRESULT DirectSoundCaptureEnumerateW(LPDSENUMCALLBACKW pDSEnumCallback, LPVOID pContext);
alias DirectSoundCaptureEnumerate = DirectSoundCaptureEnumerateW;

void push_back(T, T2) (ref T[] arr, T2 elem)
{
    arr ~= elem;
}

DWORD dsPointerBetween() (DWORD pointer, DWORD laterPointer, DWORD earlierPointer, DWORD bufferSize)
{
    if (pointer > bufferSize)
        pointer -= bufferSize;

    if (laterPointer < earlierPointer)
        laterPointer += bufferSize;

    if (pointer < earlierPointer)
        pointer += bufferSize;

    return pointer >= earlierPointer && pointer < laterPointer;
}

// A structure to hold various information related to the DirectSound
// API implementation.
struct DsHandle
{
    uint drainCounter;  // Tracks callback counts when draining
    bool internalDrain; // Indicates if stop is initiated from callback or not.
    void* id[2];
    void* buffer[2];
    bool xrun[2];
    UINT bufferPointer[2];
    DWORD dsBufferSize[2];
    DWORD dsPointerLeadTime[2]; // the number of bytes ahead of the safe pointer to lead by.
    HANDLE condition;
}


struct DsDevice
{
    LPGUID[2] id;
    bool[2] validId;
    bool found;
    string name;
}


struct DsProbeData
{
    bool isInput;
    DsDevice[] dsDevices;
}


class RtApiDs : RtApi
{
    override Api getCurrentApi()
    {
        return Api.WINDOWS_DS;
    }

    // This function is intended for internal use only.  It must be
    // public because it is called by the internal callback handler,
    // which is not a member of RtAudio.  External use of this function
    // will most likely produce highly undesireable results!
    void callbackEvent();

    this()
    {
        // Dsound will run both-threaded. If CoInitialize fails, then just
        // accept whatever the mainline chose for a threading model.
        coInitialized_ = false;
        HRESULT hr = CoInitialize(null);

        if (!FAILED(hr))
            coInitialized_ = true;
    }

    ~this()
    {
        if (coInitialized_)
            CoUninitialize();                 // balanced call.

        if (_stream.state != StreamState.STREAM_CLOSED)
            closeStream();
    }

    // The DirectSound default output is always the first device.
    override uint getDefaultOutputDevice()
    {
        return 0;
    }

    // The DirectSound default input is always the first input device,
    // which is the first capture device enumerated.
    override uint getDefaultInputDevice()
    {
        return 0;
    }

    override uint getDeviceCount()
    {
        // Set query flag for previously found devices to false, so that we
        // can check for any devices that have disappeared.
        for (uint i = 0; i < dsDevices.length; i++)
            dsDevices[i].found = false;

        // Query DirectSound devices.
        DsProbeData probeInfo;
        probeInfo.isInput   = false;
        probeInfo.dsDevices = dsDevices;

        HRESULT result = DirectSoundEnumerate(&deviceQueryCallback, &probeInfo);

        if (FAILED(result))
        {
            // errorStream_ << "getDeviceCount: error (" << getErrorString(result) << ") enumerating output devices!";
            // errorText_ = errorStream_.str();
            error(RtErrorType.WARNING);
        }

        // Query DirectSoundCapture devices.
        probeInfo.isInput = true;
        result = DirectSoundCaptureEnumerate(&deviceQueryCallback, &probeInfo);

        if (FAILED(result) )
        {
            // errorStream_ << "getDeviceCount: error (" << getErrorString(result) << ") enumerating input devices!";
            // errorText_ = errorStream_.str();
            error(RtErrorType.WARNING);
        }

        // Clean out any devices that may have disappeared.
        dsDevices = probeInfo.dsDevices.filter!(d => d.found == true).array;

        return dsDevices.length;
    }

    override DeviceInfo getDeviceInfo(uint device)
    {
        DeviceInfo info;
        info.probed = false;

        if (dsDevices.length == 0)
        {
            // Force a query of all devices
            getDeviceCount();

            if (dsDevices.length == 0)
            {
                errorText_ = "getDeviceInfo: no devices found!";
                error(RtErrorType.INVALID_USE);
                return info;
            }
        }

        if (device >= dsDevices.length)
        {
            errorText_ = "getDeviceInfo: device ID is invalid!";
            error(RtErrorType.INVALID_USE);
            return info;
        }

        HRESULT result;
        LPDIRECTSOUND output;
        DSCAPS outCaps;

        if (dsDevices[ device ].validId[0] == false)
            goto probeInput;

        result = DirectSoundCreate(dsDevices[ device ].id[0], &output, null);

        if (FAILED(result) )
        {
            // errorStream_ << "getDeviceInfo: error (" << getErrorString(result) << ") opening output device (" << dsDevices[ device ].name << ")!";
            // errorText_ = errorStream_.str();
            error(RtErrorType.WARNING);
            goto probeInput;
        }

        outCaps.dwSize = outCaps.sizeof;
        result         = output.GetCaps(&outCaps);

        if (FAILED(result) )
        {
            output.Release();

            // errorStream_ << "getDeviceInfo: error (" << getErrorString(result) << ") getting capabilities!";
            // errorText_ = errorStream_.str();
            error(RtErrorType.WARNING);
            goto probeInput;
        }

        // Get output channel information.
        info.outputChannels = ( outCaps.dwFlags & DSCAPS_PRIMARYSTEREO ) ? 2 : 1;

        // Get sample rate information.
        info.sampleRates.clear();

        for (uint k = 0; k < MAX_SAMPLE_RATES; k++)
        {
            if (SAMPLE_RATES[k] >= cast(uint)outCaps.dwMinSecondarySampleRate &&
                SAMPLE_RATES[k] <= cast(uint)outCaps.dwMaxSecondarySampleRate)
                info.sampleRates.push_back(SAMPLE_RATES[k]);
        }

        // Get format information.
        if (outCaps.dwFlags & DSCAPS_PRIMARY16BIT)
            info.nativeFormats |= RtAudioFormat.int16;

        if (outCaps.dwFlags & DSCAPS_PRIMARY8BIT)
            info.nativeFormats |= RtAudioFormat.int8;

        output.Release();

        if (getDefaultOutputDevice() == device)
            info.isDefaultOutput = true;

        if (dsDevices[ device ].validId[1] == false)
        {
            info.name   = dsDevices[ device ].name;
            info.probed = true;
            return info;
        }

probeInput:

        LPDIRECTSOUNDCAPTURE input;
        result = DirectSoundCaptureCreate(dsDevices[ device ].id[1], &input, null);

        if (FAILED(result) )
        {
            // errorStream_ << "getDeviceInfo: error (" << getErrorString(result) << ") opening input device (" << dsDevices[ device ].name << ")!";
            // errorText_ = errorStream_.str();
            error(RtErrorType.WARNING);
            return info;
        }

        DSCCAPS inCaps;
        inCaps.dwSize = inCaps.sizeof;
        result        = input.GetCaps(&inCaps);

        if (FAILED(result) )
        {
            input.Release();

            // errorStream_ << "getDeviceInfo: error (" << getErrorString(result) << ") getting object capabilities (" << dsDevices[ device ].name << ")!";
            // errorText_ = errorStream_.str();
            error(RtErrorType.WARNING);
            return info;
        }

        // Get input channel information.
        info.inputChannels = inCaps.dwChannels;

        // Get sample rate and format information.
        uint[] rates;

        if (inCaps.dwChannels >= 2)
        {
            if (inCaps.dwFormats & WAVE_FORMAT_1S16)
                info.nativeFormats |= RtAudioFormat.int16;

            if (inCaps.dwFormats & WAVE_FORMAT_2S16)
                info.nativeFormats |= RtAudioFormat.int16;

            if (inCaps.dwFormats & WAVE_FORMAT_4S16)
                info.nativeFormats |= RtAudioFormat.int16;

            if (inCaps.dwFormats & WAVE_FORMAT_96S16)
                info.nativeFormats |= RtAudioFormat.int16;

            if (inCaps.dwFormats & WAVE_FORMAT_1S08)
                info.nativeFormats |= RtAudioFormat.int8;

            if (inCaps.dwFormats & WAVE_FORMAT_2S08)
                info.nativeFormats |= RtAudioFormat.int8;

            if (inCaps.dwFormats & WAVE_FORMAT_4S08)
                info.nativeFormats |= RtAudioFormat.int8;

            if (inCaps.dwFormats & WAVE_FORMAT_96S08)
                info.nativeFormats |= RtAudioFormat.int8;

            if (info.nativeFormats & RtAudioFormat.int16)
            {
                if (inCaps.dwFormats & WAVE_FORMAT_1S16)
                    rates.push_back(11025);

                if (inCaps.dwFormats & WAVE_FORMAT_2S16)
                    rates.push_back(22050);

                if (inCaps.dwFormats & WAVE_FORMAT_4S16)
                    rates.push_back(44100);

                if (inCaps.dwFormats & WAVE_FORMAT_96S16)
                    rates.push_back(96000);
            }
            else if (info.nativeFormats & RtAudioFormat.int8)
            {
                if (inCaps.dwFormats & WAVE_FORMAT_1S08)
                    rates.push_back(11025);

                if (inCaps.dwFormats & WAVE_FORMAT_2S08)
                    rates.push_back(22050);

                if (inCaps.dwFormats & WAVE_FORMAT_4S08)
                    rates.push_back(44100);

                if (inCaps.dwFormats & WAVE_FORMAT_96S08)
                    rates.push_back(96000);
            }
        }
        else if (inCaps.dwChannels == 1)
        {
            if (inCaps.dwFormats & WAVE_FORMAT_1M16)
                info.nativeFormats |= RtAudioFormat.int16;

            if (inCaps.dwFormats & WAVE_FORMAT_2M16)
                info.nativeFormats |= RtAudioFormat.int16;

            if (inCaps.dwFormats & WAVE_FORMAT_4M16)
                info.nativeFormats |= RtAudioFormat.int16;

            if (inCaps.dwFormats & WAVE_FORMAT_96M16)
                info.nativeFormats |= RtAudioFormat.int16;

            if (inCaps.dwFormats & WAVE_FORMAT_1M08)
                info.nativeFormats |= RtAudioFormat.int8;

            if (inCaps.dwFormats & WAVE_FORMAT_2M08)
                info.nativeFormats |= RtAudioFormat.int8;

            if (inCaps.dwFormats & WAVE_FORMAT_4M08)
                info.nativeFormats |= RtAudioFormat.int8;

            if (inCaps.dwFormats & WAVE_FORMAT_96M08)
                info.nativeFormats |= RtAudioFormat.int8;

            if (info.nativeFormats & RtAudioFormat.int16)
            {
                if (inCaps.dwFormats & WAVE_FORMAT_1M16)
                    rates.push_back(11025);

                if (inCaps.dwFormats & WAVE_FORMAT_2M16)
                    rates.push_back(22050);

                if (inCaps.dwFormats & WAVE_FORMAT_4M16)
                    rates.push_back(44100);

                if (inCaps.dwFormats & WAVE_FORMAT_96M16)
                    rates.push_back(96000);
            }
            else if (info.nativeFormats & RtAudioFormat.int8)
            {
                if (inCaps.dwFormats & WAVE_FORMAT_1M08)
                    rates.push_back(11025);

                if (inCaps.dwFormats & WAVE_FORMAT_2M08)
                    rates.push_back(22050);

                if (inCaps.dwFormats & WAVE_FORMAT_4M08)
                    rates.push_back(44100);

                if (inCaps.dwFormats & WAVE_FORMAT_96M08)
                    rates.push_back(96000);
            }
        }
        else
            info.inputChannels = 0;  // technically, this would be an error

        input.Release();

        if (info.inputChannels == 0)
            return info;

        // Copy the supported rates to the info structure but avoid duplication.
        bool found;

        for (uint i = 0; i < rates.length; i++)
        {
            found = false;

            for (uint j = 0; j < info.sampleRates.length; j++)
            {
                if (rates[i] == info.sampleRates[j])
                {
                    found = true;
                    break;
                }
            }

            if (found == false)
                info.sampleRates.push_back(rates[i]);
        }

        sort(info.sampleRates);

        // If device opens for both playback and capture, we determine the channels.
        if (info.outputChannels > 0 && info.inputChannels > 0)
            info.duplexChannels = (info.outputChannels > info.inputChannels) ? info.inputChannels : info.outputChannels;

        if (device == 0)
            info.isDefaultInput = true;

        // Copy name and return.
        info.name   = dsDevices[ device ].name;
        info.probed = true;
        return info;
    }

    override bool probeDeviceOpen(uint device, StreamMode mode, uint channels,
                                  uint firstChannel, uint sampleRate,
                                  RtAudioFormat format, uint* bufferSize,
                                  StreamOptions* options)
    {
        if (channels + firstChannel > 2)
        {
            errorText_ = "probeDeviceOpen: DirectSound does not support more than 2 channels per device.";
            return FAILURE;
        }

        uint nDevices = dsDevices.length;

        if (nDevices == 0)
        {
            // This should not happen because a check is made before this function is called.
            errorText_ = "probeDeviceOpen: no devices found!";
            return FAILURE;
        }

        if (device >= nDevices)
        {
            // This should not happen because a check is made before this function is called.
            errorText_ = "probeDeviceOpen: device ID is invalid!";
            return FAILURE;
        }

        if (mode == StreamMode.OUTPUT)
        {
            if (dsDevices[ device ].validId[0] == false)
            {
                // errorStream_ << "probeDeviceOpen: device (" << device << ") does not support output!";
                // errorText_ = errorStream_.str();
                return FAILURE;
            }
        }
        else // mode == StreamMode.INPUT
        {
            if (dsDevices[ device ].validId[1] == false)
            {
                // errorStream_ << "probeDeviceOpen: device (" << device << ") does not support input!";
                // errorText_ = errorStream_.str();
                return FAILURE;
            }
        }

        // According to a note in PortAudio, using GetDesktopWindow()
        // instead of GetForegroundWindow() is supposed to avoid problems
        // that occur when the application's window is not the foreground
        // window.  Also, if the application window closes before the
        // DirectSound buffer, DirectSound can crash.  In the past, I had
        // problems when using GetDesktopWindow() but it seems fine now
        // (January 2010).  I'll leave it commented here.
        // HWND hWnd = GetForegroundWindow();
        HWND hWnd = GetDesktopWindow();

        // Check the numberOfBuffers parameter and limit the lowest value to
        // two.  This is a judgement call and a value of two is probably too
        // low for capture, but it should work for playback.
        int nBuffers = 0;

        if (options)
            nBuffers = options.numberOfBuffers;

        if (options && options.flags & StreamFlags.minimize_latency)
            nBuffers = 2;

        if (nBuffers < 2)
            nBuffers = 3;

        // Check the lower range of the user-specified buffer size and set
        // (arbitrarily) to a lower bound of 32.
        if (*bufferSize < 32)
            *bufferSize = 32;

        // Create the wave format structure.  The data format setting will
        // be determined later.
        WAVEFORMATEX waveFormat;
        waveFormat.wFormatTag     = WAVE_FORMAT_PCM;
        waveFormat.nChannels      = cast(ushort)(channels + firstChannel);
        waveFormat.nSamplesPerSec = cast(ulong)sampleRate;

        // Determine the device buffer size. By default, we'll use the value
        // defined above (32K), but we will grow it to make allowances for
        // very large software buffer sizes.
        DWORD dsBufferSize      = MINIMUM_DEVICE_BUFFER_SIZE;
        DWORD dsPointerLeadTime = 0;

        void* ohandle, bhandle;
        HRESULT result;

        if (mode == StreamMode.OUTPUT)
        {
            LPDIRECTSOUND output;
            result = DirectSoundCreate(dsDevices[ device ].id[0], &output, null);

            if (FAILED(result) )
            {
                // errorStream_ << "probeDeviceOpen: error (" << getErrorString(result) << ") opening output device (" << dsDevices[ device ].name << ")!";
                // errorText_ = errorStream_.str();
                return FAILURE;
            }

            DSCAPS outCaps;
            outCaps.dwSize = outCaps.sizeof;
            result         = output.GetCaps(&outCaps);

            if (FAILED(result) )
            {
                output.Release();

                // errorStream_ << "probeDeviceOpen: error (" << getErrorString(result) << ") getting capabilities (" << dsDevices[ device ].name << ")!";
                // errorText_ = errorStream_.str();
                return FAILURE;
            }

            // Check channel information.
            if (channels + firstChannel == 2 && !( outCaps.dwFlags & DSCAPS_PRIMARYSTEREO ) )
            {
                // errorStream_ << "getDeviceInfo: the output device (" << dsDevices[ device ].name << ") does not support stereo playback.";
                // errorText_ = errorStream_.str();
                return FAILURE;
            }

            // Check format information.
            if (format == RtAudioFormat.int16 && outCaps.dwFlags & DSCAPS_PRIMARY16BIT)
            {
                waveFormat.wBitsPerSample  = 16;
                _stream.deviceFormat[mode] = RtAudioFormat.int16;
            }
            else
            if (format == RtAudioFormat.int8 && outCaps.dwFlags & DSCAPS_PRIMARY8BIT)
            {
                waveFormat.wBitsPerSample  = 8;
                _stream.deviceFormat[mode] = RtAudioFormat.int8;
            }
            else
            {
                throw new Exception(std.string.format("Unsupported format: %s", format.to!string));
            }

            _stream.userFormat = format;

            // Update wave format structure and buffer information.
            waveFormat.nBlockAlign     = cast(ushort)(waveFormat.nChannels * waveFormat.wBitsPerSample / 8);
            waveFormat.nAvgBytesPerSec = waveFormat.nSamplesPerSec * waveFormat.nBlockAlign;
            dsPointerLeadTime = nBuffers * (*bufferSize) * (waveFormat.wBitsPerSample / 8) * channels;

            // If the user wants an even bigger buffer, increase the device buffer size accordingly.
            while (dsPointerLeadTime * 2U > dsBufferSize)
                dsBufferSize *= 2;

            // Set cooperative level to DSSCL_EXCLUSIVE ... sound stops when window focus changes.
            // result = output.SetCooperativeLevel( hWnd, DSSCL_EXCLUSIVE );
            // Set cooperative level to DSSCL_PRIORITY ... sound remains when window focus changes.
            result = output.SetCooperativeLevel(hWnd, DSSCL_PRIORITY);

            if (FAILED(result) )
            {
                output.Release();

                // errorStream_ << "probeDeviceOpen: error (" << getErrorString(result) << ") setting cooperative level (" << dsDevices[ device ].name << ")!";
                // errorText_ = errorStream_.str();
                return FAILURE;
            }

            // Even though we will write to the secondary buffer, we need to
            // access the primary buffer to set the correct output format
            // (since the default is 8-bit, 22 kHz!).  Setup the DS primary
            // buffer description.
            DSBUFFERDESC bufferDescription;
            bufferDescription.dwSize  = DSBUFFERDESC.sizeof;
            bufferDescription.dwFlags = DSBCAPS_PRIMARYBUFFER;

            // Obtain the primary buffer
            LPDIRECTSOUNDBUFFER buffer;
            result = output.CreateSoundBuffer(&bufferDescription, &buffer, null);

            if (FAILED(result) )
            {
                output.Release();

                // errorStream_ << "probeDeviceOpen: error (" << getErrorString(result) << ") accessing primary buffer (" << dsDevices[ device ].name << ")!";
                // errorText_ = errorStream_.str();
                return FAILURE;
            }

            // Set the primary DS buffer sound format.
            result = buffer.SetFormat(&waveFormat);

            if (FAILED(result) )
            {
                output.Release();

                // errorStream_ << "probeDeviceOpen: error (" << getErrorString(result) << ") setting primary buffer format (" << dsDevices[ device ].name << ")!";
                // errorText_ = errorStream_.str();
                return FAILURE;
            }

            // Setup the secondary DS buffer description.
            bufferDescription.dwSize  = DSBUFFERDESC.sizeof;
            bufferDescription.dwFlags = ( DSBCAPS_STICKYFOCUS |
                                          DSBCAPS_GLOBALFOCUS |
                                          DSBCAPS_GETCURRENTPOSITION2 |
                                          DSBCAPS_LOCHARDWARE ); // Force hardware mixing
            bufferDescription.dwBufferBytes = dsBufferSize;
            bufferDescription.lpwfxFormat   = &waveFormat;

            // Try to create the secondary DS buffer.  If that doesn't work,
            // try to use software mixing.  Otherwise, there's a problem.
            result = output.CreateSoundBuffer(&bufferDescription, &buffer, null);

            if (FAILED(result) )
            {
                bufferDescription.dwFlags = ( DSBCAPS_STICKYFOCUS |
                                              DSBCAPS_GLOBALFOCUS |
                                              DSBCAPS_GETCURRENTPOSITION2 |
                                              DSBCAPS_LOCSOFTWARE ); // Force software mixing
                result = output.CreateSoundBuffer(&bufferDescription, &buffer, null);

                if (FAILED(result) )
                {
                    output.Release();

                    // errorStream_ << "probeDeviceOpen: error (" << getErrorString(result) << ") creating secondary buffer (" << dsDevices[ device ].name << ")!";
                    // errorText_ = errorStream_.str();
                    return FAILURE;
                }
            }

            // Get the buffer size ... might be different from what we specified.
            DSBCAPS dsbcaps;
            dsbcaps.dwSize = DSBCAPS.sizeof;
            result         = buffer.GetCaps(&dsbcaps);

            if (FAILED(result) )
            {
                output.Release();
                buffer.Release();

                // errorStream_ << "probeDeviceOpen: error (" << getErrorString(result) << ") getting buffer settings (" << dsDevices[ device ].name << ")!";
                // errorText_ = errorStream_.str();
                return FAILURE;
            }

            dsBufferSize = dsbcaps.dwBufferBytes;

            // Lock the DS buffer
            LPVOID audioPtr;
            DWORD  dataLen;
            result = buffer.Lock(0, dsBufferSize, &audioPtr, &dataLen, null, null, 0);

            if (FAILED(result) )
            {
                output.Release();
                buffer.Release();

                // errorStream_ << "probeDeviceOpen: error (" << getErrorString(result) << ") locking buffer (" << dsDevices[ device ].name << ")!";
                // errorText_ = errorStream_.str();
                return FAILURE;
            }

            // Zero the DS buffer
            ZeroMemory(audioPtr, dataLen);

            // Unlock the DS buffer
            result = buffer.Unlock(audioPtr, dataLen, null, 0);

            if (FAILED(result) )
            {
                output.Release();
                buffer.Release();

                // errorStream_ << "probeDeviceOpen: error (" << getErrorString(result) << ") unlocking buffer (" << dsDevices[ device ].name << ")!";
                // errorText_ = errorStream_.str();
                return FAILURE;
            }

            ohandle = cast(void*)output;
            bhandle = cast(void*)buffer;
        }

        if (mode == StreamMode.INPUT)
        {
            LPDIRECTSOUNDCAPTURE input;
            result = DirectSoundCaptureCreate(dsDevices[ device ].id[1], &input, null);

            if (FAILED(result) )
            {
                // errorStream_ << "probeDeviceOpen: error (" << getErrorString(result) << ") opening input device (" << dsDevices[ device ].name << ")!";
                // errorText_ = errorStream_.str();
                return FAILURE;
            }

            DSCCAPS inCaps;
            inCaps.dwSize = inCaps.sizeof;
            result        = input.GetCaps(&inCaps);

            if (FAILED(result) )
            {
                input.Release();

                // errorStream_ << "probeDeviceOpen: error (" << getErrorString(result) << ") getting input capabilities (" << dsDevices[ device ].name << ")!";
                // errorText_ = errorStream_.str();
                return FAILURE;
            }

            // Check channel information.
            if (inCaps.dwChannels < channels + firstChannel)
            {
                errorText_ = "getDeviceInfo: the input device does not support requested input channels.";
                return FAILURE;
            }

            /* Check format information. */

            if (channels + firstChannel == 2)
            {
                enum stereo8bitFormats = WAVE_FORMAT_1S08 | WAVE_FORMAT_2S08 | WAVE_FORMAT_4S08 | WAVE_FORMAT_96S08;
                enum stereo16bitFormats = WAVE_FORMAT_1S16 | WAVE_FORMAT_2S16 | WAVE_FORMAT_4S16 | WAVE_FORMAT_96S16;

                if (format == RtAudioFormat.int8 && inCaps.dwFormats & stereo8bitFormats)
                {
                    waveFormat.wBitsPerSample  = 8;
                    _stream.deviceFormat[mode] = RtAudioFormat.int8;
                }
                else
                if (format == RtAudioFormat.int16 && inCaps.dwFormats & stereo16bitFormats)
                {
                    waveFormat.wBitsPerSample  = 16;
                    _stream.deviceFormat[mode] = RtAudioFormat.int16;
                }
                else
                {
                    throw new Exception(std.string.format("Unsupported format: %s", format.to!string));
                }
            }
            else // channel == 1
            {
                enum mono8bitFormats = WAVE_FORMAT_1M08 | WAVE_FORMAT_2M08 | WAVE_FORMAT_4M08 | WAVE_FORMAT_96M08;
                enum mono16bitFormats = WAVE_FORMAT_1M16 | WAVE_FORMAT_2M16 | WAVE_FORMAT_4M16 | WAVE_FORMAT_96M16;

                if (format == RtAudioFormat.int8 && inCaps.dwFormats & mono8bitFormats)
                {
                    waveFormat.wBitsPerSample  = 8;
                    _stream.deviceFormat[mode] = RtAudioFormat.int8;
                }
                else
                if (format == RtAudioFormat.int16 && inCaps.dwFormats & mono16bitFormats)
                {
                    waveFormat.wBitsPerSample  = 16;
                    _stream.deviceFormat[mode] = RtAudioFormat.int16;
                }
                else
                {
                    throw new Exception(std.string.format("Unsupported format: %s", format.to!string));
                }
            }
            _stream.userFormat = format;

            // Update wave format structure and buffer information.
            waveFormat.nBlockAlign     = cast(ushort)(waveFormat.nChannels * waveFormat.wBitsPerSample / 8);
            waveFormat.nAvgBytesPerSec = waveFormat.nSamplesPerSec * waveFormat.nBlockAlign;
            dsPointerLeadTime = nBuffers * (*bufferSize) * (waveFormat.wBitsPerSample / 8) * channels;

            // If the user wants an even bigger buffer, increase the device buffer size accordingly.
            while (dsPointerLeadTime * 2U > dsBufferSize)
                dsBufferSize *= 2;

            // Setup the secondary DS buffer description.
            DSCBUFFERDESC bufferDescription;
            bufferDescription.dwSize        = DSCBUFFERDESC.sizeof;
            bufferDescription.dwFlags       = 0;
            bufferDescription.dwReserved    = 0;
            bufferDescription.dwBufferBytes = dsBufferSize;
            bufferDescription.lpwfxFormat   = &waveFormat;

            // Create the capture buffer.
            LPDIRECTSOUNDCAPTUREBUFFER buffer;
            result = input.CreateCaptureBuffer(&bufferDescription, &buffer, null);

            if (FAILED(result) )
            {
                input.Release();

                // errorStream_ << "probeDeviceOpen: error (" << getErrorString(result) << ") creating input buffer (" << dsDevices[ device ].name << ")!";
                // errorText_ = errorStream_.str();
                return FAILURE;
            }

            // Get the buffer size ... might be different from what we specified.
            DSCBCAPS dscbcaps;
            dscbcaps.dwSize = DSCBCAPS.sizeof;
            result = buffer.GetCaps(&dscbcaps);

            if (FAILED(result) )
            {
                input.Release();
                buffer.Release();

                // errorStream_ << "probeDeviceOpen: error (" << getErrorString(result) << ") getting buffer settings (" << dsDevices[ device ].name << ")!";
                // errorText_ = errorStream_.str();
                return FAILURE;
            }

            dsBufferSize = dscbcaps.dwBufferBytes;

            // NOTE: We could have a problem here if this is a duplex stream
            // and the play and capture hardware buffer sizes are different
            // (I'm actually not sure if that is a problem or not).
            // Currently, we are not verifying that.

            // Lock the capture buffer
            LPVOID audioPtr;
            DWORD  dataLen;
            result = buffer.Lock(0, dsBufferSize, &audioPtr, &dataLen, null, null, 0);

            if (FAILED(result) )
            {
                input.Release();
                buffer.Release();

                // errorStream_ << "probeDeviceOpen: error (" << getErrorString(result) << ") locking input buffer (" << dsDevices[ device ].name << ")!";
                // errorText_ = errorStream_.str();
                return FAILURE;
            }

            // Zero the buffer
            ZeroMemory(audioPtr, dataLen);

            // Unlock the buffer
            result = buffer.Unlock(audioPtr, dataLen, null, 0);

            if (FAILED(result) )
            {
                input.Release();
                buffer.Release();

                // errorStream_ << "probeDeviceOpen: error (" << getErrorString(result) << ") unlocking input buffer (" << dsDevices[ device ].name << ")!";
                // errorText_ = errorStream_.str();
                return FAILURE;
            }

            ohandle = cast(void*)input;
            bhandle = cast(void*)buffer;
        }

        // Set various stream parameters
        DsHandle* handle = null;
        _stream.nDeviceChannels[mode] = channels + firstChannel;
        _stream.nUserChannels[mode]   = channels;
        _stream.bufferSize = *bufferSize;
        _stream.channelOffset[mode]     = firstChannel;
        _stream.deviceInterleaved[mode] = true;

        if (options && options.flags & StreamFlags.non_interleaved)
            _stream.userInterleaved = false;
        else
            _stream.userInterleaved = true;

        // Set flag for buffer conversion
        _stream.doConvertBuffer[mode] = false;

        if (_stream.nUserChannels[mode] != _stream.nDeviceChannels[mode])
            _stream.doConvertBuffer[mode] = true;

        if (_stream.userFormat != _stream.deviceFormat[mode])
            _stream.doConvertBuffer[mode] = true;

        if (_stream.userInterleaved != _stream.deviceInterleaved[mode] &&
            _stream.nUserChannels[mode] > 1)
            _stream.doConvertBuffer[mode] = true;

        // Allocate necessary internal buffers
        size_t bufferBytes = _stream.nUserChannels[mode] * (*bufferSize) * formatBytes(_stream.userFormat);
        _stream.userBuffer[mode] = enforce(cast(ubyte*)calloc(bufferBytes, 1));

        if (_stream.userBuffer[mode] is null)
        {
            errorText_ = "probeDeviceOpen: error allocating user buffer memory.";
            goto error;
        }

        if (_stream.doConvertBuffer[mode])
        {
            bool makeBuffer = true;
            bufferBytes = _stream.nDeviceChannels[mode] * formatBytes(_stream.deviceFormat[mode]);

            if (mode == StreamMode.INPUT)
            {
                if (_stream.mode == StreamMode.OUTPUT && _stream.deviceBuffer)
                {
                    ulong bytesOut = _stream.nDeviceChannels[0] * formatBytes(_stream.deviceFormat[0]);

                    if (bufferBytes <= cast(long)bytesOut)
                        makeBuffer = false;
                }
            }

            if (makeBuffer)
            {
                bufferBytes *= *bufferSize;

                if (_stream.deviceBuffer)
                    free(_stream.deviceBuffer);
                _stream.deviceBuffer = enforce(cast(ubyte*)calloc(bufferBytes, 1));

                if (_stream.deviceBuffer is null)
                {
                    errorText_ = "probeDeviceOpen: error allocating device buffer memory.";
                    goto error;
                }
            }
        }

        // Allocate our DsHandle structures for the stream.
        if (_stream.apiHandle is null)
        {
            handle = new DsHandle;

            // Create a manual-reset event.
            handle.condition = CreateEvent(null,  // no security
                                           TRUE,  // manual-reset
                                           FALSE, // non-signaled initially
                                           null); // unnamed
            _stream.apiHandle = cast(void*)handle;
        }
        else
            handle = cast(DsHandle*)_stream.apiHandle;

        handle.id[mode]     = ohandle;
        handle.buffer[mode] = bhandle;
        handle.dsBufferSize[mode]      = dsBufferSize;
        handle.dsPointerLeadTime[mode] = dsPointerLeadTime;

        _stream.device[mode] = device;
        _stream.state        = StreamState.STREAM_STOPPED;

        if (_stream.mode == StreamMode.OUTPUT && mode == StreamMode.INPUT)
            // We had already set up an output stream.
            _stream.mode = StreamMode.DUPLEX;
        else
            _stream.mode = mode;
        _stream.nBuffers   = nBuffers;
        _stream.sampleRate = sampleRate;

        // Setup the buffer conversion information structure.
        if (_stream.doConvertBuffer[mode])
            setConvertInfo(mode, firstChannel);

        static class DerivedThread : Thread
        {
            this(CallbackInfo* info)
            {
                this.info = info;
                super(&run);
            }

            CallbackInfo* info;

            void run()
            {
                RtApiDs object = cast(RtApiDs)info.object;

                while (info.isRunning)
                {
                    object.callbackEvent();
                }
            }
        }

        void threadFunc()
        {
            printf("Composed thread running.\n");
        }

        // Setup the callback thread.
        if (!_stream.callbackInfo.isRunning)
        {
            _stream.callbackInfo.isRunning = true;
            _stream.callbackInfo.object    = cast(void*)this;

            auto thread = new DerivedThread(&_stream.callbackInfo);
            thread.start();

            // ~ thread.priority = Thread.PRIORITY_MAX;
            _stream.callbackInfo.thread = thread;
        }
        return SUCCESS;

error:

        if (handle)
        {
            if (handle.buffer[0]) // the object pointer can be null and valid
            {
                LPDIRECTSOUND object       = cast(LPDIRECTSOUND)handle.id[0];
                LPDIRECTSOUNDBUFFER buffer = cast(LPDIRECTSOUNDBUFFER)handle.buffer[0];

                if (buffer)
                    buffer.Release();
                object.Release();
            }

            if (handle.buffer[1])
            {
                LPDIRECTSOUNDCAPTURE object       = cast(LPDIRECTSOUNDCAPTURE)handle.id[1];
                LPDIRECTSOUNDCAPTUREBUFFER buffer = cast(LPDIRECTSOUNDCAPTUREBUFFER)handle.buffer[1];

                if (buffer)
                    buffer.Release();
                object.Release();
            }
            CloseHandle(handle.condition);
            destroy(handle);
            _stream.apiHandle = null;
        }

        for (int i = 0; i < 2; i++)
        {
            if (_stream.userBuffer[i])
            {
                free(_stream.userBuffer[i]);
                _stream.userBuffer[i] = null;
            }
        }

        if (_stream.deviceBuffer)
        {
            free(_stream.deviceBuffer);
            _stream.deviceBuffer = null;
        }

        _stream.state = StreamState.STREAM_CLOSED;
        return FAILURE;
    }

    override void closeStream()
    {
        if (_stream.state == StreamState.STREAM_CLOSED)
        {
            errorText_ = "closeStream(): no open stream to close!";
            error(RtErrorType.WARNING);
            return;
        }

        // Stop the callback thread.
        _stream.callbackInfo.isRunning = false;

        thread_joinAll();

        DsHandle* handle = cast(DsHandle*)_stream.apiHandle;

        if (handle)
        {
            if (handle.buffer[0]) // the object pointer can be null and valid
            {
                LPDIRECTSOUND object       = cast(LPDIRECTSOUND)handle.id[0];
                LPDIRECTSOUNDBUFFER buffer = cast(LPDIRECTSOUNDBUFFER)handle.buffer[0];

                if (buffer)
                {
                    buffer.Stop();
                    buffer.Release();
                }
                object.Release();
            }

            if (handle.buffer[1])
            {
                LPDIRECTSOUNDCAPTURE object       = cast(LPDIRECTSOUNDCAPTURE)handle.id[1];
                LPDIRECTSOUNDCAPTUREBUFFER buffer = cast(LPDIRECTSOUNDCAPTUREBUFFER)handle.buffer[1];

                if (buffer)
                {
                    buffer.Stop();
                    buffer.Release();
                }
                object.Release();
            }
            CloseHandle(handle.condition);
            destroy(handle);
            _stream.apiHandle = null;
        }

        for (int i = 0; i < 2; i++)
        {
            if (_stream.userBuffer[i])
            {
                free(_stream.userBuffer[i]);
                _stream.userBuffer[i] = null;
            }
        }

        if (_stream.deviceBuffer)
        {
            free(_stream.deviceBuffer);
            _stream.deviceBuffer = null;
        }

        _stream.mode  = StreamMode.UNINITIALIZED;
        _stream.state = StreamState.STREAM_CLOSED;
    }

    override void startStream()
    {
        verifyStream();

        if (_stream.state == StreamState.STREAM_RUNNING)
        {
            errorText_ = "startStream(): the stream is already running!";
            error(RtErrorType.WARNING);
            return;
        }

        DsHandle* handle = cast(DsHandle*)_stream.apiHandle;

        // Increase scheduler frequency on older windows (a side-effect of
        // increasing timer accuracy).  On newer windows (Win2K or later),
        // this is already in effect.
        timeBeginPeriod(1);

        buffersRolling     = false;
        duplexPrerollBytes = 0;

        if (_stream.mode == StreamMode.DUPLEX)
        {
            // 0.5 seconds of silence in StreamMode.DUPLEX mode while the devices spin up and synchronize.
            duplexPrerollBytes = cast(int)(0.5 * _stream.sampleRate * formatBytes(_stream.deviceFormat[1]) * _stream.nDeviceChannels[1]);
        }

        HRESULT result = 0;

        if (_stream.mode == StreamMode.OUTPUT || _stream.mode == StreamMode.DUPLEX)
        {
            LPDIRECTSOUNDBUFFER buffer = cast(LPDIRECTSOUNDBUFFER)handle.buffer[0];
            result = buffer.Play(0, 0, DSBPLAY_LOOPING);

            if (FAILED(result) )
            {
                // errorStream_ << "startStream: error (" << getErrorString(result) << ") starting output buffer!";
                // errorText_ = errorStream_.str();
                goto unlock;
            }
        }

        if (_stream.mode == StreamMode.INPUT || _stream.mode == StreamMode.DUPLEX)
        {
            LPDIRECTSOUNDCAPTUREBUFFER buffer = cast(LPDIRECTSOUNDCAPTUREBUFFER)handle.buffer[1];
            result = buffer.Start(DSCBSTART_LOOPING);

            if (FAILED(result) )
            {
                // errorStream_ << "startStream: error (" << getErrorString(result) << ") starting input buffer!";
                // errorText_ = errorStream_.str();
                goto unlock;
            }
        }

        handle.drainCounter  = 0;
        handle.internalDrain = false;
        ResetEvent(handle.condition);
        _stream.state = StreamState.STREAM_RUNNING;

unlock:

        if (FAILED(result) )
            error(RtErrorType.SYSTEM_ERROR);
    }

    override void stopStream()
    {
        verifyStream();

        if (_stream.state == StreamState.STREAM_STOPPED)
        {
            errorText_ = "stopStream(): the stream is already stopped!";
            error(RtErrorType.WARNING);
            return;
        }

        HRESULT result = 0;
        LPVOID  audioPtr;
        DWORD dataLen;
        DsHandle* handle = cast(DsHandle*)_stream.apiHandle;

        if (_stream.mode == StreamMode.OUTPUT || _stream.mode == StreamMode.DUPLEX)
        {
            if (handle.drainCounter == 0)
            {
                handle.drainCounter = 2;
                WaitForSingleObject(handle.condition, INFINITE); // block until signaled
            }

            _stream.state = StreamState.STREAM_STOPPED;

            // Stop the buffer and clear memory
            LPDIRECTSOUNDBUFFER buffer = cast(LPDIRECTSOUNDBUFFER)handle.buffer[0];
            result = buffer.Stop();

            if (FAILED(result) )
            {
                // errorStream_ << "stopStream: error (" << getErrorString(result) << ") stopping output buffer!";
                // errorText_ = errorStream_.str();
                goto unlock;
            }

            // Lock the buffer and clear it so that if we start to play again,
            // we won't have old data playing.
            result = buffer.Lock(0, handle.dsBufferSize[0], &audioPtr, &dataLen, null, null, 0);

            if (FAILED(result) )
            {
                // errorStream_ << "stopStream: error (" << getErrorString(result) << ") locking output buffer!";
                // errorText_ = errorStream_.str();
                goto unlock;
            }

            // Zero the DS buffer
            ZeroMemory(audioPtr, dataLen);

            // Unlock the DS buffer
            result = buffer.Unlock(audioPtr, dataLen, null, 0);

            if (FAILED(result) )
            {
                // errorStream_ << "stopStream: error (" << getErrorString(result) << ") unlocking output buffer!";
                // errorText_ = errorStream_.str();
                goto unlock;
            }

            // If we start playing again, we must begin at beginning of buffer.
            handle.bufferPointer[0] = 0;
        }

        if (_stream.mode == StreamMode.INPUT || _stream.mode == StreamMode.DUPLEX)
        {
            LPDIRECTSOUNDCAPTUREBUFFER buffer = cast(LPDIRECTSOUNDCAPTUREBUFFER)handle.buffer[1];
            audioPtr = null;
            dataLen  = 0;

            _stream.state = StreamState.STREAM_STOPPED;

            result = buffer.Stop();

            if (FAILED(result) )
            {
                // errorStream_ << "stopStream: error (" << getErrorString(result) << ") stopping input buffer!";
                // errorText_ = errorStream_.str();
                goto unlock;
            }

            // Lock the buffer and clear it so that if we start to play again,
            // we won't have old data playing.
            result = buffer.Lock(0, handle.dsBufferSize[1], &audioPtr, &dataLen, null, null, 0);

            if (FAILED(result) )
            {
                // errorStream_ << "stopStream: error (" << getErrorString(result) << ") locking input buffer!";
                // errorText_ = errorStream_.str();
                goto unlock;
            }

            // Zero the DS buffer
            ZeroMemory(audioPtr, dataLen);

            // Unlock the DS buffer
            result = buffer.Unlock(audioPtr, dataLen, null, 0);

            if (FAILED(result) )
            {
                // errorStream_ << "stopStream: error (" << getErrorString(result) << ") unlocking input buffer!";
                // errorText_ = errorStream_.str();
                goto unlock;
            }

            // If we start recording again, we must begin at beginning of buffer.
            handle.bufferPointer[1] = 0;
        }

unlock:
        timeEndPeriod(1); // revert to normal scheduler frequency on lesser windows.

        if (FAILED(result) )
            error(RtErrorType.SYSTEM_ERROR);
    }

    override void abortStream()
    {
        verifyStream();

        if (_stream.state == StreamState.STREAM_STOPPED)
        {
            errorText_ = "abortStream(): the stream is already stopped!";
            error(RtErrorType.WARNING);
            return;
        }

        DsHandle* handle = cast(DsHandle*)_stream.apiHandle;
        handle.drainCounter = 2;

        stopStream();
    }

    void callbackEvent()
    {
        if (_stream.state == StreamState.STREAM_STOPPED || _stream.state == StreamState.STREAM_STOPPING)
        {
            Sleep(50); // sleep 50 milliseconds
            return;
        }

        if (_stream.state == StreamState.STREAM_CLOSED)
        {
            errorText_ = "callbackEvent(): the stream is closed ... this shouldn't happen!";
            error(RtErrorType.WARNING);
            return;
        }

        CallbackInfo* info = cast(CallbackInfo*)&_stream.callbackInfo;
        DsHandle* handle   = cast(DsHandle*)_stream.apiHandle;

        // Check if we were draining the stream and signal is finished.
        if (handle.drainCounter > _stream.nBuffers + 2)
        {
            _stream.state = StreamState.STREAM_STOPPING;

            if (handle.internalDrain == false)
                SetEvent(handle.condition);
            else
                stopStream();
            return;
        }

        // Invoke user callback to get fresh output data UNLESS we are
        // draining stream.
        if (handle.drainCounter == 0)
        {
            RtAudioCallback callback = cast(RtAudioCallback)info.callback;
            double streamTime        = getStreamTime();
            RtAudioStreamStatus status;

            if (_stream.mode != StreamMode.INPUT && handle.xrun[0] == true)
            {
                status        |= RtAudioStreamStatus.output_underflow;
                handle.xrun[0] = false;
            }

            if (_stream.mode != StreamMode.OUTPUT && handle.xrun[1] == true)
            {
                status        |= RtAudioStreamStatus.input_overflow;
                handle.xrun[1] = false;
            }

            int cbReturnValue = callback(_stream.userBuffer[0], _stream.userBuffer[1],
                                         _stream.bufferSize, streamTime, status, info.userData);

            if (cbReturnValue == 2)
            {
                _stream.state       = StreamState.STREAM_STOPPING;
                handle.drainCounter = 2;
                abortStream();
                return;
            }
            else if (cbReturnValue == 1)
            {
                handle.drainCounter  = 1;
                handle.internalDrain = true;
            }
        }

        HRESULT result;
        DWORD currentWritePointer, safeWritePointer;
        DWORD currentReadPointer, safeReadPointer;
        UINT  nextWritePointer;

        LPVOID buffer1     = null;
        LPVOID buffer2     = null;
        DWORD  bufferSize1 = 0;
        DWORD  bufferSize2 = 0;

        ubyte* buffer;
        size_t bufferBytes;

        if (buffersRolling == false)
        {
            if (_stream.mode == StreamMode.DUPLEX)
            {
                // assert( handle.dsBufferSize[0] == handle.dsBufferSize[1] );

                // It takes a while for the devices to get rolling. As a result,
                // there's no guarantee that the capture and write device pointers
                // will move in lockstep.  Wait here for both devices to start
                // rolling, and then set our buffer pointers accordingly.
                // e.g. Crystal Drivers: the capture buffer starts up 5700 to 9600
                // bytes later than the write buffer.

                // Stub: a serious risk of having a pre-emptive scheduling round
                // take place between the two GetCurrentPosition calls... but I'm
                // really not sure how to solve the problem.  Temporarily boost to
                // Realtime priority, maybe; but I'm not sure what priority the
                // DirectSound service threads run at. We *should* be roughly
                // within a ms or so of correct.

                LPDIRECTSOUNDBUFFER dsWriteBuffer = cast(LPDIRECTSOUNDBUFFER)handle.buffer[0];
                LPDIRECTSOUNDCAPTUREBUFFER dsCaptureBuffer = cast(LPDIRECTSOUNDCAPTUREBUFFER)handle.buffer[1];

                DWORD startSafeWritePointer, startSafeReadPointer;

                result = dsWriteBuffer.GetCurrentPosition(null, &startSafeWritePointer);

                if (FAILED(result) )
                {
                    // errorStream_ << "callbackEvent: error (" << getErrorString(result) << ") getting current write position!";
                    // errorText_ = errorStream_.str();
                    error(RtErrorType.SYSTEM_ERROR);
                    return;
                }
                result = dsCaptureBuffer.GetCurrentPosition(null, &startSafeReadPointer);

                if (FAILED(result) )
                {
                    // errorStream_ << "callbackEvent: error (" << getErrorString(result) << ") getting current read position!";
                    // errorText_ = errorStream_.str();
                    error(RtErrorType.SYSTEM_ERROR);
                    return;
                }

                while (true)
                {
                    result = dsWriteBuffer.GetCurrentPosition(null, &safeWritePointer);

                    if (FAILED(result) )
                    {
                        // errorStream_ << "callbackEvent: error (" << getErrorString(result) << ") getting current write position!";
                        // errorText_ = errorStream_.str();
                        error(RtErrorType.SYSTEM_ERROR);
                        return;
                    }
                    result = dsCaptureBuffer.GetCurrentPosition(null, &safeReadPointer);

                    if (FAILED(result) )
                    {
                        // errorStream_ << "callbackEvent: error (" << getErrorString(result) << ") getting current read position!";
                        // errorText_ = errorStream_.str();
                        error(RtErrorType.SYSTEM_ERROR);
                        return;
                    }

                    if (safeWritePointer != startSafeWritePointer && safeReadPointer != startSafeReadPointer)
                        break;
                    Sleep(1);
                }

                // assert( handle.dsBufferSize[0] == handle.dsBufferSize[1] );

                handle.bufferPointer[0] = safeWritePointer + handle.dsPointerLeadTime[0];

                if (handle.bufferPointer[0] >= handle.dsBufferSize[0])
                    handle.bufferPointer[0] -= handle.dsBufferSize[0];
                handle.bufferPointer[1] = safeReadPointer;
            }
            else if (_stream.mode == StreamMode.OUTPUT)
            {
                // Set the proper nextWritePosition after initial startup.
                LPDIRECTSOUNDBUFFER dsWriteBuffer = cast(LPDIRECTSOUNDBUFFER)handle.buffer[0];
                result = dsWriteBuffer.GetCurrentPosition(&currentWritePointer, &safeWritePointer);

                if (FAILED(result) )
                {
                    // errorStream_ << "callbackEvent: error (" << getErrorString(result) << ") getting current write position!";
                    // errorText_ = errorStream_.str();
                    error(RtErrorType.SYSTEM_ERROR);
                    return;
                }
                handle.bufferPointer[0] = safeWritePointer + handle.dsPointerLeadTime[0];

                if (handle.bufferPointer[0] >= handle.dsBufferSize[0])
                    handle.bufferPointer[0] -= handle.dsBufferSize[0];
            }

            buffersRolling = true;
        }

        if (_stream.mode == StreamMode.OUTPUT || _stream.mode == StreamMode.DUPLEX)
        {
            LPDIRECTSOUNDBUFFER dsBuffer = cast(LPDIRECTSOUNDBUFFER)handle.buffer[0];

            if (handle.drainCounter > 1) // write zeros to the output stream
            {
                bufferBytes  = _stream.bufferSize * _stream.nUserChannels[0];
                bufferBytes *= formatBytes(_stream.userFormat);
                memset(_stream.userBuffer[0], 0, cast(size_t)bufferBytes);
            }

            // Setup parameters and do buffer conversion if necessary.
            if (_stream.doConvertBuffer[0])
            {
                buffer = _stream.deviceBuffer;
                convertBuffer(buffer, _stream.userBuffer[0], _stream.convertInfo[0]);
                bufferBytes  = _stream.bufferSize * _stream.nDeviceChannels[0];
                bufferBytes *= formatBytes(_stream.deviceFormat[0]);
            }
            else
            {
                buffer       = _stream.userBuffer[0];
                bufferBytes  = _stream.bufferSize * _stream.nUserChannels[0];
                bufferBytes *= formatBytes(_stream.userFormat);
            }

            // No byte swapping necessary in DirectSound implementation.

            // Ahhh ... windoze.  16-bit data is signed but 8-bit data is
            // unsigned.  So, we need to convert our signed 8-bit data here to
            // unsigned.
            if (_stream.deviceFormat[0] == RtAudioFormat.int8)
                for (int i = 0; i < bufferBytes; i++)
                    buffer[i] = cast(ubyte)(buffer[i] + 128);

            DWORD dsBufferSize = handle.dsBufferSize[0];
            nextWritePointer = handle.bufferPointer[0];

            DWORD endWrite, leadPointer;

            while (true)
            {
                // Find out where the read and "safe write" pointers are.
                result = dsBuffer.GetCurrentPosition(&currentWritePointer, &safeWritePointer);

                if (FAILED(result) )
                {
                    // errorStream_ << "callbackEvent: error (" << getErrorString(result) << ") getting current write position!";
                    // errorText_ = errorStream_.str();
                    error(RtErrorType.SYSTEM_ERROR);
                    return;
                }

                // We will copy our output buffer into the region between
                // safeWritePointer and leadPointer.  If leadPointer is not
                // beyond the next endWrite position, wait until it is.
                leadPointer = safeWritePointer + handle.dsPointerLeadTime[0];

                // writeln("safeWritePointer = " << safeWritePointer << ", leadPointer = " << leadPointer << ", nextWritePointer = " << nextWritePointer);
                if (leadPointer > dsBufferSize)
                    leadPointer -= dsBufferSize;

                if (leadPointer < nextWritePointer)
                    leadPointer += dsBufferSize;                             // unwrap offset
                endWrite = nextWritePointer + bufferBytes;

                // Check whether the entire write region is behind the play pointer.
                if (leadPointer >= endWrite)
                    break;

                // If we are here, then we must wait until the leadPointer advances
                // beyond the end of our next write region. We use the
                // Sleep() function to suspend operation until that happens.
                double millis = ( endWrite - leadPointer ) * 1000.0;
                millis /= ( formatBytes(_stream.deviceFormat[0]) * _stream.nDeviceChannels[0] * _stream.sampleRate);

                if (millis < 1.0)
                    millis = 1.0;
                Sleep(cast(DWORD)millis);
            }

            if (dsPointerBetween(nextWritePointer, safeWritePointer, currentWritePointer, dsBufferSize)
                || dsPointerBetween(endWrite, safeWritePointer, currentWritePointer, dsBufferSize) )
            {
                // We've strayed into the forbidden zone ... resync the read pointer.
                handle.xrun[0]   = true;
                nextWritePointer = safeWritePointer + handle.dsPointerLeadTime[0] - bufferBytes;

                if (nextWritePointer >= dsBufferSize)
                    nextWritePointer -= dsBufferSize;
                handle.bufferPointer[0] = nextWritePointer;
                endWrite = nextWritePointer + bufferBytes;
            }

            // Lock free space in the buffer
            result = dsBuffer.Lock(nextWritePointer, bufferBytes, &buffer1,
                                   &bufferSize1, &buffer2, &bufferSize2, 0);

            if (FAILED(result) )
            {
                // errorStream_ << "callbackEvent: error (" << getErrorString(result) << ") locking buffer during playback!";
                // errorText_ = errorStream_.str();
                error(RtErrorType.SYSTEM_ERROR);
                return;
            }

            // Copy our buffer into the DS buffer
            CopyMemory(buffer1, buffer, bufferSize1);

            if (buffer2 !is null)
                CopyMemory(buffer2, buffer + bufferSize1, bufferSize2);

            // Update our buffer offset and unlock sound buffer
            dsBuffer.Unlock(buffer1, bufferSize1, buffer2, bufferSize2);

            if (FAILED(result) )
            {
                // errorStream_ << "callbackEvent: error (" << getErrorString(result) << ") unlocking buffer during playback!";
                // errorText_ = errorStream_.str();
                error(RtErrorType.SYSTEM_ERROR);
                return;
            }
            nextWritePointer        = ( nextWritePointer + bufferSize1 + bufferSize2 ) % dsBufferSize;
            handle.bufferPointer[0] = nextWritePointer;

            if (handle.drainCounter)
            {
                handle.drainCounter++;
                goto unlock;
            }
        }

        if (_stream.mode == StreamMode.INPUT || _stream.mode == StreamMode.DUPLEX)
        {
            // Setup parameters.
            if (_stream.doConvertBuffer[1])
            {
                buffer       = _stream.deviceBuffer;
                bufferBytes  = _stream.bufferSize * _stream.nDeviceChannels[1];
                bufferBytes *= formatBytes(_stream.deviceFormat[1]);
            }
            else
            {
                buffer       = _stream.userBuffer[1];
                bufferBytes  = _stream.bufferSize * _stream.nUserChannels[1];
                bufferBytes *= formatBytes(_stream.userFormat);
            }

            LPDIRECTSOUNDCAPTUREBUFFER dsBuffer = cast(LPDIRECTSOUNDCAPTUREBUFFER)handle.buffer[1];
            long  nextReadPointer = handle.bufferPointer[1];
            DWORD dsBufferSize    = handle.dsBufferSize[1];

            // Find out where the write and "safe read" pointers are.
            result = dsBuffer.GetCurrentPosition(&currentReadPointer, &safeReadPointer);

            if (FAILED(result) )
            {
                // errorStream_ << "callbackEvent: error (" << getErrorString(result) << ") getting current read position!";
                // errorText_ = errorStream_.str();
                error(RtErrorType.SYSTEM_ERROR);
                return;
            }

            if (safeReadPointer < cast(DWORD)nextReadPointer)
                safeReadPointer += dsBufferSize;                                         // unwrap offset
            DWORD endRead = cast(DWORD)(nextReadPointer + bufferBytes);

            // Handling depends on whether we are StreamMode.INPUT or StreamMode.DUPLEX.
            // If we're in StreamMode.INPUT mode then waiting is a good thing. If we're in StreamMode.DUPLEX mode,
            // then a wait here will drag the write pointers into the forbidden zone.
            //
            // In StreamMode.DUPLEX mode, rather than wait, we will back off the read pointer until
            // it's in a safe position. This causes dropouts, but it seems to be the only
            // practical way to sync up the read and write pointers reliably, given the
            // the very complex relationship between phase and increment of the read and write
            // pointers.
            //
            // In order to minimize audible dropouts in StreamMode.DUPLEX mode, we will
            // provide a pre-roll period of 0.5 seconds in which we return
            // zeros from the read buffer while the pointers sync up.

            if (_stream.mode == StreamMode.DUPLEX)
            {
                if (safeReadPointer < endRead)
                {
                    if (duplexPrerollBytes <= 0)
                    {
                        // Pre-roll time over. Be more agressive.
                        int adjustment = endRead - safeReadPointer;

                        handle.xrun[1] = true;

                        // Two cases:
                        // - large adjustments: we've probably run out of CPU cycles, so just resync exactly,
                        // and perform fine adjustments later.
                        // - small adjustments: back off by twice as much.
                        if (adjustment >= 2 * bufferBytes)
                            nextReadPointer = safeReadPointer - 2 * bufferBytes;
                        else
                            nextReadPointer = safeReadPointer - bufferBytes - adjustment;

                        if (nextReadPointer < 0)
                            nextReadPointer += dsBufferSize;
                    }
                    else
                    {
                        // In pre=roll time. Just do it.
                        nextReadPointer = safeReadPointer - bufferBytes;

                        while (nextReadPointer < 0)
                            nextReadPointer += dsBufferSize;
                    }
                    endRead = cast(DWORD)(nextReadPointer + bufferBytes);
                }
            }
            else // mode == StreamMode.INPUT
            {
                while (safeReadPointer < endRead && _stream.callbackInfo.isRunning)
                {
                    // See comments for playback.
                    double millis = (endRead - safeReadPointer) * 1000.0;
                    millis /= ( formatBytes(_stream.deviceFormat[1]) * _stream.nDeviceChannels[1] * _stream.sampleRate);

                    if (millis < 1.0)
                        millis = 1.0;
                    Sleep(cast(DWORD)millis);

                    // Wake up and find out where we are now.
                    result = dsBuffer.GetCurrentPosition(&currentReadPointer, &safeReadPointer);

                    if (FAILED(result) )
                    {
                        // errorStream_ << "callbackEvent: error (" << getErrorString(result) << ") getting current read position!";
                        // errorText_ = errorStream_.str();
                        error(RtErrorType.SYSTEM_ERROR);
                        return;
                    }

                    if (safeReadPointer < cast(DWORD)nextReadPointer)
                        safeReadPointer += dsBufferSize;                                     // unwrap offset
                }
            }

            // Lock free space in the buffer
            result = dsBuffer.Lock(cast(size_t)nextReadPointer, bufferBytes, &buffer1,
                                   &bufferSize1, &buffer2, &bufferSize2, 0);

            if (FAILED(result) )
            {
                // errorStream_ << "callbackEvent: error (" << getErrorString(result) << ") locking capture buffer!";
                // errorText_ = errorStream_.str();
                error(RtErrorType.SYSTEM_ERROR);
                return;
            }

            if (duplexPrerollBytes <= 0)
            {
                // Copy our buffer into the DS buffer
                CopyMemory(buffer, buffer1, bufferSize1);

                if (buffer2 !is null)
                    CopyMemory(buffer + bufferSize1, buffer2, bufferSize2);
            }
            else
            {
                memset(buffer, 0, bufferSize1);

                if (buffer2 !is null)
                    memset(buffer + bufferSize1, 0, bufferSize2);
                duplexPrerollBytes -= bufferSize1 + bufferSize2;
            }

            // Update our buffer offset and unlock sound buffer
            nextReadPointer = ( nextReadPointer + bufferSize1 + bufferSize2 ) % dsBufferSize;
            dsBuffer.Unlock(buffer1, bufferSize1, buffer2, bufferSize2);

            if (FAILED(result) )
            {
                // errorStream_ << "callbackEvent: error (" << getErrorString(result) << ") unlocking capture buffer!";
                // errorText_ = errorStream_.str();
                error(RtErrorType.SYSTEM_ERROR);
                return;
            }
            handle.bufferPointer[1] = cast(size_t)nextReadPointer;

            // No byte swapping necessary in DirectSound implementation.

            // If necessary, convert 8-bit data from unsigned to signed.
            if (_stream.deviceFormat[1] == RtAudioFormat.int8)
                for (int j = 0; j < bufferBytes; j++)
                    buffer[j] = cast(byte)(buffer[j] - 128);

            // Do buffer conversion if necessary.
            if (_stream.doConvertBuffer[1])
                convertBuffer(_stream.userBuffer[1], _stream.deviceBuffer, _stream.convertInfo[1]);
        }

unlock:
        RtApi.tickStreamTime();
    }

    // Definitions for utility functions and callbacks
    // specific to the DirectSound implementation.

    static extern(Windows) BOOL deviceQueryCallback(LPGUID lpguid,
                                                    const(wchar)* description,
                                                    const(wchar)* module_,
                                                    LPVOID lpContext)
    {
        DsProbeData* probeInfo = cast(DsProbeData*)lpContext;
        DsDevice[] dsDevices   = probeInfo.dsDevices;
        scope (exit)
            probeInfo.dsDevices = dsDevices;

        HRESULT hr;
        bool validDevice = false;

        if (probeInfo.isInput == true)
        {
            DSCCAPS caps;
            LPDIRECTSOUNDCAPTURE object;

            hr = DirectSoundCaptureCreate(lpguid, &object, null);

            if (hr != DS_OK)
                return TRUE;

            caps.dwSize = caps.sizeof;
            hr = object.GetCaps(&caps);

            if (hr == DS_OK)
            {
                if (caps.dwChannels > 0 && caps.dwFormats > 0)
                    validDevice = true;
            }
            object.Release();
        }
        else
        {
            DSCAPS caps;
            LPDIRECTSOUND object;
            hr = DirectSoundCreate(lpguid, &object, null);

            if (hr != DS_OK)
                return TRUE;

            caps.dwSize = caps.sizeof;
            hr = object.GetCaps(&caps);

            if (hr == DS_OK)
            {
                if (caps.dwFlags & DSCAPS_PRIMARYMONO || caps.dwFlags & DSCAPS_PRIMARYSTEREO)
                    validDevice = true;
            }
            object.Release();
        }

        // If good device, then save its name and guid.
        string name = to!string(fromWStringz(description));

        // if ( name == "Primary Sound Driver" || name == "Primary Sound Capture Driver" )
        if (lpguid is null)
            name = "Default Device";

        if (validDevice)
        {
            for (uint i = 0; i < dsDevices.length; i++)
            {
                if (dsDevices[i].name == name)
                {
                    dsDevices[i].found = true;

                    if (probeInfo.isInput)
                    {
                        dsDevices[i].id[1]      = lpguid;
                        dsDevices[i].validId[1] = true;
                    }
                    else
                    {
                        dsDevices[i].id[0]      = lpguid;
                        dsDevices[i].validId[0] = true;
                    }
                    return TRUE;
                }
            }

            DsDevice device;
            device.name  = name;
            device.found = true;

            if (probeInfo.isInput)
            {
                device.id[1]      = lpguid;
                device.validId[1] = true;
            }
            else
            {
                device.id[0]      = lpguid;
                device.validId[0] = true;
            }
            dsDevices.push_back(device);
        }

        return TRUE;
    }

    static string getErrorString(int code)
    {
        switch (code)
        {
            case DSERR_ALLOCATED:
                return "Already allocated";

            case DSERR_CONTROLUNAVAIL:
                return "Control unavailable";

            case DSERR_INVALIDPARAM:
                return "Invalid parameter";

            case DSERR_INVALIDCALL:
                return "Invalid call";

            case DSERR_GENERIC:
                return "Generic error";

            case DSERR_PRIOLEVELNEEDED:
                return "Priority level needed";

            case DSERR_OUTOFMEMORY:
                return "Out of memory";

            case DSERR_BADFORMAT:
                return "The sample rate or the channel format is not supported";

            case DSERR_UNSUPPORTED:
                return "Not supported";

            case DSERR_NODRIVER:
                return "No driver";

            case DSERR_ALREADYINITIALIZED:
                return "Already initialized";

            case DSERR_NOAGGREGATION:
                return "No aggregation";

            case DSERR_BUFFERLOST:
                return "Buffer lost";

            case DSERR_OTHERAPPHASPRIO:
                return "Another application already has priority";

            case DSERR_UNINITIALIZED:
                return "Uninitialized";

            default:
                return "DirectSound unknown error";
        }
    }

private:

    bool coInitialized_;
    bool buffersRolling;
    long duplexPrerollBytes;
    DsDevice[] dsDevices;
    bool probeDeviceOpen(uint device, StreamMode mode, uint channels,
                         uint firstChannel, uint sampleRate,
                         RtAudioFormat format, uint* bufferSize,
                         StreamOptions* options);
}
