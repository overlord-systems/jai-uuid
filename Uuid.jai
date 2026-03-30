#import "Basic";
#import "Sodium";

Uuid :: struct {
    bytes: [16]u8;
}

operator == :: (u1: Uuid, u2: Uuid) -> bool {
    return inline uuid_equal(u1, u2);
}

ZERO_UUID : Uuid : {};

uuid_v4 :: () -> Uuid {

    // https://en.wikipedia.org/wiki/Universally_unique_identifier#Version_4_(random)
    uuid : Uuid = ---;

    randombytes_buf(uuid.bytes.data.(*u64), 8);
    randombytes_buf(uuid.bytes.data.(*u64)+1, 8);

    uuid.bytes[6] = (uuid.bytes[6] & 0x0f) | 0x40; // Clear upper nibble of 7th byte and set it to version to 4
	uuid.bytes[8] = (uuid.bytes[8] & 0x3f) | 0x80; // Clear upper 2 bits and set it to variant 0b10

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

    a := uuid.bytes.data.(*u64);

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
    uuid.bytes[6] = ((mono_unix_ns >> 8).(u8,no_check) & 0x0f) | 0x70;
    uuid.bytes[7] = mono_unix_ns.(u8,no_check);

    // Since we are using 12 bits for monotonic time, 62 bits are left for the random number,
    // so one 64 bit random value at the end is enough.
    //
    // The additional 2 bits we are writing are then overwritten with the variant.
    randombytes_buf((a+1), 8);
    uuid.bytes[8] = (uuid.bytes[8] & 0x3f) | 0x80; // Clear upper 2 bits and set it to variant 0b10

    return uuid;
}

// UUIDs are just two s64 values, so equality is simply comparing each
// of the two s64 values to each other from u1 and u2
is_zero :: #bake_arguments uuid_equal(u2=ZERO_UUID);

array_find :: (array: []Uuid, item: Uuid) -> (found: bool, index: s64) {
    for array if uuid_equal(it, item) return true, it_index;
    return false, -1;
}

uuid_equal :: inline (u1: Uuid, u2: Uuid) -> bool {
    u1_s64 := u1.bytes.data.(*s64);
    u2_s64 := u2.bytes.data.(*s64);
    return u1_s64.* == u2_s64.* && (u1_s64 + 1).* == (u2_s64 + 1).*;
}

uuid_string :: (uuid: Uuid) -> string {

    // Example output: 6511ae2b-5b59-4795-ba20-370f25b6f52a
    output := string.{
        data = alloc(36),
        count = 36,
    };

    index : u8 = 0;
    for uuid.bytes {

        hex := byte_to_hex_arr[it];

        if index == 8 || index == 13 || index == 18 || index == 23 {
            output[index] = "-";
            index += 1;
        }

        // The hex string is always two chars per byte, so write the two ascii chars at once
        (*output[index]).(*u16).* = hex.data.(*u16).*;

        index += 2;
    }

    return output;
}

// Convenience function that uses temp allocator for the string
tuuid_string :: inline (uuid: Uuid) -> string {
    return uuid_string(uuid,, temp);
}

is_valid_uuid_len :: inline (s: string) -> bool {
    return (s.count == 36 && s[35] != "\0") || (s.count == 37 && s[36] == "\0");
}

// Parses a uuid in the format '019540b2-9bd3-759d-978f-d7ba4bdb0736' into a Uuid.
// Both lower/upper case strings work, but must be in the format shown above.
parse_uuid :: (s: string) -> (success: bool, uuid: Uuid) {

    if !is_valid_uuid_len(s) return false, ZERO_UUID;

    uuid: Uuid = ---;

    uuid.bytes[0] = hex_to_byte(s[0], s[1]);
    uuid.bytes[1] = hex_to_byte(s[2], s[3]);
    uuid.bytes[2] = hex_to_byte(s[4], s[5]);
    uuid.bytes[3] = hex_to_byte(s[6], s[7]);
    // -
    uuid.bytes[4] = hex_to_byte(s[9], s[10]);
    uuid.bytes[5] = hex_to_byte(s[11], s[12]);
    // -
    uuid.bytes[6] = hex_to_byte(s[14], s[15]);
    uuid.bytes[7] = hex_to_byte(s[16], s[17]);
    // -
    uuid.bytes[8] = hex_to_byte(s[19], s[20]);
    uuid.bytes[9] = hex_to_byte(s[21], s[22]);
    // -
    uuid.bytes[10] = hex_to_byte(s[24], s[25]);
    uuid.bytes[11] = hex_to_byte(s[26], s[27]);
    uuid.bytes[12] = hex_to_byte(s[28], s[29]);
    uuid.bytes[13] = hex_to_byte(s[30], s[31]);
    uuid.bytes[14] = hex_to_byte(s[32], s[33]);
    uuid.bytes[15] = hex_to_byte(s[34], s[35]);

    return true, uuid;
}

