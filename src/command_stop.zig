const std = @import("std");

const ansi = @import("ansi_codes.zig");
const dfr = @import("data_file_reader.zig");
const dt = @import("data_types.zig");
const globals = @import("globals.zig");
const id_helper = @import("id_helper.zig");
const it_helper = @import("integration_tests_helper.zig");
const table_printer = @import("table_printer.zig");
const th = @import("time_helper.zig");

const ArgumentParser = @import("argument_parser.zig").ArgumentParser;
const DataOperationError = @import("data_file_writer.zig").DataOperationError;

/// Stop the current timer
pub fn cmd(args: *ArgumentParser) !void {
    const cur_time = th.curTimestamp();
    const cur_timer = try globals.dfr.getCurrentTimer();
    const max_timer_duration: u12 = std.math.maxInt(u12);

    // check there is a timer currently running
    if (cur_timer.id_thing == 0 or cur_timer.start == 0) {
        try globals.printer.noTimerRunning();
        return;
    }

    var buf_str_id: [4]u8 = undefined;
    const str_id = id_helper.b10ToB62(&buf_str_id, cur_timer.id_thing);

    // get the name of the thing to stop
    const fpt = try globals.dfr.getFixedPartThing(cur_timer.id_thing);
    const thing_name = try globals.allocator.alloc(u8, fpt.lgt_name);
    defer globals.allocator.free(thing_name);
    _ = try globals.data_file.reader().read(thing_name);

    // interpret the arguments
    const data_timer = try interpretArguments(args);

    // check the current duration of the timer. If it's more than the maximum we stop things right
    // away and create the timer with max duration.
    if (cur_timer.start > cur_time) {
        try stopWithMaxDuration(data_timer, str_id, thing_name);
        return;
    } else if (cur_time - cur_timer.start > max_timer_duration) {
        try stopWithMaxDuration(data_timer, str_id, thing_name);
        return;
    }

    // at this point we try to stop the timer with arguments given by the user
    const t = globals.dfw.stopCurrentTimer(data_timer) catch |err| {
        switch (err) {
            DataOperationError.TooManyTimers => try globals.printer.errTooManyTimers(),
            DataOperationError.DurationAboveMax => try stopWithMaxDuration(data_timer, str_id, thing_name),
            DataOperationError.DurationBelowMin => try stopWithMinDuration(data_timer, str_id, thing_name),
            DataOperationError.StartAboveMax => try globals.printer.errStartAboveMax(),
            DataOperationError.StartBelowMin => try globals.printer.errStartBelowMin(),
            else => try globals.printer.errUnexpected(err),
        }
        return;
    };

    try globals.printer.stoppedTimer(t.id, str_id, thing_name, try th.getStepsFromMinutes(u12, t.duration));
}

/// Interpret the arguments coming from the command line
fn interpretArguments(args: *ArgumentParser) !dt.TimerToUpdate {
    const dur: ?u12 = if (args.*.duration == null)
        null
    else
        try th.getMinutesFromSteps(u12, args.*.duration.?);

    var dur_off: ?u12 = null;
    if (args.*.duration_less != null) {
        dur_off = try th.getMinutesFromSteps(u12, args.*.duration_less.?);
    } else if (args.*.duration_more != null) {
        dur_off = try th.getMinutesFromSteps(u12, args.*.duration_more.?);
    }

    var start_off: ?u25 = null;
    if (args.*.start_less != null) {
        start_off = try th.getMinutesFromSteps(u25, args.*.start_less.?);
    } else if (args.*.start_more != null) {
        start_off = try th.getMinutesFromSteps(u25, args.*.start_more.?);
    }

    return .{
        .id = 0,
        .duration = dur,
        .duration_off = dur_off,
        .add_duration_off = args.*.duration_less == null,
        .start_off = start_off,
        .add_start_off = args.*.start_less == null,
    };
}

