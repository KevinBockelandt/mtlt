const std = @import("std");

const ansi = @import("ansi_codes.zig");
const base62_helper = @import("base62_helper.zig");
const globals = @import("globals.zig");
const time_helper = @import("time_helper.zig");
const user_feedback = @import("user_feedback.zig");

const ArgumentParser = @import("argument_parser.zig").ArgumentParser;

/// Add a new timer to the data file
pub fn cmd(args: *ArgumentParser) !void {
    const cur_time = time_helper.curTimestamp();

    if (args.*.payload == null) {
        try user_feedback.errIdThingMissing();
        return;
    }
    const id_thing_str = args.*.payload.?;
    const id_thing_num = try base62_helper.b62ToB10(id_thing_str);

    try args.checkNoStartLessAndMore();

    const duration = try args.checkDurationPresence();

    // Check that there is a start offset value in the command arguments
    if (args.*.start_less == null) {
        try user_feedback.errStartOffsetMissing();
        return;
    }
    const start_less = args.*.start_less.?;

    // Check that the time offset for start is not too big
    if (cur_time < start_less) {
        try user_feedback.errStartOffsetTooBig(cur_time);
        return;
    }

    // compute the absolute value of the start time
    const start_abs = cur_time - start_less;

    if (globals.dfw.addTimerToThing(id_thing_num, start_abs, duration)) |id_timer| {
        try user_feedback.addedTimer(id_thing_str, id_timer);
    } else |err| {
        try user_feedback.errUnexpectedTimerAddition(err);
        return;
    }
}

/// Print out help for the add-timer command
pub fn help() !void {
    try std.io.getStdOut().writer().print("TODO help add-timer\n", .{});
}
