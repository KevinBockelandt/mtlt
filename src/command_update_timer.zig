const std = @import("std");

const ansi = @import("ansi_codes.zig");
const id_helper = @import("id_helper.zig");
const dt = @import("data_types.zig");
const globals = @import("globals.zig");
const it_helper = @import("integration_tests_helper.zig");
const th = @import("time_helper.zig");

const ArgumentParser = @import("argument_parser.zig").ArgumentParser;
const DataOperationError = @import("data_file_writer.zig").DataOperationError;

/// Update a timer
pub fn cmd(args: *ArgumentParser) !void {
    var buf_str_id: [4]u8 = undefined;

    try args.*.checkOnlyOneTypeDurationArg();
    try args.*.checkNoStartLessAndMore();

    var id_thing: u19 = undefined;
    var id_timer: u11 = undefined;
    var str_id_thing: []const u8 = undefined;
    var str_id_timer: []const u8 = undefined;

    // if there is no argument with the command
    if (args.*.payload == null) {
        const cur_timer = try globals.dfr.getCurrentTimer();

        // check there is a last timer id to work on
        if (cur_timer.id_thing != 0 and cur_timer.id_last_timer != 0) {
            id_thing = cur_timer.id_thing;
            id_timer = cur_timer.id_last_timer;
            str_id_thing = id_helper.b10ToB62(&buf_str_id, id_thing);
        } else {
            try globals.printer.noLastTimerToWorkOn();
            return;
        }
    } else {
        var arg_it = std.mem.splitSequence(u8, args.*.payload.?, "@");

        str_id_timer = arg_it.first();
        str_id_thing = arg_it.rest();

        id_thing = id_helper.b62ToB10(str_id_thing) catch |err| {
            try globals.printer.errUnexpectedTimerIdParsing(err);
            return;
        };
        id_timer = std.fmt.parseInt(u11, str_id_timer, 10) catch |err| {
            try globals.printer.errUnexpectedTimerIdParsing(err);
            return;
        };
    }

    // get the values to pass regarding the duration offset
    var duration_off: ?u12 = null;
    var add_duration_off = false;

    if (args.*.duration_more != null) {
        duration_off = try th.getMinutesFromSteps(u12, args.*.duration_more.?);
        add_duration_off = true;
    } else if (args.*.duration_less != null) {
        duration_off = try th.getMinutesFromSteps(u12, args.*.duration_less.?);
        add_duration_off = false;
    }

    // get the values to pass regarding the start offset
    var start_off: ?u25 = null;
    var add_start_off = false;

    if (args.*.start_more != null) {
        start_off = try th.getMinutesFromSteps(u25, args.*.start_more.?);
        add_start_off = true;
    } else if (args.*.start_less != null) {
        start_off = try th.getMinutesFromSteps(u25, args.*.start_less.?);
        add_start_off = false;
    }

    if (args.*.duration == null and duration_off == null and start_off == null) {
        try globals.printer.nothingToUpdateTimer();
    }

    const duration: ?u12 = if (args.*.duration == null)
        null
    else
        try th.getMinutesFromSteps(u12, args.*.duration.?);

    const update_data = dt.TimerToUpdate{
        .id = id_timer,
        .duration = duration,
        .duration_off = duration_off,
        .add_duration_off = add_duration_off,
        .start_off = start_off,
        .add_start_off = add_start_off,
    };

    const new_timer = globals.dfw.updateTimer(update_data, id_thing) catch |err| {
        switch (err) {
            DataOperationError.DurationBelowMin => try globals.printer.errStartLessTooBig(),
            DataOperationError.DurationAboveMax => try globals.printer.errStartMoreTooBig(),
            DataOperationError.StartBelowMin => try globals.printer.errStartLessTooBig(),
            DataOperationError.StartInFuture => try globals.printer.errStartMoreTooBig(),
            DataOperationError.TimerNotFound => try globals.printer.noTimerWithId(args.*.payload.?),
            else => try globals.printer.errUnexpectedUpdateTimer(err),
        }
        return;
    };

    // display feedback message
    const fpt = try globals.dfr.getFixedPartThing(id_thing);
    const name_thing = try globals.allocator.alloc(u8, fpt.lgt_name);
    defer globals.allocator.free(name_thing);
    _ = try globals.data_file.readAll(name_thing);

    try globals.printer.updatedTimer(str_id_thing, id_timer);
    try globals.printer.reportUpdateTimerStarted(try th.getStepsFromMinutes(u25, th.curTimestamp() - new_timer.start));
    try globals.printer.reportUpdateTimerDuration(try th.getStepsFromMinutes(u12, new_timer.duration));
}