fn stopWithMinDuration(data_timer: dt.TimerToUpdate, str_id: []const u8, thing_name: []const u8) !void {
    const t = globals.dfw.stopCurrentTimer(.{
        .id = 0,
        .duration = 0,
        .duration_off = 0,
        .add_duration_off = true,
        .start_off = data_timer.start_off,
        .add_start_off = data_timer.add_start_off,
    }) catch |err| {
        switch (err) {
            DataOperationError.TooManyTimers => try globals.printer.errTooManyTimers(),
            DataOperationError.StartAboveMax => try globals.printer.errStartAboveMax(),
            DataOperationError.StartBelowMin => try globals.printer.errStartBelowMin(),
            else => try globals.printer.errUnexpected(err),
        }
        return;
    };
    try globals.printer.stoppedTimerTooSmall(t.id, str_id);
    try globals.printer.stoppedTimer(t.id, str_id, thing_name, 0);
}

fn stopWithMaxDuration(data_timer: dt.TimerToUpdate, str_id: []const u8, thing_name: []const u8) !void {
    const t = globals.dfw.stopCurrentTimer(.{
        .id = 0,
        .duration = std.math.maxInt(u12),
        .duration_off = 0,
        .add_duration_off = true,
        .start_off = data_timer.start_off,
        .add_start_off = data_timer.add_start_off,
    }) catch |err| {
        switch (err) {
            DataOperationError.TooManyTimers => try globals.printer.errTooManyTimers(),
            DataOperationError.StartAboveMax => try globals.printer.errStartAboveMax(),
            DataOperationError.StartBelowMin => try globals.printer.errStartBelowMin(),
            else => try globals.printer.errUnexpected(err),
        }
        return;
    };
    try globals.printer.stoppedTimerTooBig(t.id, str_id);
    try globals.printer.stoppedTimer(t.id, str_id, thing_name, try th.getStepsFromMinutes(u12, t.duration));
}

/// Print out help for the stop command
pub fn help() !void {
    try std.io.getStdOut().writer().print(
        \\Usage: {s}mtlt stop{s}
        \\
        \\Stops the current timer.
        \\
        \\Options:
        \\  {s}-d{s},  {s}--duration{s}         Duration of the timer
        \\  {s}-dl{s}, {s}--duration-less{s}    # of steps to retrieve from duration
        \\  {s}-dm{s}, {s}--duration-more{s}    # of steps to add to duration
        \\  {s}-sl{s}, {s}--start-less{s}       # of steps to retrieve from start time
        \\  {s}-sm{s}, {s}--start-more{s}       # of steps to add to start time
        \\
        \\Examples:
        \\  {s}mtlt stop{s}
        \\      Stop the current timer without altering the duration or start time.
        \\
        \\  {s}mtlt stop -sl 4{s}
        \\      Stop the current timer and make it start 4 steps earlier without
        \\      altering it's duration.
        \\
        \\  {s}mtlt stop -d 8{s}
        \\      Stop the current timer and set it's duration to 8 steps without
        \\      altering it's start time.
        \\
    , .{
        ansi.colemp, ansi.colres,
        ansi.colemp, ansi.colres,
        ansi.colemp, ansi.colres,
        ansi.colemp, ansi.colres,
        ansi.colemp, ansi.colres,
        ansi.colemp, ansi.colres,
        ansi.colemp, ansi.colres,
        ansi.colemp, ansi.colres,
        ansi.colemp, ansi.colres,
        ansi.colemp, ansi.colres,
        ansi.colemp, ansi.colres,
        ansi.colemp, ansi.colres,
        ansi.colemp, ansi.colres,
        ansi.colemp, ansi.colres,
    });
}

test "no current thing" {
    const cur_time = th.curTimestamp();
    var ex_file = try it_helper.getSmallFile(cur_time);
    ex_file.cur_timer.id_thing = 0;
    var ac_file = try ex_file.clone();
    ac_file.cur_timer.id_thing = 0;

    var buf_ex_stdout: [128]u8 = undefined;
    const ex_stdout = try std.fmt.bufPrint(&buf_ex_stdout, "No timer currently running.\n", .{});

    var args = ArgumentParser{};

    try it_helper.performTest(.{
        .cmd = cmd,
        .args = &args,
        .ac_file = ac_file,
        .ex_file = ex_file,
        .ex_stdout = ex_stdout,
        .ex_stderr = "",
    });
}

