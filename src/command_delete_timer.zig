const std = @import("std");
const ansi = @import("ansi_codes.zig");
const base62_helper = @import("base62_helper.zig");
const globals = @import("globals.zig");
const user_feedback = @import("user_feedback.zig");

const ArgumentParser = @import("argument_parser.zig").ArgumentParser;

/// Delete the specified timer of a thing from the data file
pub fn cmd(args: *ArgumentParser) !void {
    var buf_str_id: [4]u8 = undefined;

    // if there is no argument with the command
    if (args.*.payload == null) {
        const cur_timer = try globals.dfr.getCurrentTimer();

        // and there is a previous timer to delete
        if (cur_timer.id_thing != 0 and cur_timer.id_last_timer != 0) {
            if (globals.dfw.deleteTimerFromFile(cur_timer.id_thing, cur_timer.id_last_timer)) |_| {
                const str_id_thing = base62_helper.b10ToB62(&buf_str_id, cur_timer.id_thing);
                try user_feedback.deletedTimer(str_id_thing, cur_timer.id_last_timer);
                try globals.dfw.resetIdLastCurrentTimer(cur_timer.id_thing, cur_timer.start);
                return;
            } else |err| {
                try user_feedback.errUnexpectedTimerDeletion(err);
                try globals.dfw.resetIdLastCurrentTimer(cur_timer.id_thing, cur_timer.start);
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

    // Actually delete and write feedback message
    if (globals.dfw.deleteTimerFromFile(id_thing, id_timer)) |_| {
        try user_feedback.deletedTimer(str_id_thing, id_timer);
    } else |err| {
        try user_feedback.errUnexpectedTimerDeletion(err);
        return err;
    }
}

/// Print out help for the delete timer command
pub fn help() !void {
    try std.io.getStdOut().writer().print(
        \\Usage: {s}mtlt delete-timer <timer_id>{s}
        \\
        \\Deletes a timer permanently from the data file.
        \\
        \\If no ID is provided, it updates the last previous timer. You can see what
        \\the last previous timer is by using {s}mtlt{s} without any sub-command.
        \\
        \\You can see the list of timers related to a thing with the {s}infos{s}
        \\command.
        \\
        \\Examples:
        \\  {s}mtlt delete-timer{s}
        \\      Delete the last previous timer.
        \\
        \\  {s}mtlt delete-timer 3d-2{s}
        \\      Delete the timer with id '3d-2'.
        \\
    , .{
        ansi.colemp, ansi.colres,
        ansi.colemp, ansi.colres,
        ansi.colemp, ansi.colres,
        ansi.colemp, ansi.colres,
        ansi.colemp, ansi.colres,
    });
}
