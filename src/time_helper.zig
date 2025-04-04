const std = @import("std");
const globals = @import("globals.zig");
const dt = @import("data_types.zig");

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

/// Compute the remaining time for a particular thing
pub fn computeTimeLeft(thing: dt.Thing) !i64 {
    var time_spent_already: u32 = 0;
    for (thing.timers) |timer| {
        time_spent_already += timer.duration;
    }

    // check there is not a current timer for this thing
    const cur_timer = try globals.dfr.getCurrentTimer();
    if (cur_timer.id_thing == thing.id and cur_timer.start != 0) {
        const dur_cur_timer = curTimestamp() - cur_timer.start;
        time_spent_already += dur_cur_timer;
    }

    return @as(i64, thing.estimation) - @as(i64, time_spent_already);
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
