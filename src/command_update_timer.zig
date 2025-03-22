const std = @import("std");

const ansi = @import("ansi_codes.zig");
const base62_helper = @import("base62_helper.zig");
const dt = @import("data_types.zig");
const globals = @import("globals.zig");
const user_feedback = @import("user_feedback.zig");

const ArgumentParser = @import("argument_parser.zig").ArgumentParser;

/// Update a timer
pub fn cmd(args: *ArgumentParser) !void {
    var buf_str_id: [4]u8 = undefined;

    try args.*.checkOnlyOneTypeDurationArg();
    try args.*.checkNoStartLessAndMore();

    // if there is no argument with the command
    if (args.*.payload == null) {
        const cur_timer = try globals.dfr.getCurrentTimer();

        // and there is a previous timer to update
        if (cur_timer.id_thing != 0 and cur_timer.id_last_timer != 0) {
            if (globals.dfw.updateTimer(.{
                .id = cur_timer.id_last_timer,
                .duration = args.*.duration,
                .duration_off = if (args.*.duration_less == null) args.*.duration_more else args.*.duration_less,
                .add_duration_off = args.*.duration_less == null,
                .start_off = if (args.*.start_less == null) args.*.start_more else args.*.start_less,
                .add_start_off = args.*.start_less == null,
            }, cur_timer.id_thing)) |_| {
                const str_id_thing = base62_helper.b10ToB62(&buf_str_id, cur_timer.id_thing);
                try user_feedback.updatedTimer(str_id_thing, cur_timer.id_last_timer);

                // TODO pass the new start offset
                try user_feedback.reportStarted(0);
                // TODO pass the new duration
                try user_feedback.reportDuration(0);
                return;
            } else |err| {
                try user_feedback.errUnexpectedUpdateTimer(err);
                return err;
            }
        }

        try user_feedback.noLastTimerToWorkOn();
        return;
    }

    var arg_it = std.mem.splitSequence(u8, args.*.payload.?, "-");

    const str_id_thing = arg_it.first();
    const str_id_timer = arg_it.rest();

    const id_thing = base62_helper.b62ToB10(str_id_thing) catch |err| {
        try user_feedback.errUnexpectedTimerIdParsing(err);
        return;
    };
    const id_timer = std.fmt.parseInt(u11, str_id_timer, 10) catch |err| {
        try user_feedback.errUnexpectedTimerIdParsing(err);
        return;
    };

    // get the values to pass regarding the duration offset
    var duration_off: ?u12 = null;
    var add_duration_off = false;

    if (args.*.duration_more != null) {
        duration_off = args.*.duration_more;
        add_duration_off = true;
    } else if (args.*.duration_less != null) {
        duration_off = args.*.duration_less;
        add_duration_off = false;
    }

    // get the values to pass regarding the start offset
    var start_off: ?u25 = null;
    var add_start_off = false;

    if (args.*.start_more != null) {
        start_off = args.*.start_more;
        add_start_off = true;
    } else if (args.*.start_less != null) {
        start_off = args.*.start_less;
        add_start_off = false;
    }

    if (args.*.duration == null and duration_off == null and start_off == null) {
        try user_feedback.nothingToUpdateTimer();
    }

    const update_data = dt.TimerToUpdate{
        .id = id_timer,
        .duration = args.*.duration,
        .duration_off = duration_off,
        .add_duration_off = add_duration_off,
        .start_off = start_off,
        .add_start_off = add_start_off,
    };

    try globals.dfw.updateTimer(update_data, id_thing);

    // display feedback message
    const fpt = try globals.dfr.getFixedPartThing(id_thing);
    const name_thing = try globals.allocator.alloc(u8, fpt.lgt_name);
    defer globals.allocator.free(name_thing);
    _ = try globals.data_file.readAll(name_thing);

    try user_feedback.updatedTimer(str_id_thing, id_timer);
}

/// Print out help for the update-timer command
pub fn help() !void {
    try std.io.getStdOut().writer().print("TODO help update-timer\n", .{});
}
