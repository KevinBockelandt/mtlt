const std = @import("std");

const dt = @import("data_types.zig");
const dfr = @import("data_file_reader.zig");
const globals = @import("globals.zig");
const time_helper = @import("time_helper.zig");

const little_end = std.builtin.Endian.little;
var w: std.fs.File.Writer = undefined;

fn printHtmlStart() !void {
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

fn printHtmlEnd() !void {
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

fn printCurrentTimerSection(cur_timer: dt.CurrentTimer) !void {
    try w.print(
        \\    <h2>CURRENT TIMER</h2>
        \\    <ul>
        \\        <li>Id thing: {d}</li>
        \\        <li>Id last timer: {d}</li>
        \\        <li>Start: {d}</li>
        \\    </ul>
    , .{ cur_timer.id_thing, cur_timer.id_last_timer, cur_timer.start });
}

fn processTag(data: []const u8) void {
    const raw_fpt = std.mem.readInt(u24, data[0..dt.lgt_fixed_tag], little_end);
    const fpt = dt.getTagFixedPartFromInt(raw_fpt);
    const name = data[dt.lgt_fixed_tag .. dt.lgt_fixed_tag + fpt.lgt_name];

    w.print(
        \\        <tr>
        \\            <td>{d}</td>
        \\            <td>{s}</td>
        \\            <td>{s}</td>
        \\        </tr>
    , .{ fpt.id, @tagName(@as(dt.Status, @enumFromInt(fpt.status))), name }) catch unreachable;
}

fn printTagsSection(parser: *dfr.DataFileReader) !void {
    try w.print(
        \\    <h2>TAGS</h2>
        \\    <table>
        \\        <tr>
        \\            <th>Id</th>
        \\            <th>Status</th>
        \\            <th>Name</th>
        \\        </tr>
    , .{});

    try parser.*.parseTags(processTag);

    try w.print(
        \\    </table>
    , .{});
}

fn processThing(data: []const u8) void {
    const int_fpt = std.mem.readInt(u136, data[0..dt.lgt_fixed_thing], little_end);
    const fpt = dt.getThingFixedPartFromInt(int_fpt);

    const s_idx_name = dt.lgt_fixed_thing;
    const e_idx_name = dt.lgt_fixed_thing + fpt.lgt_name;

    var tag_id_list = std.ArrayList(u8).init(globals.allocator);
    defer tag_id_list.deinit();

    if (fpt.num_tags > 0) {
        var s_idx_tags: usize = e_idx_name;

        for (0..fpt.num_tags) |_| {
            const tag_id = std.mem.readInt(u16, data[s_idx_tags .. s_idx_tags + 2][0..2], little_end);
            std.fmt.format(tag_id_list.writer(), "{d}, ", .{tag_id}) catch unreachable;
            s_idx_tags += 2;
        }
    }

    const args = .{
        fpt.id,
        @tagName(@as(dt.Status, @enumFromInt(fpt.status))),
        fpt.creation,
        fpt.closure,
        fpt.target,
        fpt.estimation,
        data[s_idx_name..e_idx_name],
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

    var s_idx_timers: usize = e_idx_name + fpt.num_tags * 2;

    if (fpt.num_timers > 0) {
        for (0..fpt.num_timers) |_| {
            const int_data_timer = std.mem.readInt(u48, data[s_idx_timers .. s_idx_timers + 48][0..6], little_end);
            const data_timer = dt.getTimerFromInt(int_data_timer);

            w.print(
                \\                    <tr>
                \\                        <td>{d}</td>
                \\                        <td>{d}</td>
                \\                        <td>{d}</td>
                \\                    </tr>
            , .{ data_timer.id, data_timer.duration, data_timer.start }) catch unreachable;

            s_idx_timers += 6;
        }
    }

    w.print(
        \\                </table>
        \\            </td>
        \\        </tr>
    , .{}) catch unreachable;
}

fn printThingsSection(parser: *dfr.DataFileReader) !void {
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

    try parser.*.parseThings(processThing);

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
    w = f.writer();

    try printHtmlStart();

    var parser = dfr.DataFileReader{};

    try printTagsSection(&parser);
    try printThingsSection(&parser);

    const currentTimer = try parser.getCurrentTimer();
    try printCurrentTimerSection(currentTimer);

    try printHtmlEnd();

    globals.closeDataFiles();
    globals.deinitDataFileNames();
    globals.deinitMemAllocator();
}
