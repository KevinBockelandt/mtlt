const ansi = @import("ansi_codes.zig");
const id_helper = @import("id_helper.zig");
const dt = @import("data_types.zig");
const globals = @import("globals.zig");
const it_helper = @import("integration_tests_helper.zig");
const std = @import("std");
const th = @import("time_helper.zig");
const cli_helper = @import("cli_helper.zig");

// todo remove
const dfw = @import("data_file_writer.zig");
const data_file_printer = @import("data_file_printer.zig");

const ArgumentParser = @import("argument_parser.zig").ArgumentParser;
const DataParsingError = @import("data_file_reader.zig").DataParsingError;

const little_end = std.builtin.Endian.little;

/// Delete a thing from the data file
pub fn cmd(args: *ArgumentParser) !void {
    const id_to_delete: id_helper.Id = getIdToDelete(args.*.payload) catch |err| {
        switch (err) {
            id_helper.IdError.EmptyId => @panic("Trying to parse empty ID in command delete"),
            id_helper.IdError.InvalidTagName => globals.printer.errInvalidTagId(),
            id_helper.IdError.InvalidTimerId => globals.printer.errInvalidTimerId(),
            id_helper.IdError.InvalidThingId => globals.printer.errInvalidThingId(),
        }
        return;
    };

    switch (id_to_delete) {
        .tag => deleteTag(id_to_delete.tag, args.auto_confirm),
        .thing => deleteThing(id_to_delete.tag, args.*.payload, args.auto_confirm),
        .timer => deleteTimer(id_to_delete, args.*.payload, args.auto_confirm),
    }
}

/// Get the ID of the whatever we are trying to delete
fn getIdToDelete(arg: ?[]const u8) !id_helper.Id {
    if (arg == null) {
        const cur_timer = try globals.dfr.getCurrentTimer();

        if (cur_timer.id_thing != 0) {
            return .{ .thing = cur_timer.id_thing };
        } else {
            // at this point there is simply nothing to work on

            // TODO change the error message
            try globals.printer.errIdThingMissing();
            return error.NoId;
        }
    }
}

/// Delete a tag from the data file if confirmed
fn deleteTag(tag_name: []const u8, bypass_confirm: bool) !void {
    const w = std.io.getStdOut().writer();
    w.print("About to delete the tag \"{s}{s}{s}\".\n", .{ ansi.colemp, tag_name, ansi.colres });

    if (try cli_helper.confirm(bypass_confirm)) {
        if (globals.dfw.deleteTagFromFile(tag_name)) |_| {
            try globals.printer.deletedTag(tag_name);
        } else |err| {
            switch (err) {
                DataParsingError.TagNotFound => try globals.printer.errTagNotFoundName(tag_name),
                else => return err,
            }
        }
    }
}
///
/// Delete a thing from the data file
fn deleteTimer(id: id_helper.Id, str_id_thing: []const u8, bypass_confirm: bool) !void {
    // TODO
}

/// Delete a thing from the data file
fn deleteThing(id_thing: u19, str_id_thing: []const u8, bypass_confirm: bool) !void {
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

    // get the name of the thing to delete
    if (globals.dfr.getFixedPartThing(id_thing)) |fpt| {
        const thing_name = try globals.allocator.alloc(u8, fpt.lgt_name);
        defer globals.allocator.free(thing_name);
        _ = try globals.data_file.reader().read(thing_name);

        // try to delete the thing
        try globals.dfw.deleteThingFromFile(id_thing);
        try globals.printer.deletedThing(str_id_thing, thing_name);
    } else |err| {
        switch (err) {
            DataParsingError.ThingNotFound => try globals.printer.errThingNotFoundStr(str_id_thing),
            else => return err,
        }
    }
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

test "delete thing without ID based on current thing ID" {
    const cur_time = th.curTimestamp();
    var ex_file = try it_helper.getSmallFile(cur_time);

    var buf_ex_stdout: [128]u8 = undefined;
    const ex_stdout = try std.fmt.bufPrint(&buf_ex_stdout, "Deleted thing {s}1{s} - {s}{s}{s}\n", .{ ansi.colid, ansi.colres, ansi.colemp, ex_file.things.items[2].name, ansi.colres });

    _ = ex_file.things.orderedRemove(2);
    ex_file.cur_timer.id_thing = 0;
    var args = ArgumentParser{};

    try it_helper.performTest(.{
        .cmd = cmd,
        .args = &args,
        .ac_file = try it_helper.getSmallFile(cur_time),
        .ex_file = ex_file,
        .ex_stdout = ex_stdout,
    });
}

// TODO test with no ID and no previous ID
//
// TODO test with an ID which is invalid
// TODO test with correct ID for a thing that doesn't exist
// TODO test with correct ID for a tag that doesn't exist
// TODO test with correct ID for a timer that doesn't exist
//
// TODO test with correct ID for tag no confirmation
// TODO test with correct ID for tag yes confirmation
//
// TODO test OK to delete thing
// make sure it stops associated running timer
//
// TODO test OK to delete tag
// TODO test OK to delete timer
