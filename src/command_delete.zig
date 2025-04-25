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
    // TODO get id
    // Either from argument or current thing

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
    if (!args.auto_confirm) {
        try globals.printer.confirmDeleteThing(str_id, thing_name);
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
        \\Usage: {s}mtlt delete [id]{s}
        \\
        \\Deletes either a thing, tag or timer permanently from the data file.
        \\
        \\The ID for a tag is it's name prefixed by the '#' character.
        \\
        \\If no ID is provided, it deletes the last timer. You can see what
        \\the last timer is by using {s}mtlt{s} without any sub-command.
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

// TODO test "no id - no current thing

// TODO test "no id - current thing ok

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
