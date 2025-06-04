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

const little_end = std.builtin.Endian.little;

// display infos on the time left if there is an estimation
fn displayTimeLeftInfos(cur_thing: dt.Thing) !void {
    if (cur_thing.estimation != 0) {
        const time_left = try th.computeTimeLeft(cur_thing);
        try globals.printer.reportTimeLeftInfos(@intCast(time_left), ansi.getDurCol(time_left));
    }
}

// display infos on the current timer
fn displayCurTimerInfos(start: u25) !void {
    if (start != 0) {
        var buf_dur_id: [10]u8 = undefined;
        const temp_dur: u25 = th.curTimestamp() - start;

        if (temp_dur > std.math.maxInt(u12)) {
            try globals.printer.errTimerDurationTooGreat(temp_dur);
        } else {
            const temp_dur_steps = try th.getStepsFromMinutes(u12, temp_dur);
            const str_duration = try std.fmt.bufPrint(&buf_dur_id, "{d}", .{temp_dur_steps});
            try globals.printer.reportTimerStarted(str_duration);
        }
    } else {
        try globals.printer.reportNoTimer();
    }
}

// display infos on the last timer if there is one
fn displayLastTimerInfos(cur_thing: dt.Thing, id_last_timer: u11) !void {
    for (cur_thing.timers) |timer| {
        if (timer.id == id_last_timer) {
            const started_min = @as(i64, th.curTimestamp()) - @as(i64, timer.start);
            const started_step = try th.getStepsFromMinutes(u25, started_min);
            const duration_step = try th.getStepsFromMinutes(u12, timer.duration);

            var buf_str_id: [4]u8 = undefined;
            const str_id_thing = id_helper.b10ToB62(&buf_str_id, cur_thing.id);

            try globals.printer.reportLastTimer(id_last_timer, str_id_thing, started_step, duration_step);
        }
    }
}

/// Display infos on current thing and timer
pub fn cmd(args: *ArgumentParser) !void {
    _ = args;

    var buf_str_id: [4]u8 = undefined;
    const cur_timer = try globals.dfr.getCurrentTimer();

    if (cur_timer.id_thing != 0) {
        const cur_thing = try globals.dfr.getThing(cur_timer.id_thing);
        defer cur_thing.deinit();

        const str_id_thing = id_helper.b10ToB62(&buf_str_id, cur_thing.id);

        try globals.printer.reportThingIdName(str_id_thing, cur_thing.name);
        try globals.printer.reportStatus(@tagName(cur_thing.status));

        if (cur_thing.status == .open) {
            try displayTimeLeftInfos(cur_thing);
        }

        if (cur_timer.id_last_timer != 0) {
            try displayLastTimerInfos(cur_thing, cur_timer.id_last_timer);
        }

        if (cur_thing.status == .open) {
            try displayCurTimerInfos(cur_timer.start);
        }
    } else {
        try globals.printer.reportNoCurrentThing();
    }
}

