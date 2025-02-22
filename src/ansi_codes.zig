const std = @import("std");
const globals = @import("globals.zig");

pub const StripANSICodesError = error{
    OutputStringShorter,
};

pub const WrapWithCodeError = error{
    StringToWrapTooLong,
};

pub const colnegdur = col_negative_dur;
pub const colposdur = col_positive_dur;
pub const colemp = col_emphasis;
pub const colres = col_reset;
pub const colbackres = back_col_reset;
pub const colid = col_id;
pub const colback = back_col_grayscale_2;
pub const coltit = col_title;
pub const coldurntr = col_duration_neutral;

pub const col_prefix: [7]u8 = [7]u8{ 0x1b, '[', '3', '8', ';', '5', ';' };
pub const col_negative_dur: [11]u8 = col_prefix ++ [4]u8{ '2', '0', '3', 'm' };
pub const col_positive_dur: [10]u8 = col_prefix ++ [3]u8{ '3', '5', 'm' };
pub const col_title: [10]u8 = col_prefix ++ [3]u8{ '6', '3', 'm' };
pub const col_emphasis: [10]u8 = col_prefix ++ [3]u8{ '6', '9', 'm' };
pub const col_id: [11]u8 = col_prefix ++ [4]u8{ '2', '2', '8', 'm' };
pub const col_reset: [5]u8 = [5]u8{ 0x1b, '[', '3', '9', 'm' };
pub const col_duration_neutral: [11]u8 = col_prefix ++ [4]u8{ '1', '5', '3', 'm' };

pub const clear_remaining: [4]u8 = [4]u8{ 0x1b, '[', '0', 'K' };

pub const back_col_prefix: [7]u8 = [7]u8{ 0x1b, '[', '4', '8', ';', '5', ';' };
pub const back_col_table_line: [10]u8 = back_col_prefix ++ [3]u8{ '6', '0', 'm' };
pub const back_col_grayscale_0: [11]u8 = back_col_prefix ++ [4]u8{ '2', '3', '2', 'm' };
pub const back_col_grayscale_1: [11]u8 = back_col_prefix ++ [4]u8{ '2', '3', '3', 'm' };
pub const back_col_grayscale_2: [11]u8 = back_col_prefix ++ [4]u8{ '2', '3', '4', 'm' };
pub const back_col_grayscale_3: [11]u8 = back_col_prefix ++ [4]u8{ '2', '3', '5', 'm' };
pub const back_col_grayscale_4: [11]u8 = back_col_prefix ++ [4]u8{ '2', '3', '6', 'm' };
pub const back_col_grayscale_5: [11]u8 = back_col_prefix ++ [4]u8{ '2', '3', '7', 'm' };
pub const back_col_grayscale_6: [11]u8 = back_col_prefix ++ [4]u8{ '2', '3', '8', 'm' };
pub const back_col_grayscale_7: [11]u8 = back_col_prefix ++ [4]u8{ '2', '3', '9', 'm' };
pub const back_col_grayscale_8: [11]u8 = back_col_prefix ++ [4]u8{ '2', '4', '0', 'm' };
pub const back_col_grayscale_9: [11]u8 = back_col_prefix ++ [4]u8{ '2', '4', '1', 'm' };
pub const back_col_grayscale_10: [11]u8 = back_col_prefix ++ [4]u8{ '2', '4', '2', 'm' };
pub const back_col_grayscale_11: [11]u8 = back_col_prefix ++ [4]u8{ '2', '4', '3', 'm' };
pub const back_col_grayscale_12: [11]u8 = back_col_prefix ++ [4]u8{ '2', '4', '4', 'm' };
pub const back_col_grayscale_13: [11]u8 = back_col_prefix ++ [4]u8{ '2', '4', '5', 'm' };
pub const back_col_grayscale_14: [11]u8 = back_col_prefix ++ [4]u8{ '2', '4', '6', 'm' };
pub const back_col_grayscale_15: [11]u8 = back_col_prefix ++ [4]u8{ '2', '4', '7', 'm' };
pub const back_col_grayscale_16: [11]u8 = back_col_prefix ++ [4]u8{ '2', '4', '8', 'm' };
pub const back_col_grayscale_17: [11]u8 = back_col_prefix ++ [4]u8{ '2', '4', '9', 'm' };
pub const back_col_grayscale_18: [11]u8 = back_col_prefix ++ [4]u8{ '2', '5', '0', 'm' };
pub const back_col_grayscale_19: [11]u8 = back_col_prefix ++ [4]u8{ '2', '5', '1', 'm' };
pub const back_col_grayscale_20: [11]u8 = back_col_prefix ++ [4]u8{ '2', '5', '2', 'm' };
pub const back_col_grayscale_21: [11]u8 = back_col_prefix ++ [4]u8{ '2', '5', '3', 'm' };
pub const back_col_grayscale_22: [11]u8 = back_col_prefix ++ [4]u8{ '2', '5', '4', 'm' };
pub const back_col_grayscale_23: [11]u8 = back_col_prefix ++ [4]u8{ '2', '5', '5', 'm' };
pub const back_col_highlight: [10]u8 = back_col_prefix ++ [3]u8{ '2', '2', 'm' };
pub const back_col_reset: [5]u8 = [5]u8{ 0x1b, '[', '4', '9', 'm' };

