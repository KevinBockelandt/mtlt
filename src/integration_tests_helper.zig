const data_file_printer = @import("data_file_printer.zig");
const dt = @import("data_types.zig");
const ft = @import("function_types.zig");
const dfw = @import("data_file_writer.zig");
const globals = @import("globals.zig");
const std = @import("std");
const dfp = @import("data_file_printer.zig");
const th = @import("time_helper.zig");
const ArgumentParser = @import("argument_parser.zig").ArgumentParser;

pub const integration_test_file_path = "test/integration_test_data_file.mtlt";

/// Potential types of errors during testing
pub const IntegrationTestingError = error{
    FilesNotIdentical,
};

fn printFiles(ex_file_data: dt.FullData) !void {
    try data_file_printer.printFileDataHtml(ex_file_data, "test/expected_file.html");
    try data_file_printer.printFileDataHtml(try globals.dfr.getFullData(), "test/actual_file.html");
}

/// Populate a given array with tag ids
fn generateTagIds(id_arr: []u16, min_id: u16, num_potential_ids: u16) void {
    var prng = std.Random.DefaultPrng.init(0);
    const rand = prng.random();

    for (0..id_arr.len) |i| {
        while (true) {
            const tag_id_try = rand.uintAtMost(u16, num_potential_ids) + min_id;
            var is_in_array = false;

            // check the try is not already in the array
            for (id_arr) |t| {
                if (tag_id_try == t) {
                    is_in_array = true;
                }
            }

            // if the try is not already in the array, we can use it
            if (is_in_array == false) {
                id_arr[i] = tag_id_try;
                break;
            }
        }
    }
}

/// Compare the 2 test files and expect them to be identical
pub fn compareFiles(ex_file_data: dt.FullData) !void {
    const ex_f = try std.fs.cwd().openFile(integration_test_file_path, .{ .mode = std.fs.File.OpenMode.read_only });
    const ac_f = globals.data_file;
    try ac_f.seekTo(0);

    var buf_ex_f: [2048]u8 = undefined;
    var buf_ac_f: [2048]u8 = undefined;

    var read_ex_f: usize = 0;
    var read_ac_f: usize = 0;

    while (true) {
        read_ex_f = ex_f.reader().readAll(&buf_ex_f) catch unreachable;
        read_ac_f = ac_f.reader().readAll(&buf_ac_f) catch unreachable;

        if (read_ex_f == 0 and read_ac_f == 0) {
            break;
        } else if (read_ex_f == 0 and read_ac_f != 0) {
            std.debug.print("expected file shorter than actual file\n", .{});
            try printFiles(ex_file_data);
            return IntegrationTestingError.FilesNotIdentical;
        } else if (read_ac_f == 0 and read_ex_f != 0) {
            std.debug.print("actual file shorter than expected file\n", .{});
            try printFiles(ex_file_data);
            return IntegrationTestingError.FilesNotIdentical;
        }

        if (!std.mem.eql(u8, buf_ex_f[0..read_ex_f], buf_ac_f[0..read_ac_f])) {
            std.debug.print("Comparison gives inequal results:\n", .{});

            std.debug.print("\nPRINTING OUT ACTUAL FILE DATA:\n\n", .{});
            try data_file_printer.printFileDataHex(ac_f);

            std.debug.print("\nPRINTING OUT EXPECTED FILE DATA:\n\n", .{});
            try data_file_printer.printFileDataHex(ex_f);
            std.debug.print("Content of files written in HTML files.\n", .{});

            try printFiles(ex_file_data);
            return IntegrationTestingError.FilesNotIdentical;
        }
    }
}

pub fn initTest() !void {
    try globals.printer.init();
    try globals.initDataFileNames();

    // delete the potentially existing test file
    std.fs.cwd().deleteFile(globals.data_file_path) catch |err| {
        if (err == std.posix.UnlinkError.FileNotFound) {} else {
            unreachable;
        }
    };

    try globals.openDataFiles();
}

pub fn getStarterFile() !dt.FullData {
    var to_ret: dt.FullData = .{};
    to_ret.init();
    try to_ret.tags.append(.{ .id = 3, .status = dt.StatusTag.next, .name = "next" });
    try to_ret.tags.append(.{ .id = 2, .status = dt.StatusTag.soon, .name = "soon" });
    try to_ret.tags.append(.{ .id = 1, .status = dt.StatusTag.someday, .name = "someday" });
    return to_ret;
}