/// Print out help for the update-timer command
pub fn help() !void {
    try std.io.getStdOut().writer().print(
        \\Usage: {s}mtlt update-timer [timer_id]{s}
        \\
        \\Update the given timer.
        \\
        \\If no ID is provided, it updates the last previous timer. You can see what
        \\the last previous timer is by using {s}mtlt{s} without any sub-command.
        \\
        \\Options:
        \\  {s}-sl{s}, {s}--start-less{s}       How many steps to retrieve from start time
        \\  {s}-sm{s}, {s}--start-more{s}       How many steps to add to start time
        \\  {s}-d{s},  {s}--duration{s}         How many steps for the complete duration
        \\  {s}-dl{s}, {s}--duration-less{s}    How many steps to retrieve from duration
        \\  {s}-dm{s}, {s}--duration-more{s}    How many steps to add to duration
        \\
        \\Examples:
        \\  {s}mtlt update-timer -d 18{s}
        \\      Update the current timer so that it's duration is 18 steps.
        \\
        \\  {s}mtlt update-timer -sl 10 -dm 10{s}
        \\      Update the current timer to start it 10 steps sooner and increase it's
        \\      duration by 10 steps.
        \\
        \\  {s}mtlt update-timer 4@3b -dl 22{s}
        \\      Update the timer with id '4@3b' to reduce it's duration by 22 steps.
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
        ansi.colid,  ansi.colres,
        ansi.colid,  ansi.colres,
        ansi.colemp, ansi.colres,
        ansi.colemp, ansi.colres,
        ansi.colemp, ansi.colres,
    });
}

test "update timer - manually specifying ID - ok" {
    const cur_time = th.curTimestamp();

    var ex_file = try it_helper.getSmallFile(cur_time);
    ex_file.things.items[1].timers[0].duration = 72;

    var args: ArgumentParser = .{ .payload = "1@2", .duration = 10 };

    var buf_1: [256]u8 = undefined;
    var buf_2: [256]u8 = undefined;
    var buf_3: [256]u8 = undefined;
    var buf_ex_stdout: [1024]u8 = undefined;

    const str_1 = try std.fmt.bufPrint(&buf_1, "Updated timer {s}1@2{s}\n", .{ ansi.colid, ansi.colres });
    const str_2 = try std.fmt.bufPrint(&buf_2, "  {s}started{s} : {s}{d}{s} steps ago\n", .{ ansi.colemp, ansi.colres, ansi.coldurntr, 26, ansi.colres });
    const str_3 = try std.fmt.bufPrint(&buf_3, "  {s}duration{s}: {s}{d}{s} steps\n", .{ ansi.colemp, ansi.colres, ansi.coldurntr, 10, ansi.colres });
    const ex_stdout = try std.fmt.bufPrint(&buf_ex_stdout, "{s}{s}{s}", .{ str_1, str_2, str_3 });

    try it_helper.performTest(.{
        .cmd = cmd,
        .args = &args,
        .ac_file = try it_helper.getSmallFile(cur_time),
        .ex_file = ex_file,
        .ex_stdout = ex_stdout,
        .ex_stderr = "",
    });
}

test "update timer - manually specifying ID - not existing" {
    const cur_time = th.curTimestamp();
    var args: ArgumentParser = .{ .payload = "4@2", .duration = 10 };

    var buf_ex_stderr: [256]u8 = undefined;
    const ex_stderr = try std.fmt.bufPrint(&buf_ex_stderr, "No timer found with ID {s}4@2{s}.\n", .{ ansi.colid, ansi.colres });

    try it_helper.performTest(.{
        .cmd = cmd,
        .args = &args,
        .ac_file = try it_helper.getSmallFile(cur_time),
        .ex_file = try it_helper.getSmallFile(cur_time),
        .ex_stdout = "",
        .ex_stderr = ex_stderr,
    });
}

test "update timer - manually specifying ID - invalid" {
    const cur_time = th.curTimestamp();

    var args: ArgumentParser = .{ .payload = "2.1", .duration = 10 };

    var buf_ex_stdout: [256]u8 = undefined;
    const ex_stderr = try std.fmt.bufPrint(&buf_ex_stdout, "Unexpected error during parsing of the timer ID.\nerror.InvalidCharacter\n", .{});

    try it_helper.performTest(.{
        .cmd = cmd,
        .args = &args,
        .ac_file = try it_helper.getSmallFile(cur_time),
        .ex_file = try it_helper.getSmallFile(cur_time),
        .ex_stdout = "",
        .ex_stderr = ex_stderr,
    });
}

