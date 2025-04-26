const ansi = @import("ansi_codes.zig");
const dt = @import("data_types.zig");
const globals = @import("globals.zig");
const id_helper = @import("id_helper.zig");
const it_helper = @import("integration_tests_helper.zig");
const std = @import("std");
const th = @import("time_helper.zig");
const cli_helper = @import("cli_helper.zig");
const data_file_printer = @import("data_file_printer.zig");

const ArgumentParser = @import("argument_parser.zig").ArgumentParser;
const DataParsingError = @import("data_file_reader.zig").DataParsingError;
const DataOperationError = @import("data_file_writer.zig").DataOperationError;

const little_end = std.builtin.Endian.little;

/// Delete a timer from the data file
pub fn cmd(args: *ArgumentParser) !void {
    var id_thing_part: u19 = 0;
    var id_timer_part: u11 = 0;

    // if there was an argument in the command line
    if (args.*.payload != null) {
        var id_it = std.mem.splitSequence(u8, args.*.payload.?, "@");

        const str_timer_part = id_it.first();
        const str_thing_part = id_it.rest();

        id_timer_part = std.fmt.parseInt(u11, str_timer_part, 10) catch |err| {
            switch (err) {
                error.Overflow => try globals.printer.errInvalidTimerId(),
                error.InvalidCharacter => try globals.printer.errInvalidTimerId(),
            }
            return;
        };
        id_thing_part = id_helper.b62ToB10(str_thing_part) catch |err| {
            switch (err) {
                id_helper.Base62Error.TooBig => try globals.printer.errInvalidTimerId(),
                id_helper.Base62Error.ContainsInvalidCharacters => try globals.printer.errInvalidTimerId(),
            }
            return;
        };
    } else {
        // at this point we know there was no ID argument
        const cur_timer = try globals.dfr.getCurrentTimer();

        // if no argument given, try to return last timer ID if there is one
        if (cur_timer.id_thing != 0 and cur_timer.id_last_timer != 0) {
            id_thing_part = cur_timer.id_thing;
            id_timer_part = cur_timer.id_last_timer;
        } else {
            // at this point there is simply nothing to work on
            try globals.printer.errMissingIdTimer();
            return;
        }
    }

    var buf_str_id_thing: [4]u8 = undefined;
    const str_id_thing = id_helper.b10ToB62(&buf_str_id_thing, id_thing_part);
    var buf_str_full_id: [16]u8 = undefined;
    const str_full_id = try std.fmt.bufPrint(&buf_str_full_id, "{d}@{s}", .{ id_timer_part, str_id_thing });

    // TODO ideally we would check the timer exists in the data file before asking for confirmation

    if (!args.auto_confirm) {
        try globals.printer.confirmDeleteTimer(str_full_id);
        if (try cli_helper.confirm() == false) return;
    }

    globals.dfw.deleteTimerFromFile(id_thing_part, id_timer_part) catch |err| {
        switch (err) {
            DataOperationError.TimerNotFound => try globals.printer.errTimerNotFound(str_full_id),
            else => try globals.printer.errUnexpected(err),
        }
        return;
    };

    // if that time was "last timer" we need to update that part of the file too
    const cur_timer = try globals.dfr.getCurrentTimer();
    if (cur_timer.id_thing == id_thing_part and cur_timer.id_last_timer == id_timer_part) {
        try globals.data_file.seekFromEnd(-dt.lgt_fixed_current_timer);
        const to_write = dt.getIntFromCurrentTimer(.{
            .id_thing = cur_timer.id_thing,
            .id_last_timer = 0,
            .start = 0,
        });
        try globals.data_file.writer().writeInt(u56, to_write, little_end);
    }

    try globals.printer.deletedTimer(str_full_id);
}

/// Print out help for the delete command
pub fn help() !void {
    try std.io.getStdOut().writer().print(
        \\Usage: {s}mtlt delete [id]{s}
        \\
        \\Deletes a timer permanently from the data file.
        \\
        \\If no ID is provided, it deletes the last timer. You can see what
        \\the last timer is by using {s}mtlt{s} without any sub-command.
        \\
        \\Examples:
        \\  {s}mtlt delete{s}
        \\      Delete the last timer.
        \\
        \\  {s}mtlt delete 4@8I{s}
        \\      Delete the timer with id '4@8I'.
        \\
    , .{
        ansi.colemp, ansi.colres,
        ansi.colemp, ansi.colres,
        ansi.colemp, ansi.colres,
        ansi.colemp, ansi.colres,
    });
}

test "delete timer without specifying id - no last timer" {
    const cur_time = th.curTimestamp();
    const ex_file = try it_helper.getSmallFile(cur_time);
    const ac_file = try it_helper.getSmallFile(cur_time);

    var args = ArgumentParser{ .auto_confirm = true };

    try it_helper.performTest(.{
        .cmd = cmd,
        .args = &args,
        .ac_file = ac_file,
        .ex_file = ex_file,
        .ex_stderr = "No ID provided and no last timer to operate on.\n",
    });
}

