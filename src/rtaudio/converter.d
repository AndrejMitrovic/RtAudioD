/*
 *             Copyright Andrej Mitrovic 2013.
 *  Distributed under the Boost Software License, Version 1.0.
 *     (See accompanying file LICENSE_1_0.txt or copy at
 *           http://www.boost.org/LICENSE_1_0.txt)
 */
module rtaudio.converter;

import std.math;
import std.typetuple;

///
template toSampleType(TargetType)
{
    TargetType toSampleType(T)(T input)
    {
        TargetType result;

        static if (is(T == TargetType))
            result = input;
        else
            convertSample(input, result);

        return result;
    }
}

///
version (none)
unittest
{
    foreach (SrcType; TypeTuple!(ubyte, ushort, uint, float, double))
    {
        static if (is(SrcType == float) || is(SrcType == double))
            auto srcSample = SrcType(0.215);
        else
            auto srcSample = SrcType(215);

        import std.stdio;

        foreach (TgtType; TypeTuple!(ubyte, ushort, uint, float, double))
        {
            auto tgtSample = srcSample.toSampleType!TgtType();

            auto finSample = tgtSample.toSampleType!SrcType();

            /+ assert(finSample == srcSample, msg());
                   format("%s(%s) => %s(%s) => %s(%s)",
                           SrcType.stringof, srcSample,
                           TgtType.stringof, tgtSample,
                           SrcType.stringof, finSample)); +/

            stderr.writefln("%s(%s) => %s(%s) => %s(%s)",
                            SrcType.stringof, srcSample,
                            TgtType.stringof, tgtSample,
                            SrcType.stringof, finSample);

        }

        stderr.writeln();
    }
}

private alias int8 = byte;
private alias uint8 = ubyte;
private alias int16 = short;
private alias uint16 = ushort;
private alias int32 = int;
private alias uint32 = uint;
private alias float32 = float;
private alias float64 = double;

void convertSample(float32 input, ref float64 output)
{
    output = input;
}

void convertSample(float64 input, ref float32 output)
{
    output = input;
}

void convertSample(float32 input, ref int32 output)
{
    float scaled = input * 0x7FFFFFFF;
    output = cast(int32)lrint(scaled - 0.5f);
}

void convertSample(float32 input, ref uint32 output)
{
    float scaled = input * 0x7FFFFFFF;
    output = cast(uint32)lrint(scaled - 0.5f);
}

void convertSample(float32 input, ref int16 output)
{
    float scaled = input * (32767.0f);
    output = cast(int16)lrint(scaled - 0.5f);
}

void convertSample(float32 input, ref uint16 output)
{
    float scaled = input * (32767.0f);
    output = cast(uint16)lrint(scaled - 0.5f);
}

void convertSample(float32 input, ref int8 output)
{
    output = cast(int8)(input * 127.0f);
}

void convertSample(float32 input, ref uint8 output)
{
    output = cast(uint8)(128 + (cast(uint8)(input * 127.0f)));
}

void convertSample(int32 input, ref float32 output)
{
    output = cast(float32)(cast(float64)input * (1.0 / 2147483648.0));
}

void convertSample(uint32 input, ref float64 output)
{
    output = cast(float64)(cast(float64)input * (1.0 / 2147483648.0));
}

void convertSample(int32 input, ref int16 output)
{
    output = cast(int16)(input >> 16);
}

void convertSample(uint32 input, ref uint16 output)
{
    output = cast(uint16)(input >> 16);
}

void convertSample(int32 input, ref int8 output)
{
    output = cast(int8)(input >> 24);
}

void convertSample(int32 input, ref uint8 output)
{
    output = cast(uint8)((input >> 24) + 128);
}

void convertSample(int16 input, ref float32 output)
{
    output = input * (1.0f / 32768.0f);
}

void convertSample(uint16 input, ref float64 output)
{
    output = input * (1.0f / 32768.0f);
}

void convertSample(int16 input, ref int32 output)
{
    output = input << 16;
}

void convertSample(uint16 input, ref uint32 output)
{
    output = input << 16;
}

void convertSample(int16 input, ref int8 output)
{
    output = cast(int8)(input >> 8);
}

void convertSample(int16 input, ref uint8 output)
{
    output = cast(uint8)((input >> 8) + 128);
}

void convertSample(int8 input, ref float32 output)
{
    output = input * (1.0f / 128.0f);
}

void convertSample(int8 input, ref int32 output)
{
    output = input << 24;
}

void convertSample(int8 input, ref int16 output)
{
    output = input << 8;
}

void convertSample(int8 input, ref uint8 output)
{
    output = cast(uint8)(input + 128);
}

void convertSample(uint8 input, ref float64 output)
{
    output = (input - 128) * (1.0f / 128.0f);
}

void convertSample(uint8 input, ref float32 output)
{
    output = (input - 128) * (1.0f / 128.0f);
}

void convertSample(uint8 input, ref int32 output)
{
    output = (input - 128) << 24;
}

void convertSample(uint8 input, ref uint32 output)
{
    output = (input - 128) << 24;
}

void convertSample(uint8 input, ref uint16 output)
{
    output = cast(int16)((input - 128) << 8);
}

void convertSample(uint8 input, ref int16 output)
{
    output = cast(int16)((input - 128) << 8);
}

void convertSample(uint8 input, ref int8 output)
{
    output = cast(int8)(input - 128);
}
