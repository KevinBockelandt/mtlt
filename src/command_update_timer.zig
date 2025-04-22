const std = @import("std");

const ansi = @import("ansi_codes.zig");
const id_helper = @import("id_helper.zig");
const dt = @import("data_types.zig");
const globals = @import("globals.zig");

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
                const str_id_thing = id_helper.b10ToB62(&buf_str_id, cur_timer.id_thing);
                try globals.printer.updatedTimer(str_id_thing, cur_timer.id_last_timer);

                // TODO pass the new start offset
                try globals.printer.reportStarted(0);
                // TODO pass the new duration
                try globals.printer.reportDuration(0);
                return;
            } else |err| {
                try globals.printer.errUnexpectedUpdateTimer(err);
                return err;
            }
        }

        try globals.printer.noLastTimerToWorkOn();
        return;
    }

    var arg_it = std.mem.splitSequence(u8, args.*.payload.?, "-");

    const str_id_thing = arg_it.first();
    const str_id_timer = arg_it.rest();

    const id_thing = id_helper.b62ToB10(str_id_thing) catch |err| {
        try globals.printer.errUnexpectedTimerIdParsing(err);
        return;
    };
    const id_timer = std.fmt.parseInt(u11, str_id_timer, 10) catch |err| {
        try globals.printer.errUnexpectedTimerIdParsing(err);
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
        try globals.printer.nothingToUpdateTimer();
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

    try globals.printer.updatedTimer(str_id_thing, id_timer);
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
