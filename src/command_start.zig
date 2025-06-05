const std = @import("std");

const ansi = @import("ansi_codes.zig");
const command_stop = @import("command_stop.zig");
const dfr = @import("data_file_reader.zig");
const dt = @import("data_types.zig");
const globals = @import("globals.zig");
const id_helper = @import("id_helper.zig");
const it_helper = @import("integration_tests_helper.zig");
const th = @import("time_helper.zig");

const ArgumentParser = @import("argument_parser.zig").ArgumentParser;

var buf_str_id: [4]u8 = undefined;

/// Start a timer on a thing
pub fn cmd(args: *ArgumentParser) !void {
    // get the current timer contained in the data file
    const cur_timer = try globals.dfr.getCurrentTimer();

    var id_thing: u19 = 0;

    // if there is no argument
    if (args.*.payload == null) {
        // and no previous current timer
        if (cur_timer.id_thing == 0) {
            try globals.printer.errMissingIdThing();
            return;
        } else {
            id_thing = cur_timer.id_thing;
        }
    } else {
        id_thing = id_helper.b62ToB10(args.*.payload.?) catch |err| {
            switch (err) {
                id_helper.Base62Error.TooBig => try globals.printer.errIdTooBig(),
                id_helper.Base62Error.ContainsInvalidCharacters => try globals.printer.errIdInvalidCharacters(),
            }
            return;
        };
    }

    const fpt = globals.dfr.getFixedPartThing(id_thing) catch |err| {
        switch (err) {
            dfr.DataParsingError.ThingNotFound => {
                var buf_id_thing: [4]u8 = undefined;
                const str_id_thing = id_helper.b10ToB62(&buf_id_thing, id_thing);
                try globals.printer.errThingNotFoundStr(str_id_thing);
            },
            else => try globals.printer.errUnexpected(err),
        }
        return;
    };

    const thing_name = try globals.allocator.alloc(u8, fpt.lgt_name);
    defer globals.allocator.free(thing_name);
    _ = try globals.data_file.reader().read(thing_name);
    try start_id(id_thing, thing_name);
}

/// Start a timer on a thing with the specified ID
pub fn start_id(id: u19, thing_name: []const u8) !void {
    const cur_timer = try globals.dfr.getCurrentTimer();
    const str_id = id_helper.b10ToB62(&buf_str_id, id);

    // If there is no previous current timer and we have an ID to start on
    if (cur_timer.id_thing == 0 and id != 0) {
        try globals.dfw.startCurrentTimer(id);
        try globals.printer.startedTimer(str_id, thing_name);
        return;
    }

    // If there is already a cur timer running on another ID
    if (cur_timer.id_thing != 0 and cur_timer.id_thing != id and cur_timer.start != 0) {
        // create an empty default arg parser just to pass to `stop` that requires one
        var arg_parser = ArgumentParser{};
        try command_stop.cmd(&arg_parser);
        try globals.dfw.startCurrentTimer(id);
        try globals.printer.startedTimer(str_id, thing_name);
        return;
    }

    // If there is a stopped previous current timer
    if (cur_timer.id_thing != 0 and cur_timer.start == 0) {
        try globals.dfw.startCurrentTimer(id);
        try globals.printer.startedTimer(str_id, thing_name);
        return;
    }

    // If there is already a current timer running with the same ID
    if (cur_timer.id_thing != 0 and cur_timer.id_thing == id and cur_timer.start != 0) {
        try globals.printer.timerAlreadyRunning(str_id, thing_name);
        return;
    }
}

/// Print out help for the start command
pub fn help() !void {
    try std.io.getStdOut().writer().print(
        \\Usage: {s}mtlt start [thing_id]{s}
        \\
        \\Starts a timer on the given thing.
        \\
        \\If no ID is provided, it starts a timer on the current thing. You can see
        \\what the current thing is by using {s}mtlt{s} without any sub-command.
        \\
        \\If a timer is already running, it will be stopped before the new one starts.
        \\
        \\Examples:
        \\  {s}mtlt start{s}
        \\      Starts a timer on the current thing.
        \\
        \\  {s}mtlt start 8I{s}
        \\      Starts a timer on the thing with id '8I'.
        \\
    , .{
        ansi.colemp, ansi.colres,
        ansi.colemp, ansi.colres,
        ansi.colemp, ansi.colres,
        ansi.colemp, ansi.colres,
    });
}