test "update timer - last timer ok - ok" {
    const cur_time = th.curTimestamp();

    var ac_file = try it_helper.getSmallFile(cur_time);
    ac_file.cur_timer.id_thing = 2;
    ac_file.cur_timer.id_last_timer = 1;

    var ex_file = try it_helper.getSmallFile(cur_time);
    ex_file.cur_timer.id_thing = 2;
    ex_file.cur_timer.id_last_timer = 1;
    ex_file.things.items[1].timers[0].duration = 72;

    var args: ArgumentParser = .{ .duration = 10 };

    var buf_1: [256]u8 = undefined;
    var buf_2: [256]u8 = undefined;
    var buf_3: [256]u8 = undefined;
    var buf_ex_stdout: [1024]u8 = undefined;

    const str_1 = try std.fmt.bufPrint(&buf_1, "Updated timer {s}1@2{s}\n", .{ ansi.colid, ansi.colres });
    const str_2 = try std.fmt.bufPrint(&buf_2, "  {s}started{s} : {s}{d}{s} steps ago\n", .{ ansi.colemp, ansi.colres, ansi.coldurntr, 26, ansi.colres });
    const str_3 = try std.fmt.bufPrint(&buf_3, "  {s}duration{s}: {s}{d}{s} steps\n", .{ ansi.colemp, ansi.colres, ansi.coldurntr, 10, ansi.colres });
    const ex_stdout = try std.fmt.bufPrint(&buf_ex_stdout, "{s}{s}{s}", .{ str_1, str_2, str_3 });

    try it_helper.performTest(.{
        .cmd = cmd,
        .args = &args,
        .ac_file = ac_file,
        .ex_file = ex_file,
        .ex_stdout = ex_stdout,
        .ex_stderr = "",
    });
}

test "update timer - no ID available" {
    const cur_time = th.curTimestamp();
    var args: ArgumentParser = .{ .duration = 10 };

    var buf_ex_stdout: [512]u8 = undefined;
    const ex_stdout = try std.fmt.bufPrint(&buf_ex_stdout, "There is no immediate last timer to work on. Please specify an ID.\nIt should have the format {s}<id thing>-<id timer>{s}. For example: {s}b-2{s}\n", .{ ansi.colid, ansi.colres, ansi.colid, ansi.colres });

    try it_helper.performTest(.{
        .cmd = cmd,
        .args = &args,
        .ac_file = try it_helper.getSmallFile(cur_time),
        .ex_file = try it_helper.getSmallFile(cur_time),
        .ex_stdout = ex_stdout,
        .ex_stderr = "",
    });
}

test "update timer - duration ok" {
    const cur_time = th.curTimestamp();

    var ex_file = try it_helper.getSmallFile(cur_time);
    ex_file.things.items[1].timers[0].duration = 72;

    var args: ArgumentParser = .{ .payload = "1@2", .duration = 10 };

    var buf_1: [256]u8 = undefined;
    var buf_2: [256]u8 = undefined;
    var buf_3: [256]u8 = undefined;
    var buf_ex_stdout: [1024]u8 = undefined;

    const str_1 = try std.fmt.bufPrint(&buf_1, "Updated timer {s}1@2{s}\n", .{ ansi.colid, ansi.colres });
    const str_2 = try std.fmt.bufPrint(&buf_2, "  {s}started{s} : {s}{d}{s} steps ago\n", .{ ansi.colemp, ansi.colres, ansi.coldurntr, 26, ansi.colres });
    const str_3 = try std.fmt.bufPrint(&buf_3, "  {s}duration{s}: {s}{d}{s} steps\n", .{ ansi.colemp, ansi.colres, ansi.coldurntr, 10, ansi.colres });
    const ex_stdout = try std.fmt.bufPrint(&buf_ex_stdout, "{s}{s}{s}", .{ str_1, str_2, str_3 });

    try it_helper.performTest(.{
        .cmd = cmd,
        .args = &args,
        .ac_file = try it_helper.getSmallFile(cur_time),
        .ex_file = ex_file,
        .ex_stdout = ex_stdout,
        .ex_stderr = "",
    });
}

