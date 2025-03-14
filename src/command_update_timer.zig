const std = @import("std");

const ansi = @import("ansi_codes.zig");
const base62_helper = @import("base62_helper.zig");
const dt = @import("data_types.zig");
const globals = @import("globals.zig");

const ArgumentParser = @import("argument_parser.zig").ArgumentParser;

/// Update a timer
pub fn cmd(args: *ArgumentParser) !void {
    const w = std.io.getStdOut().writer();
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
                var buf_id_timer: [4]u8 = undefined;
                const str_id_timer = try std.fmt.bufPrint(&buf_id_timer, "{d}", .{cur_timer.id_last_timer});
                const str_id_thing = base62_helper.b10ToB62(&buf_str_id, cur_timer.id_thing);
                try w.print("Updated timer {s}{s}-{s}{s}. TODO new start and duration\n", .{ ansi.colid, str_id_thing, str_id_timer, ansi.colres });
                return;
            } else |err| {
                try w.print("Error: when trying to update a timer - {}\n", .{err});
                return err;
            }
        }

        // if we reach this point, there was no argument with the command but
        // there is no operation that we can perform
        _ = try w.write("There is no immediate last timer to update and we could not parse a specific timer id\n");
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
        std.debug.print("Error: impossible to parse the ID of the timer: {}\n", .{err});
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
        _ = try w.write("Nothing to update on the timer");
        _ = try w.write("You can specify a duration (with -d), a duration offset (with -dm or -dl) or start time offset (with -sm or -sl)");
        _ = try w.write("Ex: '-dm :20' to add 20 minutes to the duration. Or '-sl 1:34' to subtract 1 hour 34 minutes from current start time");
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

    try w.print("Updated timer {s}{s}{s} of {s}{s}{s} - {s}{s}{s}\n", .{ ansi.colid, str_id_timer, ansi.colres, ansi.colid, str_id_thing, ansi.colres, ansi.colemp, name_thing, ansi.colres });
}

/// Print out help for the update-timer command
pub fn help() !void {
    try std.io.getStdOut().writer().print(
        \\Usage: {s}mtlt update-timer [timer_id]{s}
        \\
        \\Updates the given timer.
        \\
        \\If no ID is provided, it updates the last previous timer. You can see what
        \\the last previous timer is by using {s}mtlt{s} without any sub-command.
        \\
        \\Options:
        \\  {s}-sl{s}, {s}--start-less{s}       Amount of time to retrieve from start time
        \\  {s}-sm{s}, {s}--start-more{s}       Amount of time to add to start time
        \\  {s}-dl{s}, {s}--duration-less{s}    Amount of time to retrieve from duration
        \\  {s}-dm{s}, {s}--duration-more{s}    Amount of time to add to duration
        \\
        \\Examples:
        \\  {s}mtlt update-timer -sl 10 -dm 10{s}
        \\      Update the current timer to start it 10 minutes sooner and make it last 10
        \\      minutes more
        \\
        \\  {s}mtlt update-timer 3b-4 -dl 1:05{s}
        \\      Update the timer with id '3b-4' to make it last 1 hour and 5 minutes less
        \\
    , .{
        ansi.colemp, ansi.colres,
        ansi.colemp, ansi.colres,
        ansi.colid,  ansi.colres,
        ansi.colid,  ansi.colres,
        ansi.colid,  ansi.colres,
        ansi.colid,  ansi.colres,
        ansi.colid,  ansi.colres,
        ansi.colid,  ansi.colres,
        ansi.colid,  ansi.colres,
        ansi.colid,  ansi.colres,
        ansi.colemp, ansi.colres,
        ansi.colemp, ansi.colres,
    });
}
