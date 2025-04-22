const std = @import("std");

pub fn confirm() !bool {
    const w = std.io.getStdOut().writer();
    const r = std.io.getStdIn().reader();

    try w.print("Do you want to proceed? [y/N] ", .{});

    var buf: [1]u8 = undefined;
    const read = try r.read(&buf);
    if (read == 0) return false;

    return (buf[0] == 'y') or (buf[0] == 'Y');
}
