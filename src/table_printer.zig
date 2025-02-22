const ansi = @import("ansi_codes.zig");
const globals = @import("globals.zig");
const std = @import("std");
const string_helper = @import("string_helper.zig");

pub const CellAlignment = enum {
    left,
    right,
};

pub const CellFrontCol = enum {
    duration,
    emphasis,
    id,
    negative,
    positive,
    reset,
    title,
};

pub const CellBackCol = enum {
    gray,
    reset,
    highlight,
};

pub const Cell = struct {
    content: []const u8,
    alignment: CellAlignment,
    front_col: ?CellFrontCol,
    back_col: ?CellBackCol,
};

const TableError = error{
    InconsistentNumberOfColumns,
    NotEnoughLines,
};

/// Check the validity of the data to be displayed in the table
fn checkInputData(data: [][]Cell) !void {
    if (data.len < 2) {
        return TableError.NotEnoughLines;
    }

    // check that all lines have the same number of columns
    const num_col = data[0].len;
    for (data) |line| {
        if (line.len != num_col) {
            return TableError.InconsistentNumberOfColumns;
        }
    }
}

/// Return the number of spaces between a string and the max lgt of a column
fn get_lgt_padding(str: []const u8, max_lgt: usize) !usize {
    var buf_stripped: [2048]u8 = undefined;
    const stripped = try ansi.stripANSICodes(str, &buf_stripped);
    const len_stripped = try string_helper.computeDisplayLength(stripped);
    return max_lgt - len_stripped;
}

/// Print the given front color code on the standard output
fn printFrontColor(col: CellFrontCol, writer: anytype) !void {
    switch (col) {
        .duration => try writer.print("{s}", .{ansi.col_duration_neutral}),
        .emphasis => try writer.print("{s}", .{ansi.col_emphasis}),
        .id => try writer.print("{s}", .{ansi.col_id}),
        .negative => try writer.print("{s}", .{ansi.col_negative_dur}),
        .positive => try writer.print("{s}", .{ansi.col_positive_dur}),
        .reset => try writer.print("{s}", .{ansi.col_reset}),
        .title => try writer.print("{s}", .{ansi.col_title}),
    }
}

/// Print the given back color code on the standard output
fn printBackColor(col: CellBackCol, writer: anytype) !void {
    switch (col) {
        .gray => try writer.print("{s}", .{ansi.back_col_grayscale_2}),
        .highlight => try writer.print("{s}", .{ansi.back_col_highlight}),
        .reset => try writer.print("{s}", .{ansi.back_col_reset}),
    }
}

/// Print on std out the content of the specified table
pub fn printTable(data: [][]Cell) !void {
    const w = std.io.getStdOut().writer();
    try checkInputData(data);

    const num_col = data[0].len;

    var max_lgts = try globals.allocator.alloc(usize, num_col);
    defer globals.allocator.free(max_lgts);
    for (0..max_lgts.len) |i| {
        max_lgts[i] = 0;
    }

    // look for the max length string in each column
    for (data) |line| {
        for (0..line.len) |i| {
            var buf_stripped: [2048]u8 = undefined;
            const stripped = try ansi.stripANSICodes(line[i].content, &buf_stripped);

            const len_stripped = try string_helper.computeDisplayLength(stripped);

            if (len_stripped > max_lgts[i]) {
                max_lgts[i] = stripped.len;
            }
        }
    }

    // a buffer used to print spaces
    var buf_space: [2048]u8 = undefined;
    for (0..buf_space.len) |i| {
        buf_space[i] = ' ';
    }

    // print content of the table
    for (0..data.len) |i| {
        for (0..num_col) |j| {
            const cur_cell = data[i][j];

            const end = if (j == num_col - 1) "\n" else " ";
            const lgt_space = try get_lgt_padding(cur_cell.content, max_lgts[j]);

            // print start of color codes if applicable
            if (cur_cell.front_col) |fc| {
                try printFrontColor(fc, w);
            }
            if (cur_cell.back_col) |bc| {
                try printBackColor(bc, w);
            }

            // print content of the cell
            switch (cur_cell.alignment) {
                .left => {
                    try w.print("{s}", .{cur_cell.content});
                    try w.print("{s}", .{buf_space[0..lgt_space]});
                },
                .right => {
                    try w.print("{s}", .{buf_space[0..lgt_space]});
                    try w.print("{s}", .{cur_cell.content});
                },
            }

            try w.print("{s}", .{end});

            // print end of color codes if applicable
            if (cur_cell.front_col != null) {
                try printFrontColor(CellFrontCol.reset, w);
            }
            if (cur_cell.back_col != null) {
                try printBackColor(CellBackCol.reset, w);
            }

            // clear remainin of the line to avoid weird artifacts
            try w.print("{s}", .{ansi.clear_remaining});
        }
    }
}

test "not enough line" {
    var line1: [2][]const u8 = .{ "header1", "header2" };
    var data: [1][][]const u8 = .{line1[0..]};

    if (printTable(data[0..])) |_| {
        return error.TestShouldFail;
    } else |err| {
        try std.testing.expect(err == TableError.NotEnoughLines);
    }
}

test "discrepancy between column numbers" {
    var line1: [2][]const u8 = .{ "header1", "header2" };
    var line2: [1][]const u8 = .{"blabla"};
    var data: [2][][]const u8 = .{ line1[0..], line2[0..] };

    if (printTable(data[0..])) |_| {
        return error.TestShouldFail;
    } else |err| {
        try std.testing.expect(err == TableError.InconsistentNumberOfColumns);
    }
}