test "no id provided - no current thing" {
    const cur_time = th.curTimestamp();
    var ex_file = try it_helper.getSmallFile(cur_time);
    ex_file.cur_timer.id_thing = 0;
    const ac_file = try ex_file.clone();

    var buf_ex_stderr: [128]u8 = undefined;
    const ex_stderr = try std.fmt.bufPrint(&buf_ex_stderr, "No ID provided and no current thing to operate on.\n", .{});

    var args = ArgumentParser{ .auto_confirm = true };

    try it_helper.performTest(.{
        .cmd = cmd,
        .args = &args,
        .ac_file = ac_file,
        .ex_file = ex_file,
        .ex_stderr = ex_stderr,
        .ex_stdout = "",
    });
}

test "no id provided - current thing ok - no current timer" {
    const cur_time = th.curTimestamp();
    var ex_file = try it_helper.getSmallFile(cur_time);
    ex_file.cur_timer.id_thing = 2;
    ex_file.cur_timer.id_last_timer = 1;
    ex_file.cur_timer.start = cur_time;
    var ac_file = try it_helper.getSmallFile(cur_time);
    ac_file.cur_timer.id_thing = 2;
    ac_file.cur_timer.id_last_timer = 1;
    ac_file.cur_timer.start = 0;

    var buf_ex_stdout: [128]u8 = undefined;
    const ex_stdout = try std.fmt.bufPrint(&buf_ex_stdout, "Started a timer for: {s}2{s} - {s}Name thing 2{s}\n", .{ ansi.colid, ansi.colres, ansi.colemp, ansi.colres });

    var args = ArgumentParser{ .auto_confirm = true };

    try it_helper.performTest(.{
        .cmd = cmd,
        .args = &args,
        .ac_file = ac_file,
        .ex_file = ex_file,
        .ex_stdout = ex_stdout,
        .ex_stderr = "",
    });
}

test "no id provided - current thing ok - current timer ok on this thing" {
    const cur_time = th.curTimestamp();
    var ac_file = try it_helper.getSmallFile(cur_time);
    ac_file.cur_timer.id_thing = 2;
    ac_file.cur_timer.id_last_timer = 1;
    ac_file.cur_timer.start = cur_time - 20;

    var ex_file = try it_helper.getSmallFile(cur_time);
    ex_file.cur_timer.id_thing = 2;
    ex_file.cur_timer.id_last_timer = 1;
    ex_file.cur_timer.start = cur_time - 20;

    var buf_ex_stdout: [128]u8 = undefined;
    const ex_stdout = try std.fmt.bufPrint(&buf_ex_stdout, "Timer already running for: {s}2{s} - {s}Name thing 2{s}\n", .{ ansi.colid, ansi.colres, ansi.colemp, ansi.colres });

    var args = ArgumentParser{ .auto_confirm = true };

    try it_helper.performTest(.{
        .cmd = cmd,
        .args = &args,
        .ac_file = ac_file,
        .ex_file = ex_file,
        .ex_stdout = ex_stdout,
        .ex_stderr = "",
    });
}

test "id provided that doesn't exist" {
    const cur_time = th.curTimestamp();
    var ex_file = try it_helper.getSmallFile(cur_time);
    ex_file.cur_timer.id_last_timer = 1;
    ex_file.cur_timer.start = cur_time;
    const ac_file = try ex_file.clone();

    var buf_ex_stderr: [128]u8 = undefined;
    const ex_stderr = try std.fmt.bufPrint(&buf_ex_stderr, "Thing with id {s}404{s} not found\n", .{ ansi.colemp, ansi.colres });

    var args = ArgumentParser{ .payload = "404", .auto_confirm = true };

    try it_helper.performTest(.{
        .cmd = cmd,
        .args = &args,
        .ac_file = ac_file,
        .ex_file = ex_file,
        .ex_stderr = ex_stderr,
        .ex_stdout = "",
    });
}

test "id provided is too big" {
    var args = ArgumentParser{ .payload = "idtoolong", .auto_confirm = true };

    try it_helper.performTest(.{
        .cmd = cmd,
        .args = &args,
        .ac_file = try it_helper.getStarterFile(),
        .ex_file = try it_helper.getStarterFile(),
        .ex_stderr = "The provided ID is too big.\n",
        .ex_stdout = "",
    });
}

test "id provided contains invalid characters" {
    var args = ArgumentParser{ .payload = "i.i", .auto_confirm = true };

    try it_helper.performTest(.{
        .cmd = cmd,
        .args = &args,
        .ac_file = try it_helper.getStarterFile(),
        .ex_file = try it_helper.getStarterFile(),
        .ex_stderr = "The provided ID contains invalid characters.\n",
        .ex_stdout = "",
    });
}

