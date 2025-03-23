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

fn writeTagHtml(tag: dt.Tag, w: *const std.fs.File.Writer) void {
    w.*.print(
        \\        <tr>
        \\            <td>{d}</td>
        \\            <td>{s}</td>
        \\            <td>{s}</td>
        \\        </tr>
    , .{ tag.id, @tagName(tag.status), tag.name }) catch unreachable;
}

fn printTagsSection(w: std.fs.File.Writer, parser: *dfr.DataFileReader) !void {
    try w.print(
        \\    <h2>TAGS</h2>
        \\    <table>
        \\        <tr>
        \\            <th>Id</th>
        \\            <th>Status</th>
        \\            <th>Name</th>
        \\        </tr>
    , .{});

    try parser.*.parseTags(.{ .WriteTagHtml = .{
        .func = writeTagHtml,
        .file = &w,
    } });

    try w.print(
        \\    </table>
    , .{});
}

fn writeThingHtml(thing: dt.Thing, w: *const std.fs.File.Writer) void {
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
        thing.target,
        thing.estimation,
        thing.name,
        tag_id_list.items,
    };

    w.print(
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
    , args) catch unreachable;

    w.print(
        \\        <tr class="detail-row">
        \\            <td colspan="8">
        \\                <table>
    , .{}) catch unreachable;

    for (thing.timers) |timer| {
        w.print(
            \\                    <tr>
            \\                        <td>{d}</td>
            \\                        <td>{d}</td>
            \\                        <td>{d}</td>
            \\                    </tr>
        , .{ timer.id, timer.duration, timer.start }) catch unreachable;
    }

    w.print(
        \\                </table>
        \\            </td>
        \\        </tr>
    , .{}) catch unreachable;
}

fn printThingsSection(w: std.fs.File.Writer, parser: *dfr.DataFileReader) !void {
    try w.print(
        \\    <h2>THINGS</h2>
        \\    <table>
        \\        <tr>
        \\            <th>Id</th>
        \\            <th>Status</th>
        \\            <th>Creation</th>
        \\            <th>Closure</th>
        \\            <th>Target</th>
        \\            <th>Estimation</th>
        \\            <th>Name</th>
        \\            <th>Tags</th>
        \\        </tr>
    , .{});

    try parser.*.parseThings(.{ .WriteThingHtml = .{
        .func = writeThingHtml,
        .file = &w,
    } });

    try w.print(
        \\    </table>
    , .{});
}

pub fn main() !void {
    try globals.initDataFileNames(null);
    try globals.openDataFiles();

    // create the file that will contain the printout
    const f = try std.fs.cwd().createFile("printout_date_file.html", .{});
    defer f.close();
    const w = f.writer();

    try printHtmlStart(w);

    var parser = dfr.DataFileReader{};

    try printTagsSection(w, &parser);
    try printThingsSection(w, &parser);

    const currentTimer = try parser.getCurrentTimer();
    try printCurrentTimerSection(w, currentTimer);

    try printHtmlEnd(w);

    globals.closeDataFiles();
    globals.deinitDataFileNames();
    globals.deinitMemAllocator();
}
