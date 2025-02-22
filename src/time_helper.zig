const std = @import("std");
const globals = @import("globals.zig");

// ALL timestamps that are used in the application are starting on January first 2020.
// This is used to push back the issue with year 2038 when you store timestamps on 32 bits
// The following constant is used to compute a timestamp following this logic
pub const num_sec_offset_1970_2020 = 1577836800;

pub const TimeError = error{
    InvalidDurationString,
    EmptyDuration,
    NumberTooBig,
    DurationTooGreat,
};

/// Get the number of minutes since January 1 2020
pub fn curTimestamp() u25 {
    const cur_time_sec: i64 = @intCast(std.time.timestamp() - num_sec_offset_1970_2020);
    return @intCast(@divFloor(cur_time_sec, 60));
}

/// Create a XXhXXm formated string for a given duration (indicated in minutes)
pub fn formatDuration(str: []u8, dur: i64) ![]const u8 {
    const abs_dur = @abs(dur);

    const numHours = try std.math.divFloor(u64, abs_dur, 60);
    const numMin = abs_dur - (numHours * 60);

    const without_sign = try std.fmt.bufPrint(str[1..], "{d}:{d:0>2}", .{ numHours, numMin });
    str[0] = if (dur < 0) '-' else '+';
    return str[0 .. without_sign.len + 1];
}

/// Create a XXhXXm formated string for a given positive duration (indicated in minutes)
pub fn formatDurationNoSign(str: []u8, dur: u64) ![]const u8 {
    const numHours = try std.math.divFloor(u64, dur, 60);
    const numMin = dur - (numHours * 60);
    return try std.fmt.bufPrint(str[0..], "{d}:{d:0>2}", .{ numHours, numMin });
}

// Parse a duration string in format hh:mm and return the total number of minutes
pub fn parseDuration(dur: []const u8, max: type) !u32 {
    if (dur.len == 0) {
        return TimeError.EmptyDuration;
    }

    var separator_index: usize = 0;
    var already_found_separator: bool = false;

    // make sure the string only contains valid characters
    for (dur, 0..dur.len) |c, i| {
        switch (c) {
            ':' => {
                if (already_found_separator) {
                    return TimeError.InvalidDurationString;
                }
                separator_index = i;
                already_found_separator = true;
            },
            '0'...'9' => continue,
            else => return TimeError.InvalidDurationString,
        }
    }

    var total_min: u25 = 0;

    // if there is no separator we only parse minutes
    if (!already_found_separator) {
        total_min = try std.fmt.parseInt(u25, dur[0..], 10);
    } else if (dur[0] == ':') {
        // if there is a separator at the very start, we only parse minutes
        total_min = try std.fmt.parseInt(u25, dur[1..], 10);
    } else if (dur[dur.len - 1] == ':') {
        // if there is a separator at the very end, we only parse hours
        total_min = try std.fmt.parseInt(u25, dur[0 .. dur.len - 1], 10) * 60;
    } else {
        // in other cases, we parse both
        const hours = try std.fmt.parseInt(u25, dur[0..separator_index], 10);
        const minutes = try std.fmt.parseInt(u25, dur[separator_index + 1 ..], 10);
        total_min = try std.math.add(u25, minutes, try std.math.mul(u25, hours, 60));
    }

    if (total_min > std.math.maxInt(max)) {
        return TimeError.DurationTooGreat;
    }

    return total_min;
}

test "formatDuration - 0h0m" {
    var buf: [20]u8 = undefined;
    try std.testing.expect(std.mem.eql(u8, try formatDuration(&buf, 0), "+0:00"));
}

test "formatDuration - 0h2m" {
    var buf: [20]u8 = undefined;
    try std.testing.expect(std.mem.eql(u8, try formatDuration(&buf, 2), "+0:02"));
}

test "formatDuration - 2h30m" {
    var buf: [20]u8 = undefined;
    try std.testing.expect(std.mem.eql(u8, try formatDuration(&buf, 150), "+2:30"));
}

test "formatDuration - 1h0m" {
    var buf: [20]u8 = undefined;
    try std.testing.expect(std.mem.eql(u8, try formatDuration(&buf, 60), "+1:00"));
}

test "formatDuration - -0h10m" {
    var buf: [20]u8 = undefined;
    try std.testing.expect(std.mem.eql(u8, try formatDuration(&buf, -10), "-0:10"));
}

test "formatDuration - -2h30m" {
    var buf: [20]u8 = undefined;
    try std.testing.expect(std.mem.eql(u8, try formatDuration(&buf, -150), "-2:30"));
}

test "parseDuration 0:0" {
    const dur = try parseDuration("0:0", u25);
    try std.testing.expect(dur == 0);
}

test "parseDuration 5:0" {
    const dur = try parseDuration("5:0", u25);
    try std.testing.expect(dur == 300);
}

test "parseDuration 0:6" {
    const dur = try parseDuration("0:6", u25);
    try std.testing.expect(dur == 6);
}

test "parseDuration 0:70" {
    const dur = try parseDuration("0:70", u25);
    try std.testing.expect(dur == 70);
}

test "parseDuration :70" {
    const dur = try parseDuration(":70", u25);
    try std.testing.expect(dur == 70);
}

test "parseDuration 10:" {
    const dur = try parseDuration("10:", u25);
    try std.testing.expect(dur == 600);
}

test "parseDuration 42" {
    const dur = try parseDuration("42", u25);
    try std.testing.expect(dur == 42);
}

test "parseDuration <empty>" {
    const dur = parseDuration("", u25);
    try std.testing.expect(dur == TimeError.EmptyDuration);
}

test "parseDuration 3e:12" {
    const dur = parseDuration("3e:12", u25);
    try std.testing.expect(dur == TimeError.InvalidDurationString);
}

test "parseDuration 3:12:4" {
    const dur = parseDuration("3:12:4", u25);
    try std.testing.expect(dur == TimeError.InvalidDurationString);
}

test "parseDuration 1000:" {
    const dur = parseDuration("1000:", u12);
    try std.testing.expect(dur == TimeError.DurationTooGreat);
}
