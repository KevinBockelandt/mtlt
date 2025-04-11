const std = @import("std");
const globals = @import("globals.zig");
const dt = @import("data_types.zig");

// ALL timestamps that are used in the application are starting on January first 2020.
// This is used to push back the issue with year 2038 when you store timestamps on 32 bits
// The following constant is used to compute a timestamp following this logic
pub const num_sec_offset_1970_2020 = 1577836800;

pub const TimeError = error{
    EmptyDuration,
    NumberTooBig,
    ReturnVarTypeTooSmall,
    CantConvertSignedToUnsigned,
    UnsupportedReturnType,
};

/// Get the number of minutes since January 1 2020
pub fn curTimestamp() u25 {
    const cur_time_sec: i64 = @intCast(std.time.timestamp() - num_sec_offset_1970_2020);
    return @intCast(@divFloor(cur_time_sec, 60));
}

/// Get the number of steps corresponding to a certain number of minutes
pub fn getStepsFromMinutes(comptime T: type, min: i64) !T {
    const min_float: f64 = @as(f64, @floatFromInt(min));
    const coef: f64 = 7.2;

    const res = min_float / coef;

    // handle the value differently according to the desired type
    switch (@typeInfo(T)) {
        .int, .comptime_int => {
            if (min < 0 and std.math.minInt(T) >= 0) {
                return TimeError.CantConvertSignedToUnsigned;
            }

            const res_int: i64 = @intFromFloat(@round(res));

            if (res_int < std.math.minInt(T) or res_int > std.math.maxInt(T)) {
                return TimeError.ReturnVarTypeTooSmall;
            } else {
                return @intCast(res_int);
            }
        },
        .float, .comptime_float => return @floatCast(res),
        else => return TimeError.UnsupportedReturnType,
    }
}

/// Get the number of minutes corresponding to a certain number of steps
pub fn getMinutesFromSteps(comptime T: type, steps: i64) !T {
    const steps_float: f64 = @as(f64, @floatFromInt(steps));
    const coef: f64 = 7.2;

    const res = steps_float * coef;

    switch (@typeInfo(T)) {
        .int, .comptime_int => {
            if (steps < 0 and std.math.minInt(T) >= 0) {
                return TimeError.CantConvertSignedToUnsigned;
            }

            const res_int: i64 = @intFromFloat(@round(res));

            if (res_int < std.math.minInt(T) or res_int > std.math.maxInt(T)) {
                return TimeError.ReturnVarTypeTooSmall;
            } else {
                return @intCast(res_int);
            }
        },
        .float, .comptime_float => return @floatCast(res),
        else => return TimeError.UnsupportedReturnType,
    }
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

test "getStepsFromMinutes - u8 - 0" {
    const res = try getStepsFromMinutes(u8, 0);
    try std.testing.expect(res == 0);
}

test "getStepsFromMinutes - u8 - 3" {
    const res = try getStepsFromMinutes(u8, 3);
    try std.testing.expect(res == 0);
}

test "getStepsFromMinutes - u8 - 6" {
    const res = try getStepsFromMinutes(u8, 6);
    try std.testing.expect(res == 1);
}

test "getStepsFromMinutes - u8 - -6" {
    const res = getStepsFromMinutes(u8, -6);
    try std.testing.expect(res == TimeError.CantConvertSignedToUnsigned);
}

test "getStepsFromMinutes - []const u8 - 5" {
    const res = getStepsFromMinutes([]const u8, 5);
    try std.testing.expect(res == TimeError.UnsupportedReturnType);
}

test "getStepsFromMinutes - u8 - 50000" {
    const res = getStepsFromMinutes(u8, 50000);
    try std.testing.expect(res == TimeError.ReturnVarTypeTooSmall);
}

test "getStepsFromMinutes - i16 - 50000" {
    const res = try getStepsFromMinutes(i16, 50000);
    try std.testing.expect(res == 6944);
}

test "getStepsFromMinutes - i16 - -50000" {
    const res = try getStepsFromMinutes(i16, -50000);
    try std.testing.expect(res == -6944);
}

test "getStepsFromMinutes - f16 - 6" {
    const res = try getStepsFromMinutes(f16, 6);
    try std.testing.expect(@abs(res - 0.83333) <= 0.001);
}

test "getStepsFromMinutes - f32 - -45000" {
    const res = try getStepsFromMinutes(f32, -45000);
    try std.testing.expect(@abs(res - (-6250)) <= 0.001);
}

test "getMinutesFromSteps - u8 - 0" {
    const res = try getMinutesFromSteps(u8, 0);
    try std.testing.expect(res == 0);
}

test "getMinutesFromSteps - u8 - 2" {
    const res = try getMinutesFromSteps(u8, 2);
    try std.testing.expect(res == 14);
}

test "getMinutesFromSteps - u8 - 3" {
    const res = try getMinutesFromSteps(u8, 3);
    try std.testing.expect(res == 22);
}

test "getMinutesFromSteps - u8 - -3" {
    const res = getMinutesFromSteps(u8, -3);
    try std.testing.expect(res == TimeError.CantConvertSignedToUnsigned);
}

test "getMinutesFromSteps - []const u8 - 5" {
    const res = getMinutesFromSteps([]const u8, 5);
    try std.testing.expect(res == TimeError.UnsupportedReturnType);
}

test "getMinutesFromSteps - u8 - 5000" {
    const res = getMinutesFromSteps(u8, 5000);
    try std.testing.expect(res == TimeError.ReturnVarTypeTooSmall);
}

test "getMinutesFromSteps - i32 - 6944" {
    const res = try getMinutesFromSteps(i32, 6944);
    try std.testing.expect(res == 49997);
}

test "getMinutesFromSteps - i32 - -6944" {
    const res = try getMinutesFromSteps(i32, -6944);
    try std.testing.expect(res == -49997);
}

test "getMinutesFromSteps - f16 - 6" {
    const res = try getMinutesFromSteps(f16, 6);
    try std.testing.expect(@abs(res - 43.2) <= 0.001);
}

test "getMinutesFromSteps - f32 - -5386" {
    const res = try getMinutesFromSteps(f32, -5386);
    try std.testing.expect(@abs(res - (-38779.20000)) <= 0.001);
}