test "delete timer without specifying id - ok" {
    const cur_time = th.curTimestamp();
    var ex_file = try it_helper.getSmallFile(cur_time);
    var ac_file = try it_helper.getSmallFile(cur_time);
    ex_file.cur_timer.id_thing = 2;
    ex_file.cur_timer.id_last_timer = 0;
    ac_file.cur_timer.id_thing = 2;
    ac_file.cur_timer.id_last_timer = 2;

    var buf_ex_stdout: [128]u8 = undefined;
    const ex_stdout = try std.fmt.bufPrint(&buf_ex_stdout, "Deleted timer {s}2@2{s}.\n", .{ ansi.colid, ansi.colres });

    var timers_thing_2 = try globals.allocator.alloc(dt.Timer, 1);
    timers_thing_2[0] = .{ .id = 1, .duration = try th.getMinutesFromSteps(u12, 20), .start = cur_time - 190 };
    ex_file.things.items[1].timers = timers_thing_2[0..];

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

test "delete timer for an invalid timer id" {
    const cur_time = th.curTimestamp();

    var buf_ex_stderr: [128]u8 = undefined;
    const ex_stderr = try std.fmt.bufPrint(&buf_ex_stderr, "The provided timer ID is invalid.\n", .{});

    var args = ArgumentParser{ .payload = "4@a.a", .auto_confirm = true };

    try it_helper.performTest(.{
        .cmd = cmd,
        .args = &args,
        .ac_file = try it_helper.getSmallFile(cur_time),
        .ex_file = try it_helper.getSmallFile(cur_time),
        .ex_stderr = ex_stderr,
    });
}

test "delete timer for a non existing timer id" {
    const cur_time = th.curTimestamp();

    var buf_ex_stderr: [128]u8 = undefined;
    const ex_stderr = try std.fmt.bufPrint(&buf_ex_stderr, "The provided timer ID is invalid.\n", .{});

    var args = ArgumentParser{ .payload = "4@a.a", .auto_confirm = true };

    try it_helper.performTest(.{
        .cmd = cmd,
        .args = &args,
        .ac_file = try it_helper.getSmallFile(cur_time),
        .ex_file = try it_helper.getSmallFile(cur_time),
        .ex_stderr = ex_stderr,
    });
}

test "delete timer ok - small file - remove last timer" {
    const cur_time = th.curTimestamp();
    var ex_file = try it_helper.getSmallFile(cur_time);
    var ac_file = try it_helper.getSmallFile(cur_time);
    ex_file.cur_timer.id_thing = 2;
    ex_file.cur_timer.id_last_timer = 0;
    ac_file.cur_timer.id_thing = 2;
    ac_file.cur_timer.id_last_timer = 2;

    var buf_ex_stdout: [128]u8 = undefined;
    const ex_stdout = try std.fmt.bufPrint(&buf_ex_stdout, "Deleted timer {s}2@2{s}.\n", .{ ansi.colid, ansi.colres });

    var timers_thing_2 = try globals.allocator.alloc(dt.Timer, 1);
    timers_thing_2[0] = .{ .id = 1, .duration = try th.getMinutesFromSteps(u12, 20), .start = cur_time - 190 };
    ex_file.things.items[1].timers = timers_thing_2[0..];

    var args = ArgumentParser{ .payload = "2@2", .auto_confirm = true };

    try it_helper.performTest(.{
        .cmd = cmd,
        .args = &args,
        .ac_file = ac_file,
        .ex_file = ex_file,
        .ex_stdout = ex_stdout,
    });
}

test "delete timer ok - small file - don't remove last timer" {
    const cur_time = th.curTimestamp();
    var ex_file = try it_helper.getSmallFile(cur_time);
    var ac_file = try it_helper.getSmallFile(cur_time);
    ex_file.cur_timer.id_thing = 2;
    ex_file.cur_timer.id_last_timer = 1;
    ac_file.cur_timer.id_thing = 2;
    ac_file.cur_timer.id_last_timer = 1;

    var buf_ex_stdout: [128]u8 = undefined;
    const ex_stdout = try std.fmt.bufPrint(&buf_ex_stdout, "Deleted timer {s}2@2{s}.\n", .{ ansi.colid, ansi.colres });

    var timers_thing_2 = try globals.allocator.alloc(dt.Timer, 1);
    timers_thing_2[0] = .{ .id = 1, .duration = try th.getMinutesFromSteps(u12, 20), .start = cur_time - 190 };
    ex_file.things.items[1].timers = timers_thing_2[0..];

    var args = ArgumentParser{ .payload = "2@2", .auto_confirm = true };

    try it_helper.performTest(.{
        .cmd = cmd,
        .args = &args,
        .ac_file = ac_file,
        .ex_file = ex_file,
        .ex_stdout = ex_stdout,
    });
}
