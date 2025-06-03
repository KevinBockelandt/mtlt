const std = @import("std");

const ansi = @import("ansi_codes.zig");
const dfr = @import("data_file_reader.zig");
const dt = @import("data_types.zig");
const globals = @import("globals.zig");
const id_helper = @import("id_helper.zig");
const sh = @import("string_helper.zig");
const table_printer = @import("table_printer.zig");
const th = @import("time_helper.zig");

const CellAlignment = @import("table_printer.zig").CellAlignment;
const ArgumentParser = @import("argument_parser.zig").ArgumentParser;

const little_end = std.builtin.Endian.little;

// Complete list of tags in the data file
var tags: std.ArrayList(dt.Tag) = undefined;

/// Compare 2 things_to_sort in order to sort them
fn compareThings(_: void, a: dt.ThingToSort, b: dt.ThingToSort) bool {
    const a_kick = if (a.thing.kickoff != 0) a.thing.kickoff else std.math.maxInt(u25);
    const b_kick = if (b.thing.kickoff != 0) b.thing.kickoff else std.math.maxInt(u25);

    const cur_time: i64 = @intCast(th.curTimestamp());

    const a_kick_offset: i64 = try th.getStepsFromMinutes(i64, @as(i64, @intCast(a_kick)) - cur_time);
    const b_kick_offset: i64 = try th.getStepsFromMinutes(i64, @as(i64, @intCast(b_kick)) - cur_time);

    // if the kickoff time is already passed or below 200
    if (a_kick_offset <= 200 or b_kick_offset <= 200) {
        return a_kick_offset < b_kick_offset;
    }

    // if one of the 2 things has a "now" priority and not the other one
    if (a.highest_prio == 3 and b.highest_prio < 3) {
        return true;
    } else if (b.highest_prio == 3 and a.highest_prio < 3) {
        return false;
    }

    // if the kickoff time is below 600
    if (a_kick_offset <= 600 or b_kick_offset <= 600) {
        return a_kick_offset < b_kick_offset;
    }

    // at this point, it's just a matter of priority
    return a.highest_prio > b.highest_prio;
}

fn addThingToSortToList(thing: dt.Thing, arr: *std.ArrayList(dt.ThingToSort)) void {
    if (thing.status != dt.StatusThing.open) {
        return;
    }

    const highest_prio = try getHighestPriorityOfThing(thing);
    if (highest_prio > 2) {
        return;
    }

    const dup_thing = thing.dupe();

    arr.*.append(.{ .thing = dup_thing, .coef = 0, .highest_prio = 0 }) catch |err| {
        std.debug.print("ERROR: while trying to add a thing to next report during parsing: {}\n", .{err});
    };
}

fn getHighestPriorityOfThing(thing: dt.Thing) !u2 {
    var highest_prio: u2 = 0;
    for (thing.tags) |t_id| {
        // TODO could sorting stuff improve performance here
        for (tags.items) |tag| {
            if (t_id == tag.id) {
                const prio = @intFromEnum(tag.status);
                if (prio > highest_prio) {
                    highest_prio = prio;
                }
                break;
            }
        }
    }

    return highest_prio;
}

fn addTagToStr(buf: []u8, cur_pos: usize, tag_name: []const u8) !usize {
    var slice: []const u8 = undefined;

    if (cur_pos == 0) {
        slice = try std.fmt.bufPrint(buf, "{s}{s}{s}", .{ ansi.colid, tag_name, ansi.colres });
    } else {
        slice = try std.fmt.bufPrint(buf, ", {s}{s}{s}", .{ ansi.colid, tag_name, ansi.colres });
    }

    return slice.len;
}

fn displayTagsPerPriority() !void {
    var num_tags_prio_max: usize = 0;
    var num_tags_prio_mid: usize = 0;
    var num_tags_prio_min: usize = 0;

    const max_lgt_str: usize = 1024;
    const max_lgt_tag: usize = 64;

    var buf_str_max: [max_lgt_str]u8 = undefined;
    var lgt_str_max: usize = 0;
    var buf_str_mid: [max_lgt_str]u8 = undefined;
    var lgt_str_mid: usize = 0;
    var buf_str_min: [max_lgt_str]u8 = undefined;
    var lgt_str_min: usize = 0;

    for (tags.items) |tag| {
        switch (tag.status) {
            dt.StatusTag.now => {
                num_tags_prio_max += 1;
                if (lgt_str_max < max_lgt_str - max_lgt_tag - 3) {
                    lgt_str_max += try addTagToStr(buf_str_max[lgt_str_max..], lgt_str_max, tag.name);
                } else {
                    const slice = try std.fmt.bufPrint(buf_str_max[lgt_str_max..], ", {s}", .{"…"});
                    lgt_str_max += slice.len;
                }
            },
            dt.StatusTag.soon => {
                num_tags_prio_mid += 1;
                if (lgt_str_mid < max_lgt_str - max_lgt_tag - 3) {
                    lgt_str_mid += try addTagToStr(buf_str_mid[lgt_str_mid..], lgt_str_mid, tag.name);
                } else {
                    const slice = try std.fmt.bufPrint(buf_str_mid[lgt_str_mid..], ", {s}", .{"…"});
                    lgt_str_mid += slice.len;
                }
            },
            dt.StatusTag.someday => {
                num_tags_prio_min += 1;
                if (lgt_str_min < max_lgt_str - max_lgt_tag - 3) {
                    lgt_str_min += try addTagToStr(buf_str_min[lgt_str_min..], lgt_str_min, tag.name);
                } else {
                    const slice = try std.fmt.bufPrint(buf_str_min[lgt_str_min..], ", {s}", .{"…"});
                    lgt_str_min += slice.len;
                }
            },
            else => continue,
        }
    }

    const w = std.io.getStdOut().writer();
    try w.print("Tags     {s}now{s} ({d}): {s}\n", .{ ansi.colemp, ansi.colres, num_tags_prio_max, buf_str_max[0..lgt_str_max] });
    try w.print("Tags    {s}soon{s} ({d}): {s}\n", .{ ansi.colemp, ansi.colres, num_tags_prio_mid, buf_str_mid[0..lgt_str_mid] });
    try w.print("Tags {s}someday{s} ({d}): {s}\n\n", .{ ansi.colemp, ansi.colres, num_tags_prio_min, buf_str_min[0..lgt_str_min] });
}