test "mtlt report - no current thing nor last timer nor current timer" {
    const cur_time = th.curTimestamp();
    var ex_file = try it_helper.getSmallFile(cur_time);
    ex_file.cur_timer.id_thing = 0;
    ex_file.cur_timer.id_last_timer = 0;
    const ac_file = try ex_file.clone();

    var buf_ex_stdout: [512]u8 = undefined;
    const ex_stdout = try std.fmt.bufPrint(&buf_ex_stdout, "There is no current thing.\nSee \"mtlt help\" for help.\n", .{});

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

test "mtlt report - current thing status closed" {
    const cur_time = th.curTimestamp();
    var ex_file = try it_helper.getSmallFile(cur_time);
    ex_file.cur_timer.id_thing = 3;
    ex_file.cur_timer.id_last_timer = 0;
    const ac_file = try ex_file.clone();

    var buf_thing: [128]u8 = undefined;
    var buf_status: [128]u8 = undefined;
    var buf_ex_stdout: [512]u8 = undefined;

    const str_thing = try std.fmt.bufPrint(&buf_thing, "        {s}thing{s}: {s}3{s} - Name thing 3\n", .{ ansi.colemp, ansi.colres, ansi.colid, ansi.colres });
    const str_status = try std.fmt.bufPrint(&buf_status, "       {s}status{s}: closed\n", .{ ansi.colemp, ansi.colres });
    const ex_stdout = try std.fmt.bufPrint(&buf_ex_stdout, "{s}{s}", .{ str_thing, str_status });

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

test "mtlt report - current thing OK - no last timer - no current timer - no estimation" {
    const cur_time = th.curTimestamp();
    var ex_file = try it_helper.getSmallFile(cur_time);
    ex_file.cur_timer.id_thing = 2;
    ex_file.cur_timer.id_last_timer = 0;
    ex_file.things.items[1].estimation = 0;
    const ac_file = try ex_file.clone();

    var buf_thing: [128]u8 = undefined;
    const str_thing = try std.fmt.bufPrint(&buf_thing, "        {s}thing{s}: {s}2{s} - Name thing 2\n", .{ ansi.colemp, ansi.colres, ansi.colid, ansi.colres });

    var buf_status: [128]u8 = undefined;
    const str_status = try std.fmt.bufPrint(&buf_status, "       {s}status{s}: open\n", .{ ansi.colemp, ansi.colres });

    var buf_timer: [128]u8 = undefined;
    const str_timer = try std.fmt.bufPrint(&buf_timer, "{s}current timer{s}: none\n", .{ ansi.colemp, ansi.colres });

    var buf_ex_stdout: [512]u8 = undefined;
    const ex_stdout = try std.fmt.bufPrint(&buf_ex_stdout, "{s}{s}{s}", .{ str_thing, str_status, str_timer });

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

test "mtlt report - current thing OK - no last timer - no current timer - left positive" {
    const cur_time = th.curTimestamp();
    var ex_file = try it_helper.getSmallFile(cur_time);
    ex_file.cur_timer.id_thing = 1;
    ex_file.cur_timer.id_last_timer = 0;
    ex_file.things.items[2].estimation = 80;
    var timers = try globals.allocator.alloc(dt.Timer, 2);
    timers[0] = .{ .id = 1, .duration = try th.getMinutesFromSteps(u12, 20), .start = cur_time - 100 };
    timers[1] = .{ .id = 2, .duration = try th.getMinutesFromSteps(u12, 20), .start = cur_time - 60 };
    ex_file.things.items[2].timers = timers[0..];

    const ac_file = try ex_file.clone();

    var buf_thing: [128]u8 = undefined;
    var buf_status: [128]u8 = undefined;
    var buf_left: [128]u8 = undefined;
    var buf_timer: [128]u8 = undefined;
    var buf_ex_stdout: [512]u8 = undefined;

    const str_thing = try std.fmt.bufPrint(&buf_thing, "        {s}thing{s}: {s}1{s} - Name thing 1\n", .{ ansi.colemp, ansi.colres, ansi.colid, ansi.colres });
    const str_status = try std.fmt.bufPrint(&buf_status, "       {s}status{s}: open\n", .{ ansi.colemp, ansi.colres });
    const str_left = try std.fmt.bufPrint(&buf_left, "         {s}left{s}: {s}40{s} steps\n", .{ ansi.colemp, ansi.colres, ansi.colposdur, ansi.colres });
    const str_timer = try std.fmt.bufPrint(&buf_timer, "{s}current timer{s}: none\n", .{ ansi.colemp, ansi.colres });
    const ex_stdout = try std.fmt.bufPrint(&buf_ex_stdout, "{s}{s}{s}{s}", .{ str_thing, str_status, str_left, str_timer });

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

test "mtlt report - current thing OK - no last timer - no current timer - left negative" {
    const cur_time = th.curTimestamp();
    var ex_file = try it_helper.getSmallFile(cur_time);
    ex_file.cur_timer.id_thing = 1;
    ex_file.cur_timer.id_last_timer = 0;
    ex_file.things.items[2].estimation = 30;
    var timers = try globals.allocator.alloc(dt.Timer, 2);
    timers[0] = .{ .id = 1, .duration = try th.getMinutesFromSteps(u12, 20), .start = cur_time - 100 };
    timers[1] = .{ .id = 2, .duration = try th.getMinutesFromSteps(u12, 20), .start = cur_time - 60 };
    ex_file.things.items[2].timers = timers[0..];

    const ac_file = try ex_file.clone();

    var buf_thing: [128]u8 = undefined;
    var buf_status: [128]u8 = undefined;
    var buf_left: [128]u8 = undefined;
    var buf_timer: [128]u8 = undefined;
    var buf_ex_stdout: [512]u8 = undefined;

    const str_thing = try std.fmt.bufPrint(&buf_thing, "        {s}thing{s}: {s}1{s} - Name thing 1\n", .{ ansi.colemp, ansi.colres, ansi.colid, ansi.colres });
    const str_status = try std.fmt.bufPrint(&buf_status, "       {s}status{s}: open\n", .{ ansi.colemp, ansi.colres });
    const str_left = try std.fmt.bufPrint(&buf_left, "         {s}left{s}: {s}-10{s} steps\n", .{ ansi.colemp, ansi.colres, ansi.colnegdur, ansi.colres });
    const str_timer = try std.fmt.bufPrint(&buf_timer, "{s}current timer{s}: none\n", .{ ansi.colemp, ansi.colres });
    const ex_stdout = try std.fmt.bufPrint(&buf_ex_stdout, "{s}{s}{s}{s}", .{ str_thing, str_status, str_left, str_timer });

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

test "mtlt report - current thing OK - no last timer - current timer ok - left negative" {
    const cur_time = th.curTimestamp();
    var ex_file = try it_helper.getSmallFile(cur_time);
    ex_file.cur_timer.id_thing = 1;
    ex_file.cur_timer.id_last_timer = 0;
    ex_file.cur_timer.start = cur_time - try th.getMinutesFromSteps(u12, 30);
    ex_file.things.items[2].estimation = 50;
    var timers = try globals.allocator.alloc(dt.Timer, 2);
    timers[0] = .{ .id = 1, .duration = try th.getMinutesFromSteps(u12, 20), .start = cur_time - 100 };
    timers[1] = .{ .id = 2, .duration = try th.getMinutesFromSteps(u12, 20), .start = cur_time - 60 };
    ex_file.things.items[2].timers = timers[0..];

    const ac_file = try ex_file.clone();

    var buf_thing: [128]u8 = undefined;
    var buf_status: [128]u8 = undefined;
    var buf_left: [128]u8 = undefined;
    var buf_timer: [128]u8 = undefined;
    var buf_ex_stdout: [512]u8 = undefined;

    const str_thing = try std.fmt.bufPrint(&buf_thing, "        {s}thing{s}: {s}1{s} - Name thing 1\n", .{ ansi.colemp, ansi.colres, ansi.colid, ansi.colres });
    const str_status = try std.fmt.bufPrint(&buf_status, "       {s}status{s}: open\n", .{ ansi.colemp, ansi.colres });
    const str_left = try std.fmt.bufPrint(&buf_left, "         {s}left{s}: {s}-20{s} steps\n", .{ ansi.colemp, ansi.colres, ansi.colnegdur, ansi.colres });
    const str_timer = try std.fmt.bufPrint(&buf_timer, "{s}current timer{s}: started {s}30{s} steps ago\n", .{ ansi.colemp, ansi.colres, ansi.coldurntr, ansi.colres });
    const ex_stdout = try std.fmt.bufPrint(&buf_ex_stdout, "{s}{s}{s}{s}", .{ str_thing, str_status, str_left, str_timer });

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

test "mtlt report - current thing OK - no last timer - current timer too big" {
    const cur_time = th.curTimestamp();
    var ex_file = try it_helper.getSmallFile(cur_time);
    ex_file.cur_timer.id_thing = 1;
    ex_file.cur_timer.id_last_timer = 0;
    ex_file.cur_timer.start = cur_time - try th.getMinutesFromSteps(u25, 570);
    const ac_file = try ex_file.clone();

    var buf_thing: [128]u8 = undefined;
    var buf_status: [128]u8 = undefined;
    var buf_ex_stdout: [512]u8 = undefined;

    const str_thing = try std.fmt.bufPrint(&buf_thing, "        {s}thing{s}: {s}1{s} - Name thing 1\n", .{ ansi.colemp, ansi.colres, ansi.colid, ansi.colres });
    const str_status = try std.fmt.bufPrint(&buf_status, "       {s}status{s}: open\n", .{ ansi.colemp, ansi.colres });
    const ex_stdout = try std.fmt.bufPrint(&buf_ex_stdout, "{s}{s}", .{ str_thing, str_status });

    var buf_ex_stderr: [512]u8 = undefined;
    const ex_stderr = try std.fmt.bufPrint(&buf_ex_stderr, "The current timer has a duration of {s}{d}{s}.\nThe maximum allowed duration is {s}{d}{s}.\nPlease use \"mtlt stop\".\n", .{ ansi.colemp, 4104, ansi.colres, ansi.colemp, std.math.maxInt(u12), ansi.colres });

    var args = ArgumentParser{};

    try it_helper.performTest(.{
        .cmd = cmd,
        .args = &args,
        .ac_file = ac_file,
        .ex_file = ex_file,
        .ex_stdout = ex_stdout,
        .ex_stderr = ex_stderr,
    });
}

test "mtlt report - current thing OK - last timer ok - no current timer - left positive" {
    const cur_time = th.curTimestamp();
    var ex_file = try it_helper.getSmallFile(cur_time);
    ex_file.cur_timer.id_thing = 1;
    ex_file.cur_timer.id_last_timer = 1;
    ex_file.things.items[2].estimation = 80;
    var timers = try globals.allocator.alloc(dt.Timer, 2);
    timers[0] = .{ .id = 1, .duration = try th.getMinutesFromSteps(u12, 20), .start = cur_time - 100 };
    timers[1] = .{ .id = 2, .duration = try th.getMinutesFromSteps(u12, 20), .start = cur_time - 60 };
    ex_file.things.items[2].timers = timers[0..];

    const ac_file = try ex_file.clone();

    var buf_thing: [128]u8 = undefined;
    var buf_status: [128]u8 = undefined;
    var buf_left: [128]u8 = undefined;
    var buf_timer: [128]u8 = undefined;
    var buf_last_timer: [256]u8 = undefined;
    var buf_ex_stdout: [1024]u8 = undefined;

    const str_thing = try std.fmt.bufPrint(&buf_thing, "        {s}thing{s}: {s}1{s} - Name thing 1\n", .{ ansi.colemp, ansi.colres, ansi.colid, ansi.colres });
    const str_status = try std.fmt.bufPrint(&buf_status, "       {s}status{s}: open\n", .{ ansi.colemp, ansi.colres });
    const str_left = try std.fmt.bufPrint(&buf_left, "         {s}left{s}: {s}40{s} steps\n", .{ ansi.colemp, ansi.colres, ansi.colposdur, ansi.colres });
    const str_last_timer = try std.fmt.bufPrint(&buf_last_timer, "   {s}last timer{s}: {s}1@1{s}, {s}started{s}: {s}14{s} steps ago, {s}lasted{s}: {s}20{s} steps\n", .{ ansi.colemp, ansi.colres, ansi.colid, ansi.colres, ansi.colemp, ansi.colres, ansi.coldurntr, ansi.colres, ansi.colemp, ansi.colres, ansi.coldurntr, ansi.colres });
    const str_timer = try std.fmt.bufPrint(&buf_timer, "{s}current timer{s}: none\n", .{ ansi.colemp, ansi.colres });
    const ex_stdout = try std.fmt.bufPrint(&buf_ex_stdout, "{s}{s}{s}{s}{s}", .{ str_thing, str_status, str_left, str_last_timer, str_timer });

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
