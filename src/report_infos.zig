const std = @import("std");

const ansi = @import("ansi_codes.zig");
const base62_helper = @import("base62_helper.zig");
const dfr = @import("data_file_reader.zig");
const dt = @import("data_types.zig");
const globals = @import("globals.zig");
const table_printer = @import("table_printer.zig");
const th = @import("time_helper.zig");

const CellAlignment = @import("table_printer.zig").CellAlignment;
const ArgumentParser = @import("argument_parser.zig").ArgumentParser;

const little_end = std.builtin.Endian.little;

/// Display informations on the specified thing
pub fn infosReport(args: *ArgumentParser) !void {
    // get the current timer contained in the data file
    const cur_timer = try globals.dfr.getCurrentTimer();

    // ID of the thing to display infos about
    var id_thing: u19 = undefined;

    if (args.*.payload == null) {
        // and no previous current timer
        if (cur_timer.id_thing == 0) {
            _ = try std.io.getStdOut().write("Need to specify the id of the thing to get infos about\n");
            return;
        } else {
            id_thing = cur_timer.id_thing;
        }
    } else {
        id_thing = try base62_helper.b62ToB10(args.*.payload.?);
    }

    const thing_to_display = try globals.dfr.getThing(id_thing);
    defer {
        globals.allocator.free(thing_to_display.name);
        globals.allocator.free(thing_to_display.tags);
        globals.allocator.free(thing_to_display.timers);
    }

    try displayTableReport(thing_to_display);
}