test "id provided ok - no current timer" {
    const cur_time = th.curTimestamp();
    var ac_file = try it_helper.getSmallFile(cur_time);
    ac_file.cur_timer.id_thing = 2;
    ac_file.cur_timer.id_last_timer = 1;
    ac_file.cur_timer.start = 0;

    var ex_file = try it_helper.getSmallFile(cur_time);
    ex_file.cur_timer.id_thing = 2;
    ex_file.cur_timer.id_last_timer = 1;
    ex_file.cur_timer.start = cur_time;

    var buf_start: [128]u8 = undefined;
    var buf_ex_stdout: [512]u8 = undefined;

    const str_start = try std.fmt.bufPrint(&buf_start, "Started a timer for: {s}2{s} - {s}Name thing 2{s}\n", .{ ansi.colid, ansi.colres, ansi.colemp, ansi.colres });
    const ex_stdout = try std.fmt.bufPrint(&buf_ex_stdout, "{s}", .{str_start});

    var args = ArgumentParser{ .payload = "2", .auto_confirm = true };

    try it_helper.performTest(.{
        .cmd = cmd,
        .args = &args,
        .ac_file = ac_file,
        .ex_file = ex_file,
        .ex_stdout = ex_stdout,
        .ex_stderr = "",
    });
}

test "id provided ok - current timer ok on provided thing" {
    const cur_time = th.curTimestamp();
    var ac_file = try it_helper.getSmallFile(cur_time);
    ac_file.cur_timer.id_thing = 2;
    ac_file.cur_timer.id_last_timer = 1;
    ac_file.cur_timer.start = cur_time - 20;

    var ex_file = try it_helper.getSmallFile(cur_time);
    ex_file.cur_timer.id_thing = 2;
    ex_file.cur_timer.id_last_timer = 1;
    ex_file.cur_timer.start = cur_time - 20;

    var buf_ex_stdout: [128]u8 = undefined;
    const ex_stdout = try std.fmt.bufPrint(&buf_ex_stdout, "Timer already running for: {s}2{s} - {s}Name thing 2{s}\n", .{ ansi.colid, ansi.colres, ansi.colemp, ansi.colres });

    var args = ArgumentParser{ .payload = "2", .auto_confirm = true };

    try it_helper.performTest(.{
        .cmd = cmd,
        .args = &args,
        .ac_file = ac_file,
        .ex_file = ex_file,
        .ex_stdout = ex_stdout,
        .ex_stderr = "",
    });
}

test "id provided ok - current timer ok on another thing" {
    const cur_time = th.curTimestamp();
    var ac_file = try it_helper.getSmallFile(cur_time);
    ac_file.cur_timer.id_thing = 1;
    ac_file.cur_timer.id_last_timer = 0;
    ac_file.cur_timer.start = cur_time - 20;

    var ex_file = try it_helper.getSmallFile(cur_time);
    ex_file.cur_timer.id_thing = 2;
    ex_file.cur_timer.id_last_timer = 1;
    ex_file.cur_timer.start = cur_time;

    var timers = try globals.allocator.alloc(dt.Timer, 1);
    timers[0] = .{ .id = 1, .duration = 20, .start = cur_time - 20 };
    ex_file.things.items[2].timers = timers[0..];

    var buf_stop: [256]u8 = undefined;
    var buf_start: [128]u8 = undefined;
    var buf_ex_stdout: [512]u8 = undefined;

    const str_stop = try std.fmt.bufPrint(&buf_stop, "Stopped timer {s}1@1{s} for {s}1{s} - {s}Name thing 1{s}. It lasted {s}3{s} steps.\n", .{ ansi.colid, ansi.colres, ansi.colid, ansi.colres, ansi.colemp, ansi.colres, ansi.colemp, ansi.colres });
    const str_start = try std.fmt.bufPrint(&buf_start, "Started a timer for: {s}2{s} - {s}Name thing 2{s}\n", .{ ansi.colid, ansi.colres, ansi.colemp, ansi.colres });
    const ex_stdout = try std.fmt.bufPrint(&buf_ex_stdout, "{s}{s}", .{ str_stop, str_start });

    var args = ArgumentParser{ .payload = "2", .auto_confirm = true };

    try it_helper.performTest(.{
        .cmd = cmd,
        .args = &args,
        .ac_file = ac_file,
        .ex_file = ex_file,
        .ex_stdout = ex_stdout,
        .ex_stderr = "",
    });
}