test "current thing ok - no running timer" {
    const cur_time = th.curTimestamp();

    var buf_ex_stdout: [128]u8 = undefined;
    const ex_stdout = try std.fmt.bufPrint(&buf_ex_stdout, "No timer currently running.\n", .{});

    var args = ArgumentParser{};

    try it_helper.performTest(.{
        .cmd = cmd,
        .args = &args,
        .ac_file = try it_helper.getSmallFile(cur_time),
        .ex_file = try it_helper.getSmallFile(cur_time),
        .ex_stdout = ex_stdout,
        .ex_stderr = "",
    });
}

test "current thing ok - running timer too big - creation ok" {
    const cur_time = th.curTimestamp();
    const max_u12: u12 = std.math.maxInt(u12);

    const start_time = cur_time - max_u12 - 10;

    var ex_file = try it_helper.getSmallFile(cur_time);
    ex_file.cur_timer.id_last_timer = 1;
    var timers = try globals.allocator.alloc(dt.Timer, 1);
    timers[0] = .{ .id = 1, .duration = max_u12, .start = start_time };
    ex_file.things.items[2].timers = timers[0..];

    var ac_file = try it_helper.getSmallFile(cur_time);
    ac_file.cur_timer.start = start_time;

    var buf_1: [256]u8 = undefined;
    var buf_2: [256]u8 = undefined;
    var buf_3: [256]u8 = undefined;
    var buf_ex_stdout: [1024]u8 = undefined;

    const str_1 = try std.fmt.bufPrint(&buf_1, "The duration of the timer exceeds the possible limit. It will be set to the maximum when stopping the timer.\n", .{});
    const str_2 = try std.fmt.bufPrint(&buf_2, "Feel free to use \"{s}mtlt update-timer 1@1{s}\" to adjust this timer or \"{s}mtlt add-timer 1{s}\" to create a new timer.\n", .{ ansi.colemp, ansi.colres, ansi.colemp, ansi.colres });
    const str_3 = try std.fmt.bufPrint(&buf_3, "Stopped timer {s}1@1{s} for {s}1{s} - {s}Name thing 1{s}. It lasted {s}{d}{s} steps.\n", .{ ansi.colid, ansi.colres, ansi.colid, ansi.colres, ansi.colemp, ansi.colres, ansi.colemp, try th.getStepsFromMinutes(u12, max_u12), ansi.colres });
    const ex_stdout = try std.fmt.bufPrint(&buf_ex_stdout, "{s}{s}{s}", .{ str_1, str_2, str_3 });

    var args = ArgumentParser{};

    try it_helper.performTest(.{
        .cmd = cmd,
        .args = &args,
        .ac_file = ac_file,
        .ex_file = ex_file,
        .ex_stdout = ex_stdout,
        .ex_stderr = "",
    });
}

test "current thing ok - running timer too big - creation impossible too much timers" {
    const cur_time = th.curTimestamp();
    const max_u12: u12 = std.math.maxInt(u12);

    var ac_file = try it_helper.getSmallFile(cur_time);
    ac_file.cur_timer.start = cur_time - max_u12 - 10;

    // create the maximum number of timers possible for this thing
    var timers = try globals.allocator.alloc(dt.Timer, 2047);
    for (0..2047) |i| {
        timers[i] = .{ .id = @intCast(2047 - i), .duration = 10, .start = cur_time };
    }
    ac_file.things.items[2].timers = timers[0..];

    const ex_file = try ac_file.clone();

    var buf_ex_stderr: [1024]u8 = undefined;
    const ex_stderr = try std.fmt.bufPrint(&buf_ex_stderr, "The maximum number of timers for this thing is reached.\nDeleting existing timers will not help. You will need to create a new thing.\n", .{});

    var args = ArgumentParser{};

    try it_helper.performTest(.{
        .cmd = cmd,
        .args = &args,
        .ac_file = ac_file,
        .ex_file = ex_file,
        .ex_stdout = "",
        .ex_stderr = ex_stderr,
    });
}

