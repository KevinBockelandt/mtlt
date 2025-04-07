const std = @import("std");

const ansi = @import("ansi_codes.zig");
const data_file_printer = @import("data_file_printer.zig");
const dfr = @import("data_file_reader.zig");
const dfw = @import("data_file_writer.zig");
const dt = @import("data_types.zig");
const globals = @import("globals.zig");
const it_helper = @import("integration_tests_helper.zig");
const string_helper = @import("string_helper.zig");

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
        try globals.printer.errMissingTagNameToAdd();
        return;
    }

    const priority = if (args.*.priority) |p| p else dt.StatusTag.someday;

    if (globals.dfw.addTagToFile(args.*.payload.?, priority)) |new_tag_id| {
        _ = new_tag_id;
        try globals.printer.createdTag(args.*.payload.?);
    } else |err| {
        switch (err) {
            DataOperationError.NameTooLong => try globals.printer.errNameTagTooLong(args.*.payload.?),
            DataOperationError.TooManyTags => try globals.printer.errTooManyTags(),
            DataOperationError.TagWithThisNameAlreadyExisting => try globals.printer.errNameTagAlreadyExisting(args.*.payload.?),
            DataOperationError.NameContainingInvalidCharacters => try globals.printer.errNameTagInvalidChara(),
            else => return err,
        }
    }
}