fn displayAlreadyPlanned() !void {
    var buf_str: [128]u8 = undefined;

    // the array of data we want to display as a table
    var to_display = try globals.allocator.alloc([]table_printer.Cell, 2);
    defer globals.allocator.free(to_display);

    to_display[0] = try globals.allocator.alloc(table_printer.Cell, 6);
    defer globals.allocator.free(to_display[0]);
    to_display[1] = try globals.allocator.alloc(table_printer.Cell, 6);
    defer globals.allocator.free(to_display[1]);

    to_display[0][0] = .{ .content = "For the next", .alignment = .right, .front_col = .emphasis, .back_col = null };
    to_display[1][0] = .{ .content = "Already planned", .alignment = .right, .front_col = .emphasis, .back_col = null };

    const time_planned: [5]usize = .{ 111, 222, 333, 444, 555 };

    for (1..6) |i| {
        const str_for_next = try std.fmt.bufPrint(&buf_str, "{d}", .{i * 200});
        to_display[0][i] = .{
            .content = try globals.allocator.dupe(u8, str_for_next),
            .alignment = .right,
            .front_col = null,
            .back_col = null,
        };

        const str_planned = try std.fmt.bufPrint(&buf_str, "{d}", .{time_planned[i - 1]});
        to_display[1][i] = .{
            .content = try globals.allocator.dupe(u8, str_planned),
            .alignment = .right,
            .front_col = null,
            .back_col = null,
        };
    }

    try table_printer.printTable(to_display);

    // Free memory for all that we allocated
    for (1..6) |i| {
        globals.allocator.free(to_display[0][i].content);
        globals.allocator.free(to_display[1][i].content);
    }

    _ = try std.io.getStdOut().write("\n");
}

/// Display a report of the things to do by order of priority
pub fn planReport(args: *ArgumentParser) !void {
    _ = args;

    // get the complete list of tags in the data file
    tags = std.ArrayList(dt.Tag).init(globals.allocator);
    defer {
        for (tags.items) |tag| {
            tag.deinit();
        }
        tags.deinit();
    }
    try globals.dfr.getAllTags(&tags);

    // display the section of the report dedicated to tags
    try displayTagsPerPriority();

    // Array list of things included in the report
    var things_to_sort = std.ArrayList(dt.ThingToSort).init(globals.allocator);
    defer things_to_sort.deinit();

    try globals.dfr.parseThings(.{ .AddThingToSortToArrayList = .{
        .func = addThingToSortToList,
        .thing_array = &things_to_sort,
    } });

    if (things_to_sort.items.len < 1) {
        try globals.printer.planReportEmpty();
        return;
    }

    const things_to_sort_slice = try things_to_sort.toOwnedSlice();
    defer globals.allocator.free(things_to_sort_slice);
    std.mem.sort(dt.ThingToSort, things_to_sort_slice, {}, compareThings);

    // display the section of the report dedicated to time already planned
    try displayAlreadyPlanned();

    // var limit = if (args.*.limit != null) args.*.limit.? else 10;
    // limit = if (limit > things_to_sort_slice.len) @intCast(things_to_sort_slice.len) else limit;
    const limit = things_to_sort_slice.len;

    try displayTableReport(things_to_sort_slice[0..limit]);

    // free memory
    for (things_to_sort_slice) |thing_to_sort| {
        thing_to_sort.deinit();
    }
}