pub fn getSmallFile(cur_time: u25) !dt.FullData {
    var to_ret: dt.FullData = .{};
    to_ret.init();

    var tags_thing_3 = try globals.allocator.alloc(u16, 1);
    tags_thing_3[0] = 2;
    try to_ret.things.append(.{
        .id = 3,
        .creation = cur_time - 800,
        .kickoff = 0,
        .estimation = 36,
        .closure = cur_time - 100,
        .status = dt.StatusThing.closed,
        .name = "Name thing 3",
        .tags = tags_thing_3[0..],
        .timers = &[_]dt.Timer{},
    });

    var tags_thing_2 = try globals.allocator.alloc(u16, 1);
    tags_thing_2[0] = 3;
    var timers_thing_2 = try globals.allocator.alloc(dt.Timer, 2);
    timers_thing_2[0] = .{ .id = 1, .duration = try th.getMinutesFromSteps(u12, 20), .start = cur_time - 190 };
    timers_thing_2[1] = .{ .id = 2, .duration = try th.getMinutesFromSteps(u12, 50), .start = cur_time - 60 };
    try to_ret.things.append(.{
        .id = 2,
        .creation = cur_time - 200,
        .kickoff = cur_time + 400,
        .estimation = 6,
        .closure = 0,
        .status = dt.StatusThing.open,
        .name = "Name thing 2",
        .tags = tags_thing_2[0..],
        .timers = timers_thing_2[0..],
    });

    try to_ret.things.append(.{
        .id = 1,
        .creation = cur_time,
        .kickoff = 0,
        .estimation = 0,
        .closure = 0,
        .status = dt.StatusThing.open,
        .name = "Name thing 1",
        .tags = &[_]u16{},
        .timers = &[_]dt.Timer{},
    });

    try to_ret.tags.append(.{ .id = 3, .status = dt.StatusTag.next, .name = "next" });
    try to_ret.tags.append(.{ .id = 2, .status = dt.StatusTag.soon, .name = "soon" });
    try to_ret.tags.append(.{ .id = 1, .status = dt.StatusTag.someday, .name = "someday" });

    to_ret.cur_timer = .{
        .id_thing = 1,
        .id_last_timer = 0,
        .start = 0,
    };
    return to_ret;
}

pub fn getMediumFile(cur_time: u25) !dt.FullData {
    var to_ret: dt.FullData = .{};
    to_ret.init();

    var prng = std.Random.DefaultPrng.init(0);
    const rand = prng.random();

    // Generate things
    var buf_thing_name: [32]u8 = undefined;
    for (0..60) |i| {
        const idx = 60 - i;

        // tags of the thing. The first 3 tags are excluded from the random selection
        const num_tags_for_this_thing = rand.uintAtMost(u8, 6);
        var tags_of_thing = try globals.allocator.alloc(u16, num_tags_for_this_thing);
        generateTagIds(tags_of_thing, 4, 29);

        // timers of the thing
        var timers_thing_0 = try globals.allocator.alloc(dt.Timer, 2);
        timers_thing_0[0] = .{ .id = 1, .duration = 20, .start = cur_time - 190 };
        timers_thing_0[1] = .{ .id = 2, .duration = 50, .start = cur_time - 60 };

        // name of the thing
        const str_thing_name = try std.fmt.bufPrint(&buf_thing_name, "Name thing {d}", .{idx});
        const alloc_thing_name = try globals.allocator.dupe(u8, str_thing_name);

        // fixed part of the thing

        try to_ret.things.append(.{
            .id = @intCast(idx),
            .creation = cur_time - 200,
            .kickoff = cur_time + 400,
            .estimation = 6,
            .closure = 0,
            .status = dt.StatusThing.open,
            .name = alloc_thing_name,
            .tags = tags_of_thing[0..],
            .timers = timers_thing_0[0..],
        });
    }

    // Generate tags
    var buf_tag_name: [8]u8 = undefined;
    for (0..30) |i| {
        const idx = 33 - i;
        const str_tag_name = try std.fmt.bufPrint(&buf_tag_name, "tag_{d}", .{idx});
        const alloc_tag_name = try globals.allocator.dupe(u8, str_tag_name);
        const status_tag = rand.uintAtMost(u2, 3);
        try to_ret.tags.append(.{ .id = @intCast(idx), .status = @enumFromInt(status_tag), .name = alloc_tag_name });
    }
    try to_ret.tags.append(.{ .id = 3, .status = dt.StatusTag.next, .name = "next" });
    try to_ret.tags.append(.{ .id = 2, .status = dt.StatusTag.soon, .name = "soon" });
    try to_ret.tags.append(.{ .id = 1, .status = dt.StatusTag.someday, .name = "someday" });

    to_ret.cur_timer = .{
        .id_thing = 1,
        .id_last_timer = 0,
        .start = 0,
    };

    // Some things will have specific non random data used in tests
    var single_tag = try globals.allocator.alloc(u16, 1);
    single_tag[0] = 3;
    to_ret.things.items[10].tags = single_tag[0..];
    to_ret.things.items[20].tags = single_tag[0..];

    var double_tag = try globals.allocator.alloc(u16, 2);
    double_tag[0] = 3;
    double_tag[1] = 2;
    to_ret.things.items[30].tags = double_tag[0..];
    to_ret.things.items[40].tags = double_tag[0..];

    var triple_tag = try globals.allocator.alloc(u16, 3);
    triple_tag[0] = 3;
    triple_tag[1] = 2;
    triple_tag[2] = 1;
    to_ret.things.items[50].tags = triple_tag[0..];

    return to_ret;
}

