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
    try std.io.getStdOut().writer().print(
        \\Usage: {s}mtlt update-tag <old_name> -n <new_name>{s}
        \\
        \\Updates the name of a tag
        \\
        \\The tag names can only contain ASCII letters, numbers and the '_' or '-'
        \\characters
        \\
        \\Options:
        \\  {s}-n{s}, {s}--name{s}            New name of the tag
        \\
        \\Examples:
        \\  {s}mtlt update-tag old_name -n new_name{s}
        \\      Update the tag called 'old_name' to change it to 'new_name'.
        \\
        \\  {s}mtlt update-tag withTypo -n withoutTypo{s}
        \\      Update the tag called 'withTypo' to change it to 'withoutTypo'.
        \\
    , .{
        ansi.colemp, ansi.colres,
        ansi.colid,  ansi.colres,
        ansi.colid,  ansi.colres,
        ansi.colemp, ansi.colres,
        ansi.colemp, ansi.colres,
    });
}
