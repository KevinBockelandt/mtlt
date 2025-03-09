const std = @import("std");

const ansi = @import("ansi_codes.zig");
const globals = @import("globals.zig");

const ArgumentParser = @import("argument_parser.zig").ArgumentParser;
const DataOperationError = @import("data_file_writer.zig").DataOperationError;
const DataParsingError = @import("data_file_reader.zig").DataParsingError;

/// Update the name of a tag
pub fn cmd(args: *ArgumentParser) !void {
    const w = std.io.getStdOut().writer();

    if (args.*.payload == null) {
        _ = try w.write("The current name of the tag to udpate is missing");
        _ = try w.write("The format of the command is \"mtlt udpate-tag <old_name> -n <new_name>\"");
        return;
    }

    if (args.*.name == null) {
        _ = try w.write("The new name for the tag needs to be specified with the \"-n\" or \"--name\" flag");
        _ = try w.write("The format of the command is \"mtlt udpate-tag <old_name> -n <new_name>\"");
        return;
    }

    // perform the operation
    if (globals.dfw.updateTagName(args.*.payload.?, args.*.name.?)) |_| {
        try w.print("Tag {s}{s}{s} is now nammed {s}{s}{s}\n", .{ ansi.colemp, args.*.payload.?, ansi.colres, ansi.colemp, args.*.name.?, ansi.colres });
    } else |err| {
        switch (err) {
            DataParsingError.TagNotFound => try w.print("Error: no tag with name {s}{s}{s} found\n", .{ ansi.colemp, args.*.payload.?, ansi.colres }),
            DataOperationError.NameTooLong => try w.print("Error: the new name is too long {s}{s}{s}\n", .{ ansi.colemp, args.*.name.?, ansi.colres }),
            DataOperationError.TagWithThisNameAlreadyExisting => try w.print("Error: a tag with the name {s}{s}{s} already exists\n", .{ ansi.colemp, args.*.name.?, ansi.colres }),
            else => return err,
        }
    }
}

/// Print out help for the update-tag command
pub fn help() !void {
    try std.io.getStdOut().writer().print("TODO help update-tag\n", .{});
}
