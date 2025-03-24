const std = @import("std");
const globals = @import("globals.zig");
const dt = @import("data_types.zig");
const data_file_printer = @import("data_file_printer.zig");

pub const integration_test_file_path = "test/integration_test_data_file.mtlt";

/// Potential types of errors during testing
pub const IntegrationTestingError = error{
    FilesNotIdentical,
};

fn printFiles(ex_file_data: dt.FullData) !void {
    try data_file_printer.printFileData(ex_file_data, "test/expected_file.html");
    try data_file_printer.printFileData(try globals.dfr.getFullData(), "test/actual_file.html");
}

/// Compare the 2 test files and expect them to be identical
pub fn compareFiles(ex_file_data: dt.FullData) !void {
    const ex_f = try std.fs.cwd().openFile(integration_test_file_path, .{ .mode = std.fs.File.OpenMode.read_only });
    const ac_f = globals.data_file;
    try ac_f.seekTo(0);

    var buf_ex_f: [2048]u8 = undefined;
    var buf_ac_f: [2048]u8 = undefined;

    var read_ex_f: usize = 0;
    var read_ac_f: usize = 0;

    while (true) {
        read_ex_f = ex_f.reader().readAll(&buf_ex_f) catch unreachable;
        read_ac_f = ac_f.reader().readAll(&buf_ac_f) catch unreachable;

        if (read_ex_f == 0 and read_ac_f == 0) {
            break;
        } else if (read_ex_f == 0 and read_ac_f != 0) {
            std.debug.print("expected file shorter than actual file\n", .{});
            try printFiles(ex_file_data);
            return IntegrationTestingError.FilesNotIdentical;
        } else if (read_ac_f == 0 and read_ex_f != 0) {
            std.debug.print("actual file shorter than expected file\n", .{});
            try printFiles(ex_file_data);
            return IntegrationTestingError.FilesNotIdentical;
        }

        if (!std.mem.eql(u8, buf_ex_f[0..read_ex_f], buf_ac_f[0..read_ac_f])) {
            std.debug.print("Comparison gives inequal results\n", .{});
            try printFiles(ex_file_data);
            return IntegrationTestingError.FilesNotIdentical;
        }
    }
}

pub fn initTest() !void {
    try globals.initDataFileNames();

    // delete the potentially existing test file
    std.fs.cwd().deleteFile(globals.data_file_path) catch |err| {
        if (err == std.posix.UnlinkError.FileNotFound) {} else {
            unreachable;
        }
    };

    try globals.openDataFiles();
}

pub fn deinitTest() void {
    globals.closeDataFiles();
    globals.deinitDataFileNames();
}
