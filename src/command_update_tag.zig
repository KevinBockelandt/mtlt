const std = @import("std");

const ansi = @import("ansi_codes.zig");
const globals = @import("globals.zig");
const user_feedback = @import("user_feedback.zig");

const ArgumentParser = @import("argument_parser.zig").ArgumentParser;
const DataOperationError = @import("data_file_writer.zig").DataOperationError;
const DataParsingError = @import("data_file_reader.zig").DataParsingError;

/// Update the name of a tag
pub fn cmd(args: *ArgumentParser) !void {
    if (args.*.payload == null) {
        try user_feedback.errUpdateTagMissingOldName();
        return;
    }

    if (args.*.name == null) {
        try user_feedback.errUpdateTagMissingNewName();
        return;
    }

    // perform the operation
    if (globals.dfw.updateTagName(args.*.payload.?, args.*.name.?)) |_| {
        try user_feedback.updatedTag(args.payload.?, args.*.name.?);
    } else |err| {
        switch (err) {
            DataParsingError.TagNotFound => try user_feedback.errTagNotFoundName(args.*.payload.?),
            DataOperationError.NameTooLong => try user_feedback.errNameTagTooLong(args.*.name.?),
            DataOperationError.TagWithThisNameAlreadyExisting => try user_feedback.errNameTagAlreadyExisting(args.*.name.?),
            else => return err,
        }
    }
}

/// Print out help for the update-tag command
pub fn help() !void {
    try std.io.getStdOut().writer().print("TODO help update-tag\n", .{});
}
