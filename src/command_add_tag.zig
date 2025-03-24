const std = @import("std");

const ansi = @import("ansi_codes.zig");
const data_file_printer = @import("data_file_printer.zig");
const dfr = @import("data_file_reader.zig");
const dfw = @import("data_file_writer.zig");
const dt = @import("data_types.zig");
const globals = @import("globals.zig");
const it_helper = @import("integration_tests_helper.zig");
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

test "add tag in empty file" {
    try it_helper.initTest();
    defer it_helper.deinitTest();

    // create the expected file
    var ex_file: dt.FullData = .{};
    ex_file.init();
    defer ex_file.tags.deinit();
    defer ex_file.things.deinit();

    try ex_file.tags.append(.{ .id = 1, .status = dt.Status.ongoing, .name = "testtag" });
    try dfw.writeFullData(ex_file, it_helper.integration_test_file_path);

    // create the actual file by executing the command
    var args: ArgumentParser = .{ .payload = "testtag" };
    try cmd(&args);

    // check the files match properly
    try it_helper.compareFiles(ex_file);
}

test "add tag in file containing only tags" {
    try it_helper.initTest();
    defer it_helper.deinitTest();

    // create the expected file
    var ex_file: dt.FullData = .{};
    ex_file.init();
    defer ex_file.tags.deinit();
    defer ex_file.things.deinit();

    try ex_file.tags.append(.{ .id = 2, .status = dt.Status.ongoing, .name = "newtest" });
    try ex_file.tags.append(.{ .id = 1, .status = dt.Status.closed, .name = "testtag" });
    try dfw.writeFullData(ex_file, it_helper.integration_test_file_path);

    // create the base for the actual file and perform command on it
    var base_file: dt.FullData = .{};
    base_file.init();
    defer base_file.tags.deinit();
    defer base_file.things.deinit();

    try base_file.tags.append(.{ .id = 1, .status = dt.Status.closed, .name = "testtag" });
    try dfw.writeFullData(base_file, globals.data_file_path);

    var args: ArgumentParser = .{ .payload = "newtest" };
    try cmd(&args);

    // check the files match properly
    try it_helper.compareFiles(ex_file);
}
