module audio_probe;

import std.stdio;

import rtaudio;

pragma(lib, "winmm.lib");

int main()
{
    // Create an api map.
    string[int] apiMap;
    apiMap[Api.MACOSX_CORE]   = "OS-X Core Audio";
    // apiMap[Api.WINDOWS_ASIO]  = "Windows ASIO";  // todo later
    apiMap[Api.WINDOWS_DS]    = "Windows Direct Sound";
    apiMap[Api.UNIX_JACK]     = "Jack Client";
    apiMap[Api.LINUX_ALSA]    = "Linux ALSA";
    apiMap[Api.LINUX_PULSE]   = "Linux PulseAudio";
    apiMap[Api.LINUX_OSS]     = "Linux OSS";
    apiMap[Api.RTAUDIO_DUMMY] = "RtAudio Dummy";

    Api[] apis;
    RtAudio.getCompiledApi(apis);

    writeln("\nRtAudio Version ", RtAudio.getVersion());

    writeln("\nCompiled APIs:\n");

    for (size_t i = 0; i < apis.length; i++)
        writeln("  ", apiMap[ apis[i] ]);

    RtAudio audio = new RtAudio();
    DeviceInfo info;

    writeln("\nCurrent API: ", apiMap[audio.getCurrentApi()]);

    size_t devices = audio.getDeviceCount();
    writeln("\nFound ", devices, " device(s) ...\n");

    for (size_t i = 0; i < devices; i++)
    {
        info = audio.getDeviceInfo(i);

        writeln("\nDevice Name = ", info.name);

        if (info.probed == false)
            writeln("Probe Status = UNsuccessful\n");
        else
        {
            writeln("Probe Status = Successful\n");
            writeln("Output Channels = ", info.outputChannels);
            writeln("Input Channels = ", info.inputChannels);
            writeln("Duplex Channels = ", info.duplexChannels);

            if (info.isDefaultOutput)
                writeln("This is the default output device.\n");
            else
                writeln("This is NOT the default output device.\n");

            if (info.isDefaultInput)
                writeln("This is the default input device.\n");
            else
                writeln("This is NOT the default input device.\n");

            if (info.nativeFormats == 0)
                writeln("No natively supported data formats(?)!");
            else
            {
                writeln("Natively supported data formats:\n");

                if (info.nativeFormats & RtAudioFormat.int8)
                    writeln("  8-bit int\n");

                if (info.nativeFormats & RtAudioFormat.int16)
                    writeln("  16-bit int\n");

                if (info.nativeFormats & RtAudioFormat.int24)
                    writeln("  24-bit int\n");

                if (info.nativeFormats & RtAudioFormat.int32)
                    writeln("  32-bit int\n");

                if (info.nativeFormats & RtAudioFormat.float32)
                    writeln("  32-bit float\n");

                if (info.nativeFormats & RtAudioFormat.float64)
                    writeln("  64-bit float\n");
            }

            if (info.sampleRates.length < 1)
                writeln("No supported sample rates found!");
            else
            {
                writeln("Supported sample rates = ");

                for (size_t j = 0; j < info.sampleRates.length; j++)
                    writeln(info.sampleRates[j], " ");
            }
            writeln();
        }
    }

    writeln();

    return 0;
}
