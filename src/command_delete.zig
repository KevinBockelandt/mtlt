const ansi = @import("ansi_codes.zig");
const id_helper = @import("id_helper.zig");
const dt = @import("data_types.zig");
const globals = @import("globals.zig");
const it_helper = @import("integration_tests_helper.zig");
const std = @import("std");
const th = @import("time_helper.zig");
const cli_helper = @import("cli_helper.zig");
const data_file_printer = @import("data_file_printer.zig");

const ArgumentParser = @import("argument_parser.zig").ArgumentParser;
const DataParsingError = @import("data_file_reader.zig").DataParsingError;
const DataOperationError = @import("data_file_writer.zig").DataOperationError;

const little_end = std.builtin.Endian.little;

/// Delete a thing from the data file
pub fn cmd(args: *ArgumentParser) !void {
    const id_to_delete: id_helper.Id = getIdToDelete(args.*.payload) catch |err| {
        switch (err) {
            id_helper.IdError.EmptyId => @panic("Trying to parse empty ID in command delete"),
            id_helper.IdError.InvalidTagName => try globals.printer.errInvalidTagId(),
            id_helper.IdError.InvalidTimerId => try globals.printer.errInvalidTimerId(),
            id_helper.IdError.InvalidThingId => try globals.printer.errInvalidThingId(),
            error.NoId => try globals.printer.errMissingId(),
            else => try globals.printer.errUnexpected(err),
        }
        return;
    };

    switch (id_to_delete) {
        .tag => try deleteTag(id_to_delete.tag, args.auto_confirm),
        .thing => try deleteThing(id_to_delete.thing, args.auto_confirm),
        .timer => try deleteTimer(id_to_delete, args.auto_confirm),
    }
}

/// Get the ID of the whatever we are trying to delete
fn getIdToDelete(arg: ?[]const u8) !id_helper.Id {
    if (arg) |a| {
        return id_helper.parseId(a);
    }

    // at this point we know there was no ID argument
    const cur_timer = try globals.dfr.getCurrentTimer();

    // if no argument given, try to return last timer ID if there is one
    if (cur_timer.id_thing != 0 and cur_timer.id_last_timer != 0) {
        return .{ .timer = .{
            .thing_part = cur_timer.id_thing,
            .timer_part = cur_timer.id_last_timer,
        } };
    }

    // at this point there is simply nothing to work on
    return error.NoId;
}

/// Delete a tag from the data file if confirmed
fn deleteTag(tag_name: []const u8, bypass_confirm: bool) !void {
    const w = std.io.getStdOut().writer();

    // check that the tag exist in the date file
    _ = globals.dfr.getPosTag(tag_name) catch |err| {
        switch (err) {
            DataParsingError.TagNotFound => try globals.printer.errTagNotFoundName(tag_name),
            else => try globals.printer.errUnexpected(err),
        }
        return;
    };

    // get confirmation if necessary
    if (!bypass_confirm) {
        // TODO put that in the printer
        try w.print("About to delete the tag \"{s}{s}{s}\".\n", .{ ansi.colemp, tag_name, ansi.colres });
        if (try cli_helper.confirm() == false) return;
    }

    try globals.dfw.deleteTagFromFile(tag_name);
    try globals.printer.deletedTag(tag_name);
}

