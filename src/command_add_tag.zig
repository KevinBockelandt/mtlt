const std = @import("std");

const ansi = @import("ansi_codes.zig");
const dt = @import("data_types.zig");
const dfr = @import("data_file_reader.zig");
const globals = @import("globals.zig");
const string_helper = @import("string_helper.zig");
const user_feedback = @import("user_feedback.zig");

const ArgumentParser = @import("argument_parser.zig").ArgumentParser;
const DataOperationError = @import("data_file_writer.zig").DataOperationError;

pub const CommandError = error{
    NoDuration,
    SeveralDurationArgs,
    StartLessAndMore,
};

/// Add a new tag to the data file
pub fn cmd(args: *ArgumentParser) !void {
    if (args.*.payload == null) {
        try user_feedback.errMissingTagNameToAdd();
        return;
    }

    // check for invalid characters in the tag name
    for (args.*.payload.?) |c| {
        if (!string_helper.isValidTagNameChar(c)) {
            try user_feedback.errNameTagInvalidChara();
            return;
        }
    }

    if (globals.dfw.addTagToFile(args.*.payload.?)) |new_tag_id| {
        _ = new_tag_id;
        try user_feedback.createdTag(args.*.payload.?);
    } else |err| {
        if (err == DataOperationError.NameTooLong) {
            try user_feedback.errNameTagTooLong(args.*.payload.?);
        } else if (err == DataOperationError.TagWithThisNameAlreadyExisting) {
            try user_feedback.errNameTagAlreadyExisting(args.*.payload.?);
        } else {
            return err;
        }
    }
}

/// Display help text for this command
pub fn help() !void {
    try std.io.getStdOut().writer().print(
        \\Usage: {s}mtlt add-tag <tag_name>{s}
        \\
        \\Creates a new tag.
        \\
        \\The tag name can only contain ASCII letters, numbers and the '_' or '-'
        \\characters.
        \\
        \\Examples:
        \\  {s}mtlt add-tag "myCoolTag"{s}
        \\      Create a new tag called 'myCoolTag'.
        \\
        \\  {s}mtlt add-tag "1-also-good"{s}
        \\      Create a new tag called '1-also-good'.
        \\
        \\  {s}mtlt add-tag "_it_works"{s}
        \\      Create a new tag called '_it_works'.
        \\
    , .{
        ansi.colemp, ansi.colres,
        ansi.colemp, ansi.colres,
        ansi.colemp, ansi.colres,
        ansi.colemp, ansi.colres,
    });
}
