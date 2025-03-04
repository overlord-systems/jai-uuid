#import "Basic";
#import "Sodium";

Uuid :: #type [16]u8;

ZERO_UUID : Uuid : .[0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0];

uuid_v4 :: () -> Uuid {

    // https://en.wikipedia.org/wiki/Universally_unique_identifier#Version_4_(random)
    uuid : Uuid = ---;

    randombytes_buf(uuid.data.(*u64), 8);
    randombytes_buf(uuid.data.(*u64)+1, 8);

    uuid[6] = (uuid[6] & 0x0f) | 0x40; // Clear upper nibble of 7th byte and set it to version to 4
	uuid[8] = (uuid[8] & 0x3f) | 0x80; // Clear upper 2 bits and set it to variant 0b10

    return uuid;
}

uuid_v7 :: () -> Uuid #no_aoc {

    #import "Basic"; // For Apollo_Time
    #import "Unixtime";

    // https://en.wikipedia.org/wiki/Universally_unique_identifier#Version_7_(timestamp_and_random)
    //
    // First 48 bits are millisecond unix timestamp, 4 bits for version, 2 bits for variant (must be 0b10), and remaining 74 bits are random.
    //
    // One potential issue is, if you are generating multiple uuidv7 one after the other, they won't be monotonic as they will fall
    // in the same millisecond. Now this could be ok as they are still unique, but as per the spec you are *optionally* allowed to use
    // 12 to 42 bits for some kind of 'counter' that allows you to sidestep this issue and keep things monotonic.
    //
    // The solution used here, similar to how Postgres implements v7, is to use put 12 bits of nanosecond time. Here, we use
    // consensus/wall/system time for the unix timestamp and 12 bits from the monotonic clock.
    //
    // Here is how our UUID v7 is setup (taken from: https://brandur.org/fragments/uuid-v7-monotonicity)
    //
    // 0                   1                   2                   3
    // 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1
    // +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
    // |                      48 bits unix_ts_ms                       |
    // +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
    // |   48 bits unix_ts_ms (cont)   |  ver  |    12 bits rand_a     |
    // +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
    // |var|                    62 bits rand_b                         |
    // +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
    // |                     62 bits rand_b (cont)                     |
    // +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
    uuid : Uuid = ---;

    a := uuid.data.(*u64);

    wall_at := current_time_consensus();
    wall_unix_ms := to_unix_ms(wall_at);

    // First 6 bytes (48 bits) are taken by time, so we just set 8 bytes, and then overwrite
    // the extra 2 bytes (indices 6 and 7) with proper data (version and monotonic counter).
    //
    // Unfortunately, we have to write the time big endian, so most significant part goes into
    // the first index, and so on.
    #if CPU == .X64 {

        // This bswap instructions is used to convert big<->little endian by swapping
        // byte positions, similar to our shifts and assigns on non-x86 CPUs.
        wall_unix_ms_big_endian := wall_unix_ms.(u64,no_check);
        #asm {
            bswap.64 wall_unix_ms_big_endian;
        }

        // We only want 48 bits, so this shift gets rid of the ones outside our range
        a.* = (wall_unix_ms_big_endian >> 16);

    } else {

        uuid[0] = (wall_unix_ms >> 40).(u8,no_check);
        uuid[1] = (wall_unix_ms >> 32).(u8,no_check);
        uuid[2] = (wall_unix_ms >> 24).(u8,no_check);
        uuid[3] = (wall_unix_ms >> 16).(u8,no_check);
        uuid[4] = (wall_unix_ms >> 8).(u8,no_check);
        uuid[5] = (wall_unix_ms).(u8,no_check);
    }

    // Write version in upper nibble of index 6, then use lower nibble of index 6
    // and index 7 for the monotonic counter.
    mono_at := current_time_monotonic();
    mono_unix_ns := to_unix_ns(mono_at).(s16,no_check); // We are only using 1.5 bytes, so just get s16

    // Clear upper nibble of 7th byte and set it to version to 7, and set the other half to the upper
    // part of the unix timestamp.
    //
    // For example, if timestamp has upper_byte=55 and lower_byte=123 (upper meaning more significant),
    // then the lower nibble of 55 will be set on index 6, and the lower byte will be set on index 7
    uuid[6] = ((mono_unix_ns >> 8).(u8,no_check) & 0x0f) | 0x70;
    uuid[7] = mono_unix_ns.(u8,no_check);

    // Since we are using 12 bits for monotonic time, 62 bits are left for the random number,
    // so one 64 bit random value at the end is enough.
    //
    // The additional 2 bits we are writing are then overwritten with the variant.
    randombytes_buf((a+1), 8);
    uuid[8] = (uuid[8] & 0x3f) | 0x80; // Clear upper 2 bits and set it to variant 0b10

    return uuid;
}

