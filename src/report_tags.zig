const std = @import("std");

const ansi = @import("ansi_codes.zig");
const dfr = @import("data_file_reader.zig");
const dt = @import("data_types.zig");
const globals = @import("globals.zig");
const table_printer = @import("table_printer.zig");
const user_feedback = @import("user_feedback.zig");

const CellAlignment = @import("table_printer.zig").CellAlignment;
const ArgumentParser = @import("argument_parser.zig").ArgumentParser;

const little_end = std.builtin.Endian.little;

// Array list of tags included in the report
var tags_to_sort: std.ArrayList(dt.TagToSort) = undefined;

/// Process a thing to check if it is associated to the specified tag
pub fn checkThingForTagAssociation(thing: dt.Thing, tag_id: u16, num_open: *u24, num_closed: *u24) void {
    for (thing.tags) |tag| {
        if (tag == tag_id) {
            if (thing.status == dt.StatusThing.open) {
                num_open.* += 1;
            } else {
                num_closed.* += 1;
            }
            return;
        }
    }
}

/// Compare 2 tags_to_sort according to their associated coef used for sorting
fn compareTags(_: void, a: dt.TagToSort, b: dt.TagToSort) bool {
    return a.coef > b.coef;
}

fn addTagToSortToList(tag: dt.Tag, arr: *std.ArrayList(dt.TagToSort)) void {
    const dup_tag = tag.dupe();

    arr.*.append(.{ .tag = dup_tag, .num_open_things_associated = 0, .num_closed_things_associated = 0, .coef = 0 }) catch |err| {
        std.debug.print("ERROR: while trying to add a tag to a list during parsing: {}\n", .{err});
    };
}

/// Display a report of the tags in the data file
pub fn tagsReport(args: *ArgumentParser) !void {
    // TODO add filters for tags with flag -a and --exclude-tags

    // create a list of all the tags to display
    tags_to_sort = std.ArrayList(dt.TagToSort).init(globals.allocator);
    defer tags_to_sort.deinit();

    try globals.dfr.parseTags(.{ .AddTagToSortToArrayList = .{
        .func = addTagToSortToList,
        .tag_array = &tags_to_sort,
    } });

    if (tags_to_sort.items.len < 1) {
        try user_feedback.noTagsToList();
        return;
    }

    // complete the list by getting the number of associated things for each tag
    for (0..tags_to_sort.items.len) |i| {
        const id_cur_tag = tags_to_sort.items[i].tag.id;
        var num_open_things_for_current_tag: u24 = 0;
        var num_closed_things_for_current_tag: u24 = 0;

        try globals.dfr.parseThings(.{ .CheckThingForTagAssociation = .{
            .func = checkThingForTagAssociation,
            .tag_id = id_cur_tag,
            .num_open = &num_open_things_for_current_tag,
            .num_closed = &num_closed_things_for_current_tag,
        } });

        tags_to_sort.items[i].num_open_things_associated = num_open_things_for_current_tag;
        tags_to_sort.items[i].num_closed_things_associated = num_closed_things_for_current_tag;
        tags_to_sort.items[i].coef =
            (@as(u64, @intFromEnum(tags_to_sort.items[i].tag.status)) * 1000000) +
            num_open_things_for_current_tag;
    }

    // sort the list of tags
    const tags_to_sort_slice = try tags_to_sort.toOwnedSlice();
    defer globals.allocator.free(tags_to_sort_slice);
    std.mem.sort(dt.TagToSort, tags_to_sort_slice, {}, compareTags);

    // compute the number of items to display
    var idx_end_slice = tags_to_sort_slice.len;
    if (args.*.limit == null and idx_end_slice > globals.default_report_limit) {
        idx_end_slice = globals.default_report_limit;
    } else if (args.*.limit != null and idx_end_slice > args.*.limit.? and args.*.limit.? != 0) {
        idx_end_slice = args.*.limit.?;
    }

    try displayTableReport(tags_to_sort_slice[0..idx_end_slice]);

    // display an additional line after the table regarding number of tags
    var buf_missing_tags: [96]u8 = undefined;
    const nbr_missing_tags: usize = tags_to_sort_slice.len - idx_end_slice;

    const str_missing_tags = if (nbr_missing_tags == 0)
        try std.fmt.bufPrint(&buf_missing_tags, "{s}{d}{s} tags shown", .{ ansi.coltit, idx_end_slice, ansi.colres })
    else
        try std.fmt.bufPrint(&buf_missing_tags, "{s}{d}{s} tags shown - {s}{d}{s} tags not shown because of the display limit", .{ ansi.coltit, idx_end_slice, ansi.colres, ansi.coltit, nbr_missing_tags, ansi.colres });

    try std.io.getStdOut().writer().print("\n{s}\n", .{str_missing_tags});

    // free memory
    for (tags_to_sort_slice) |tag_to_sort| {
        tag_to_sort.deinit();
    }
}