/// Return the color of a duration according to if it's positive or negative
pub fn getDurCol(dur: i64) []const u8 {
    return if (dur >= 0) col_positive_dur[0..] else col_negative_dur[0..];
}

/// Wrap the given string with the specified codes. Caller owns created memory
pub fn wrapWithCode(prefix: []const u8, to_wrap: []const u8, suffix: []const u8) ![]const u8 {
    if (to_wrap.len > 2000) {
        return WrapWithCodeError.StringToWrapTooLong;
    }

    var buf: [2048]u8 = undefined;
    const to_dupe = try std.fmt.bufPrint(&buf, "{s}{s}{s}", .{ prefix, to_wrap, suffix });
    return globals.allocator.dupe(u8, to_dupe);
}

/// Strip the ANSI codes from the given string
// DOES NOT HANDLE MALFORMED ESCAPE SEQUENCES! MAKE SURE THE INPUT STRINGS ARE
// CORRECT PLUS IT DOES ONLY HANDLE SEQUENCES WHERE TERMINATING CHARACTERS ARE
// RECOGNISED BY isTerminalCharacter.
// TODO review this. The code looks ugly
pub fn stripANSICodes(in_str: []const u8, out_str: []u8) ![]u8 {
    if (out_str.len < in_str.len) return StripANSICodesError.OutputStringShorter;
    var idx_in: u16 = 0;
    var idx_out: u16 = 0;

    while (idx_in < in_str.len) {
        if (in_str[idx_in] == 0x1B and idx_in < in_str.len - 1) {
            if (in_str[idx_in + 1] == '[') {
                // at this point we assume we are in a valid escape sequence
                idx_in += 2;
                while (idx_in < in_str.len and isValidAnsiChar(in_str[idx_in])) {
                    idx_in += 1;
                    if (isTerminalChar(in_str[idx_in - 1])) {
                        break;
                    }
                }
            }
        } else {
            out_str[idx_out] = in_str[idx_in];
            idx_in += 1;
            idx_out += 1;
        }
    }
    return out_str[0..idx_out];
}

/// Return true if the specified character is a valid character in an ANSI escape sequence
fn isValidAnsiChar(c: u8) bool {
    if (isTerminalChar(c)) return true;
    const valid_char = [_]u8{ '0', '1', '2', '3', '4', '5', '6', '7', '8', '9', ';' };
    for (valid_char) |to_test| {
        if (c == to_test) return true;
    }
    return false;
}

/// Return true if the specified character is a terminating character for an ANSI escape sequence
// DOES NOT COVER ALL LEGAL TERMINATING CHARACTER. THIS ONLY FITS THE NEEDS OF THIS SPECIFIC PROGRAM
fn isTerminalChar(c: u8) bool {
    const tc = [_]u8{'m'};
    for (tc) |to_test| {
        if (c == to_test) return true;
    }
    return false;
}

test "stripANSICodes for '2:26 after'" {
    var buf_in_str: [40]u8 = undefined;
    const in_str = try std.fmt.bufPrint(&buf_in_str, "{s}2:26 after{s}", .{ col_positive_dur, col_reset });
    var buf_out_str: [60]u8 = undefined;
    const out_str = try stripANSICodes(in_str, &buf_out_str);
    try std.testing.expect(out_str.len == 10);
}

test "stripANSICodes for '0:00 over'" {
    var buf_in_str: [40]u8 = undefined;
    const in_str = try std.fmt.bufPrint(&buf_in_str, "{s}0:00 over{s}", .{ col_negative_dur, col_reset });
    var buf_out_str: [60]u8 = undefined;
    const out_str = try stripANSICodes(in_str, &buf_out_str);
    try std.testing.expect(out_str.len == 9);
}

test "stripANSICodes for '0:02 below'" {
    var buf_in_str: [40]u8 = undefined;
    const in_str = try std.fmt.bufPrint(&buf_in_str, "{s}0:02 below{s}", .{ col_positive_dur, col_reset });
    var buf_out_str: [60]u8 = undefined;
    const out_str = try stripANSICodes(in_str, &buf_out_str);
    try std.testing.expect(out_str.len == 10);
}

test "stripANSICodes for 'testtest'" {
    const in_str = "testtest";
    var buf_out_str: [60]u8 = undefined;
    const out_str = try stripANSICodes(in_str, &buf_out_str);
    try std.testing.expect(out_str.len == 8);
}