// UUIDs are just two s64 values, so equality is simply comparing each
// of the two s64 values to each other from u1 and u2
uuid_equal :: inline (u1: Uuid, u2: Uuid) -> bool {
    u1_s64 := u1.data.(*s64);
    u2_s64 := u2.data.(*s64);
    return u1_s64.* == u2_s64.* && (u1_s64 + 1).* == (u2_s64 + 1).*;
}

uuid_string :: (uuid: Uuid) -> string {

    // @TODO: @PERF: We can use a lookup table and get rid of sprint?
    push_context {

        context.print_style.default_format_int.base = 16;
        context.print_style.default_format_int.minimum_digits = 2;

        formatted := sprint("%0%0%0%0-%0%0-%0%0-%0%0-%0%0%0%0%0%0",
            uuid[0], uuid[1], uuid[2], uuid[3],
            uuid[4], uuid[5],
            uuid[6], uuid[7],
            uuid[8], uuid[9],
            uuid[10], uuid[11],
            uuid[12], uuid[13], uuid[14], uuid[15],
        );

        return formatted;
    }
}

// Convenience function that uses temp allocator for the string
tuuid_string :: inline (uuid: Uuid) -> string {
    return uuid_string(uuid,, allocator=temp);
}

// Parses a uuid in the format '019540b2-9bd3-759d-978f-d7ba4bdb0736' into a Uuid.
// Both lower/upper case strings work, but must be in the format shown above.
parse_uuid :: (s: string) -> (success: bool, uuid: Uuid = ZERO_UUID) {

    valid := s.count == 36 || (s.count == 37 && s[36] == #char "\0");
    if !valid return false;

    uuid: Uuid = ---;

    uuid[0] = hex_to_byte(s[0], s[1]);
    uuid[1] = hex_to_byte(s[2], s[3]);
    uuid[2] = hex_to_byte(s[4], s[5]);
    uuid[3] = hex_to_byte(s[6], s[7]);
    // -
    uuid[4] = hex_to_byte(s[9], s[10]);
    uuid[5] = hex_to_byte(s[11], s[12]);
    // -
    uuid[6] = hex_to_byte(s[14], s[15]);
    uuid[7] = hex_to_byte(s[16], s[17]);
    // -
    uuid[8] = hex_to_byte(s[19], s[20]);
    uuid[9] = hex_to_byte(s[21], s[22]);
    // -
    uuid[10] = hex_to_byte(s[24], s[25]);
    uuid[11] = hex_to_byte(s[26], s[27]);
    uuid[12] = hex_to_byte(s[28], s[29]);
    uuid[13] = hex_to_byte(s[30], s[31]);
    uuid[14] = hex_to_byte(s[32], s[33]);
    uuid[15] = hex_to_byte(s[34], s[35]);

    return true, uuid;
}

must_parse_uuid :: inline (s: string) -> uuid: Uuid {
    success, uuid := parse_uuid(s);
    assert(success, "uuid string '%' failed to parse", s);

    return uuid;
}

#scope_module;

// Takes an ascii representation of hex (e.g. 15 stored as "f")
// and returns it as the hex value. Example: "f"->15, "a"->10, and so on.
hex_ascii_to_hex :: inline (a: u8) -> u8 {
    return ifx a <= #char "9" a - 48 else to_lower(a) - 87;
}

// Takes a single hex byte as two nibbles and returns a decimal representation
hex_to_byte :: inline (upper: u8, lower: u8) -> u8 {

    upper = hex_ascii_to_hex(upper);
    lower = hex_ascii_to_hex(lower);
    
    return upper*16 + lower;
}
