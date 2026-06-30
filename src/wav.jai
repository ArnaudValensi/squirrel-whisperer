// Encode raw PCM into a canonical 44-byte-header WAV (little-endian).
// Used to package captured mic samples for upload to Groq.

encode_wav :: (pcm: [] u8, sample_rate: u32, channels: u16, bits_per_sample: u16) -> [] u8 {
    block_align : u16 = channels * (bits_per_sample / 8);
    byte_rate   : u32 = sample_rate * block_align;
    data_size   : u32 = xx pcm.count;
    riff_size   : u32 = 36 + data_size;

    out := NewArray(44 + pcm.count, u8);
    c := 0;

    put_str :: (out: [] u8, c: *int, s: string) #expand {
        for 0..s.count-1 { out[<<c] = s[it]; <<c += 1; }
    }
    put_u32 :: (out: [] u8, c: *int, v: u32) #expand {
        out[<<c+0] = xx (v & 0xff);
        out[<<c+1] = xx ((v >> 8)  & 0xff);
        out[<<c+2] = xx ((v >> 16) & 0xff);
        out[<<c+3] = xx ((v >> 24) & 0xff);
        <<c += 4;
    }
    put_u16 :: (out: [] u8, c: *int, v: u16) #expand {
        out[<<c+0] = xx (v & 0xff);
        out[<<c+1] = xx ((v >> 8) & 0xff);
        <<c += 2;
    }

    put_str(out, *c, "RIFF");
    put_u32(out, *c, riff_size);
    put_str(out, *c, "WAVE");

    put_str(out, *c, "fmt ");
    put_u32(out, *c, 16);                 // PCM fmt chunk size
    put_u16(out, *c, 1);                  // audio format = PCM
    put_u16(out, *c, channels);
    put_u32(out, *c, sample_rate);
    put_u32(out, *c, byte_rate);
    put_u16(out, *c, block_align);
    put_u16(out, *c, bits_per_sample);

    put_str(out, *c, "data");
    put_u32(out, *c, data_size);

    memcpy(out.data + c, pcm.data, pcm.count);
    return out;
}