/// Setup the table printer to display the data to the user
fn displayTableReport(tags: []dt.TagToSort) !void {
    const num_cols: u8 = 4;

    // used to create strings to display on the report
    var buf_str: [64]u8 = undefined;

    // the array of data we want to display as a table
    var to_display = try globals.allocator.alloc([]table_printer.Cell, tags.len + 1);
    defer globals.allocator.free(to_display);

    // setup the header of the table
    to_display[0] = try globals.allocator.alloc(table_printer.Cell, num_cols);
    defer globals.allocator.free(to_display[0]);
    to_display[0][0] = .{ .content = "Status", .alignment = .left, .front_col = .title, .back_col = .gray };
    to_display[0][1] = .{ .content = "Name", .alignment = .left, .front_col = .title, .back_col = .gray };
    to_display[0][2] = .{ .content = "Priority", .alignment = .left, .front_col = .title, .back_col = .gray };
    to_display[0][3] = .{ .content = "# things (open/closed)", .alignment = .left, .front_col = .title, .back_col = .gray };

    // setup the data of the table based on the list of tags we want to display
    for (tags, 1..tags.len + 1) |tag_to_sort, i| {
        const tag = tag_to_sort.tag;
        to_display[i] = try globals.allocator.alloc(table_printer.Cell, num_cols);
        const line_back_col: ?table_printer.CellBackCol = if (i % 2 != 0) null else .gray;

        to_display[i][0] = .{
            .content = if (tag.status == dt.StatusTag.closed) "closed" else "open",
            .alignment = .left,
            .front_col = null,
            .back_col = line_back_col,
        };

        to_display[i][1] = .{
            .content = try globals.allocator.dupe(u8, tag.name),
            .alignment = .left,
            .front_col = .id,
            .back_col = line_back_col,
        };

        to_display[i][2] = .{
            .content = if (tag.status != dt.StatusTag.closed) @tagName(tag.status) else "-",
            .alignment = .left,
            .front_col = null,
            .back_col = line_back_col,
        };

        const str_num_associated_things = try std.fmt.bufPrint(&buf_str, "{d} / {d}", .{
            tag_to_sort.num_open_things_associated,
            tag_to_sort.num_closed_things_associated,
        });
        to_display[i][3] = .{
            .content = try globals.allocator.dupe(u8, str_num_associated_things),
            .alignment = .right,
            .front_col = null,
            .back_col = line_back_col,
        };
    }

    try table_printer.printTable(to_display);

    // Free memory for all that we allocated
    for (1..tags.len + 1) |i| {
        globals.allocator.free(to_display[i][1].content);
        globals.allocator.free(to_display[i][3].content);
        globals.allocator.free(to_display[i]);
    }
}

/// Print out help for the tags command
pub fn help() !void {
    try std.io.getStdOut().writer().print(
        \\Usage: {s}mtlt tags{s}
        \\
        \\Displays a list of all tags present in the data file. By default,
        \\closed tags are not included.
        \\
        \\Options:
        \\  {s}-l{s}, {s}--limit{s}           How many tags to display at most
        \\                        (0 means no limit)
        \\      {s}--include-closed{s}  Should include closed tags
        \\
        \\Examples:
        \\  {s}mtlt tags{s}
        \\      Display the list of open tags with the default limit.
        \\
        \\  {s}mtlt tags -l 0 --include-closed{s}
        \\      Display open and closed tags without any number limit.
        \\
        \\  {s}mtlt tags -l 20{s}
        \\      Display the 20 first open tags.
        \\
    , .{
        ansi.colemp, ansi.colres,
        ansi.colid,  ansi.colres,
        ansi.colid,  ansi.colres,
        ansi.colid,  ansi.colres,
        ansi.colemp, ansi.colres,
        ansi.colemp, ansi.colres,
        ansi.colemp, ansi.colres,
    });
}