test "current thing ok - running timer ok - no options - creation ok" {
    const cur_time = th.curTimestamp();
    const dur: u12 = 20;

    var ex_file = try it_helper.getSmallFile(cur_time);
    ex_file.cur_timer.start = 0;
    ex_file.cur_timer.id_last_timer = 1;
    var timers = try globals.allocator.alloc(dt.Timer, 1);
    timers[0] = .{ .id = 1, .duration = dur, .start = cur_time - dur };
    ex_file.things.items[2].timers = timers[0..];

    var ac_file = try it_helper.getSmallFile(cur_time);
    ac_file.cur_timer.start = cur_time - dur;

    var buf_ex_stdout: [1024]u8 = undefined;
    const ex_stdout = try std.fmt.bufPrint(&buf_ex_stdout, "Stopped timer {s}1@1{s} for {s}1{s} - {s}Name thing 1{s}. It lasted {s}3{s} steps.\n", .{ ansi.colid, ansi.colres, ansi.colid, ansi.colres, ansi.colemp, ansi.colres, ansi.colemp, ansi.colres });

    var args = ArgumentParser{};

    try it_helper.performTest(.{
        .cmd = cmd,
        .args = &args,
        .ac_file = ac_file,
        .ex_file = ex_file,
        .ex_stdout = ex_stdout,
        .ex_stderr = "",
    });
}

test "current thing ok - running timer ok - no options - creation impossible too much timers" {
    const cur_time = th.curTimestamp();

    var ac_file = try it_helper.getSmallFile(cur_time);
    ac_file.cur_timer.start = cur_time;

    // create the maximum number of timers possible for this thing
    var timers = try globals.allocator.alloc(dt.Timer, 2047);
    for (0..2047) |i| {
        timers[i] = .{ .id = @intCast(2047 - i), .duration = 10, .start = cur_time };
    }
    ac_file.things.items[2].timers = timers[0..];

    const ex_file = try ac_file.clone();

    var buf_ex_stderr: [1024]u8 = undefined;
    const ex_stderr = try std.fmt.bufPrint(&buf_ex_stderr, "The maximum number of timers for this thing is reached.\nDeleting existing timers will not help. You will need to create a new thing.\n", .{});

    var args = ArgumentParser{};

    try it_helper.performTest(.{
        .cmd = cmd,
        .args = &args,
        .ac_file = ac_file,
        .ex_file = ex_file,
        .ex_stdout = "",
        .ex_stderr = ex_stderr,
    });
}

test "current thing ok - running timer ok - option duration more too big" {
    const cur_time = th.curTimestamp();
    const start_offset: u25 = 120;
    const max_u12: u12 = std.math.maxInt(u12);
    const max_steps: usize = @intFromFloat(@round(std.math.maxInt(u12) / th.step_coef));
    const dur_more: u12 = max_steps - 10;

    var ex_file = try it_helper.getSmallFile(cur_time);
    ex_file.cur_timer.start = 0;
    ex_file.cur_timer.id_last_timer = 1;
    var timers = try globals.allocator.alloc(dt.Timer, 1);
    timers[0] = .{ .id = 1, .duration = max_u12, .start = cur_time - start_offset };
    ex_file.things.items[2].timers = timers[0..];

    var ac_file = try it_helper.getSmallFile(cur_time);
    ac_file.cur_timer.start = cur_time - start_offset;

    var buf_1: [256]u8 = undefined;
    var buf_2: [256]u8 = undefined;
    var buf_3: [256]u8 = undefined;
    var buf_ex_stdout: [1024]u8 = undefined;

    const str_1 = try std.fmt.bufPrint(&buf_1, "The duration of the timer exceeds the possible limit. It will be set to the maximum when stopping the timer.\n", .{});
    const str_2 = try std.fmt.bufPrint(&buf_2, "Feel free to use \"{s}mtlt update-timer 1@1{s}\" to adjust this timer or \"{s}mtlt add-timer 1{s}\" to create a new timer.\n", .{ ansi.colemp, ansi.colres, ansi.colemp, ansi.colres });
    const str_3 = try std.fmt.bufPrint(&buf_3, "Stopped timer {s}1@1{s} for {s}1{s} - {s}Name thing 1{s}. It lasted {s}{d}{s} steps.\n", .{ ansi.colid, ansi.colres, ansi.colid, ansi.colres, ansi.colemp, ansi.colres, ansi.colemp, try th.getStepsFromMinutes(u12, max_u12), ansi.colres });
    const ex_stdout = try std.fmt.bufPrint(&buf_ex_stdout, "{s}{s}{s}", .{ str_1, str_2, str_3 });

    var args = ArgumentParser{ .duration_more = dur_more };

    try it_helper.performTest(.{
        .cmd = cmd,
        .args = &args,
        .ac_file = ac_file,
        .ex_file = ex_file,
        .ex_stdout = ex_stdout,
        .ex_stderr = "",
    });
}