/// Setup the table printer to display the data to the user
fn displayTableReport(things: []dt.ThingToSort) !void {
    const num_cols: u8 = 5;

    // string for the thing IDs
    var buf_str: [4096]u8 = undefined;

    // the array of data we want to display as a table
    var to_display = try globals.allocator.alloc([]table_printer.Cell, things.len + 1);
    defer globals.allocator.free(to_display);

    // setup the header of the table
    to_display[0] = try globals.allocator.alloc(table_printer.Cell, num_cols);
    defer globals.allocator.free(to_display[0]);
    to_display[0][0] = .{ .content = "ID", .alignment = .left, .front_col = .title, .back_col = .gray };
    to_display[0][1] = .{ .content = "Name", .alignment = .left, .front_col = .title, .back_col = .gray };
    to_display[0][2] = .{ .content = "Priority", .alignment = .left, .front_col = .title, .back_col = .gray };
    to_display[0][3] = .{ .content = "Kickoff", .alignment = .left, .front_col = .title, .back_col = .gray };
    to_display[0][4] = .{ .content = "Tags", .alignment = .left, .front_col = .title, .back_col = .gray };

    // setup the data of the table based on the list of tags we want to display
    for (things, 1..things.len + 1) |thing_to_sort, i| {
        const thing = thing_to_sort.thing;
        to_display[i] = try globals.allocator.alloc(table_printer.Cell, num_cols);
        const line_back_col: ?table_printer.CellBackCol = if (i % 2 != 0) null else .gray;

        // ID COLUMN
        const str_id = id_helper.b10ToB62(buf_str[0..4], thing.id);
        to_display[i][0] = .{
            .content = try globals.allocator.dupe(u8, str_id),
            .alignment = .left,
            .front_col = .id,
            .back_col = line_back_col,
        };

        // NAME COLUMN
        to_display[i][1] = .{
            .content = try globals.allocator.dupe(u8, thing.name),
            .alignment = .left,
            .front_col = null,
            .back_col = line_back_col,
        };

        // PRIORITY COLUMN
        to_display[i][2] = .{
            .content = switch (thing_to_sort.highest_prio) {
                0 => try globals.allocator.dupe(u8, "-"),
                1 => try globals.allocator.dupe(u8, "-"),
                2 => try globals.allocator.dupe(u8, "soon"),
                3 => try globals.allocator.dupe(u8, "now"),
            },
            .alignment = .left,
            .front_col = null,
            .back_col = line_back_col,
        };

        // KICKOFF COLUMN
        if (thing.kickoff > 0) {
            const kickoff_offset_min: i64 = @as(i64, @intCast(thing.kickoff)) - @as(i64, @intCast(th.curTimestamp()));
            const kickoff_offset: i64 = try th.getStepsFromMinutes(i64, kickoff_offset_min);

            if (kickoff_offset >= 0) {
                const kickoff_offset_str = try std.fmt.bufPrint(&buf_str, "{s}in {d}{s}", .{ ansi.colposdur, kickoff_offset, ansi.colres });
                to_display[i][3] = .{
                    .content = try globals.allocator.dupe(u8, kickoff_offset_str),
                    .alignment = .left,
                    .front_col = null,
                    .back_col = line_back_col,
                };
            } else {
                const kickoff_offset_str = try std.fmt.bufPrint(&buf_str, "{s}{d} ago{s}", .{ ansi.colnegdur, kickoff_offset, ansi.colres });
                to_display[i][3] = .{
                    .content = try globals.allocator.dupe(u8, kickoff_offset_str),
                    .alignment = .left,
                    .front_col = null,
                    .back_col = line_back_col,
                };
            }
        } else {
            to_display[i][3] = .{
                .content = try globals.allocator.dupe(u8, "-"),
                .alignment = .left,
                .front_col = null,
                .back_col = line_back_col,
            };
        }

        // TAGS column
        to_display[i][4] = .{
            .content = try globals.allocator.dupe(u8, try sh.getTagNamesFromIds(&buf_str, thing.tags)),
            .alignment = .left,
            .front_col = null,
            .back_col = line_back_col,
        };
    }

    try table_printer.printTable(to_display);

    // Free memory for all that we allocated
    for (1..things.len + 1) |i| {
        globals.allocator.free(to_display[i][0].content);
        globals.allocator.free(to_display[i][1].content);
        globals.allocator.free(to_display[i][2].content);
        globals.allocator.free(to_display[i][3].content);
        globals.allocator.free(to_display[i][4].content);
        globals.allocator.free(to_display[i]);
    }
}

/// Print out help for the next command
pub fn help() !void {
    try std.io.getStdOut().writer().print(
        \\Usage: {s}mtlt next [OPTIONS]{s}
        \\
        \\Display the list of open things by order of priority.
        \\
        \\By default only the first 10 things are displayed. You can remove or
        \\change this limit with the limit option.
        \\
        \\Options:
        \\  {s}-l{s}, {s}--limit{s}       How many things to display at most
        \\                    (0 means no limit)
        \\
        \\Examples:
        \\  {s}mtlt next{s}
        \\      Display the next 10 most urgent things to do.
        \\
        \\  {s}mtlt next -l 0{s}
        \\      Display all the open things sorted by priority.
        \\
    , .{
        ansi.colemp, ansi.colres,
        ansi.colid,  ansi.colres,
        ansi.colid,  ansi.colres,
        ansi.colemp, ansi.colres,
        ansi.colemp, ansi.colres,
    });
}
