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

// Amount of time planned for the next 1000 steps
var time_planned: [5]usize = .{ 0, 0, 0, 0, 0 };

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

fn addThingToSortToList(thing: dt.Thing, arr: *std.ArrayList(dt.ThingToSort), included_tag_ids: []u16, excluded_tag_ids: []u16) void {
    if (thing.status != dt.StatusThing.open) {
        return;
    }

    // ignore this thing if it's part of the excluded tags list
    for (excluded_tag_ids) |et| {
        for (thing.tags) |tt| {
            if (tt == et) {
                return;
            }
        }
    }

    // ignore this thing if there is a list of requested tag and it's not part of it
    if (included_tag_ids.len > 0) {
        var is_in_list = false;
        for (included_tag_ids) |it| {
            for (thing.tags) |tt| {
                if (tt == it) {
                    is_in_list = true;
                    break;
                }
            }
        }

        if (is_in_list == false) {
            return;
        }
    }

    const cur_time: i64 = @intCast(th.curTimestamp());
    const kickoff_offset: i64 = try th.getStepsFromMinutes(i64, @as(i64, @intCast(thing.kickoff)) - cur_time);

    switch (kickoff_offset) {
        0...200 => time_planned[0] += thing.estimation,
        201...400 => time_planned[1] += thing.estimation,
        401...600 => time_planned[2] += thing.estimation,
        601...800 => time_planned[3] += thing.estimation,
        801...1000 => time_planned[4] += thing.estimation,
        else => {},
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

    var buf: [128]u8 = undefined;

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

    // the array of data we want to display as a table
    var to_display = try globals.allocator.alloc([]table_printer.Cell, 4);
    defer globals.allocator.free(to_display);

    // setup the header of the table
    to_display[0] = try globals.allocator.alloc(table_printer.Cell, 3);
    defer globals.allocator.free(to_display[0]);
    to_display[0][0] = .{ .content = "Priority", .alignment = .left, .front_col = .title, .back_col = .gray };
    to_display[0][1] = .{ .content = "#", .alignment = .left, .front_col = .title, .back_col = .gray };
    to_display[0][2] = .{ .content = "Tag names", .alignment = .left, .front_col = .title, .back_col = .gray };

    // now line
    to_display[1] = try globals.allocator.alloc(table_printer.Cell, 3);
    to_display[1][0] = .{ .content = "now", .alignment = .right, .front_col = null, .back_col = null };
    const str_num_max = try std.fmt.bufPrint(&buf, "{d}", .{num_tags_prio_max});
    to_display[1][1] = .{ .content = try globals.allocator.dupe(u8, str_num_max), .alignment = .left, .front_col = null, .back_col = null };
    to_display[1][2] = .{ .content = buf_str_max[0..lgt_str_max], .alignment = .left, .front_col = null, .back_col = null };

    // soon line
    to_display[2] = try globals.allocator.alloc(table_printer.Cell, 3);
    to_display[2][0] = .{ .content = "soon", .alignment = .right, .front_col = null, .back_col = .gray };
    const str_num_mid = try std.fmt.bufPrint(&buf, "{d}", .{num_tags_prio_mid});
    to_display[2][1] = .{ .content = try globals.allocator.dupe(u8, str_num_mid), .alignment = .left, .front_col = null, .back_col = .gray };
    to_display[2][2] = .{ .content = buf_str_mid[0..lgt_str_mid], .alignment = .left, .front_col = null, .back_col = .gray };

    // someday line
    to_display[3] = try globals.allocator.alloc(table_printer.Cell, 3);
    to_display[3][0] = .{ .content = "someday", .alignment = .right, .front_col = null, .back_col = null };
    const str_num_min = try std.fmt.bufPrint(&buf, "{d}", .{num_tags_prio_min});
    to_display[3][1] = .{ .content = try globals.allocator.dupe(u8, str_num_min), .alignment = .left, .front_col = null, .back_col = null };
    to_display[3][2] = .{ .content = buf_str_min[0..lgt_str_min], .alignment = .left, .front_col = null, .back_col = null };

    try table_printer.printTable(to_display);

    globals.allocator.free(to_display[1][1].content);
    globals.allocator.free(to_display[2][1].content);
    globals.allocator.free(to_display[3][1].content);
    globals.allocator.free(to_display[1]);
    globals.allocator.free(to_display[2]);
    globals.allocator.free(to_display[3]);
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

    _ = try std.io.getStdOut().write("\n");
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
    time_planned = .{ 0, 0, 0, 0, 0 };

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

    // convert list of tags to include to use u16 instead of names
    var included_tag_ids = std.ArrayList(u16).init(globals.allocator);
    defer included_tag_ids.deinit();
    for (args.*.tags.items) |tag_to_include| {
        for (tags.items) |tag_in_file| {
            if (std.mem.eql(u8, tag_in_file.name, tag_to_include)) {
                try included_tag_ids.append(tag_in_file.id);
                break;
            }
        }
    }

    // convert list of tags to exclude to use u16 instead of names
    var excluded_tag_ids = std.ArrayList(u16).init(globals.allocator);
    defer excluded_tag_ids.deinit();
    for (args.*.excluded_tags.items) |tag_to_exclude| {
        for (tags.items) |tag_in_file| {
            if (std.mem.eql(u8, tag_in_file.name, tag_to_exclude)) {
                try excluded_tag_ids.append(tag_in_file.id);
                break;
            }
        }
    }

    // Array list of things included in the report
    var things_to_sort = std.ArrayList(dt.ThingToSort).init(globals.allocator);
    defer things_to_sort.deinit();

    try globals.dfr.parseThings(.{ .AddThingToSortToArrayListTagFiltered = .{
        .func = addThingToSortToList,
        .thing_array = &things_to_sort,
        .included_tag_ids = included_tag_ids.items,
        .excluded_tag_ids = excluded_tag_ids.items,
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

    var limit = if (args.*.limit != null) args.*.limit.? else 10;
    limit = if (limit > things_to_sort_slice.len) @intCast(things_to_sort_slice.len) else limit;

    try displayTableReport(things_to_sort_slice[0..limit]);

    // free memory
    for (things_to_sort_slice) |thing_to_sort| {
        thing_to_sort.deinit();
    }
}

/// Setup the table printer to display the data to the user
fn displayTableReport(things: []dt.ThingToSort) !void {
    const num_cols: u8 = 6;

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
    to_display[0][4] = .{ .content = "Left", .alignment = .left, .front_col = .title, .back_col = .gray };
    to_display[0][5] = .{ .content = "Tags", .alignment = .left, .front_col = .title, .back_col = .gray };

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

        // LEFT COLUMN
        if (thing.estimation > 0) {
            var time_spent: i64 = 0;
            for (thing.timers) |t| {
                time_spent += t.duration;
            }

            const time_left: i64 = @as(i64, @intCast(thing.estimation)) - try th.getStepsFromMinutes(i64, time_spent);

            if (time_left >= 0) {
                const time_left_str = try std.fmt.bufPrint(&buf_str, "{s}{d}{s}", .{ ansi.colposdur, time_left, ansi.colres });
                to_display[i][4] = .{
                    .content = try globals.allocator.dupe(u8, time_left_str),
                    .alignment = .left,
                    .front_col = null,
                    .back_col = line_back_col,
                };
            } else {
                const time_left_str = try std.fmt.bufPrint(&buf_str, "{s}{d}{s}", .{ ansi.colnegdur, time_left, ansi.colres });
                to_display[i][4] = .{
                    .content = try globals.allocator.dupe(u8, time_left_str),
                    .alignment = .left,
                    .front_col = null,
                    .back_col = line_back_col,
                };
            }
        } else {
            to_display[i][4] = .{
                .content = try globals.allocator.dupe(u8, "-"),
                .alignment = .left,
                .front_col = null,
                .back_col = line_back_col,
            };
        }

        // TAGS column
        to_display[i][5] = .{
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
        globals.allocator.free(to_display[i][5].content);
        globals.allocator.free(to_display[i]);
    }
}

/// Print out help for the next command
pub fn help() !void {
    try std.io.getStdOut().writer().print(
        \\Usage: {s}mtlt plan [OPTIONS]{s}
        \\
        \\Display a list of things that would need planification.
        \\
        \\By default only the first 10 things are displayed. You can remove or
        \\change this limit with the limit option.
        \\
        \\Options:
        \\  {s}-l{s}, {s}--limit{s}          How many things to display at most
        \\                       (0 means no limit)
        \\  {s}-t{s}, {s}--tags{s}           List of tag names to include in the array
        \\                       of displayed things
        \\      {s}--excluded-tags{s}  List of tag names to exclude from  the array
        \\                       of displayed things
        \\
        \\Examples:
        \\  {s}mtlt plan{s}
        \\      Display the 10 things that you would potentially plan to do
        \\      first.
        \\
        \\  {s}mtlt plan -l 0{s}
        \\      Display most things except the most urgent (that will be
        \\      present in the {s}next{s} report). Without a limit on the
        \\      number of things displayed and sorted by priority.
        \\
        \\  {s}mtlt -t cool dev{s}
        \\      Display things having the "cool" and "dev" tags associated that
        \\      you would potentially plan to do first.
        \\
    , .{
        ansi.colemp, ansi.colres,
        ansi.colid,  ansi.colres,
        ansi.colid,  ansi.colres,
        ansi.colid,  ansi.colres,
        ansi.colid,  ansi.colres,
        ansi.colid,  ansi.colres,
        ansi.colemp, ansi.colres,
        ansi.colemp, ansi.colres,
        ansi.colemp, ansi.colres,
        ansi.colemp, ansi.colres,
    });
}
