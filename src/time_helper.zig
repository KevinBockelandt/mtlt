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
    StepVarTypeTooSmall,
};

/// Get the number of minutes since January 1 2020
pub fn curTimestamp() u25 {
    const cur_time_sec: i64 = @intCast(std.time.timestamp() - num_sec_offset_1970_2020);
    return @intCast(@divFloor(cur_time_sec, 60));
}

/// Get the number of steps corresponding to a certain number of minutes
pub fn getStepsFromMinutes(comptime T: type, min: i64) !T {
    const steps: f64 = @as(f64, @floatFromInt(min)) / 7.2;

    // TODO check that `min` is not negative if `T` is unsigned

    if (steps > std.math.maxInt(T)) {
        return TimeError.StepVarTypeTooSmall;
    } else {
        return @intFromFloat(@round(steps));
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
    std.testing.expect(res == 0) catch |err| {
        std.debug.print("Actual: {}\n", .{res});
        return err;
    };
}

test "getStepsFromMinutes - u8 - 3" {
    const res = try getStepsFromMinutes(u8, 3);
    std.testing.expect(res == 0) catch |err| {
        std.debug.print("Actual: {}\n", .{res});
        return err;
    };
}

test "getStepsFromMinutes - u8 - 5" {
    const res = try getStepsFromMinutes(u8, 5);
    std.testing.expect(res == 1) catch |err| {
        std.debug.print("Actual: {}\n", .{res});
        return err;
    };
}

test "getStepsFromMinutes - u8 - 50000" {
    const res = getStepsFromMinutes(u8, 50000);
    try std.testing.expect(res == TimeError.StepVarTypeTooSmall);
}
