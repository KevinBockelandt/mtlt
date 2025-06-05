const std = @import("std");

const ansi = @import("ansi_codes.zig");
const dt = @import("data_types.zig");
const globals = @import("globals.zig");
const id_helper = @import("id_helper.zig");
const it_helper = @import("integration_tests_helper.zig");
const th = @import("time_helper.zig");

const ArgumentParser = @import("argument_parser.zig").ArgumentParser;
const DataOperationError = @import("data_file_writer.zig").DataOperationError;

/// Add a new timer to the data file
pub fn cmd(args: *ArgumentParser) !void {
    const cur_time = th.curTimestamp();
    const cur_timer = try globals.dfr.getCurrentTimer();
    var id_thing: u19 = 0;

    // if there was an argument in the command line
    if (args.*.payload != null) {
        id_thing = id_helper.b62ToB10(args.*.payload.?) catch |err| {
            switch (err) {
                id_helper.Base62Error.TooBig => try globals.printer.errIdTooBig(),
                id_helper.Base62Error.ContainsInvalidCharacters => try globals.printer.errIdInvalidCharacters(),
            }
            return;
        };
    } else {
        // at this point we know there was no ID argument
        if (cur_timer.id_thing != 0) {
            id_thing = cur_timer.id_thing;
        } else {
            try globals.printer.errMissingIdThing();
            return;
        }
    }

    // get a string for the thing ID
    var buf_str_id: [4]u8 = undefined;
    const str_id = id_helper.b10ToB62(&buf_str_id, id_thing);

    //  get the duration of the timer to add
    if (args.*.duration == null) {
        try globals.printer.errDurationMissing();
        return;
    }
    const duration = try th.getMinutesFromSteps(u12, args.*.duration.?);

    var start_time = cur_time;

    // If there is a start-less argument, compute start-time accordingly
    if (args.*.start_less) |sl| {
        const ssl = try th.getMinutesFromSteps(u25, sl);

        // check that the offset is not too big
        if (cur_time < ssl) {
            try globals.printer.errStartOffsetTooBig(try th.getStepsFromMinutes(u25, cur_time));
            return;
        }

        start_time = cur_time - ssl;
    }

    // If there is a start-more argument, compute start-time accordingly
    if (args.*.start_more) |sm| {
        const ssm = try th.getMinutesFromSteps(u25, sm);
        const mins_until_max = std.math.maxInt(u25) - cur_time;

        // check that the offset is not too big
        if (mins_until_max < ssm) {
            try globals.printer.errStartOffsetTooBig(try th.getStepsFromMinutes(u25, mins_until_max));
            return;
        }

        start_time = cur_time + ssm;
    }

    if (globals.dfw.addTimerToThing(id_thing, start_time, duration)) |id_timer| {
        try globals.printer.addedTimer(str_id, id_timer);

        try globals.dfw.updateCurrentTimer(.{
            .id_thing = id_thing,
            .id_last_timer = id_timer,
            .start = 0,
        });
    } else |err| {
        switch (err) {
            DataOperationError.TooManyTimers => try globals.printer.errTooManyTimers(),
            else => try globals.printer.errUnexpectedTimerAddition(err),
        }
        return;
    }
}

