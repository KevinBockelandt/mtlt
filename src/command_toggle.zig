const std = @import("std");

const ansi = @import("ansi_codes.zig");
const command_stop = @import("command_stop.zig");
const dt = @import("data_types.zig");
const globals = @import("globals.zig");
const id_helper = @import("id_helper.zig");
const it_helper = @import("integration_tests_helper.zig");
const th = @import("time_helper.zig");

const ArgumentParser = @import("argument_parser.zig").ArgumentParser;
const DataParsingError = @import("data_file_reader.zig").DataParsingError;

const little_end = std.builtin.Endian.little;

/// Toggle the status of a thing
pub fn cmd(args: *ArgumentParser) !void {
    var buf_str_id: [4]u8 = undefined;

    // get the current timer contained in the data file
    var cur_timer = try globals.dfr.getCurrentTimer();

    var id_thing: u19 = undefined;

    // determine the id of the thing to toggle
    if (args.*.payload == null) {
        // no argument and no previous current timer
        if (cur_timer.id_thing == 0) {
            try globals.printer.errMissingIdThing();
            return;
        } else {
            id_thing = cur_timer.id_thing;
        }
    } else {
        id_thing = try id_helper.b62ToB10(args.*.payload.?);
    }

    const str_id = id_helper.b10ToB62(&buf_str_id, id_thing);

    //  stop a potential current timer running associated to the thing to toggle
    if (globals.dfr.getFixedPartThing(id_thing)) |fpt| {
        if (fpt.status == @intFromEnum(dt.StatusThing.open) and cur_timer.id_thing == id_thing and cur_timer.start != 0) {
            try command_stop.cmd(args);
            cur_timer = try globals.dfr.getCurrentTimer();
        }
    } else |err| {
        if (err == DataParsingError.ThingNotFound) {
            try globals.printer.errThingNotFoundNum(id_thing);
            return err;
        } else {
            return err;
        }
    }

    // now that the current timer is closed (if needed), we get the full infos on the thing
    const thing_data = try globals.dfr.getThing(id_thing);
    defer thing_data.deinit();

    // actually toggle the status
    if (globals.dfw.toggleThingStatus(id_thing)) |new_status| {
        const str_new_status: []const u8 = @tagName(new_status);

        try globals.printer.reportThingIdName(str_id, thing_data.name);
        try globals.printer.reportStatus(str_new_status);

        // display recap on the time spent on this thing
        if (thing_data.timers.len > 0) {
            // get the total amount of time spent on this thing
            var total_time_spent: i64 = 0;
            for (thing_data.timers) |timer| {
                total_time_spent += timer.duration;
            }

            // convert total time spent from minutes to steps
            total_time_spent = try th.getStepsFromMinutes(i64, total_time_spent);

            const remaining_time: i64 = @as(i64, @intCast(thing_data.estimation)) - total_time_spent;
            const col_remaining_time = ansi.getDurCol(remaining_time);

            if (thing_data.estimation > 0) {
                try globals.printer.reportTimeLeftInfos(@intCast(remaining_time), col_remaining_time);
            }
        }

        // if we re-opened the thing
        if (new_status == dt.StatusThing.open) {
            if (args.*.should_start) {
                cur_timer.start = th.curTimestamp();
            }
            cur_timer.id_last_timer = 0;
        }

        cur_timer.id_thing = id_thing;
        try globals.dfw.updateCurrentTimer(cur_timer);
    } else |err| {
        switch (err) {
            DataParsingError.ThingNotFound => try globals.printer.errThingNotFoundStr(str_id),
            else => try globals.printer.errUnexpectedToggleThing(err),
        }
    }
}

/// Print out help for the toggle command
pub fn help() !void {
    try std.io.getStdOut().writer().print(
        \\Usage: {s}mtlt toggle-tag [thing_id]{s}
        \\
        \\Toggles the status of a thing between open and closed.
        \\
        \\If no ID is provided, it toggles the current thing. You can see what
        \\the current thing is by using {s}mtlt{s} without any sub-command.
        \\
        \\Examples:
        \\  {s}mtlt toggle{s}
        \\      Toggle status of the current thing.
        \\
        \\  {s}mtlt toggle 2B{s}
        \\      Toggle status of the thing with ID '2B'.
        \\
    , .{
        ansi.colemp, ansi.colres,
        ansi.colemp, ansi.colres,
        ansi.colemp, ansi.colres,
        ansi.colemp, ansi.colres,
    });
}