/// Setup the table printer to display the data of the thing
fn displayTableReport(thing: dt.Thing) !void {
    const w = std.io.getStdOut().writer();
    const cur_time = th.curTimestamp();

    // string for the thing ID
    var buf_id_thing: [4]u8 = undefined;
    const str_id_thing = base62_helper.b10ToB62(&buf_id_thing, thing.id);

    // target
    var str_target: []const u8 = undefined;
    const offset_target: i64 = @as(i64, @intCast(thing.target)) - @as(i64, @intCast(cur_time));
    var buf_target: [100]u8 = undefined;
    str_target = try th.formatDurationNoSign(&buf_target, @abs(offset_target));

    // creation time
    var buf_creation: [100]u8 = undefined;
    const offset_creation: i64 = @as(i64, @intCast(thing.creation)) - @as(i64, @intCast(cur_time));
    const str_creation = try th.formatDurationNoSign(&buf_creation, @abs(offset_creation));

    // initial estimation
    var buf_estimation: [100]u8 = undefined;
    const str_estimation = if (thing.estimation > 0)
        try th.formatDurationNoSign(&buf_estimation, thing.estimation)
    else
        "-";

    // closure time
    var buf_closure: [100]u8 = undefined;
    const offset_closure: i64 = @as(i64, @intCast(thing.closure)) - @as(i64, @intCast(cur_time));
    const str_closure = if (thing.closure > 0)
        try th.formatDurationNoSign(&buf_closure, @abs(offset_closure))
    else
        "-";

    // offset closure time / target
    var buf_off_closure: [100]u8 = undefined;
    const offset_off_closure: i64 = offset_closure - offset_target;
    const str_off_closure = try th.formatDurationNoSign(&buf_off_closure, @abs(offset_off_closure));

    // will contain the string for all the associated tags
    var buf_tags: [20000]u8 = undefined;
    var idx_buf_tags: usize = 0;
    // used to manipulate the tag names
    var buf_str_tag_name: [128]u8 = undefined;

    // create string for the tags
    // TODO should factorize this code
    if (thing.tags.len > 0) {
        for (thing.tags, 0..thing.tags.len) |tag_id, j| {
            if (globals.dfr.getTagNameFromId(&buf_str_tag_name, tag_id)) |name_to_add| {
                const e_idx_name = idx_buf_tags + name_to_add.len;
                std.mem.copyForwards(u8, buf_tags[idx_buf_tags..e_idx_name], name_to_add);

                // add a , between tag names. Except for the last one
                if (j != thing.tags.len - 1) {
                    std.mem.copyForwards(u8, buf_tags[e_idx_name..][0..2], ", ");
                    idx_buf_tags = e_idx_name + 2;
                } else {
                    idx_buf_tags = e_idx_name;
                }
            } else |err| {
                if (err == dfr.DataParsingError.TagNotFound) {
                    std.debug.print("Error: the tag with ID: {d} was not found\n", .{tag_id});
                } else {
                    std.debug.print("Error: while getting name for tag {d} - {}\n", .{ tag_id, err });
                }
            }
        }
    } else {
        buf_tags[0] = '-';
        idx_buf_tags = 1;
    }

    // create a table with all the timers
    var timers_table = try globals.allocator.alloc([]table_printer.Cell, thing.timers.len + 1);
    defer globals.allocator.free(timers_table);
    var total_spent_time: u64 = 0;

    const num_cols = 3;

    // setup the header of the table
    timers_table[0] = try globals.allocator.alloc(table_printer.Cell, num_cols);
    defer globals.allocator.free(timers_table[0]);
    timers_table[0][0] = .{ .content = "ID", .alignment = .left, .front_col = .title, .back_col = .gray };
    timers_table[0][1] = .{ .content = "Start", .alignment = .left, .front_col = .title, .back_col = .gray };
    timers_table[0][2] = .{ .content = "Duration", .alignment = .left, .front_col = .title, .back_col = .gray };

    // go through all timers to create the table to display
    for (thing.timers, 1..thing.timers.len + 1) |timer, i| {
        total_spent_time += timer.duration;
        const line_back_col: ?table_printer.CellBackCol = if (i % 2 != 0) null else .gray;

        timers_table[i] = try globals.allocator.alloc(table_printer.Cell, num_cols);

        // ID column
        var buf_id: [128]u8 = undefined;
        const str_id: []u8 = try std.fmt.bufPrint(&buf_id, "{s}-{d}", .{ str_id_thing, timer.id });
        timers_table[i][0] = .{
            .content = try globals.allocator.dupe(u8, str_id),
            .alignment = .right,
            .front_col = .id,
            .back_col = line_back_col,
        };

        // START column
        var buf_start_num: [128]u8 = undefined;
        var buf_start_str: [128]u8 = undefined;
        const offset_start: i64 = @as(i64, @intCast(timer.start)) - @as(i64, @intCast(cur_time));
        const str_start_num = try th.formatDurationNoSign(&buf_start_num, @abs(offset_start));

        var str_start_str: []u8 = undefined;
        if (offset_start < 0) {
            str_start_str = try std.fmt.bufPrint(&buf_start_str, "{s}{s}{s} ago", .{ ansi.coldurntr, str_start_num, ansi.colres });
        } else {
            str_start_str = try std.fmt.bufPrint(&buf_start_str, "{s}{s}{s} hence", .{ ansi.coldurntr, str_start_num, ansi.colres });
        }

        timers_table[i][1] = .{
            .content = try globals.allocator.dupe(u8, str_start_str),
            .alignment = .left,
            .front_col = null,
            .back_col = line_back_col,
        };

        // DURATION column
        var buf_duration: [128]u8 = undefined;
        const str_duration = try th.formatDurationNoSign(&buf_duration, timer.duration);
        timers_table[i][2] = .{
            .content = try globals.allocator.dupe(u8, str_duration),
            .alignment = .right,
            .front_col = .duration,
            .back_col = line_back_col,
        };
    }

    // total time spent
    var buf_time_spent: [100]u8 = undefined;
    const str_time_spent = try th.formatDurationNoSign(&buf_time_spent, total_spent_time);

    // time offset
    const time_offset: i64 = @as(i64, @intCast(total_spent_time)) - @as(i64, @intCast(thing.estimation));
    var buf_time_offset: [100]u8 = undefined;
    const str_time_offset = try th.formatDurationNoSign(&buf_time_offset, @abs(time_offset));

    try w.print("{s}                ID{s} : {s}{s}{s}\n", .{ ansi.colemp, ansi.colres, ansi.colid, str_id_thing, ansi.colres });
    try w.print("{s}              Name{s} : {s}\n", .{ ansi.colemp, ansi.colres, thing.name });
    try w.print("{s}            Status{s} : {s}\n", .{ ansi.colemp, ansi.colres, @tagName(thing.status) });
    try w.print("{s}   Associated tags{s} : {s}\n", .{ ansi.colemp, ansi.colres, buf_tags[0..idx_buf_tags] });
    try w.print("\n", .{});
    try w.print("{s}     Creation time{s} : {s} ago\n", .{ ansi.colemp, ansi.colres, str_creation });
    if (thing.target > 0) {
        if (offset_target > 0) {
            try w.print("{s}            Target{s} : in {s}\n", .{ ansi.colemp, ansi.colres, str_target });
        } else {
            try w.print("{s}            Target{s} : {s} ago\n", .{ ansi.colemp, ansi.colres, str_target });
        }
    } else {
        try w.print("{s}            Target{s} : -\n", .{ ansi.colemp, ansi.colres });
    }
    if (thing.closure > 0) {
        if (thing.target > 0) {
            if (offset_off_closure > 0) {
                try w.print("{s}      Closure time{s} : {s} ago ({s}{s} over{s} target)\n", .{ ansi.colemp, ansi.colres, str_closure, ansi.colnegdur, str_off_closure, ansi.colres });
            } else {
                try w.print("{s}      Closure time{s} : {s} ago ({s}{s} under{s} target)\n", .{ ansi.colemp, ansi.colres, str_closure, ansi.colposdur, str_off_closure, ansi.colres });
            }
        } else {
            try w.print("{s}      Closure time{s} : {s} ago\n", .{ ansi.colemp, ansi.colres, str_closure });
        }
    } else {
        try w.print("{s}      Closure time{s} : -\n", .{ ansi.colemp, ansi.colres });
    }
    try w.print("\n", .{});
    try w.print("{s}Initial estimation{s} : {s}\n", .{ ansi.colemp, ansi.colres, str_estimation });
    if (thing.estimation > 0) {
        if (time_offset > 0) {
            try w.print("{s}  Total time spent{s} : {s} ({s}{s} over{s} estimation)\n", .{ ansi.colemp, ansi.colres, str_time_spent, ansi.colnegdur, str_time_offset, ansi.colres });
        } else {
            try w.print("{s}  Total time spent{s} : {s} ({s}{s} under{s} estimation)\n", .{ ansi.colemp, ansi.colres, str_time_spent, ansi.colposdur, str_time_offset, ansi.colres });
        }
    } else {
        try w.print("{s}  Total time spent{s} : {s}\n", .{ ansi.colemp, ansi.colres, str_time_spent });
    }

    if (thing.timers.len > 0) {
        try w.print("{s}    List of timers{s} :\n\n", .{ ansi.colemp, ansi.colres });
        try table_printer.printTable(timers_table);
    } else {
        try w.print("{s}    List of timers{s} : -\n", .{ ansi.colemp, ansi.colres });
    }

    // Free memory for all that we allocated
    for (1..thing.timers.len + 1) |i| {
        globals.allocator.free(timers_table[i][0].content);
        globals.allocator.free(timers_table[i][1].content);
        globals.allocator.free(timers_table[i][2].content);
        globals.allocator.free(timers_table[i]);
    }
}

/// Print out help for the infos command
pub fn help() !void {
    try std.io.getStdOut().writer().print(
        \\Usage: {s}mtlt infos [thing_id]{s}
        \\
        \\Displays all informations related to the specified thing.
        \\
        \\If no ID is provided, this command will act on the current thing.
        \\
        \\Examples:
        \\  {s}mtlt infos{s}
        \\  {s}mtlt infos b5{s}
        \\
    , .{
        ansi.colemp, ansi.colres,
        ansi.colemp, ansi.colres,
        ansi.colemp, ansi.colres,
    });
}