test "update timer - duration less too big" {
    const cur_time = th.curTimestamp();

    var args: ArgumentParser = .{ .payload = "1@2", .duration_less = 100 };

    var buf_ex_stderr: [1024]u8 = undefined;
    const ex_stderr = try std.fmt.bufPrint(&buf_ex_stderr, "The value of the start-less option is too big. No operation performed.\n", .{});

    try it_helper.performTest(.{
        .cmd = cmd,
        .args = &args,
        .ac_file = try it_helper.getSmallFile(cur_time),
        .ex_file = try it_helper.getSmallFile(cur_time),
        .ex_stdout = "",
        .ex_stderr = ex_stderr,
    });
}

test "update timer - duration less ok" {
    const cur_time = th.curTimestamp();

    var ex_file = try it_helper.getSmallFile(cur_time);
    ex_file.things.items[1].timers[0].duration = 72;

    var args: ArgumentParser = .{ .payload = "1@2", .duration_less = 10 };

    var buf_1: [256]u8 = undefined;
    var buf_2: [256]u8 = undefined;
    var buf_3: [256]u8 = undefined;
    var buf_ex_stdout: [1024]u8 = undefined;

    const str_1 = try std.fmt.bufPrint(&buf_1, "Updated timer {s}1@2{s}\n", .{ ansi.colid, ansi.colres });
    const str_2 = try std.fmt.bufPrint(&buf_2, "  {s}started{s} : {s}{d}{s} steps ago\n", .{ ansi.colemp, ansi.colres, ansi.coldurntr, 26, ansi.colres });
    const str_3 = try std.fmt.bufPrint(&buf_3, "  {s}duration{s}: {s}{d}{s} steps\n", .{ ansi.colemp, ansi.colres, ansi.coldurntr, 10, ansi.colres });
    const ex_stdout = try std.fmt.bufPrint(&buf_ex_stdout, "{s}{s}{s}", .{ str_1, str_2, str_3 });

    try it_helper.performTest(.{
        .cmd = cmd,
        .args = &args,
        .ac_file = try it_helper.getSmallFile(cur_time),
        .ex_file = ex_file,
        .ex_stdout = ex_stdout,
        .ex_stderr = "",
    });
}

test "update timer - duration more too big" {
    const cur_time = th.curTimestamp();

    var args: ArgumentParser = .{ .payload = "1@2", .duration_more = try th.getStepsFromMinutes(u12, std.math.maxInt(u12) - 10) };

    var buf_ex_stderr: [1024]u8 = undefined;
    const ex_stderr = try std.fmt.bufPrint(&buf_ex_stderr, "The value of the start-more option is too big. No operation performed.\n", .{});

    try it_helper.performTest(.{
        .cmd = cmd,
        .args = &args,
        .ac_file = try it_helper.getSmallFile(cur_time),
        .ex_file = try it_helper.getSmallFile(cur_time),
        .ex_stdout = "",
        .ex_stderr = ex_stderr,
    });
}

test "update timer - duration more ok" {
    const cur_time = th.curTimestamp();

    var ex_file = try it_helper.getSmallFile(cur_time);
    ex_file.things.items[1].timers[0].duration = 216;

    var args: ArgumentParser = .{ .payload = "1@2", .duration_more = 10 };

    var buf_1: [256]u8 = undefined;
    var buf_2: [256]u8 = undefined;
    var buf_3: [256]u8 = undefined;
    var buf_ex_stdout: [1024]u8 = undefined;

    const str_1 = try std.fmt.bufPrint(&buf_1, "Updated timer {s}1@2{s}\n", .{ ansi.colid, ansi.colres });
    const str_2 = try std.fmt.bufPrint(&buf_2, "  {s}started{s} : {s}{d}{s} steps ago\n", .{ ansi.colemp, ansi.colres, ansi.coldurntr, 26, ansi.colres });
    const str_3 = try std.fmt.bufPrint(&buf_3, "  {s}duration{s}: {s}{d}{s} steps\n", .{ ansi.colemp, ansi.colres, ansi.coldurntr, 30, ansi.colres });
    const ex_stdout = try std.fmt.bufPrint(&buf_ex_stdout, "{s}{s}{s}", .{ str_1, str_2, str_3 });

    try it_helper.performTest(.{
        .cmd = cmd,
        .args = &args,
        .ac_file = try it_helper.getSmallFile(cur_time),
        .ex_file = ex_file,
        .ex_stdout = ex_stdout,
        .ex_stderr = "",
    });
}

