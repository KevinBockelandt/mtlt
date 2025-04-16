const std = @import("std");

const dt = @import("data_types.zig");
const dfr = @import("data_file_reader.zig");
const globals = @import("globals.zig");
const time_helper = @import("time_helper.zig");
const ft = @import("function_types.zig");

const little_end = std.builtin.Endian.little;

fn printHtmlStart(w: std.fs.File.Writer) !void {
    _ = try w.write(
        \\<!DOCTYPE html>
        \\<html>
        \\    <head>
        \\        <style>
        \\        body {
        \\        font-family: sans-serif;
        \\        }
        \\        table {
        \\        border-collapse: collapse;
        \\        }
        \\        h1 {text-align: center;}
        \\        h2 {
        \\        margin-top: 3rem;
        \\        text-align: center;
        \\        }
        \\        table tr:nth-child(even){
        \\        background-color: #f2f2f2;
        \\        }
        \\        td, th {
        \\        padding: 0.5rem 1rem
        \\        }
        \\        .detail-row { display: none; }
        \\        .detail-row.show { display: table-row; }
        \\        .main-row { border-bottom: 1px dashed black; }
        \\        </style>
        \\    </head>
        \\    <body>
        \\        <h1>MTLT Data File Content</h1>
    );
}

fn printHtmlEnd(w: std.fs.File.Writer) !void {
    _ = try w.write(
        \\    </body>
        \\    <script>
        \\    document.querySelectorAll('.main-row').forEach((mainRow) => {
        \\    console.log("found a row");
        \\    mainRow.addEventListener('click', () => {
        \\    console.log("clicked on row");
        \\    const detailRow = mainRow.nextElementSibling;
        \\    if (detailRow && detailRow.classList.contains('detail-row')) {
        \\    detailRow.classList.toggle('show');
        \\    }
        \\    });
        \\    });
        \\    </script>
        \\</html>
    );
}

fn printCurrentTimerSection(w: std.fs.File.Writer, cur_timer: dt.CurrentTimer) !void {
    try w.print(
        \\    <h2>CURRENT TIMER</h2>
        \\    <ul>
        \\        <li>Id thing: {d}</li>
        \\        <li>Id last timer: {d}</li>
        \\        <li>Start: {d}</li>
        \\    </ul>
    , .{ cur_timer.id_thing, cur_timer.id_last_timer, cur_timer.start });
}

fn printTagsSection(w: std.fs.File.Writer, tags: std.ArrayList(dt.Tag)) !void {
    try w.print(
        \\    <h2>TAGS</h2>
        \\    <table>
        \\        <tr>
        \\            <th>Id</th>
        \\            <th>Status</th>
        \\            <th>Name</th>
        \\        </tr>
    , .{});

    for (tags.items) |tag| {
        try w.print(
            \\        <tr>
            \\            <td>{d}</td>
            \\            <td>{s}</td>
            \\            <td>{s}</td>
            \\        </tr>
        , .{ tag.id, @tagName(tag.status), tag.name });
    }

    try w.print(
        \\    </table>
    , .{});
}

fn printThingsSection(w: std.fs.File.Writer, things: std.ArrayList(dt.Thing)) !void {
    try w.print(
        \\    <h2>THINGS</h2>
        \\    <table>
        \\        <tr>
        \\            <th>Id</th>
        \\            <th>Status</th>
        \\            <th>Creation</th>
        \\            <th>Closure</th>
        \\            <th>Kickoff</th>
        \\            <th>Estimation</th>
        \\            <th>Name</th>
        \\            <th>Tags</th>
        \\        </tr>
    , .{});

    for (things.items) |thing| {
        var tag_id_list = std.ArrayList(u8).init(globals.allocator);
        defer tag_id_list.deinit();

        for (thing.tags) |tag_id| {
            std.fmt.format(tag_id_list.writer(), "{d}, ", .{tag_id}) catch unreachable;
        }

        const args = .{
            thing.id,
            @tagName(thing.status),
            thing.creation,
            thing.closure,
            thing.kickoff,
            thing.estimation,
            thing.name,
            tag_id_list.items,
        };

        try w.print(
            \\        <tr class="main-row">
            \\            <td>{d}</td>
            \\            <td>{s}</td>
            \\            <td>{d}</td>
            \\            <td>{d}</td>
            \\            <td>{d}</td>
            \\            <td>{d}</td>
            \\            <td>{s}</td>
            \\            <td>{s}</td>
            \\        </tr>
        , args);

        try w.print(
            \\        <tr class="detail-row">
            \\            <td colspan="8">
            \\                <table>
        , .{});

        for (thing.timers) |timer| {
            try w.print(
                \\                    <tr>
                \\                        <td>{d}</td>
                \\                        <td>{d}</td>
                \\                        <td>{d}</td>
                \\                    </tr>
            , .{ timer.id, timer.duration, timer.start });
        }

        try w.print(
            \\                </table>
            \\            </td>
            \\        </tr>
        , .{});
    }

    try w.print(
        \\    </table>
    , .{});
}