test "current thing ok - running timer ok - option duration less too big" {
    const cur_time = th.curTimestamp();
    const start_offset: u25 = 120;
    const max_steps: usize = @intFromFloat(@round(std.math.maxInt(u12) / th.step_coef));
    const dur_less: u12 = max_steps - 10;

    var ex_file = try it_helper.getSmallFile(cur_time);
    ex_file.cur_timer.start = 0;
    ex_file.cur_timer.id_last_timer = 1;
    var timers = try globals.allocator.alloc(dt.Timer, 1);
    timers[0] = .{ .id = 1, .duration = 0, .start = cur_time - start_offset };
    ex_file.things.items[2].timers = timers[0..];

    var ac_file = try it_helper.getSmallFile(cur_time);
    ac_file.cur_timer.start = cur_time - start_offset;

    var buf_1: [256]u8 = undefined;
    var buf_2: [256]u8 = undefined;
    var buf_3: [256]u8 = undefined;
    var buf_ex_stdout: [1024]u8 = undefined;

    const str_1 = try std.fmt.bufPrint(&buf_1, "The requested duration for the timer falls below 0. It will be set to 0.\n", .{});
    const str_2 = try std.fmt.bufPrint(&buf_2, "Feel free to use \"{s}mtlt update-timer 1@1{s}\" to adjust the duration of this timer.\n", .{ ansi.colemp, ansi.colres });
    const str_3 = try std.fmt.bufPrint(&buf_3, "Stopped timer {s}1@1{s} for {s}1{s} - {s}Name thing 1{s}. It lasted {s}0{s} steps.\n", .{ ansi.colid, ansi.colres, ansi.colid, ansi.colres, ansi.colemp, ansi.colres, ansi.colemp, ansi.colres });
    const ex_stdout = try std.fmt.bufPrint(&buf_ex_stdout, "{s}{s}{s}", .{ str_1, str_2, str_3 });

    var args = ArgumentParser{ .duration_less = dur_less };

    try it_helper.performTest(.{
        .cmd = cmd,
        .args = &args,
        .ac_file = ac_file,
        .ex_file = ex_file,
        .ex_stdout = ex_stdout,
        .ex_stderr = "",
    });
}

test "current thing ok - running timer ok - option duration ok" {
    const cur_time = th.curTimestamp();
    const wanted_dur_min: u12 = 50;
    const start_offset: u25 = 120;

    var ex_file = try it_helper.getSmallFile(cur_time);
    ex_file.cur_timer.start = 0;
    ex_file.cur_timer.id_last_timer = 1;
    var timers = try globals.allocator.alloc(dt.Timer, 1);
    timers[0] = .{ .id = 1, .duration = wanted_dur_min, .start = cur_time - start_offset };
    ex_file.things.items[2].timers = timers[0..];

    var ac_file = try it_helper.getSmallFile(cur_time);
    ac_file.cur_timer.start = cur_time - start_offset;

    var buf_ex_stdout: [1024]u8 = undefined;
    const ex_stdout = try std.fmt.bufPrint(&buf_ex_stdout, "Stopped timer {s}1@1{s} for {s}1{s} - {s}Name thing 1{s}. It lasted {s}7{s} steps.\n", .{ ansi.colid, ansi.colres, ansi.colid, ansi.colres, ansi.colemp, ansi.colres, ansi.colemp, ansi.colres });

    var args = ArgumentParser{ .duration = 7 };

    try it_helper.performTest(.{
        .cmd = cmd,
        .args = &args,
        .ac_file = ac_file,
        .ex_file = ex_file,
        .ex_stdout = ex_stdout,
        .ex_stderr = "",
    });
}

