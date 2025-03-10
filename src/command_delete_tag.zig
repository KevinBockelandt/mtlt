const std = @import("std");
const ansi = @import("ansi_codes.zig");
const globals = @import("globals.zig");
const user_feedback = @import("user_feedback.zig");

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
        // TODO use a switch here
        if (err == DataParsingError.TagNotFound) {
            try user_feedback.errorTagNotFound(args.*.payload.?);
        } else {
            return err;
        }
    }
}

/// Print out help for the delete tag command
pub fn help() !void {
    try std.io.getStdOut().writer().print("TODO help delete tag\n", .{});
}
