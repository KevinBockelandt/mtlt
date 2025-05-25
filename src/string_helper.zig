// TODO a lot of functions from this module actually already exist in the standard library

const std = @import("std");
const ansi_codes = @import("ansi_codes.zig");
const dfr = @import("data_file_reader.zig");
const globals = @import("globals.zig");

const max_num_lines_cut_string = 25;

/// Contains a version of a string that is cut into several lines
const CutString = struct {
    /// Number of lines once the original string is cut
    nb_lines: u8 = 0,
    /// Array of potential lines once it's cut. We limit it to 25 lines
    /// TODO potential optimization here using an ArrayList
    lines: [max_num_lines_cut_string][]const u8 = undefined,
};

pub const StringError = error{
    MalformedUTF8Data,
    StringTooLong,
    EmptyString,
};

/// Fill a given string with the specified character
pub fn fillStr(str: []u8, char: u8) void {
    var i: usize = 0;
    while (i < str.len) : (i += 1) {
        str[i] = char;
    }
}

/// Very basic check to know if all characters are letters or numbers
/// TODO should be able to handle more than ascii chara
pub fn isValidTagName(name: []const u8) bool {
    if (name.len < 1) return false;

    for (name) |c| {
        if ((c < 'a' or c > 'z') and
            (c < 'A' or c > 'Z') and
            (c < '0' or c > '9') and
            (c != '_') and (c != '-'))
        {
            return false;
        }
    }
    return true;
}

/// Cut a string according to a given length so that it's split into
/// lines no longer than the maximum length
/// The length refers to a number of cells of the terminal
pub fn cutString(str_to_cut: []const u8, max_lgt: u16) StringError!CutString {
    var to_return: CutString = .{};
    var i: u32 = 0;
    var idx_char_start_cur_line: u32 = 0;
    var lgt_cur_line: u16 = 0;

    while (i < str_to_cut.len) {
        const numBytes = try getNumBytesUTF8(str_to_cut[i]);

        if (i <= str_to_cut.len - numBytes) {
            const b1 = str_to_cut[i];
            const b2 = if (numBytes > 1) str_to_cut[i + 1] else 0;
            const b3 = if (numBytes > 2) str_to_cut[i + 2] else 0;
            const b4 = if (numBytes > 3) str_to_cut[i + 3] else 0;

            const code_point = try getCodePointFromUTF8(b1, b2, b3, b4);
            const disp_lgt = getLengthFromCodePoint(code_point);

            // if this character will make us go over the limit.
            // stop the current line and start a new one
            if (lgt_cur_line + disp_lgt > max_lgt) {
                // if we already created the maximum number of lines and we need
                // another one -> trigger an error
                if (to_return.nb_lines == max_num_lines_cut_string) {
                    return StringError.StringTooLong;
                }

                // create a new slice from the input string corresponding to the cut line
                to_return.lines[to_return.nb_lines] = str_to_cut[idx_char_start_cur_line..i];
                to_return.nb_lines += 1;

                // setup data for a new line
                idx_char_start_cur_line = i;
                lgt_cur_line = disp_lgt;
            } else {
                lgt_cur_line += disp_lgt;
            }

            i += numBytes;
        } else {
            return StringError.MalformedUTF8Data;
        }
    }

    // we reached the end of the input string but there is some data in the
    // current line that we need to add to the return struct
    if (to_return.nb_lines == max_num_lines_cut_string) {
        return StringError.StringTooLong;
    }

    // create a new slice from the input string corresponding to the cut line
    to_return.lines[to_return.nb_lines] = str_to_cut[idx_char_start_cur_line..i];
    to_return.nb_lines += 1;

    return to_return;
}

/// Return the number of cells of terminal needed to display the specified
/// unicode string
pub fn computeDisplayLength(str: []const u8) StringError!usize {
    var disp_lgt: usize = 0;
    var i: usize = 0;
    var buf_stripped: [1024]u8 = undefined;

    const stripped_str = ansi_codes.stripANSICodes(str, &buf_stripped) catch |err| {
        // TODO see how to merge error unions
        std.debug.print("{}", .{err});
        return 0;
    };

    // go through all the bytes in the input string
    while (i < stripped_str.len) {
        const numBytes = try getNumBytesUTF8(stripped_str[i]);

        if (i <= stripped_str.len - numBytes) {
            const b1 = stripped_str[i];
            const b2 = if (numBytes > 1) stripped_str[i + 1] else 0;
            const b3 = if (numBytes > 2) stripped_str[i + 2] else 0;
            const b4 = if (numBytes > 3) stripped_str[i + 3] else 0;

            // get codepoint
            const code_point = try getCodePointFromUTF8(b1, b2, b3, b4);

            disp_lgt += getLengthFromCodePoint(code_point);
            i += numBytes;
        } else {
            return StringError.MalformedUTF8Data;
        }
    }

    return disp_lgt;
}