test "current thing ok - running timer ok - option duration less ok" {
    const cur_time = th.curTimestamp();
    const dur_less: u12 = 29;
    const start_offset: u25 = 120;

    var ex_file = try it_helper.getSmallFile(cur_time);
    ex_file.cur_timer.start = 0;
    ex_file.cur_timer.id_last_timer = 1;
    var timers = try globals.allocator.alloc(dt.Timer, 1);
    timers[0] = .{ .id = 1, .duration = start_offset - dur_less, .start = cur_time - start_offset };
    ex_file.things.items[2].timers = timers[0..];

    var ac_file = try it_helper.getSmallFile(cur_time);
    ac_file.cur_timer.start = cur_time - start_offset;

    var buf_ex_stdout: [1024]u8 = undefined;
    const ex_stdout = try std.fmt.bufPrint(&buf_ex_stdout, "Stopped timer {s}1@1{s} for {s}1{s} - {s}Name thing 1{s}. It lasted {s}13{s} steps.\n", .{ ansi.colid, ansi.colres, ansi.colid, ansi.colres, ansi.colemp, ansi.colres, ansi.colemp, ansi.colres });

    var args = ArgumentParser{ .duration_less = 4 };

    try it_helper.performTest(.{
        .cmd = cmd,
        .args = &args,
        .ac_file = ac_file,
        .ex_file = ex_file,
        .ex_stdout = ex_stdout,
        .ex_stderr = "",
    });
}

test "current thing ok - running timer ok - option duration more ok" {
    const cur_time = th.curTimestamp();
    const dur_more: u12 = 29;
    const start_offset: u25 = 120;

    var ex_file = try it_helper.getSmallFile(cur_time);
    ex_file.cur_timer.start = 0;
    ex_file.cur_timer.id_last_timer = 1;
    var timers = try globals.allocator.alloc(dt.Timer, 1);
    timers[0] = .{ .id = 1, .duration = start_offset + dur_more, .start = cur_time - start_offset };
    ex_file.things.items[2].timers = timers[0..];

    var ac_file = try it_helper.getSmallFile(cur_time);
    ac_file.cur_timer.start = cur_time - start_offset;

    var buf_ex_stdout: [1024]u8 = undefined;
    const ex_stdout = try std.fmt.bufPrint(&buf_ex_stdout, "Stopped timer {s}1@1{s} for {s}1{s} - {s}Name thing 1{s}. It lasted {s}21{s} steps.\n", .{ ansi.colid, ansi.colres, ansi.colid, ansi.colres, ansi.colemp, ansi.colres, ansi.colemp, ansi.colres });

    var args = ArgumentParser{ .duration_more = 4 };

    try it_helper.performTest(.{
        .cmd = cmd,
        .args = &args,
        .ac_file = ac_file,
        .ex_file = ex_file,
        .ex_stdout = ex_stdout,
        .ex_stderr = "",
    });
}

test "current thing ok - running timer ok - option start-less too big" {
    const cur_time = th.curTimestamp();
    const start_offset: u25 = 120;
    const max_steps: usize = @intFromFloat(@round(std.math.maxInt(u25) / th.step_coef));
    const start_less: u25 = max_steps - 10;

    var ex_file = try it_helper.getSmallFile(cur_time);
    ex_file.cur_timer.start = cur_time - start_offset;

    var ac_file = try it_helper.getSmallFile(cur_time);
    ac_file.cur_timer.start = cur_time - start_offset;

    var buf_ex_stderr: [1024]u8 = undefined;
    const ex_stderr = try std.fmt.bufPrint(&buf_ex_stderr, "The starting moment for a timer cannot be this far in the past.\n", .{});

    var args = ArgumentParser{ .start_less = start_less };

    try it_helper.performTest(.{
        .cmd = cmd,
        .args = &args,
        .ac_file = ac_file,
        .ex_file = ex_file,
        .ex_stdout = "",
        .ex_stderr = ex_stderr,
    });
}

test "current thing ok - running timer ok - option start-more too big" {
    const cur_time = th.curTimestamp();
    const start_offset: u25 = 120;
    const start_more: u25 = 20;

    var ex_file = try it_helper.getSmallFile(cur_time);
    ex_file.cur_timer.start = cur_time - start_offset;

    var ac_file = try it_helper.getSmallFile(cur_time);
    ac_file.cur_timer.start = cur_time - start_offset;

    var buf_ex_stderr: [1024]u8 = undefined;
    const ex_stderr = try std.fmt.bufPrint(&buf_ex_stderr, "The starting moment for a timer cannot be in the future.\n", .{});

    var args = ArgumentParser{ .start_more = start_more };

    try it_helper.performTest(.{
        .cmd = cmd,
        .args = &args,
        .ac_file = ac_file,
        .ex_file = ex_file,
        .ex_stdout = "",
        .ex_stderr = ex_stderr,
    });
}

