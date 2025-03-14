const std = @import("std");
const ansi = @import("ansi_codes.zig");
const base62_helper = @import("base62_helper.zig");
const dt = @import("data_types.zig");
const globals = @import("globals.zig");

const ArgumentParser = @import("argument_parser.zig").ArgumentParser;
const DataParsingError = @import("data_file_reader.zig").DataParsingError;

const little_end = std.builtin.Endian.little;

/// Delete a thing from the data file
pub fn cmd(args: *ArgumentParser) !void {
    const w = std.io.getStdOut().writer();
    var id_thing_to_delete: u19 = 0;
    var buf_str_id: [4]u8 = undefined;

    // if there is no argument with the command
    if (args.*.payload == null) {
        const cur_timer = try globals.dfr.getCurrentTimer();

        // and there is a previous thing to delete
        if (cur_timer.id_thing != 0) {
            id_thing_to_delete = cur_timer.id_thing;
        } else {
            _ = try w.write("Need to specify the id of the thing to remove\n");
        }
    } else {
        id_thing_to_delete = try base62_helper.b62ToB10(args.*.payload.?);
    }

    // check if there is a running timer for this thing. If yes stop it
    const cur_timer = try globals.dfr.getCurrentTimer();
    if (cur_timer.id_thing == id_thing_to_delete) {
        try globals.data_file.seekFromEnd(-dt.lgt_fixed_current_timer);
        const to_write = dt.getIntFromCurrentTimer(.{
            .id_thing = 0,
            .id_last_timer = 0,
            .start = 0,
        });
        try globals.data_file.writer().writeInt(u56, to_write, little_end);
    }

    // get the name of the thing to delete
    if (globals.dfr.getFixedPartThing(id_thing_to_delete)) |fpt| {
        const thing_name = try globals.allocator.alloc(u8, fpt.lgt_name);
        defer globals.allocator.free(thing_name);
        _ = try globals.data_file.reader().read(thing_name);

        // try to delete the thing
        try globals.dfw.deleteThingFromFile(id_thing_to_delete);
        const str_id_thing = base62_helper.b10ToB62(&buf_str_id, id_thing_to_delete);
        try w.print("Deleted thing {s}{s}{s} - {s}{s}{s}\n", .{ ansi.colid, str_id_thing, ansi.colres, ansi.colemp, thing_name, ansi.colres });
    } else |err| {
        switch (err) {
            DataParsingError.ThingNotFound => try std.io.getStdOut().writer().print("Error: thing with id {s}{s}{s} not found", .{ ansi.colemp, args.*.payload.?, ansi.colres }),
            else => return err,
        }
    }
}

/// Print out help for the delete command
pub fn help() !void {
    try std.io.getStdOut().writer().print(
        \\Usage: {s}mtlt delete [thing_id]{s}
        \\
        \\Deletes a thing permanently from the data file.
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
    , .{
        ansi.colemp, ansi.colres,
        ansi.colemp, ansi.colres,
        ansi.colemp, ansi.colres,
        ansi.colemp, ansi.colres,
    });
}