/// Return the number of bytes of the UTF-8 encoded character from
/// which we specify the first byte
pub fn getNumBytesUTF8(first_byte: u8) !u8 {
    if (first_byte & 0b10000000 == 0b00000000) {
        return 1;
    } else if (first_byte & 0b11100000 == 0b11000000) {
        return 2;
    } else if (first_byte & 0b11110000 == 0b11100000) {
        return 3;
    } else if (first_byte & 0b11111000 == 0b11110000) {
        return 4;
    }
    return StringError.MalformedUTF8Data;
}

/// Return a version of the given slice with trimmed surrounding spaces
pub fn trimSurroundingSpaces(str: []const u8) error{EmptyString}![]const u8 {
    if (str.len == 0) {
        return StringError.EmptyString;
    }

    var beg: usize = 0;

    while (true) {
        if (beg >= str.len) {
            return StringError.EmptyString;
        } else if (str[beg] != ' ') {
            break;
        } else {
            beg += 1;
        }
    }

    var end: usize = str.len - 1;

    while (true) {
        if (end < 0) {
            return StringError.EmptyString;
        } else if (str[end] != ' ') {
            break;
        } else {
            end -= 1;
        }
    }

    return str[beg .. end + 1];
}

/// Return true if the specified unicode code point corresponds to a character
/// that needs 2 columns to be displayed on screen
fn getLengthFromCodePoint(code_point: u32) u8 {
    // control characters and combining characters
    if ((0x0000 <= code_point and code_point <= 0x001F) or
        (0x007F <= code_point and code_point <= 0x009F) or
        (0x0300 <= code_point and code_point <= 0x036F))
    {
        return 0;
    }

    if ((0x1100 <= code_point and code_point <= 0x115F) or // Hangul Jamo
        (0x2329 <= code_point and code_point <= 0x232A) or // LEFT-POINTING ANGLE BRACKET, RIGHT-POINTING ANGLE BRACKET
        (0x2E80 <= code_point and code_point <= 0x303E) or // CJK Radicals Supplement, etc.
        (0x3040 <= code_point and code_point <= 0x3247) or // Hiragana, Katakana, etc.
        (0x3250 <= code_point and code_point <= 0x4DBF) or // CJK Strokes
        (0x4E00 <= code_point and code_point <= 0xA4C6) or // CJK Unified Ideographs, Yi Radicals
        (0xA960 <= code_point and code_point <= 0xA97C) or // Hangul Jamo Extended-A
        (0xAC00 <= code_point and code_point <= 0xD7A3) or // Hangul Syllables
        (0xF900 <= code_point and code_point <= 0xFAFF) or // CJK Compatibility Ideographs
        (0xFE10 <= code_point and code_point <= 0xFE19) or // Vertical forms
        (0xFE30 <= code_point and code_point <= 0xFE6F) or // CJK Compatibility Forms
        (0xFF01 <= code_point and code_point <= 0xFF60) or // Full-width ASCII variants
        (0xFFE0 <= code_point and code_point <= 0xFFE6)) // Full-width currency symbols
    {
        return 2;
    }

    return 1;
}