/// Print out help for the add-timer command
pub fn help() !void {
    try std.io.getStdOut().writer().print(
        \\Usage: {s}mtlt add-timer [thing_id] -d <duration>{s}
        \\
        \\Adds a new timer for the given thing. The duration is mandatory and expressed in
        \\steps. Unless an offset is specified, the start time for the timer is right now.
        \\
        \\If no ID is provided, it adds a timer to the current thing. You can see what
        \\the current thing is by using {s}mtlt{s} without any sub-command.
        \\
        \\Options:
        \\  {s}-sl{s}, {s}--start-less{s}  Number of steps to remove from now to get start time
        \\  {s}-sm{s}, {s}--start-more{s}  Number of steps to add to now to get start time
        \\  {s}-d{s},  {s}--duration{s}    Duration of the timer to add
        \\
        \\Examples:
        \\  {s}mtlt add-timer -sl 10 -d 10{s}
        \\      Add a timer to the current thing which started 10 steps ago and
        \\      lasted 10 steps.
        \\
        \\  {s}mtlt add-timer 3b -d 25{s}
        \\      Add a timer to the thing with ID 3b which starts just now and lasts 25 steps.
        \\
        \\  {s}mtlt add-timer F4 -sm 5 -d 15{s}
        \\      Add a timer to the thing with id F4 which will start in 5 steps and last 15
        \\      steps.
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

test "no current thing - no arg id" {
    var ac_file = try it_helper.getStarterFile();
    ac_file.cur_timer.id_thing = 0;
    var args: ArgumentParser = .{};

    try it_helper.performTest(.{
        .cmd = cmd,
        .args = &args,
        .ac_file = ac_file,
        .ex_stderr = "No ID provided and no current thing to operate on.\n",
    });
}

test "no current thing - arg id ok - duration ok" {
    const cur_time = th.curTimestamp();
    const dur: u12 = 36;

    var ac_file = try it_helper.getSmallFile(cur_time);
    ac_file.cur_timer.id_thing = 0;

    var ex_file = try it_helper.getSmallFile(cur_time);
    ex_file.cur_timer.id_thing = 3;
    ex_file.cur_timer.id_last_timer = 1;
    var timers = try globals.allocator.alloc(dt.Timer, 1);
    timers[0] = .{ .id = 1, .duration = dur, .start = cur_time };
    ex_file.things.items[0].timers = timers[0..];

    var args: ArgumentParser = .{ .payload = "3", .duration = 5 };

    var buf_ex_stdout: [256]u8 = undefined;
    const ex_stdout = try std.fmt.bufPrint(&buf_ex_stdout, "Added timer {s}1@3{s}\n", .{ ansi.colid, ansi.colres });

    try it_helper.performTest(.{
        .cmd = cmd,
        .args = &args,
        .ac_file = ac_file,
        .ex_file = ex_file,
        .ex_stdout = ex_stdout,
        .ex_stderr = "",
    });
}

test "current thing ok - duration ok" {
    const cur_time = th.curTimestamp();
    const dur: u12 = 36;

    var ex_file = try it_helper.getSmallFile(cur_time);
    ex_file.cur_timer.id_last_timer = 1;
    var timers = try globals.allocator.alloc(dt.Timer, 1);
    timers[0] = .{ .id = 1, .duration = dur, .start = cur_time };
    ex_file.things.items[2].timers = timers[0..];

    var args: ArgumentParser = .{ .duration = 5 };

    var buf_ex_stdout: [256]u8 = undefined;
    const ex_stdout = try std.fmt.bufPrint(&buf_ex_stdout, "Added timer {s}1@1{s}\n", .{ ansi.colid, ansi.colres });

    try it_helper.performTest(.{
        .cmd = cmd,
        .args = &args,
        .ac_file = try it_helper.getSmallFile(cur_time),
        .ex_file = ex_file,
        .ex_stdout = ex_stdout,
        .ex_stderr = "",
    });
}

test "start-less too big" {
    const cur_time = th.curTimestamp();

    const max_start_less: u25 = try th.getStepsFromMinutes(u25, cur_time);
    var args: ArgumentParser = .{ .duration = 5, .start_less = max_start_less + 1 };

    var buf_ex_stderr: [256]u8 = undefined;
    const ex_stderr = try std.fmt.bufPrint(&buf_ex_stderr, "The time offset between now and the start of the timer is too big. Maximum is: {d} steps.\n", .{max_start_less});

    try it_helper.performTest(.{
        .cmd = cmd,
        .args = &args,
        .ac_file = try it_helper.getSmallFile(cur_time),
        .ex_file = try it_helper.getSmallFile(cur_time),
        .ex_stderr = ex_stderr,
        .ex_stdout = "",
    });
}

test "start-less 0" {
    const cur_time = th.curTimestamp();
    const dur: u12 = 36;

    var ex_file = try it_helper.getSmallFile(cur_time);
    ex_file.cur_timer.id_last_timer = 1;
    var timers = try globals.allocator.alloc(dt.Timer, 1);
    timers[0] = .{ .id = 1, .duration = dur, .start = cur_time };
    ex_file.things.items[2].timers = timers[0..];

    var args: ArgumentParser = .{ .duration = 5, .start_less = 0 };

    var buf_ex_stdout: [256]u8 = undefined;
    const ex_stdout = try std.fmt.bufPrint(&buf_ex_stdout, "Added timer {s}1@1{s}\n", .{ ansi.colid, ansi.colres });

    try it_helper.performTest(.{
        .cmd = cmd,
        .args = &args,
        .ac_file = try it_helper.getSmallFile(cur_time),
        .ex_file = ex_file,
        .ex_stdout = ex_stdout,
        .ex_stderr = "",
    });
}

test "start-more too big" {
    const cur_time = th.curTimestamp();

    const max_start_more: u25 = try th.getStepsFromMinutes(u25, std.math.maxInt(u25) - cur_time);
    var args: ArgumentParser = .{ .duration = 5, .start_more = max_start_more + 1 };

    var buf_ex_stderr: [256]u8 = undefined;
    const ex_stderr = try std.fmt.bufPrint(&buf_ex_stderr, "The time offset between now and the start of the timer is too big. Maximum is: {d} steps.\n", .{max_start_more});

    try it_helper.performTest(.{
        .cmd = cmd,
        .args = &args,
        .ac_file = try it_helper.getSmallFile(cur_time),
        .ex_file = try it_helper.getSmallFile(cur_time),
        .ex_stderr = ex_stderr,
        .ex_stdout = "",
    });
}

test "no duration" {
    var args: ArgumentParser = .{};

    try it_helper.performTest(.{
        .cmd = cmd,
        .args = &args,
        .ac_file = try it_helper.getSmallFile(th.curTimestamp()),
        .ex_stderr = "You need to specify a duration (with the -d flag)\n",
    });
}

test "too much timers" {
    const cur_time = th.curTimestamp();

    var ac_file = try it_helper.getSmallFile(cur_time);

    // create the maximum number of timers possible for this thing
    var timers = try globals.allocator.alloc(dt.Timer, 2047);
    for (0..2047) |i| {
        timers[i] = .{ .id = @intCast(2047 - i), .duration = 10, .start = cur_time };
    }
    ac_file.things.items[2].timers = timers[0..];

    const ex_file = try ac_file.clone();

    var buf_ex_stderr: [1024]u8 = undefined;
    const ex_stderr = try std.fmt.bufPrint(&buf_ex_stderr, "The maximum number of timers for this thing is reached.\nDeleting existing timers will not help. You will need to create a new thing.\n", .{});

    var args = ArgumentParser{ .duration = 5 };

    try it_helper.performTest(.{
        .cmd = cmd,
        .args = &args,
        .ac_file = ac_file,
        .ex_file = ex_file,
        .ex_stdout = "",
        .ex_stderr = ex_stderr,
    });
}
