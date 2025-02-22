const std = @import("std");

const dt = @import("data_types.zig");
const dfr = @import("data_file_reader.zig");
const globals = @import("globals.zig");
const time_helper = @import("time_helper.zig");

const little_end = std.builtin.Endian.little;

/// Print a tag of the data file on the standard output
fn printTagFromStr(data: []const u8) void {
    const int_fpt = std.mem.readInt(u24, data[0..dt.lgt_fixed_tag], little_end);
    const fpt = dt.getTagFixedPartFromInt(int_fpt);

    const s_idx_name = dt.lgt_fixed_tag;
    const e_idx_name = dt.lgt_fixed_tag + fpt.lgt_name;

    printNoFail("{d:_>5} {s:_<8} {s}\n", .{
        fpt.id,
        @tagName(@as(dt.Status, @enumFromInt(fpt.status))),
        data[s_idx_name..e_idx_name],
    });
}

/// Print a thing of the data file on the standard output
fn printThingFromStr(data: []const u8) void {
    const int_fpt = std.mem.readInt(u136, data[0..dt.lgt_fixed_thing], little_end);
    const fpt = dt.getThingFixedPartFromInt(int_fpt);

    const s_idx_name = dt.lgt_fixed_thing;
    const e_idx_name = dt.lgt_fixed_thing + fpt.lgt_name;

    var str_closure: [20]u8 = undefined;

    if (time_helper.formatDuration(&str_closure, fpt.closure)) |slice_str_closure| {
        // print fixed content of thing + name
        printNoFail("{d:_>6} {s} {d:_>6} {d:_>8} {d:_>8} {s:_>7} {d:_>3} {d:_>5} {s}\n", .{
            fpt.id,
            slice_str_closure,
            fpt.creation,
            fpt.target,
            fpt.estimation,
            @tagName(@as(dt.Status, @enumFromInt(fpt.status))),
            fpt.num_tags,
            fpt.num_timers,
            data[s_idx_name..e_idx_name],
        });
    } else |err| {
        std.debug.print("Error when formating duration: {}", .{err});
    }

    // print list of associated tag IDs
    if (fpt.num_tags > 0) {
        var s_idx_tags: usize = e_idx_name;
        printNoFail("  ", .{});

        for (0..fpt.num_tags) |_| {
            printNoFail("{d:_>5} ", .{std.mem.readInt(u16, data[s_idx_tags .. s_idx_tags + 2][0..2], little_end)});
            s_idx_tags += 2;
        }

        printNoFail("\n", .{});
    }

    // print list of associated timers
    var s_idx_timers: usize = e_idx_name + fpt.num_tags * 2;

    if (fpt.num_timers > 0) {
        for (0..fpt.num_timers) |_| {
            const int_data_timer = std.mem.readInt(u48, data[s_idx_timers .. s_idx_timers + 48][0..6], little_end);
            const data_timer = dt.getTimerFromInt(int_data_timer);

            printNoFail("  {d:_>5} {d:_>6} {d:_>8}\n", .{
                data_timer.id,
                data_timer.duration,
                data_timer.start,
            });
            s_idx_timers += 6;
        }
    }

    printNoFail("\n", .{});
}

/// Print the current timer on the standard output
fn printCurrentTimerFromStr(data: []const u8) void {
    const int_fpt = std.mem.readInt(u56, data[0..dt.lgt_fixed_current_timer], little_end);
    const fpt = dt.getCurrentTimerFromInt(int_fpt);

    printNoFail("\nCurrent Timer:\n", .{});
    printNoFail("ID thing: {d} ID timer: {d} Start: {d}\n", .{ fpt.id_thing, fpt.id_last_timer, fpt.start });
}

/// Print the given string into the standard output ignoring potential errors
fn printNoFail(comptime fmt: []const u8, args: anytype) void {
    std.io.getStdOut().writer().print(fmt, args) catch |err| {
        std.debug.print("ERROR while printing on the standard output\n", .{});
        std.debug.print("{}\n", .{err});
    };
}

pub fn main() !void {
    const args = try std.process.argsAlloc(globals.allocator);
    defer std.process.argsFree(globals.allocator, args);

    // you can pass an argument to the command to specify a file to print other than the default one
    if (args.len < 2) {
        try globals.initDataFileNames(null);
    } else {
        try globals.initDataFileNames(args[1]);
    }
    try globals.openDataFiles();
    defer globals.closeDataFiles();
    defer globals.deinitDataFileNames();

    const r = globals.data_file.reader();
    var parser = dfr.DataFileReader{};

    // print length tag section
    const bytes_tag_section = try r.readInt(u64, little_end);
    std.debug.print("Total bytes tag section: {d} - {x}\n", .{ bytes_tag_section, bytes_tag_section });

    // print total number of tags
    const num_tags = try r.readInt(u16, little_end);
    std.debug.print("Num tags in file: {d}\n\n", .{num_tags});

    // print all the tags
    try parser.parseTags(printTagFromStr);
    std.debug.print("\n", .{});

    // print total number of things
    try globals.data_file.seekTo(bytes_tag_section);
    const num_things = try r.readInt(u24, little_end);
    std.debug.print("Num things in file: {d}\n\n", .{num_things});

    // print all the things
    try parser.parseThings(printThingFromStr);

    // print the current timer
    try parser.parseCurrentTimer(printCurrentTimerFromStr);
}