/// Return the unicode codepoint corresponding the the specified UTF-8 data
fn getCodePointFromUTF8(b1: u8, b2: u8, b3: u8, b4: u8) StringError!u32 {
    const maskNumBytes1 = b1 & 0b10000000;
    const maskNumBytes2 = b1 & 0b11100000;
    const maskNumBytes3 = b1 & 0b11110000;
    const maskNumBytes4 = b1 & 0b11111000;

    const maskFirst2 = 0b00111111;
    const maskFirst3 = 0b00011111;
    const maskFirst4 = 0b00001111;
    const maskFirst5 = 0b00000111;

    if (maskNumBytes1 == 0b00000000) {
        return @intCast(b1);
    } else if (maskNumBytes2 == 0b11000000) {
        var toRet: u32 = 0;
        toRet |= (b1 & maskFirst3);
        toRet <<= 6;
        toRet |= (b2 & maskFirst2);

        return toRet;
    } else if (maskNumBytes3 == 0b11100000) {
        var toRet: u32 = 0;
        toRet |= (b1 & maskFirst4);
        toRet <<= 6;
        toRet |= (b2 & maskFirst2);
        toRet <<= 6;
        toRet |= (b3 & maskFirst2);

        return toRet;
    } else if (maskNumBytes4 == 0b11110000) {
        var toRet: u32 = 0;
        toRet |= (b1 & maskFirst5);
        toRet <<= 6;
        toRet |= (b2 & maskFirst2);
        toRet <<= 6;
        toRet |= (b3 & maskFirst2);
        toRet <<= 6;
        toRet |= (b4 & maskFirst2);

        return toRet;
    }

    return StringError.MalformedUTF8Data;
}

/// Return a string with tag names from a list of tag ids
pub fn getTagNamesFromIds(buf: *[4096]u8, tag_ids: []const u16) ![]const u8 {
    if (tag_ids.len == 0) {
        buf[0] = '-';
        return buf[0..1];
    }

    var idx_buf_tags: usize = 0;
    var buf_str_tag_name: [64]u8 = undefined;

    for (tag_ids, 0..tag_ids.len) |tag_id, i| {
        if (globals.dfr.getTagNameFromId(&buf_str_tag_name, tag_id)) |name_to_add| {
            const e_idx_name = idx_buf_tags + name_to_add.len;
            std.mem.copyForwards(u8, buf[idx_buf_tags..e_idx_name], name_to_add);

            // add a , between tag names. Except for the last one
            if (i != tag_ids.len - 1) {
                std.mem.copyForwards(u8, buf[e_idx_name..][0..2], ", ");
                idx_buf_tags = e_idx_name + 2;
            } else {
                idx_buf_tags = e_idx_name;
            }
        } else |err| {
            if (err == dfr.DataParsingError.TagNotFound) {
                try globals.printer.errTagNotFoundId(tag_id);
            } else {
                try globals.printer.errUnexpectedGetTagName(tag_id, err);
            }
        }
    }

    return buf[0..idx_buf_tags];
}

test "getCodePointFromUTF8 - 1 byte" {
    const cp = try getCodePointFromUTF8(0b01101110, 0x00, 0x00, 0x00);
    try std.testing.expect(cp == 0x0000006E);
}

test "getCodePointFromUTF8 - 2 bytes" {
    const cp = try getCodePointFromUTF8(0b11000011, 0b10001001, 0x00, 0x00);
    try std.testing.expect(cp == 0x000000C9);
}

test "getCodePointFromUTF8 - 3 bytes" {
    const cp = try getCodePointFromUTF8(0b11100010, 0b10000010, 0b10101100, 0x00);
    try std.testing.expect(cp == 0x000020AC);
}

test "getCodePointFromUTF8 - 4 bytes" {
    const cp = try getCodePointFromUTF8(0b11110000, 0b10011111, 0b10011000, 0b10000000);
    try std.testing.expect(cp == 0x0001F600);
}

test "computeDisplayLength - basic ascii" {
    const disp_lgt = try computeDisplayLength("Hello, World!");
    try std.testing.expect(disp_lgt == 13);
}

test "computeDisplayLength - basic ascii with ANSI code" {
    const str_to_test = [8]u8{ 'H', 'e', 0x1b, '[', '3', '8', ';', 'l' };
    const disp_lgt = try computeDisplayLength(&str_to_test);
    try std.testing.expect(disp_lgt == 3);
}

test "computeDisplayLength - wide characters - east asian" {
    const disp_lgt = try computeDisplayLength("漢字テスト");
    try std.testing.expect(disp_lgt == 10);
}

test "computeDisplayLength - wide characters - full width latin" {
    const disp_lgt = try computeDisplayLength("ＡＢＣ");
    try std.testing.expect(disp_lgt == 6);
}

test "computeDisplayLength - combining characters - accented characters" {
    const str_to_test = [3]u8{ 'e', 0x03, 0x03 };
    const disp_lgt = try computeDisplayLength(&str_to_test);
    try std.testing.expect(disp_lgt == 1);
}