/// Print the content of the given data file into an HTML page (for debug purposes)
pub fn printFileDataHtml(file_data: dt.FullData, path_out_file: []const u8) !void {
    // create the file that will contain the printout
    const f = try std.fs.cwd().createFile(path_out_file, .{});
    defer f.close();
    const w = f.writer();

    try printHtmlStart(w);
    try printTagsSection(w, file_data.tags);
    try printThingsSection(w, file_data.things);
    try printCurrentTimerSection(w, file_data.cur_timer);
    try printHtmlEnd(w);
}

/// Print the content of the given data file onto stdout in hexadecimal (for debug purposes)
pub fn printFileDataHex(f: std.fs.File) !void {
    const r = f.reader();
    try f.seekTo(0);

    const total_bytes_tag_section = try r.readInt(u64, little_end);
    std.debug.print("{x}    - total bytes tag section\n", .{total_bytes_tag_section});

    const num_tags_in_file = try r.readInt(u16, little_end);
    std.debug.print("{x}      - num tags in file\n", .{num_tags_in_file});

    std.debug.print("--------- TAGS ---------\n", .{});

    for (0..num_tags_in_file) |_| {
        const int_fpt = try r.readInt(u24, little_end);
        const parsed_fpt = dt.getTagFixedPartFromInt(int_fpt);
        const buf_tag_name = try globals.allocator.alloc(u8, parsed_fpt.lgt_name);
        _ = try r.read(buf_tag_name);
        std.debug.print("{x}  - {s}\n", .{ int_fpt, buf_tag_name });
        globals.allocator.free(buf_tag_name);
    }

    const num_things_in_file = try r.readInt(u24, little_end);
    std.debug.print("{x}    - num things in file\n", .{num_things_in_file});

    for (0..num_things_in_file) |_| {
        std.debug.print("---------- THING --------\n", .{});

        const int_fpt = try r.readInt(u136, little_end);
        const parsed_fpt = dt.getThingFixedPartFromInt(int_fpt);
        std.debug.print("{x}\n", .{int_fpt});

        const buf_thing_name = try globals.allocator.alloc(u8, parsed_fpt.lgt_name);
        _ = try r.read(buf_thing_name);
        std.debug.print("{x} - {s}\n", .{ buf_thing_name, buf_thing_name });

        for (0..parsed_fpt.num_tags) |_| {
            const tag_id = try r.readInt(u16, little_end);
            std.debug.print("{x:0>4}, ", .{tag_id});
        }

        std.debug.print("\n", .{});
        for (0..parsed_fpt.num_timers) |_| {
            const int_timer = try r.readInt(u48, little_end);
            std.debug.print("{x:0>12}\n", .{int_timer});
        }
    }

    std.debug.print("----- CURRENT TIMER -----\n", .{});
    const int_cur_timer = try r.readInt(u56, little_end);
    std.debug.print("{x}\n", .{int_cur_timer});
}

pub fn main() !void {
    try globals.initDataFileNames(null);
    try globals.openDataFiles();

    var parser = dfr.DataFileReader{};
    var file_data = try parser.getFullData();

    try printFileDataHtml(file_data, "printout_data_file.html");

    file_data.deinit();
    globals.closeDataFiles();
    globals.deinitDataFileNames();
    globals.deinitMemAllocator();
}
