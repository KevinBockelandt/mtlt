const std = @import("std");
const dt = @import("data_types.zig");
const globals = @import("globals.zig");
const commands = @import("commands.zig");
const time_helper = @import("time_helper.zig");

const little_end = std.builtin.Endian.little;

pub const integration_test_file_path = "test/integration_test_data_file.mtlt";

/// Potential types of errors during testing
pub const IntegrationTestingError = error{
    FilesNotIdentical,
};

/// Create a test file that can be used later to compare it's content
fn createTestFile(tags: []dt.Tag, things: []dt.Thing, cur_timer: dt.CurrentTimer) !void {
    const f = try std.fs.cwd().createFile(integration_test_file_path, .{});
    defer f.close();
    const w = f.writer();

    // momentarily write 0 for the length of the tag section. Will be updated later
    var lgt_tag_section: usize = 0;
    try w.writeInt(u64, lgt_tag_section, little_end);
    try w.writeInt(u16, @intCast(tags.len), little_end);
    lgt_tag_section += 10;

    // add all the tags
    for (tags) |tag| {
        try w.writeInt(u24, dt.getIntFromTagFixedPart(.{
            .lgt_name = @intCast(tag.name.len),
            .status = @intFromEnum(tag.status),
            .id = tag.id,
        }), little_end);
        _ = try w.write(tag.name);
        lgt_tag_section += dt.lgt_fixed_tag + tag.name.len;
    }

    // rewrite the correct length for the tag section
    try f.seekTo(0);
    try w.writeInt(u64, lgt_tag_section, little_end);
    try f.seekTo(lgt_tag_section);

    // add all the things
    try w.writeInt(u24, @intCast(things.len), little_end);

    for (things) |thing| {
        try w.writeInt(u136, dt.getIntFromThingFixedPart(.{
            .lgt_name = @intCast(thing.name.len),
            .id = thing.id,
            .num_timers = @intCast(thing.timers.len),
            .num_tags = @intCast(thing.tags.len),
            .status = @intFromEnum(thing.status),
            .target = thing.target,
            .estimation = thing.estimation,
            .closure = thing.closure,
            .closure_direction = thing.closure_direction,
        }), little_end);
        _ = try w.write(thing.name);

        // write the associated tags
        for (thing.tags) |tag| {
            try w.writeInt(u16, tag, little_end);
        }

        // write the associated timers
        for (thing.timers) |timer| {
            try w.writeInt(u48, dt.getIntFromTimer(.{
                .id = timer.id,
                .duration = timer.duration,
                .start = timer.start,
            }), little_end);
        }
    }

    // add the current timer
    var int_cur_timer: u48 = cur_timer.id;
    int_cur_timer = int_cur_timer << 25 | cur_timer.start;
    int_cur_timer = int_cur_timer << 4;

    try w.writeInt(u48, int_cur_timer, little_end);
}

/// Compare the 2 test files and expect them to be identical
fn compareFiles() !void {
    const f1 = try std.fs.cwd().openFile(integration_test_file_path, .{ .mode = std.fs.File.OpenMode.read_only });
    const f2 = globals.data_file;
    try f2.seekTo(0);

    var buf_f1: [2048]u8 = undefined;
    var buf_f2: [2048]u8 = undefined;

    var read_f1: usize = 0;
    var read_f2: usize = 0;

    while (true) {
        read_f1 = f1.reader().readAll(&buf_f1) catch unreachable;
        read_f2 = f2.reader().readAll(&buf_f2) catch unreachable;

        if (read_f1 == 0 and read_f2 == 0) {
            break;
        } else if (read_f1 == 0 and read_f2 != 0) {
            std.debug.print("F1 shorter than F2\n", .{});
            return IntegrationTestingError.FilesNotIdentical;
        } else if (read_f2 == 0 and read_f1 != 0) {
            std.debug.print("F2 shorter than F1\n", .{});
            return IntegrationTestingError.FilesNotIdentical;
        }

        if (!std.mem.eql(u8, buf_f1[0..read_f1], buf_f2[0..read_f2])) {
            std.debug.print("Comparison gives inequal results\n", .{});
            return IntegrationTestingError.FilesNotIdentical;
        }
    }
}

/// Test the "add" command
fn testCommandAdd() !void {
    // create the reference test file
    var tags = [1]dt.Tag{.{
        .id = 1,
        .status = dt.Status.ongoing,
        .name = "testtag",
    }};

    var thing_1_tags = [_]u16{1};
    var thing_1_timers = [0]dt.Timer{};

    var things = [1]dt.Thing{.{
        .id = 1,
        .target = time_helper.curTimestamp() + 400,
        .estimation = 120,
        .closure = 0,
        .closure_direction = @intFromEnum(dt.ClosureDirection.before_target),
        .status = dt.Status.ongoing,
        .name = "This is a thing",
        .tags = &thing_1_tags,
        .timers = &thing_1_timers,
    }};

    const cur_timer = dt.CurrentTimer{
        .id = 0,
        .start = 0,
    };

    try createTestFile(&tags, &things, cur_timer);

    // Perform the actual command
    const args = try globals.allocator.alloc([:0]u8, 7);
    args[0] = try globals.allocator.dupeZ(u8, "This is a thing");
    args[1] = try globals.allocator.dupeZ(u8, "-a");
    args[2] = try globals.allocator.dupeZ(u8, "testtag");
    args[3] = try globals.allocator.dupeZ(u8, "-t");
    args[4] = try globals.allocator.dupeZ(u8, "6:40");
    args[5] = try globals.allocator.dupeZ(u8, "-e");
    args[6] = try globals.allocator.dupeZ(u8, "2:");

    defer {
        for (args) |arg| {
            globals.allocator.free(arg);
        }
        globals.allocator.free(args);
    }

    try commands.addThing(args);

    try compareFiles();
}

pub fn main() !void {
    std.fs.cwd().deleteFile(globals.default_data_file_path) catch |err| {
        if (err == std.posix.UnlinkError.FileNotFound) {} else {
            unreachable;
        }
    };

    try globals.openDataFiles(globals.default_data_file_path, globals.default_back_data_file_path);
    defer globals.closeDataFiles();
    defer globals.deinitMemAllocator();

    // TEST go here
    try testCommandAdd();
}
