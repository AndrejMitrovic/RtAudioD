module play_flac;

pragma(lib, "winmm.lib");

import rtaudio;

import dflac;

import deimos.flac.all;

import core.stdc.stdlib;
import core.thread;

import std.conv;
import std.exception;
import std.stdio;
import std.range;
import std.typetuple;

/// Choose whether to interleave the buffers (can also be configured to be a runtime option).
enum RTAUDIO_USE_INTERLEAVED = false;

/// The format type used in our callbacks (use only int8/int16 formats for most devices).
enum DeviceFormatType = RtAudioFormat.int16;

/// Sample type based on the selected format type.
private alias DeviceSampleType = GetSampleType!DeviceFormatType;

/// Sample type of the loaded audio waveform (you can pick any sample type here).
alias AudioSampleType = short;

/// Temporary data the callback reads and manipulates, which avoids the use of globals.
struct CallbackData
{
    size_t channelCount;
    size_t frameCounter;
    bool doCheckFrameCount;
    size_t totalFrameCount;

    FlacHeader flacHeader;
    AudioSampleType[][] buffer;
}

// todo: we need to return proper status codes as defined in RtAudio, use an enum and re-define
// the callback as returning the enum rather than an int.
enum StatusCode
{
    ok = 0,
    outOfFrames = 1
}

///
int audio_callback(void* outputBuffer, void* /*inputBuffer*/, size_t frameCount,
                   double /*streamTime*/, RtAudioStreamStatus status, void* userData)
{
    CallbackData* data = cast(CallbackData*)userData;
    DeviceSampleType[] buffer = (cast(DeviceSampleType*)outputBuffer)[0 .. (data.channelCount * frameCount)];

    if (status)
        writeln("Stream underflow detected!");

    fill_buffer_samples(buffer, frameCount, data);

    data.frameCounter += frameCount;

    if (data.doCheckFrameCount && data.frameCounter >= data.totalFrameCount)
        return StatusCode.outOfFrames;

    return StatusCode.ok;
}

static if (RTAUDIO_USE_INTERLEAVED)
    alias fill_buffer_samples = play_flac_interleaved;
else
    alias fill_buffer_samples = play_flac_non_interleaved;

///
alias convert = toSampleType!DeviceSampleType;

///
void play_flac_interleaved(DeviceSampleType[] buffer, size_t frameCount, CallbackData* data)
{
    // slice it (no copy)
    auto channelSlices = data.buffer[];

    size_t sampleIdx;

    foreach (chanSampleIdx; 0 .. frameCount)
    {
        foreach (chanIdx; 0 .. data.channelCount)
        {
            buffer[sampleIdx++] = channelSlices[chanIdx][chanSampleIdx].convert();
        }
    }

    // remove the data from the buffer
    foreach (ref flacChannelBuffer; data.buffer)
        flacChannelBuffer.popFrontN(frameCount);
}

///
void play_flac_non_interleaved(DeviceSampleType[] buffer, size_t frameCount, CallbackData* data)
{
    // slice it (no copy)
    auto channelSlices = data.buffer[];

    foreach (channelBuffer; buffer.chunks(frameCount))
    {
        auto channelData = channelSlices.front;
        channelSlices.popFront();

        foreach (ref sample; channelBuffer)
        {
            sample = channelData.front.convert();
            channelData.popFront();
        }
    }

    // remove the data from the buffer
    foreach (ref flacChannelBuffer; data.buffer)
        flacChannelBuffer.popFrontN(frameCount);
}

// todo: windows-only
extern(C) int kbhit();

///
void printUsage()
{
    writeln();
    writeln("usage: playwav wavefile N <device> <channelOffset> <time>");
    writeln("    where wavefile = path to a .wav file,");
    writeln("    where N = number of channels,");
    writeln("    device = optional device to use (default = 0),");
    writeln("    channelOffset = an optional channel offset on the device (default = 0),");
    writeln("    and time = an optional time duration in seconds (default = no limit).\n");
}

///
int main(string[] args)
{
    // minimal command-line checking
    if (args.length < 3 || args.length > 6)
    {
        printUsage();
        return 1;
    }

    RtAudio dac = new RtAudio();

    if (dac.getDeviceCount() < 1)
    {
        writeln("\nNo audio devices found!\n");
        return 1;
    }

    size_t frameCount, sampleRate, device, offset;

    CallbackData data;
    data.channelCount = to!size_t(args[2]);

    data.flacHeader = readFlacHeader(args[1]);

    data.buffer = readFlacData!AudioSampleType(args[1]);

    // or use our own buffer
    version (none)
    {
        data.buffer = uninitializedArray!(AudioSampleType[][])(
            data.flacHeader.numChannels, cast(size_t)data.flacHeader.samplesPerChannel);
    }

    readFlacData(args[1], data.buffer);

    sampleRate = data.flacHeader.sampleRate;
    enforce(data.flacHeader.numChannels == data.channelCount);  // hardcode for now

    if (args.length > 3)
        device = to!size_t(args[3]);

    if (args.length > 4)
        offset = to!size_t(args[4]);

    if (args.length > 5)
    {
        float time = to!float(args[5]);
        data.totalFrameCount = to!size_t(sampleRate * time);
    }

    if (data.totalFrameCount > 0)
        data.doCheckFrameCount = true;

    // Let RtAudio print messages to stderr.
    dac.showWarnings(true);

    // Set our stream parameters for output only.
    enum inParams = null;

    frameCount = 512;  // desired frame count
    StreamParameters oParams;
    oParams.deviceId     = device;
    oParams.nChannels    = data.channelCount;
    oParams.firstChannel = offset;

    StreamOptions options;
    options.flags  = StreamFlags.hog_device;
    options.flags |= StreamFlags.schedule_realtime;

    static if (!RTAUDIO_USE_INTERLEAVED)
        options.flags |= StreamFlags.non_interleaved;

    dac.openStream(&oParams, inParams, DeviceFormatType, sampleRate, &frameCount,
                   &audio_callback, &data, &options);

    dac.startStream();

    scope (exit)
    {
        if (dac.isStreamOpen())
            dac.closeStream();
    }

    if (data.doCheckFrameCount)
    {
        while (dac.isStreamRunning() == true)
            Thread.sleep(1000.msecs);
    }
    else
    {
        stderr.writefln("Stream latency = %s", dac.getStreamLatency());
        stderr.writefln("Playing ... press any key to quit (buffer size = %s)", frameCount);
        while (!kbhit) { }

        // Stop the stream
        dac.stopStream();
    }

    return 0;
}
