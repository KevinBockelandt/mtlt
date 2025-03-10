const std = @import("std");
const ansi = @import("ansi_codes.zig");
const base62_helper = @import("base62_helper.zig");
const globals = @import("globals.zig");

const ArgumentParser = @import("argument_parser.zig").ArgumentParser;

/// Delete the specified timer of a thing from the data file
pub fn cmd(args: *ArgumentParser) !void {
    const w = std.io.getStdOut().writer();
    var buf_str_id: [4]u8 = undefined;

    // if there is no argument with the command
    if (args.*.payload == null) {
        const cur_timer = try globals.dfr.getCurrentTimer();

        // and there is a previous timer to delete
        if (cur_timer.id_thing != 0 and cur_timer.id_last_timer != 0) {
            if (globals.dfw.deleteTimerFromFile(cur_timer.id_thing, cur_timer.id_last_timer)) |_| {
                var buf_id_timer: [4]u8 = undefined;
                const str_id_timer = try std.fmt.bufPrint(&buf_id_timer, "{d}", .{cur_timer.id_last_timer});
                const str_id_thing = base62_helper.b10ToB62(&buf_str_id, cur_timer.id_thing);
                try w.print("Deleted timer {s}{s}-{s}{s}\n", .{ ansi.colid, str_id_thing, str_id_timer, ansi.colres });
                try globals.dfw.resetIdLastCurrentTimer(cur_timer.id_thing, cur_timer.start);
                return;
            } else |err| {
                try w.print("Error: when trying to delete a timer - {}\n", .{err});
                try globals.dfw.resetIdLastCurrentTimer(cur_timer.id_thing, cur_timer.start);
                return err;
            }
        }

        // if we reach this point, there was no argument with the command but
        // there is no operation that we can perform
        _ = try w.write("There is no immediate last timer to delete and we could not parse a specific timer id\n");
        try w.print("Those should have the format {s}<id thing>-<id timer>{s}. For example: {s}b-2{s}\n", .{ ansi.colid, ansi.colres, ansi.colid, ansi.colres });
        return;
    }

    var arg_it = std.mem.splitSequence(u8, args.*.payload.?, "-");

    const str_id_thing = arg_it.first();
    const str_id_timer = arg_it.rest();

    const id_thing = base62_helper.b62ToB10(str_id_thing) catch |err| {
        std.debug.print("Error: impossible to parse the ID of the thing: {}\n", .{err});
        return;
    };
    const id_timer = std.fmt.parseInt(u11, str_id_timer, 10) catch |err| {
        std.debug.print("Error: impossible to parse the ID of the thing: {}\n", .{err});
        return;
    };

    // Actually delete and write feedback message
    if (globals.dfw.deleteTimerFromFile(id_thing, id_timer)) |_| {
        try w.print("Deleted timer {s}{s}-{s}{s}\n", .{ ansi.colid, str_id_thing, str_id_timer, ansi.colres });
    } else |err| {
        try w.print("Error: when trying to delete a timer - {}\n", .{err});
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
        \\You can see the list of timers related to a thing with the {s}infos{s}
        \\command.
        \\
        \\Examples:
        \\  {s}mtlt delete-timer{s}
        \\  {s}mtlt delete-timer 3d-2{s}
        \\
    , .{
        ansi.colemp, ansi.colres,
        ansi.colemp, ansi.colres,
        ansi.colemp, ansi.colres,
        ansi.colemp, ansi.colres,
    });
}
