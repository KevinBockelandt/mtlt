const ansi = @import("ansi_codes.zig");
const id_helper = @import("id_helper.zig");
const dt = @import("data_types.zig");
const globals = @import("globals.zig");
const it_helper = @import("integration_tests_helper.zig");
const std = @import("std");
const th = @import("time_helper.zig");

// todo remove
const dfw = @import("data_file_writer.zig");
const data_file_printer = @import("data_file_printer.zig");

const ArgumentParser = @import("argument_parser.zig").ArgumentParser;
const DataParsingError = @import("data_file_reader.zig").DataParsingError;

const little_end = std.builtin.Endian.little;

/// Delete a thing from the data file
pub fn cmd(args: *ArgumentParser) !void {
    var id_thing_to_delete: u19 = 0;

    // if there is no argument with the command
    if (args.*.payload == null) {
        const cur_timer = try globals.dfr.getCurrentTimer();

        // and there is a previous thing to delete
        if (cur_timer.id_thing != 0) {
            id_thing_to_delete = cur_timer.id_thing;
        } else {
            // TODO change the error message
            try globals.printer.errIdThingMissing();
        }
    } else {
        // TODO get the ID according to it's type
        // Have a taged union with -type -id_value
        id_thing_to_delete = try id_helper.b62ToB10(args.*.payload.?);
    }
}

/// Delete a thing from the data file
fn delete_thing(id_thing: u19, str_id_thing: []const u8) !void {
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