test "current thing ok - running timer ok - option start-less ok" {
    const cur_time = th.curTimestamp();
    const start_less: u12 = 29;
    const start_offset: u25 = 120;

    var ex_file = try it_helper.getSmallFile(cur_time);
    ex_file.cur_timer.start = 0;
    ex_file.cur_timer.id_last_timer = 1;
    var timers = try globals.allocator.alloc(dt.Timer, 1);
    timers[0] = .{ .id = 1, .duration = start_offset, .start = cur_time - start_offset - start_less };
    ex_file.things.items[2].timers = timers[0..];

    var ac_file = try it_helper.getSmallFile(cur_time);
    ac_file.cur_timer.start = cur_time - start_offset;

    var buf_ex_stdout: [1024]u8 = undefined;
    const ex_stdout = try std.fmt.bufPrint(&buf_ex_stdout, "Stopped timer {s}1@1{s} for {s}1{s} - {s}Name thing 1{s}. It lasted {s}17{s} steps.\n", .{ ansi.colid, ansi.colres, ansi.colid, ansi.colres, ansi.colemp, ansi.colres, ansi.colemp, ansi.colres });

    var args = ArgumentParser{ .start_less = 4 };

    try it_helper.performTest(.{
        .cmd = cmd,
        .args = &args,
        .ac_file = ac_file,
        .ex_file = ex_file,
        .ex_stdout = ex_stdout,
        .ex_stderr = "",
    });
}

test "current thing ok - running timer ok - option start-more ok" {
    const cur_time = th.curTimestamp();
    const start_more: u12 = 29;
    const start_offset: u25 = 120;

    var ex_file = try it_helper.getSmallFile(cur_time);
    ex_file.cur_timer.start = 0;
    ex_file.cur_timer.id_last_timer = 1;
    var timers = try globals.allocator.alloc(dt.Timer, 1);
    timers[0] = .{ .id = 1, .duration = start_offset, .start = cur_time - start_offset + start_more };
    ex_file.things.items[2].timers = timers[0..];

    var ac_file = try it_helper.getSmallFile(cur_time);
    ac_file.cur_timer.start = cur_time - start_offset;

    var buf_ex_stdout: [1024]u8 = undefined;
    const ex_stdout = try std.fmt.bufPrint(&buf_ex_stdout, "Stopped timer {s}1@1{s} for {s}1{s} - {s}Name thing 1{s}. It lasted {s}17{s} steps.\n", .{ ansi.colid, ansi.colres, ansi.colid, ansi.colres, ansi.colemp, ansi.colres, ansi.colemp, ansi.colres });

    var args = ArgumentParser{ .start_more = 4 };

    try it_helper.performTest(.{
        .cmd = cmd,
        .args = &args,
        .ac_file = ac_file,
        .ex_file = ex_file,
        .ex_stdout = ex_stdout,
        .ex_stderr = "",
    });
}

test "current thing ok - running timer ok - duration too big - start-more too big" {
    const cur_time = th.curTimestamp();
    const start_offset: u25 = 120;
    const start_more: u25 = 20;
    const max_steps: usize = @intFromFloat(@round(std.math.maxInt(u12) / th.step_coef));

    var ex_file = try it_helper.getSmallFile(cur_time);
    ex_file.cur_timer.start = cur_time - start_offset;

    var ac_file = try it_helper.getSmallFile(cur_time);
    ac_file.cur_timer.start = cur_time - start_offset;

    var buf_ex_stderr: [1024]u8 = undefined;
    const ex_stderr = try std.fmt.bufPrint(&buf_ex_stderr, "The starting moment for a timer cannot be in the future.\n", .{});

    var args = ArgumentParser{ .duration = max_steps - 1, .start_more = start_more };

    try it_helper.performTest(.{
        .cmd = cmd,
        .args = &args,
        .ac_file = ac_file,
        .ex_file = ex_file,
        .ex_stdout = "",
        .ex_stderr = ex_stderr,
    });
}