test "computeDisplayLength - control characters" {
    const disp_lgt = try computeDisplayLength("A\nB\tC");
    try std.testing.expect(disp_lgt == 3);
}

test "cutString - test 1" {
    const cs = try cutString("abcdefghij", 3);
    try std.testing.expect(cs.nb_lines == 4);
    try std.testing.expect(std.mem.eql(u8, cs.lines[0], "abc"));
    try std.testing.expect(std.mem.eql(u8, cs.lines[1], "def"));
    try std.testing.expect(std.mem.eql(u8, cs.lines[2], "ghi"));
    try std.testing.expect(std.mem.eql(u8, cs.lines[3], "j"));
}

test "cutString - test 2" {
    const cs = try cutString("abcdefghij", 20);
    try std.testing.expect(cs.nb_lines == 1);
    try std.testing.expect(std.mem.eql(u8, cs.lines[0], "abcdefghij"));
}

test "cutString - test 3" {
    _ = cutString("abcdefghijklmnopqrstuvwxyzabcdefghij", 1) catch |err| {
        try std.testing.expect(err == StringError.StringTooLong);
    };
}

test "cutString - test 4" {
    const cs = try cutString("abécdefghij", 3);
    try std.testing.expect(cs.nb_lines == 4);
    try std.testing.expect(std.mem.eql(u8, cs.lines[0], "abé"));
    try std.testing.expect(std.mem.eql(u8, cs.lines[1], "cde"));
}

test "cutString - test 5" {
    const cs = try cutString("abＢcdefghij", 3);
    try std.testing.expect(cs.nb_lines == 5);
    try std.testing.expect(std.mem.eql(u8, cs.lines[0], "ab"));
    try std.testing.expect(std.mem.eql(u8, cs.lines[1], "Ｂc"));
}

test "trimSurroundingSpaces - empty string 1" {
    if (trimSurroundingSpaces("")) |_| {
        unreachable;
    } else |err| {
        try std.testing.expect(err == error.EmptyString);
    }
}

test "trimSurroundingSpaces - empty string 2" {
    if (trimSurroundingSpaces("       ")) |_| {
        unreachable;
    } else |err| {
        try std.testing.expect(err == error.EmptyString);
    }
}

test "trimSurroundingSpaces - only first chara" {
    const ts = try trimSurroundingSpaces("a      ");
    try std.testing.expect(std.mem.eql(u8, ts, "a"));
}

test "trimSurroundingSpaces - only last chara" {
    const ts = try trimSurroundingSpaces("      z");
    try std.testing.expect(std.mem.eql(u8, ts, "z"));
}

test "trimSurroundingSpaces - spaces inside" {
    const ts = try trimSurroundingSpaces("a     z");
    try std.testing.expect(std.mem.eql(u8, ts, "a     z"));
}

test "trimSurroundingSpaces - no surrounding spaces" {
    const ts = try trimSurroundingSpaces("abcdefg");
    try std.testing.expect(std.mem.eql(u8, ts, "abcdefg"));
}

test "trimSurroundingSpaces - trim start" {
    const ts = try trimSurroundingSpaces("   abcdefg");
    try std.testing.expect(std.mem.eql(u8, ts, "abcdefg"));
}

test "trimSurroundingSpaces - trim end" {
    const ts = try trimSurroundingSpaces("abcdefg   ");
    try std.testing.expect(std.mem.eql(u8, ts, "abcdefg"));
}

test "isValidTagName - empty string" {
    try std.testing.expect(!isValidTagName(""));
}

test "isValidTagName - string with only spaces" {
    try std.testing.expect(!isValidTagName("  "));
}

test "isValidTagName - valid name 1" {
    try std.testing.expect(isValidTagName("valid"));
}

test "isValidTagName - valid name 2" {
    try std.testing.expect(isValidTagName("va-li_d"));
}

test "isValidTagName - valid name 3" {
    try std.testing.expect(isValidTagName("_valid-"));
}

test "isValidTagName - invalid because space" {
    try std.testing.expect(!isValidTagName("val id"));
}

test "isValidTagName - invalid because @" {
    try std.testing.expect(!isValidTagName("@id"));
}

// TODO test fillStr
