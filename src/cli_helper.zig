const std = @import("std");

pub fn confirm() !bool {
    const w = std.io.getStdOut().writer();
    const r = std.io.getStdIn().reader();

    try w.print("Do you want to proceed? [y/N] ", .{});

    var first: u8 = 0;
    var got_input = false;

    var buf: [1]u8 = undefined;
    while (true) {
        const read = try r.read(&buf);

        if (read == 0) {
            break;
        } else if (buf[0] == '\n') {
            break;
        }

        if (!got_input) {
            first = buf[0];
            got_input = true;
        }
    }

    return first == 'y' or first == 'Y';
}