test "update timer - start less too big" {
    const cur_time = th.curTimestamp();

    var args: ArgumentParser = .{ .payload = "1@2", .start_less = try th.getStepsFromMinutes(u25, th.curTimestamp()) };

    var buf_ex_stderr: [128]u8 = undefined;
    const ex_stderr = try std.fmt.bufPrint(&buf_ex_stderr, "The value of the start-less option is too big. No operation performed.\n", .{});

    try it_helper.performTest(.{
        .cmd = cmd,
        .args = &args,
        .ac_file = try it_helper.getSmallFile(cur_time),
        .ex_file = try it_helper.getSmallFile(cur_time),
        .ex_stdout = "",
        .ex_stderr = ex_stderr,
    });
}

test "update timer - start less ok" {
    const cur_time = th.curTimestamp();

    var ex_file = try it_helper.getSmallFile(cur_time);
    ex_file.things.items[1].timers[0].start = cur_time - 262;

    var args: ArgumentParser = .{ .payload = "1@2", .start_less = 10 };

    var buf_1: [256]u8 = undefined;
    var buf_2: [256]u8 = undefined;
    var buf_3: [256]u8 = undefined;
    var buf_ex_stdout: [1024]u8 = undefined;

    const str_1 = try std.fmt.bufPrint(&buf_1, "Updated timer {s}1@2{s}\n", .{ ansi.colid, ansi.colres });
    const str_2 = try std.fmt.bufPrint(&buf_2, "  {s}started{s} : {s}{d}{s} steps ago\n", .{ ansi.colemp, ansi.colres, ansi.coldurntr, 36, ansi.colres });
    const str_3 = try std.fmt.bufPrint(&buf_3, "  {s}duration{s}: {s}{d}{s} steps\n", .{ ansi.colemp, ansi.colres, ansi.coldurntr, 20, ansi.colres });
    const ex_stdout = try std.fmt.bufPrint(&buf_ex_stdout, "{s}{s}{s}", .{ str_1, str_2, str_3 });

    try it_helper.performTest(.{
        .cmd = cmd,
        .args = &args,
        .ac_file = try it_helper.getSmallFile(cur_time),
        .ex_file = ex_file,
        .ex_stdout = ex_stdout,
        .ex_stderr = "",
    });
}

test "update timer - start more gets in the future" {
    const cur_time = th.curTimestamp();

    var args: ArgumentParser = .{ .payload = "1@2", .start_more = 100 };

    var buf_ex_stderr: [128]u8 = undefined;
    const ex_stderr = try std.fmt.bufPrint(&buf_ex_stderr, "The value of the start-more option is too big. No operation performed.\n", .{});

    try it_helper.performTest(.{
        .cmd = cmd,
        .args = &args,
        .ac_file = try it_helper.getSmallFile(cur_time),
        .ex_file = try it_helper.getSmallFile(cur_time),
        .ex_stdout = "",
        .ex_stderr = ex_stderr,
    });
}

test "update timer - start more ok" {
    const cur_time = th.curTimestamp();

    var ex_file = try it_helper.getSmallFile(cur_time);
    ex_file.things.items[1].timers[0].start = cur_time - 118;

    var args: ArgumentParser = .{ .payload = "1@2", .start_more = 10 };

    var buf_1: [256]u8 = undefined;
    var buf_2: [256]u8 = undefined;
    var buf_3: [256]u8 = undefined;
    var buf_ex_stdout: [1024]u8 = undefined;

    const str_1 = try std.fmt.bufPrint(&buf_1, "Updated timer {s}1@2{s}\n", .{ ansi.colid, ansi.colres });
    const str_2 = try std.fmt.bufPrint(&buf_2, "  {s}started{s} : {s}{d}{s} steps ago\n", .{ ansi.colemp, ansi.colres, ansi.coldurntr, 16, ansi.colres });
    const str_3 = try std.fmt.bufPrint(&buf_3, "  {s}duration{s}: {s}{d}{s} steps\n", .{ ansi.colemp, ansi.colres, ansi.coldurntr, 20, ansi.colres });
    const ex_stdout = try std.fmt.bufPrint(&buf_ex_stdout, "{s}{s}{s}", .{ str_1, str_2, str_3 });

    try it_helper.performTest(.{
        .cmd = cmd,
        .args = &args,
        .ac_file = try it_helper.getSmallFile(cur_time),
        .ex_file = ex_file,
        .ex_stdout = ex_stdout,
        .ex_stderr = "",
    });
}
