module play_wav;

pragma(lib, "winmm.lib");

import rtaudio;
import waved;

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
private alias DeviceSampleType = GetSampleType!FormatType;

///
alias convert = toSampleType!DeviceSampleType;

/// Scale multiplier based on the selected format type.
private enum ScaleMultiplier = GetScaleMultiplier!FormatType;

/// Temporary data the callback reads and manipulates, which avoids the use of globals.
struct CallbackData
{
    size_t channelCount;
    size_t frameCounter;
    bool doCheckFrameCount;
    size_t totalFrameCount;

    SoundFile soundFile;
}

// todo: we need to return proper status codes as defined in RtAudio, use an enum and re-define
// the callback as returning the enum rather than an int.
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
    DeviceSampleType[] buffer = (cast(DeviceSampleType*)outputBuffer)[0 .. (data.channelCount * frameCount)];

    if (status)
        writeln("Stream underflow detected!");

    wav_audio_callback(buffer, frameCount, data);

    data.frameCounter += frameCount;

    if (data.doCheckFrameCount && data.frameCounter >= data.totalFrameCount)
        return StatusCode.outOfFrames;

    return StatusCode.ok;
}

static if (RTAUDIO_USE_INTERLEAVED)
    alias wav_audio_callback = play_wav_interleaved;
else
    alias wav_audio_callback = play_wav_non_interleaved;

///
void play_wav_interleaved(DeviceSampleType[] buffer, size_t frameCount, CallbackData* data)
{
    size_t sampleIdx;

    foreach (_; 0 .. frameCount)
    {
        foreach (chanIdx; 0 .. data.channelCount)
        {
            buffer[sampleIdx++] = data.soundFile.data.front.convert();
            data.soundFile.data.popFront();
        }
    }
}

///
void play_wav_non_interleaved(DeviceSampleType[] buffer, size_t frameCount, CallbackData* data)
{
    // all samples for this iteration for all the channels
    immutable totalSamples = frameCount * data.channelCount;

    // grab the interleaved data as a slice
    auto wavSlice = data.soundFile.data[0 .. totalSamples];

    // remove the data from the buffer
    data.soundFile.data.popFrontN(totalSamples);

    foreach (channelBuffer; buffer.chunks(frameCount))
    {
        // lazily take interleaved data for this channel
        auto wavChannelBuffer = wavSlice.stride(data.channelCount).take(frameCount);

        foreach (ref sample; channelBuffer)
        {
            sample = wavChannelBuffer.front.convert();
            wavChannelBuffer.popFront();
        }

        wavSlice.popFront();  // each channel stride begins at next initial offset
    }
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

    data.soundFile = decodeWAVE(args[1]);
    sampleRate = data.soundFile.sampleRate;
    enforce(data.soundFile.numChannels == data.channelCount);  // hardcode for now

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

    // Open and start the stream
    dac.openStream(&oParams, inParams, FormatType, sampleRate, &frameCount,
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
