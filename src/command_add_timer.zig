const std = @import("std");

const ansi = @import("ansi_codes.zig");
const base62_helper = @import("base62_helper.zig");
const globals = @import("globals.zig");
const time_helper = @import("time_helper.zig");

const ArgumentParser = @import("argument_parser.zig").ArgumentParser;

/// Add a new timer to the data file
pub fn cmd(args: *ArgumentParser) !void {
    const w = std.io.getStdOut().writer();
    const cur_time = time_helper.curTimestamp();

    if (args.*.payload == null) {
        _ = try w.write("Error: could not parse the id of the thing on which to add a timer\n");
        return;
    }
    const id_thing_str = args.*.payload.?;
    const id_thing_num = try base62_helper.b62ToB10(id_thing_str);

    try args.checkNoStartLessAndMore();

    const duration = try args.checkDurationPresence();

    // Check that there is a start offset value in the command arguments
    if (args.*.start_less == null) {
        _ = try w.write("Error: you need to specify the time offset between now and the start of the timer (with the -sl flag)\n");
        return;
    }
    const start_less = args.*.start_less.?;

    // Check that the time offset for start is not too big
    if (cur_time < start_less) {
        try w.print("Error: the time offset between now and the start of the timer is too big. Maximum is: {d}\n", .{cur_time});
        return;
    }

    // compute the absolute value of the start time
    const start_abs = cur_time - start_less;

    if (globals.dfw.addTimerToThing(id_thing_num, start_abs, duration)) |id_timer| {
        try w.print("Added timer {s}{s}-{d}{s}\n", .{ ansi.colid, id_thing_str, id_timer, ansi.colres });
    } else |err| {
        try w.print("Error: during the addition of a timer. TODO: {}\n", .{err});
        return;
    }
}

/// Print out help for the add-timer command
pub fn help() !void {
    try std.io.getStdOut().writer().print(
        \\Usage: {s}mtlt add-timer [thing_id]{s}
        \\
        \\Adds a new timer for the given thing.
        \\
        \\If no ID is provided, it adds a timer to the current thing. You can see what
        \\the current thing is by using {s}mtlt{s} without any sub-command.
        \\
        \\Options:
        \\  {s}-sl{s}, {s}--start-less{s}     Amount of time to remove from now to get start time
        \\  {s}-sm{s}, {s}--start-more{s}     Amount of time to add to now to get start time
        \\  {s}-d{s},  {s}--duration{s}       Duration of the timer to add
        \\
        \\Examples:
        \\  {s}mtlt add-timer -sl 10 -d 10{s}
        \\      Add a timer to the current thing which started 10 minutes ago and
        \\      lasted 10 minutes.
        \\
        \\  {s}mtlt add-timer 3b -d 1:10{s}
        \\      Add a timer to the thing with ID 3b which started just now and lasts
        \\      1 hour 10 minutes.
        \\
        \\  {s}mtlt add-timer F4 -sm 5 -d 15{s}
        \\      Add a timer to the thing with id F4 which will start in 5 minutes and
        \\      last 15 minutes.
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
        ansi.colemp, ansi.colres,
        ansi.colemp, ansi.colres,
        ansi.colemp, ansi.colres,
    });
}
