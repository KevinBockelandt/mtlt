const builtin = @import("builtin");
const std = @import("std");

const data_file_writer = @import("data_file_writer.zig");
const printer_header = @import("printer.zig");

const DataFileReader = @import("data_file_reader.zig").DataFileReader;
const DataFileWriter = @import("data_file_writer.zig").DataFileWriter;

pub const default_report_limit: u32 = 20;

pub var data_file_path: []const u8 = undefined;
pub var back_data_file_path: []const u8 = undefined;

pub var data_file: std.fs.File = undefined;
pub var back_data_file: std.fs.File = undefined;

const data_file_path_env = "MTLT_DATA_FILE_FULL_PATH";
const test_data_file_path_env = "TEST_MTLT_DATA_FILE_FULL_PATH";

var gpa = std.heap.GeneralPurposeAllocator(.{}){};
pub var allocator = gpa.allocator();
pub var dfw: DataFileWriter = .{};
pub var dfr: DataFileReader = .{};
pub var printer: printer_header.Printer = .{};
pub const num_sec_offset_1970_2020 = 1577836800;

pub fn initDataFileNames() !void {
    const df_env_var = if (builtin.mode == .Debug) test_data_file_path_env else data_file_path_env;

    // Try to get the environement variable necessary for the data file path

    if (std.process.getEnvVarOwned(allocator, df_env_var)) |dfp| {
        data_file_path = try allocator.dupe(u8, dfp);
        allocator.free(dfp);
    } else |err| {
        switch (err) {
            error.EnvironmentVariableNotFound => try printer.missingEnvVar(df_env_var),
            error.InvalidWtf8 => try printer.errInvalidEnvVar(df_env_var),
            else => try printer.errUnexpectedGetEnvVar(df_env_var, err),
        }

        return err;
    }

    var buf_dfp: [2048]u8 = undefined;
    back_data_file_path = try allocator.dupe(u8, try std.fmt.bufPrint(&buf_dfp, "{s}.backup", .{data_file_path}));
}

pub fn deinitDataFileNames() void {
    allocator.free(data_file_path);
    allocator.free(back_data_file_path);
}

pub fn openDataFiles() !void {
    if (std.fs.cwd().openFile(data_file_path, .{ .mode = std.fs.File.OpenMode.read_write })) |f| {
        data_file = f;
    } else |err| {
        switch (err) {
            std.fs.File.OpenError.FileNotFound => {
                data_file = try std.fs.cwd().createFile(data_file_path, .{ .truncate = true, .read = true });
                try data_file_writer.generateEmptyDataFile();
            },
            else => {
                std.debug.panic("Could not open the data file: {}\n", .{err});
            },
        }
    }

    // recreate the backup file every time
    back_data_file = try std.fs.cwd().createFile(back_data_file_path, .{ .truncate = true });
}

pub fn closeDataFiles() void {
    data_file.close();
    back_data_file.close();
}

pub fn swapDataFiles() !void {
    closeDataFiles();
    try std.fs.cwd().deleteFile(data_file_path);
    try std.fs.cwd().rename(back_data_file_path, data_file_path);
    try openDataFiles();
}

pub fn deinitMemAllocator() void {
    const deinit_status = gpa.deinit();
    if (deinit_status == .leak) {
        std.debug.panic("Problem when releasing the allocator\n", .{});
    }
}

/// Print the given string into the standard output ignoring potential errors
pub fn printNoFail(comptime fmt: []const u8, args: anytype) void {
    std.io.getStdOut().writer().print(fmt, args) catch |err| {
        std.debug.print("ERROR while printing on the standard output\n", .{});
        std.debug.print("{}\n", .{err});
    };
}
