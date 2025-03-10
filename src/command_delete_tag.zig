const std = @import("std");
const ansi = @import("ansi_codes.zig");
const globals = @import("globals.zig");

const ArgumentParser = @import("argument_parser.zig").ArgumentParser;
const DataParsingError = @import("data_file_reader.zig").DataParsingError;

const little_end = std.builtin.Endian.little;

/// Delete a tag from the data file
pub fn cmd(args: *ArgumentParser) !void {
    const w = std.io.getStdOut().writer();

    if (args.*.payload == null) {
        _ = try w.write("Need to specify the name(s) of the tag(s) to remove\n");
        return;
    }

    if (globals.dfw.deleteTagFromFile(args.*.payload.?)) |_| {
        try w.print("The tag {s}{s}{s} was deleted\n", .{ ansi.colemp, args.*.payload.?, ansi.colres });
    } else |err| {
        if (err == DataParsingError.TagNotFound) {
            try w.print("Error: No tag found with the name {s}{s}{s}\n", .{ ansi.colemp, args.*.payload.?, ansi.colres });
        } else {
            return err;
        }
    }
}

/// Print out help for the delete tag command
pub fn help() !void {
    try std.io.getStdOut().writer().print(
        \\Usage: {s}mtlt delete-tag <tag_name>{s}
        \\
        \\Deletes a tag permanently from the date file.
        \\
        \\Examples:
        \\  {s}mtlt delete-tag theTag{s}
        \\
    , .{
        ansi.colemp, ansi.colres,
        ansi.colemp, ansi.colres,
    });
}