must_parse_uuid :: inline (s: string) -> uuid: Uuid {
    success, uuid := parse_uuid(s);
    assert(success, "uuid string '%' failed to parse", s);

    return uuid;
}

// The passed uuid must be a v7. Passing another version will result in garbage output.
unix_ms_from_uuid :: (uuid: Uuid) -> Unixts {

    unix_ms : Unixts = uuid.bytes.data.(*Unixts).*;

    // Time is stored big endian, so we make little endian
    #if CPU == .X64 {

        // This bswap instructions is used to convert big<->little endian by swapping
        // byte positions, similar to our shifts and assigns on non-x86 CPUs.
        little_endian := unix_ms.(u64,no_check);
        #asm {
            bswap.64 little_endian;
        }

        unix_ms = (little_endian >> 16).(Unixts,no_check);

    } else {

        unix_ms = (16 << unix_ms) >> 16;

        little_endian := unix_ms;
        little_endian[0] = (unix_ms >> 40).(u8,no_check);
        little_endian[1] = (unix_ms >> 32).(u8,no_check);
        little_endian[2] = (unix_ms >> 24).(u8,no_check);
        little_endian[3] = (unix_ms >> 16).(u8,no_check);
        little_endian[4] = (unix_ms >> 8).(u8,no_check);
        little_endian[5] = (unix_ms).(u8,no_check);

        unix_ms = little_endian;
    }

    return unix_ms;
}

#scope_module;

// Takes an ascii representation of hex (e.g. 15 stored as "f")
// and returns it as the hex value. Example: "f"->15, "a"->10, and so on.
hex_ascii_to_hex :: inline (a: u8) -> u8 {
    return ifx a <= "9" then a - 48 else to_lower(a) - 87;
}

// Takes a single hex byte as two nibbles and returns a decimal representation
hex_to_byte :: inline (upper: u8, lower: u8) -> u8 {

    upper = hex_ascii_to_hex(upper);
    lower = hex_ascii_to_hex(lower);

    return upper*16 + lower;
}

byte_to_hex_arr : [256]string : string.[
    "00", "01", "02", "03", "04", "05", "06", "07", "08", "09", "0a", "0b", "0c", "0d", "0e", "0f",
    "10", "11", "12", "13", "14", "15", "16", "17", "18", "19", "1a", "1b", "1c", "1d", "1e", "1f",
    "20", "21", "22", "23", "24", "25", "26", "27", "28", "29", "2a", "2b", "2c", "2d", "2e", "2f",
    "30", "31", "32", "33", "34", "35", "36", "37", "38", "39", "3a", "3b", "3c", "3d", "3e", "3f",
    "40", "41", "42", "43", "44", "45", "46", "47", "48", "49", "4a", "4b", "4c", "4d", "4e", "4f",
    "50", "51", "52", "53", "54", "55", "56", "57", "58", "59", "5a", "5b", "5c", "5d", "5e", "5f",
    "60", "61", "62", "63", "64", "65", "66", "67", "68", "69", "6a", "6b", "6c", "6d", "6e", "6f",
    "70", "71", "72", "73", "74", "75", "76", "77", "78", "79", "7a", "7b", "7c", "7d", "7e", "7f",
    "80", "81", "82", "83", "84", "85", "86", "87", "88", "89", "8a", "8b", "8c", "8d", "8e", "8f",
    "90", "91", "92", "93", "94", "95", "96", "97", "98", "99", "9a", "9b", "9c", "9d", "9e", "9f",
    "a0", "a1", "a2", "a3", "a4", "a5", "a6", "a7", "a8", "a9", "aa", "ab", "ac", "ad", "ae", "af",
    "b0", "b1", "b2", "b3", "b4", "b5", "b6", "b7", "b8", "b9", "ba", "bb", "bc", "bd", "be", "bf",
    "c0", "c1", "c2", "c3", "c4", "c5", "c6", "c7", "c8", "c9", "ca", "cb", "cc", "cd", "ce", "cf",
    "d0", "d1", "d2", "d3", "d4", "d5", "d6", "d7", "d8", "d9", "da", "db", "dc", "dd", "de", "df",
    "e0", "e1", "e2", "e3", "e4", "e5", "e6", "e7", "e8", "e9", "ea", "eb", "ec", "ed", "ee", "ef",
    "f0", "f1", "f2", "f3", "f4", "f5", "f6", "f7", "f8", "f9", "fa", "fb", "fc", "fd", "fe", "ff",
];