/// Delete a timer from the data file
fn deleteTimer(id: id_helper.Id, bypass_confirm: bool) !void {
    const w = std.io.getStdOut().writer();
    const id_thing = id.timer.thing_part;
    const id_timer = id.timer.timer_part;

    var buf_str_id_thing: [4]u8 = undefined;
    const str_id_thing = id_helper.b10ToB62(&buf_str_id_thing, id_thing);
    var buf_str_full_id: [16]u8 = undefined;
    const str_full_id = try std.fmt.bufPrint(&buf_str_full_id, "{d}@{s}", .{ id_timer, str_id_thing });

    // TODO ideally we would check the timer exists in the data file before asking for confirmation

    if (!bypass_confirm) {
        // TODO put that in the printer
        try w.print("About to delete the timer \"{s}{s}{s}\".\n", .{ ansi.colemp, str_full_id, ansi.colres });
        if (try cli_helper.confirm() == false) return;
    }

    globals.dfw.deleteTimerFromFile(id.timer.thing_part, id.timer.timer_part) catch |err| {
        switch (err) {
            DataOperationError.TimerNotFound => try globals.printer.errTimerNotFound(str_full_id),
            else => try globals.printer.errUnexpected(err),
        }
        return;
    };

    // if that time was "last timer" we need to update that part of the file too
    const cur_timer = try globals.dfr.getCurrentTimer();
    if (cur_timer.id_thing == id_thing and cur_timer.id_last_timer == id_timer) {
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

/// Delete a thing from the data file
fn deleteThing(id_thing: u19, bypass_confirm: bool) !void {
    const w = std.io.getStdOut().writer();
    var buf_str_id: [4]u8 = undefined;
    const str_id = id_helper.b10ToB62(&buf_str_id, id_thing);

    // get infos on the thing to delete
    const fpt = globals.dfr.getFixedPartThing(id_thing) catch |err| {
        switch (err) {
            DataParsingError.ThingNotFound => try globals.printer.errThingNotFoundStr(str_id),
            else => try globals.printer.errUnexpected(err),
        }
        return;
    };

    // get specifically the name
    const thing_name = try globals.allocator.alloc(u8, fpt.lgt_name);
    defer globals.allocator.free(thing_name);
    _ = try globals.data_file.reader().read(thing_name);

    // ask confirmation before deleting the thing
    if (!bypass_confirm) {
        try w.print("About to delete thing {s}{s}{s} - {s}{s}{s}\n", .{ ansi.colid, str_id, ansi.colres, ansi.colemp, thing_name, ansi.colres });
        if (try cli_helper.confirm() == false) return;
    }

    // check if there is a running timer for this thing. If yes stop it
    const cur_timer = try globals.dfr.getCurrentTimer();
    if (cur_timer.id_thing == id_thing) {
        try globals.data_file.seekFromEnd(-dt.lgt_fixed_current_timer);
        const to_write = dt.getIntFromCurrentTimer(.{
            .id_thing = 0,
            .id_last_timer = 0,
            .start = 0,
        });
        try globals.data_file.writer().writeInt(u56, to_write, little_end);
    }

    try globals.dfw.deleteThingFromFile(id_thing);
    try globals.printer.deletedThing(str_id, thing_name);
}

/// Print out help for the delete command
pub fn help() !void {
    try std.io.getStdOut().writer().print(
        \\Usage: {s}mtlt delete <id>{s}
        \\
        \\Deletes either a thing, tag or timer permanently from the data file.
        \\
        \\The ID for a tag is it's name prefixed by the '#' character.
        \\
        \\If no ID is provided, it deletes the current thing. You can see what
        \\the current thing is by using {s}mtlt{s} without any sub-command.
        \\
        \\Examples:
        \\  {s}mtlt delete{s}
        \\      Delete the current thing.
        \\
        \\  {s}mtlt delete 8I{s}
        \\      Delete the thing with id '8I'.
        \\
        \\  {s}mtlt delete #urgent{s}
        \\      Delete the tag with name 'urgent'.
        \\
        \\  {s}mtlt delete 4@8I{s}
        \\      Delete the timer with id '4@8I'.
        \\
    , .{
        ansi.colemp, ansi.colres,
        ansi.colemp, ansi.colres,
        ansi.colemp, ansi.colres,
        ansi.colemp, ansi.colres,
        ansi.colemp, ansi.colres,
        ansi.colemp, ansi.colres,
    });
}

test "delete thing with an invalid thing ID" {
    const cur_time = th.curTimestamp();

    var buf_ex_stderr: [128]u8 = undefined;
    const ex_stderr = try std.fmt.bufPrint(&buf_ex_stderr, "The provided thing ID is invalid.\n", .{});

    var args = ArgumentParser{ .payload = "4h.4", .auto_confirm = true };

    try it_helper.performTest(.{
        .cmd = cmd,
        .args = &args,
        .ac_file = try it_helper.getSmallFile(cur_time),
        .ex_file = try it_helper.getSmallFile(cur_time),
        .ex_stderr = ex_stderr,
    });
}

test "delete thing for a non existing thing in data file" {
    const cur_time = th.curTimestamp();

    var buf_ex_stderr: [128]u8 = undefined;
    const ex_stderr = try std.fmt.bufPrint(&buf_ex_stderr, "Thing with id {s}AAA{s} not found\n", .{ ansi.colemp, ansi.colres });

    var args = ArgumentParser{ .payload = "AAA", .auto_confirm = true };

    try it_helper.performTest(.{
        .cmd = cmd,
        .args = &args,
        .ac_file = try it_helper.getSmallFile(cur_time),
        .ex_file = try it_helper.getSmallFile(cur_time),
        .ex_stderr = ex_stderr,
    });
}

test "delete thing with ID - small file" {
    const cur_time = th.curTimestamp();
    var ex_file = try it_helper.getSmallFile(cur_time);

    var buf_ex_stdout: [128]u8 = undefined;
    const ex_stdout = try std.fmt.bufPrint(&buf_ex_stdout, "Deleted thing {s}1{s} - {s}{s}{s}\n", .{ ansi.colid, ansi.colres, ansi.colemp, ex_file.things.items[2].name, ansi.colres });

    _ = ex_file.things.orderedRemove(2);
    ex_file.cur_timer.id_thing = 0;
    var args = ArgumentParser{ .payload = "1", .auto_confirm = true };

    try it_helper.performTest(.{
        .cmd = cmd,
        .args = &args,
        .ac_file = try it_helper.getSmallFile(cur_time),
        .ex_file = ex_file,
        .ex_stdout = ex_stdout,
    });
}

test "delete thing with ID - medium file" {
    const cur_time = th.curTimestamp();
    var ex_file = try it_helper.getMediumFile(cur_time);
    const ac_file = try ex_file.clone();

    var buf_ex_stdout: [128]u8 = undefined;
    const ex_stdout = try std.fmt.bufPrint(&buf_ex_stdout, "Deleted thing {s}K{s} - {s}{s}{s}\n", .{ ansi.colid, ansi.colres, ansi.colemp, ex_file.things.items[40].name, ansi.colres });

    _ = ex_file.things.orderedRemove(40);
    var args = ArgumentParser{ .payload = "K", .auto_confirm = true };

    try it_helper.performTest(.{
        .cmd = cmd,
        .args = &args,
        .ac_file = ac_file,
        .ex_file = ex_file,
        .ex_stdout = ex_stdout,
        .ex_stderr = "",
    });
}

test "delete thing and make sure it updates current timer" {
    const cur_time = th.curTimestamp();
    var ex_file = try it_helper.getSmallFile(cur_time);
    var ac_file = try it_helper.getSmallFile(cur_time);
    ac_file.cur_timer.start = 234235;

    var buf_ex_stdout: [128]u8 = undefined;
    const ex_stdout = try std.fmt.bufPrint(&buf_ex_stdout, "Deleted thing {s}1{s} - {s}{s}{s}\n", .{ ansi.colid, ansi.colres, ansi.colemp, ex_file.things.items[2].name, ansi.colres });

    _ = ex_file.things.orderedRemove(2);
    ex_file.cur_timer.id_thing = 0;
    var args = ArgumentParser{ .payload = "1", .auto_confirm = true };

    try it_helper.performTest(.{
        .cmd = cmd,
        .args = &args,
        .ac_file = ac_file,
        .ex_file = ex_file,
        .ex_stdout = ex_stdout,
    });
}

test "delete tag for a non existing tag in data file" {
    const cur_time = th.curTimestamp();

    var buf_ex_stderr: [128]u8 = undefined;
    const ex_stderr = try std.fmt.bufPrint(&buf_ex_stderr, "Tag with the name {s}nonexisting{s} not found\n", .{ ansi.colemp, ansi.colres });

    var args = ArgumentParser{ .payload = "#nonexisting", .auto_confirm = true };

    try it_helper.performTest(.{
        .cmd = cmd,
        .args = &args,
        .ac_file = try it_helper.getSmallFile(cur_time),
        .ex_file = try it_helper.getSmallFile(cur_time),
        .ex_stderr = ex_stderr,
    });
}

test "delete tag for an invalid tag name" {
    const cur_time = th.curTimestamp();

    var buf_ex_stderr: [128]u8 = undefined;
    const ex_stderr = try std.fmt.bufPrint(&buf_ex_stderr, "The provided tag ID is invalid.\n", .{});

    var args = ArgumentParser{ .payload = "#invalid.id", .auto_confirm = true };

    try it_helper.performTest(.{
        .cmd = cmd,
        .args = &args,
        .ac_file = try it_helper.getSmallFile(cur_time),
        .ex_file = try it_helper.getSmallFile(cur_time),
        .ex_stderr = ex_stderr,
    });
}

test "delete tag OK simple" {
    const cur_time = th.curTimestamp();
    var ex_file = try it_helper.getSmallFile(cur_time);

    var buf_ex_stdout: [128]u8 = undefined;
    const ex_stdout = try std.fmt.bufPrint(&buf_ex_stdout, "The tag {s}now{s} was deleted\n", .{ ansi.colemp, ansi.colres });

    _ = ex_file.tags.orderedRemove(0);
    globals.allocator.free(ex_file.things.items[1].tags);
    ex_file.things.items[1].tags = &[_]u16{};

    var args = ArgumentParser{ .payload = "#now", .auto_confirm = true };

    try it_helper.performTest(.{
        .cmd = cmd,
        .args = &args,
        .ac_file = try it_helper.getSmallFile(cur_time),
        .ex_file = ex_file,
        .ex_stdout = ex_stdout,
    });
}

test "delete tag OK complex" {
    const cur_time = th.curTimestamp();
    var ex_file = try it_helper.getMediumFile(cur_time);
    const ac_file = try ex_file.clone();

    // remove the "now" tag from the file
    _ = ex_file.tags.orderedRemove(30);

    ex_file.things.items[10].tags = &[_]u16{};
    ex_file.things.items[20].tags = &[_]u16{};

    var tag_2 = try globals.allocator.alloc(u16, 1);
    tag_2[0] = 2;

    ex_file.things.items[30].tags = tag_2[0..];
    ex_file.things.items[40].tags = tag_2[0..];

    var tag_2_1 = try globals.allocator.alloc(u16, 2);
    tag_2_1[0] = 2;
    tag_2_1[1] = 1;
    ex_file.things.items[50].tags = tag_2_1[0..];

    var buf_ex_stdout: [128]u8 = undefined;
    const ex_stdout = try std.fmt.bufPrint(&buf_ex_stdout, "The tag {s}now{s} was deleted\n", .{ ansi.colemp, ansi.colres });

    var args = ArgumentParser{ .payload = "#now", .auto_confirm = true };

    try it_helper.performTest(.{
        .cmd = cmd,
        .args = &args,
        .ac_file = ac_file,
        .ex_file = ex_file,
        .ex_stdout = ex_stdout,
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
    timers_thing_2[0] = .{ .id = 1, .duration = 20, .start = cur_time - 190 };
    ex_file.things.items[1].timers = timers_thing_2[0..];

    var args = ArgumentParser{ .auto_confirm = true };

    try it_helper.performTest(.{
        .cmd = cmd,
        .args = &args,
        .ac_file = ac_file,
        .ex_file = ex_file,
        .ex_stdout = ex_stdout,
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
    timers_thing_2[0] = .{ .id = 1, .duration = 20, .start = cur_time - 190 };
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
    timers_thing_2[0] = .{ .id = 1, .duration = 20, .start = cur_time - 190 };
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