pub fn deinitTest() void {
    globals.closeDataFiles();
    globals.deinitDataFileNames();
    globals.printer.deinit();
}

const TestData = struct {
    cmd: *const fn (*ArgumentParser) anyerror!void,
    args: *ArgumentParser,
    ex_stdout: ?[]const u8 = null,
    ex_stderr: ?[]const u8 = null,
    ac_file: dt.FullData,
    ex_file: ?dt.FullData = null,
};

pub fn setupTest(ac_file: dt.FullData) !void {
    try globals.printer.init();
    try globals.initDataFileNames();

    // delete the potentially existing test file
    std.fs.cwd().deleteFile(globals.data_file_path) catch |err| {
        if (err == std.posix.UnlinkError.FileNotFound) {} else {
            unreachable;
        }
    };

    try globals.openDataFiles();
    try dfw.writeFullData(ac_file, globals.data_file_path);
}

pub fn closeTest() !void {
    globals.printer.deinit();
    globals.deinitDataFileNames();
    globals.closeDataFiles();
}

pub fn performTest(td: TestData) !void {
    try globals.printer.init();
    defer globals.printer.deinit();

    try globals.initDataFileNames();
    defer globals.deinitDataFileNames();

    // delete the potentially existing test file
    std.fs.cwd().deleteFile(globals.data_file_path) catch |err| {
        if (err == std.posix.UnlinkError.FileNotFound) {} else {
            unreachable;
        }
    };

    try globals.openDataFiles();
    defer globals.closeDataFiles();

    try dfw.writeFullData(td.ac_file, globals.data_file_path);

    // actually execute the command
    try td.cmd(td.args);

    // if there should be something on the stderr
    if (td.ex_stderr) |ex_stderr| {
        const ac_stderr = globals.printer.err_buff[0..globals.printer.cur_pos_err_buff];
        std.testing.expect(std.mem.eql(u8, ac_stderr, ex_stderr)) catch |err| {
            std.debug.print("ac_stderr:\n{s}\n", .{ac_stderr});
            std.debug.print("ex_stderr:\n{s}\n", .{ex_stderr});
            return err;
        };
    }

    // if there should be something on the stdout
    if (td.ex_stdout) |ex_stdout| {
        const ac_stdout = globals.printer.out_buff[0..globals.printer.cur_pos_out_buff];
        std.testing.expect(std.mem.eql(u8, ac_stdout, ex_stdout)) catch |err| {
            std.debug.print("ac_stdout:\n{s}\n", .{ac_stdout});
            std.debug.print("ex_stdout:\n{s}\n", .{ex_stdout});
            return err;
        };
    }

    // if we should compare the 2 files
    if (td.ex_file) |ex_file| {
        try dfw.writeFullData(ex_file, integration_test_file_path);
        try compareFiles(ex_file);
    }
}