test "toggle - the current thing - no current thing" {
    const cur_time = th.curTimestamp();

    var ac_file = try it_helper.getSmallFile(cur_time);
    ac_file.cur_timer.id_thing = 0;

    var ex_file = try it_helper.getSmallFile(cur_time);
    ex_file.cur_timer.id_thing = 0;

    var buf_ex_stderr: [1024]u8 = undefined;
    const ex_stderr = try std.fmt.bufPrint(&buf_ex_stderr, "No ID provided and no current thing to operate on.\n", .{});

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

test "toggle - the current thing - closing ok - no timer" {
    const cur_time = th.curTimestamp();

    var ex_file = try it_helper.getSmallFile(cur_time);
    ex_file.things.items[2].closure = cur_time;
    ex_file.things.items[2].status = dt.StatusThing.closed;

    var args = ArgumentParser{};

    try it_helper.performTest(.{
        .cmd = cmd,
        .args = &args,
        .ac_file = try it_helper.getSmallFile(cur_time),
        .ex_file = ex_file,
        .ex_stderr = "",
    });
}

test "toggle - the current thing - closing ok - timer stopped" {
    const cur_time = th.curTimestamp();

    var ac_file = try it_helper.getSmallFile(cur_time);
    ac_file.cur_timer.start = cur_time - 100;
    ac_file.cur_timer.id_thing = 1;

    var ex_file = try it_helper.getSmallFile(cur_time);
    var timers = try globals.allocator.alloc(dt.Timer, 1);
    timers[0] = .{ .id = 1, .duration = 100, .start = cur_time - 100 };

    ex_file.things.items[2].closure = cur_time;
    ex_file.things.items[2].status = dt.StatusThing.closed;
    ex_file.things.items[2].timers = timers[0..];
    ex_file.cur_timer.start = 0;
    ex_file.cur_timer.id_thing = 1;
    ex_file.cur_timer.id_last_timer = 1;

    var args = ArgumentParser{};

    try it_helper.performTest(.{
        .cmd = cmd,
        .args = &args,
        .ac_file = ac_file,
        .ex_file = ex_file,
        .ex_stderr = "",
    });
}

test "toggle - the current thing - opening ok - starts timer" {
    const cur_time = th.curTimestamp();

    var ac_file = try it_helper.getSmallFile(cur_time);
    ac_file.cur_timer.id_thing = 3;

    var ex_file = try it_helper.getSmallFile(cur_time);
    ex_file.things.items[0].closure = 0;
    ex_file.things.items[0].status = dt.StatusThing.open;

    ex_file.cur_timer.start = cur_time;
    ex_file.cur_timer.id_thing = 3;

    var args: ArgumentParser = .{ .should_start = true };

    try it_helper.performTest(.{
        .cmd = cmd,
        .args = &args,
        .ac_file = ac_file,
        .ex_file = ex_file,
        .ex_stderr = "",
    });
}

test "toggle - id thing - opening ok - no timer to start" {
    const cur_time = th.curTimestamp();

    var ac_file = try it_helper.getSmallFile(cur_time);
    ac_file.things.items[2].status = dt.StatusThing.closed;
    ac_file.cur_timer.id_thing = 3;
    ac_file.cur_timer.id_last_timer = 2;

    var ex_file = try it_helper.getSmallFile(cur_time);
    ex_file.things.items[2].closure = 0;
    ex_file.things.items[2].status = dt.StatusThing.open;

    ex_file.cur_timer.id_thing = 1;
    ex_file.cur_timer.id_last_timer = 0;

    var args: ArgumentParser = .{ .payload = "1" };

    try it_helper.performTest(.{
        .cmd = cmd,
        .args = &args,
        .ac_file = ac_file,
        .ex_file = ex_file,
        .ex_stderr = "",
    });
}
