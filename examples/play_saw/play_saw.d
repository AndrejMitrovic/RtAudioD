module play_saw;

pragma(lib, "winmm.lib");

import rtaudio;

import core.stdc.stdlib;
import core.thread;

import std.conv;
import std.exception;
import std.stdio;
import std.range;
import std.typetuple;

/// Choose whether to interleave the buffers (can also be configured to be a runtime option).
enum RTAUDIO_USE_INTERLEAVED = false;

/// Scales based on the increasing size of the sample types.
private alias Scales = TypeTuple!(127.0, 32767.0, 8388607.0, 2147483647.0, 1.0, 1.0);

/// Get the scaling multiplier based on the sample type.
enum GetScaleMultiplier(Type) = Scales[staticIndexOf!(Type, SampleTypes)];

/// Get the scaling multiplier based on the format type.
enum GetScaleMultiplier(RtAudioFormat format) = Scales[staticIndexOf!(format, FormatTypes)];

/// The format type used in our callbacks.
enum FormatType = RtAudioFormat.int16;

/// Sample type based on the selected format type.
private alias SampleType = GetSampleType!FormatType;

/// Scale multiplier based on the selected format type.
private enum ScaleMultiplier = GetScaleMultiplier!FormatType;

/// The larger the rate the higher-pitched the sound will be.
enum BASE_RATE = 0.005;

/// Temporary data the callback reads and manipulates, which avoids the use of globals.
struct CallbackData
{
    size_t channelCount;
    size_t frameCounter;
    bool doCheckFrameCount;
    size_t totalFrameCount;
    double[] lastValues;
}

enum StatusCode
{
    ok = 0,
    outOfFrames = 1
}

/// The main callback
int audio_callback(void* outputBuffer, void* /*inputBuffer*/, size_t frameCount,
                   double /*streamTime*/, RtAudioStreamStatus status, void* userData)
{
    CallbackData* data = cast(CallbackData*)userData;
    SampleType[] buffer = (cast(SampleType*)outputBuffer)[0 .. (data.channelCount * frameCount)];

    if (status)
        writeln("Stream underflow detected!");

    saw_audio_callback(buffer, frameCount, data);

    data.frameCounter += frameCount;

    if (data.doCheckFrameCount && data.frameCounter >= data.totalFrameCount)
        return StatusCode.outOfFrames;

    return StatusCode.ok;
}

static if (RTAUDIO_USE_INTERLEAVED)
    alias saw_audio_callback = saw_interleaved;
else
    alias saw_audio_callback = saw_non_interleaved;

/// Interleaved version of the sawtooth generating callback.
void saw_interleaved(SampleType[] buffer, size_t frameCount, CallbackData* data)
{
    size_t sampleIdx;

    foreach (_; 0 .. frameCount)
    {
        foreach (chanIdx; 0 .. data.channelCount)
        {
            buffer[sampleIdx++] = cast(SampleType)(data.lastValues[chanIdx] * ScaleMultiplier * 0.5);

            double increment = BASE_RATE * (chanIdx + 1 + (chanIdx * 0.1));
            data.lastValues[chanIdx] += increment;

            if (data.lastValues[chanIdx] >= 1.0)
                data.lastValues[chanIdx] -= 2.0;
        }
    }
}

/// Non-interleaved version of the sawtooth generating callback.
void saw_non_interleaved(SampleType[] buffer, size_t frameCount, CallbackData* data)
{
    size_t chanIdx;
    foreach (channelBuffer; buffer.chunks(frameCount))
    {
        // use a different increment for each channel
        double increment = BASE_RATE * (chanIdx + 1 + (chanIdx * 0.1));

        foreach (ref sample; channelBuffer)
        {
            sample = cast(SampleType)(data.lastValues[chanIdx] * ScaleMultiplier * 0.5);
            data.lastValues[chanIdx] += increment;

            if (data.lastValues[chanIdx] >= 1.0)
                data.lastValues[chanIdx] -= 2.0;
        }

        ++chanIdx;
    }
}

// todo: windows-only
extern(C) int kbhit();

///
void printUsage()
{
    writeln();
    writeln("usage: playsaw N samplerate <device> <channelOffset> <time>");
    writeln("    where N = number of channels,");
    writeln("    samplerate = the sample rate,");
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
    data.channelCount = to!size_t(args[1]);

    sampleRate = to!size_t(args[2]);

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

    auto valsPtr = enforce(cast(double*)calloc(data.channelCount, double.sizeof));
    data.lastValues = valsPtr[0 .. data.channelCount];

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

    // Open and start the stream
    dac.openStream(&oParams, inParams, FormatType, sampleRate, &frameCount,
                   &audio_callback, &data, &options);
    dac.startStream();

    scope (exit)
    {
        if (dac.isStreamOpen())
            dac.closeStream();

        free(data.lastValues.ptr);
    }

    if (data.doCheckFrameCount)
    {
        while (dac.isStreamRunning() == true)
            Thread.sleep(1000.msecs);
    }
    else
    {
        writefln("Stream latency = %s", dac.getStreamLatency());
        writefln("Playing ... press any key to quit (buffer size = %s)", frameCount);
        while (!kbhit) { }

        // Stop the stream
        dac.stopStream();
    }

    return 0;
}