/// Display help text for this command
pub fn help() !void {
    try std.io.getStdOut().writer().print(
        \\Usage: {s}mtlt add-tag <tag_name> [OPTIONS]{s}
        \\
        \\Creates a new tag.
        \\
        \\The tag name can only contain ASCII letters, numbers and the '_' or '-'
        \\characters. If no priority is specified, 'someday' is used by default.
        \\
        \\Options:
        \\  {s}-p{s}, {s}--priority{s}         Can be 'now', 'soon' or 'someday'
        \\
        \\Examples:
        \\  {s}mtlt add-tag "myCoolTag"{s}
        \\      Create a new tag called 'myCoolTag' with priority 'someday'.
        \\
        \\  {s}mtlt add-tag "1-also-good" -p now{s}
        \\      Create a new tag called '1-also-good' with priority 'now'.
        \\
        \\  {s}mtlt add-tag "_it_works" -p soon{s}
        \\      Create a new tag called '_it_works' with priority 'soon'.
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

test "add tag in starter file without specifying priority" {
    try it_helper.initTest();
    defer it_helper.deinitTest();

    // create the expected file
    var ex_file = try it_helper.getStarterFile();
    defer ex_file.tags.deinit();
    defer ex_file.things.deinit();

    try ex_file.tags.insert(0, .{ .id = 4, .status = dt.StatusTag.someday, .name = "testtag" });
    try dfw.writeFullData(ex_file, it_helper.integration_test_file_path);

    // create the base for the actual file and perform command on it
    const actual_file = try it_helper.getStarterFile();
    try dfw.writeFullData(actual_file, globals.data_file_path);

    var args: ArgumentParser = .{ .payload = "testtag", .priority = null };
    try cmd(&args);

    // check the files match properly
    try it_helper.compareFiles(ex_file);
}

test "add tag in starter file with priority someday" {
    try it_helper.initTest();
    defer it_helper.deinitTest();

    // create the expected file
    var ex_file = try it_helper.getStarterFile();
    defer ex_file.tags.deinit();
    defer ex_file.things.deinit();

    try ex_file.tags.insert(0, .{ .id = 4, .status = dt.StatusTag.someday, .name = "testtag" });
    try dfw.writeFullData(ex_file, it_helper.integration_test_file_path);

    // create the base for the actual file and perform command on it
    const actual_file = try it_helper.getStarterFile();
    try dfw.writeFullData(actual_file, globals.data_file_path);

    var args: ArgumentParser = .{ .payload = "testtag", .priority = dt.StatusTag.someday };
    try cmd(&args);

    // check the files match properly
    try it_helper.compareFiles(ex_file);
}

test "add tag in starter file with priority soon" {
    try it_helper.initTest();
    defer it_helper.deinitTest();

    // create the expected file
    var ex_file = try it_helper.getStarterFile();
    defer ex_file.tags.deinit();
    defer ex_file.things.deinit();

    try ex_file.tags.insert(0, .{ .id = 4, .status = dt.StatusTag.soon, .name = "testsoon" });
    try dfw.writeFullData(ex_file, it_helper.integration_test_file_path);

    // create the base for the actual file and perform command on it
    const actual_file = try it_helper.getStarterFile();
    try dfw.writeFullData(actual_file, globals.data_file_path);

    var args: ArgumentParser = .{ .payload = "testsoon", .priority = dt.StatusTag.soon };
    try cmd(&args);

    // check the files match properly
    try it_helper.compareFiles(ex_file);
}

test "add tag in starter file with priority now" {
    try it_helper.initTest();
    defer it_helper.deinitTest();

    // create the expected file
    var ex_file = try it_helper.getStarterFile();
    defer ex_file.tags.deinit();
    defer ex_file.things.deinit();

    try ex_file.tags.insert(0, .{ .id = 4, .status = dt.StatusTag.now, .name = "testnow" });
    try dfw.writeFullData(ex_file, it_helper.integration_test_file_path);

    // create the base for the actual file and perform command on it
    const actual_file = try it_helper.getStarterFile();
    try dfw.writeFullData(actual_file, globals.data_file_path);

    var args: ArgumentParser = .{ .payload = "testnow", .priority = dt.StatusTag.now };
    try cmd(&args);

    // check the files match properly
    try it_helper.compareFiles(ex_file);
}

test "add tag in a file where the max tag ID is reached" {
    try it_helper.initTest();
    defer it_helper.deinitTest();

    // create the expected file
    var test_file = try it_helper.getStarterFile();
    try test_file.tags.insert(0, .{ .id = 65535, .status = dt.StatusTag.now, .name = "maxIdTag" });
    defer test_file.tags.deinit();
    defer test_file.things.deinit();

    try dfw.writeFullData(test_file, globals.data_file_path);

    var args: ArgumentParser = .{ .payload = "overboardIdTag", .priority = dt.StatusTag.now };
    try cmd(&args);

    const actual = globals.printer.err_buff[0..globals.printer.cur_pos_err_buff];
    const expected = "The maximum number of tags in the data file is reached.\nDeleting existing tags will not help. If you need more tags, you will need to start a new data file.\n";
    try std.testing.expect(std.mem.eql(u8, actual, expected));
}

test "add already existing tag" {
    try it_helper.initTest();
    defer it_helper.deinitTest();

    // create the expected file
    var test_file = try it_helper.getStarterFile();
    defer test_file.tags.deinit();
    defer test_file.things.deinit();

    try dfw.writeFullData(test_file, globals.data_file_path);

    var args: ArgumentParser = .{ .payload = "soon" };
    try cmd(&args);

    const actual = globals.printer.err_buff[0..globals.printer.cur_pos_err_buff];
    var buf_expected: [512]u8 = undefined;
    const expected = try std.fmt.bufPrint(&buf_expected, "A tag with the name {s}{s}{s} already exists\n", .{ ansi.colemp, "soon", ansi.colres });
    try std.testing.expect(std.mem.eql(u8, actual, expected));
}

test "add tag but missing payload" {
    try it_helper.initTest();
    defer it_helper.deinitTest();

    // create the expected file
    var test_file = try it_helper.getStarterFile();
    defer test_file.tags.deinit();
    defer test_file.things.deinit();

    try dfw.writeFullData(test_file, globals.data_file_path);

    var args: ArgumentParser = .{};
    try cmd(&args);

    const actual = globals.printer.err_buff[0..globals.printer.cur_pos_err_buff];
    const expected = "Missing the name of the tag to create\n";
    try std.testing.expect(std.mem.eql(u8, actual, expected));
}
